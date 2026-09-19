#include "llama-kv-cache.h"

#include "llama-impl.h"
#include "llama-io.h"
#include "llama-model.h"
#include "llama-context.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <limits>
#include <map>
#include <stdexcept>
#include <unordered_map>

static bool ggml_is_power_of_2(int n) {
    return (n & (n - 1)) == 0;
}

// orthonormal Walsh-Hadamard rotation matrix
// note: res^2 == I
static void ggml_gen_hadamard(ggml_tensor * tensor) {
    assert(tensor->type == GGML_TYPE_F32);

    const int n = tensor->ne[0];

    assert(ggml_is_power_of_2(n));
    assert(tensor->ne[1] == n);
    assert(tensor->ne[2] == 1);
    assert(tensor->ne[3] == 1);

    std::vector<float> data_f32;

    float * data = (float *) tensor->data;

    if (tensor->type != GGML_TYPE_F32) {
        data_f32.resize(n*n);
        data = data_f32.data();
    }

    data[0*n + 0] = 1.0 / sqrtf(n);

    for (int s = 1; s < n; s *= 2) {
        for (int i = 0; i < s; i++) {
            for (int j = 0; j < s; j++) {
                const float val = data[i*n + j];

                data[(i + s)*n + (j    )] =  val;
                data[(i    )*n + (j + s)] =  val;
                data[(i + s)*n + (j + s)] = -val;
            }
        }
    }

    if (tensor->type != GGML_TYPE_F32) {
        ggml_quantize_chunk(tensor->type, data, tensor->data, 0, 1, n*n, nullptr);
    }
}

//
// llama_kv_cache
//

llama_kv_cache::llama_kv_cache(
        const llama_model & model,
        const llama_hparams & hparams,
                ggml_type   type_k,
                ggml_type   type_v,
                     bool   v_trans,
                     bool   offload,
                     bool   unified,
                 uint32_t   kv_size,
                 uint32_t   n_seq_max,
                 uint32_t   n_pad,
                 uint32_t   n_swa,
           llama_swa_type   swa_type,
           llama_memory_t   mem_other,
    const layer_filter_cb & filter,
    const  layer_reuse_cb & reuse,
    const  layer_share_cb & share,
             const char *   name_tag) :
    model(model), hparams(hparams), v_trans(v_trans),
    n_seq_max(n_seq_max), n_stream(unified ? 1 : n_seq_max), n_pad(n_pad), n_swa(n_swa), swa_type(swa_type),
    other(static_cast<llama_kv_cache *>(mem_other)),
    v_cells_impl(other ? other->v_cells_impl : std::make_shared<llama_kv_cells_vec>()),
    v_cells(*v_cells_impl) {

    // shared cells view the source cache's K/V tensors, so the cell count
    // follows the source allocation: a fitted target can be smaller than the
    // draft default and oversized views would overflow the source tensors
    if (other) {
        const uint32_t size_other = other->get_size();
        if (kv_size != size_other) {
            LLAMA_LOG_WARN("%s: kv_size = %u overridden to %u to match the shared source cache\n", __func__, kv_size, size_other);
            kv_size = size_other;
        }
    }

    GGML_ASSERT(kv_size % n_pad == 0);

    const uint32_t n_layer = hparams.n_layer_all;

    // define a comparator for the buft -> ctx map to ensure that the order is well-defined:
    struct ggml_backend_buft_comparator {
        bool operator()(const ggml_backend_buffer_type_t & lhs, const ggml_backend_buffer_type_t & rhs) const {
            return strcmp(ggml_backend_buft_name(lhs), ggml_backend_buft_name(rhs)) < 0;
        }
    };
    std::map<ggml_backend_buffer_type_t, ggml_context_ptr, ggml_backend_buft_comparator> ctx_map;

    // create a context for each buffer type
    auto ctx_for_buft = [&](ggml_backend_buffer_type_t buft) -> ggml_context * {
        auto it = ctx_map.find(buft);
        if (it == ctx_map.end()) {
            ggml_init_params params = {
                /*.mem_size   =*/ size_t(2u*(1 + n_stream)*n_layer*ggml_tensor_overhead()),
                /*.mem_buffer =*/ NULL,
                /*.no_alloc   =*/ true,
            };

            ggml_context * ctx = ggml_init(params);
            if (!ctx) {
                return nullptr;
            }

            ctx_map.emplace(buft, ctx);

            return ctx;
        }

        return it->second.get();
    };

    GGML_ASSERT(n_stream == 1 || n_stream == n_seq_max);

    v_heads.resize(n_stream);
    for (uint32_t s = 0; s < n_stream; ++s) {
        v_heads[s] = 0;
    }

    v_cells.resize(n_stream);
    for (uint32_t s = 0; s < n_stream; ++s) {
        v_cells[s].resize(kv_size);
    }

    // by default, all sequence ids are mapped to the 0th stream
    seq_to_stream.resize(LLAMA_MAX_SEQ, 0);

    if (n_stream > 1) {
        seq_to_stream.resize(n_stream, 0);
        for (uint32_t s = 0; s < n_stream; ++s) {
            seq_to_stream[s] = s;
        }
    }

    // [TAG_V_CACHE_VARIABLE]
    if (v_trans && hparams.is_n_embd_v_gqa_variable()) {
        LLAMA_LOG_WARN("%s: the V embeddings have different sizes across layers and FA is not enabled - padding V cache to %d\n",
                __func__, hparams.n_embd_v_gqa_max());
    }

    const bool is_mla = hparams.is_mla();

    for (uint32_t il = 0; il < n_layer; il++) {
        if (!hparams.has_kv(il)) {
            LLAMA_LOG_DEBUG("%s: layer %3d: does not have KV cache\n", __func__, il);
            continue;
        }

        if (filter && !filter(il)) {
            LLAMA_LOG_DEBUG("%s: layer %3d: filtered\n", __func__, il);
            continue;
        }

        if (share && other) {
            const int32_t il_share = share(il);

            if (il_share >= 0) {
                const auto & layer_share = other->layers[other->map_layer_ids[il_share]];

                LLAMA_LOG_WARN("%s: layer %3d: sharing with layer %d. k = %p, v = %p\n", __func__, il, il_share,
                        layer_share.k->data, layer_share.v->data);

                map_layer_ids[il] = layers.size();

                layers.push_back(layer_share);
                layers.back().il = il;

                continue;
            }
        }

        if (n_embd_head_k_all == 0) {
            n_embd_head_k_all = (int32_t) hparams.n_embd_head_k(il);
        } else if (n_embd_head_k_all > 0 && n_embd_head_k_all != (int32_t) hparams.n_embd_head_k(il)) {
            n_embd_head_k_all = -1;
        }

        if (!is_mla) {
            if (n_embd_head_v_all == 0) {
                n_embd_head_v_all = (int32_t) hparams.n_embd_head_v(il);
            } else if (n_embd_head_v_all > 0 && n_embd_head_v_all != (int32_t) hparams.n_embd_head_v(il)) {
                n_embd_head_v_all = -1;
            }
        }

        // [TAG_V_CACHE_VARIABLE]
        const uint32_t n_embd_k_gqa =            hparams.n_embd_k_gqa(il);
        const uint32_t n_embd_v_gqa = !v_trans ? hparams.n_embd_v_gqa(il) : hparams.n_embd_v_gqa_max();

        const char * dev_name = "CPU";

        ggml_backend_buffer_type_t buft = ggml_backend_cpu_buffer_type();

        if (offload) {
            auto * dev = model.dev_layer(il);
            buft = ggml_backend_dev_buffer_type(dev);

            dev_name = ggml_backend_dev_name(dev);
        }

        LLAMA_LOG_DEBUG("%s: layer %3d: dev = %s\n", __func__, il, dev_name);

        ggml_context * ctx = ctx_for_buft(buft);
        if (!ctx) {
            throw std::runtime_error("failed to create ggml context for kv cache");
        }

        const bool has_k = true;
        const bool has_v = !is_mla;

        ggml_tensor * k = has_k ? ggml_new_tensor_3d(ctx, type_k, n_embd_k_gqa, kv_size, n_stream) : nullptr;
        ggml_tensor * v = has_v ? ggml_new_tensor_3d(ctx, type_v, n_embd_v_gqa, kv_size, n_stream) : nullptr;

        has_k && ggml_format_name(k, "cache_%sk_l%d", name_tag, il);
        has_v && ggml_format_name(v, "cache_%sv_l%d", name_tag, il);

        std::vector<ggml_tensor *> k_stream;
        std::vector<ggml_tensor *> v_stream;

        for (uint32_t s = 0; s < n_stream; ++s) {
            k_stream.push_back(has_k ? ggml_view_2d(ctx, k, n_embd_k_gqa, kv_size, k->nb[1], s*k->nb[2]) : nullptr);
            v_stream.push_back(has_v ? ggml_view_2d(ctx, v, n_embd_v_gqa, kv_size, v->nb[1], s*v->nb[2]) : nullptr);
        }

        map_layer_ids[il] = layers.size();

        layers.push_back({ il, k, v, k_stream, v_stream, });
    }

    if (reuse) {
        LLAMA_LOG_DEBUG("%s: reusing layers:\n", __func__);

        for (uint32_t il = 0; il < n_layer; il++) {
            const int32_t il_reuse = reuse(il);

            if (il_reuse < 0) {
                LLAMA_LOG_DEBUG("%s: - layer %3d: no reuse\n", __func__, il);
                continue;
            }

            if (filter && !filter(il)) {
                LLAMA_LOG_DEBUG("%s: - layer %3d: filtered\n", __func__, il);
                continue;
            }

            GGML_ASSERT(map_layer_ids.find(il_reuse) != map_layer_ids.end());

            map_layer_ids[il] = map_layer_ids[il_reuse];

            LLAMA_LOG_DEBUG("%s: - layer %3d: reuse layer %d, is_swa = %d\n", __func__, il, il_reuse, hparams.is_swa(il));
        }
    }

    // allocate tensors and initialize the buffers to avoid NaNs in the padding
    for (auto & [buft, ctx] : ctx_map) {
        ggml_backend_buffer_t buf;
        if (hparams.no_alloc) {
            buf = ggml_backend_buft_alloc_buffer(buft, /*size =*/ 0); // dummy buffer
            for (ggml_tensor * t = ggml_get_first_tensor(ctx.get()); t != nullptr; t = ggml_get_next_tensor(ctx.get(), t)) {
                t->buffer = buf; // set dummy buffer for KV cache so that the backend scheduler won't try to allocate it
            }
        } else {
            buf = ggml_backend_alloc_ctx_tensors_from_buft(ctx.get(), buft); // real buffer
        }
        if (!buf) {
            throw std::runtime_error("failed to allocate buffer for kv cache");
        }

        LLAMA_LOG_INFO("%s: %10s KV buffer size = %8.2f MiB\n", __func__, ggml_backend_buffer_name(buf), ggml_backend_buffer_get_size(buf)/1024.0/1024.0);

        ggml_backend_buffer_clear(buf, 0);
        ctxs_bufs.emplace_back(std::move(ctx), buf);
    }

    {
        const size_t memory_size_k = size_k_bytes();
        const size_t memory_size_v = size_v_bytes();

        LLAMA_LOG_INFO("%s: size = %7.2f MiB (%6u cells, %3d layers, %2u/%u seqs), K (%s): %7.2f MiB, V (%s): %7.2f MiB\n", __func__,
                (float)(memory_size_k + memory_size_v) / (1024.0f * 1024.0f), kv_size, (int) layers.size(), n_seq_max, n_stream,
                ggml_type_name(type_k), (float)memory_size_k / (1024.0f * 1024.0f),
                ggml_type_name(type_v), (float)memory_size_v / (1024.0f * 1024.0f));
    }

    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        n_embd_head_k_all = other->n_embd_head_k_all;
        n_embd_head_v_all = other->n_embd_head_v_all;

        attn_rot_k = other->attn_rot_k;
        attn_rot_v = other->attn_rot_v;
    } else {
        const char * LLAMA_ATTN_ROT_DISABLE = getenv("LLAMA_ATTN_ROT_DISABLE");
        const bool attn_rot_disable = LLAMA_ATTN_ROT_DISABLE ? atoi(LLAMA_ATTN_ROT_DISABLE) : false;
        if (attn_rot_disable) {
            LLAMA_LOG_WARN("%s: attention rotation force disabled (LLAMA_ATTN_ROT_DISABLE)\n", __func__);
        }

        attn_rot_k =
            !attn_rot_disable &&
            n_embd_head_k_all > 0 &&
            ggml_is_quantized(type_k) &&
            hparams.n_embd_head_k() % 64 == 0;

        // always create Hadamard rotation tensors for DeepSeek lightning indexers
        if ((model.arch == LLM_ARCH_DEEPSEEK32 || model.arch == LLM_ARCH_DEEPSEEK4 ||
                model.arch == LLM_ARCH_GLM_DSA || model.arch == LLM_ARCH_DOTS3NOTE) &&
                hparams.n_embd_head_k_full == hparams.indexer_head_size) {
            attn_rot_k = true;
        }

        attn_rot_v =
            !attn_rot_disable &&
            n_embd_head_v_all > 0 &&
            ggml_is_quantized(type_v) &&
            hparams.n_embd_head_v() % 64 == 0;
    }

    LLAMA_LOG_INFO("%s: attn_rot_k = %d, n_embd_head_k_all = %d\n", __func__, attn_rot_k, n_embd_head_k_all);
    LLAMA_LOG_INFO("%s: attn_rot_v = %d, n_embd_head_k_all = %d\n", __func__, attn_rot_v, n_embd_head_v_all);

    // pre-compute the haramard matrices and keep them in host memory
    // TODO: in the future, we can make copies in the backend buffers to avoid host -> device transfers
    if (attn_rot_k || attn_rot_v) {
        for (int64_t n = 64; n <= std::max(n_embd_head_k_all, n_embd_head_v_all); n *= 2) {
            attn_rot_hadamard[n] = std::vector<float>(n*n);

            ggml_init_params params = {
                /* .mem_size   = */ 1*ggml_tensor_overhead(),
                /* .mem_buffer = */ nullptr,
                /* .no_alloc   = */ true,
            };

            ggml_context_ptr ctx { ggml_init(params) };

            ggml_tensor * tmp = ggml_new_tensor_2d(ctx.get(), GGML_TYPE_F32, n, n);
            tmp->data = attn_rot_hadamard[n].data();

            ggml_gen_hadamard(tmp);
        }
    }

    const char * LLAMA_KV_CACHE_DEBUG = getenv("LLAMA_KV_CACHE_DEBUG");
    debug = LLAMA_KV_CACHE_DEBUG ? atoi(LLAMA_KV_CACHE_DEBUG) : 0;
}

void llama_kv_cache::clear(bool data) {
    for (uint32_t s = 0; s < n_stream; ++s) {
        v_cells[s].reset();
        v_heads[s] = 0;
    }

    if (data) {
        for (auto & [_, buf] : ctxs_bufs) {
            ggml_backend_buffer_clear(buf.get(), 0);
        }
    }
}

bool llama_kv_cache::seq_rm(llama_seq_id seq_id, llama_pos p0, llama_pos p1) {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return true;
    }

    // TODO: fix incosistent handling of `seq_id < 0` and `seq_id == -1` in the codebase [TAG_LLAMA_SEQ_ID_NEG]
    GGML_ASSERT(seq_id == -1 || (seq_id >= 0 && (size_t) seq_id < seq_to_stream.size()));

    if (p0 < 0) {
        p0 = 0;
    }

    if (p1 < 0) {
        p1 = std::numeric_limits<llama_pos>::max();
    }

    if (seq_id >= 0) {
        auto & cells = v_cells[seq_to_stream[seq_id]];
        auto & head  = v_heads[seq_to_stream[seq_id]];

        uint32_t new_head = cells.size();

        for (uint32_t i = 0; i < cells.size(); ++i) {
            if (!cells.pos_in(i, p0, p1)) {
                continue;
            }

            if (cells.seq_has(i, seq_id) && cells.seq_rm(i, seq_id)) {
                if (new_head == cells.size()) {
                    new_head = i;
                }
            }
        }

        // If we freed up a slot, set head to it so searching can start there.
        if (new_head != cells.size() && new_head < head) {
            head = new_head;
        }
    } else {
        // match any sequence
        for (uint32_t s = 0; s < n_stream; ++s) {
            auto & cells = v_cells[s];
            auto & head  = v_heads[s];

            uint32_t new_head = cells.size();

            for (uint32_t i = 0; i < cells.size(); ++i) {
                if (!cells.pos_in(i, p0, p1)) {
                    continue;
                }

                cells.rm(i);

                if (new_head == cells.size()) {
                    new_head = i;
                }
            }

            // If we freed up a slot, set head to it so searching can start there.
            if (new_head != cells.size() && new_head < head) {
                head = new_head;
            }
        }
    }

    return true;
}

void llama_kv_cache::seq_cp(llama_seq_id seq_id_src, llama_seq_id seq_id_dst, llama_pos p0, llama_pos p1) {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return;
    }

    GGML_ASSERT(seq_id_src >= 0 && (size_t) seq_id_src < seq_to_stream.size());
    GGML_ASSERT(seq_id_dst >= 0 && (size_t) seq_id_dst < seq_to_stream.size());

    const auto s0 = seq_to_stream[seq_id_src];
    const auto s1 = seq_to_stream[seq_id_dst];

    if (s0 == s1) {
        // since both sequences are in the same stream, no data copy is necessary
        // we just have to update the cells meta data

        auto & cells = v_cells[s0];

        if (seq_id_src == seq_id_dst) {
            return;
        }

        if (p0 < 0) {
            p0 = 0;
        }

        if (p1 < 0) {
            p1 = std::numeric_limits<llama_pos>::max();
        }

        for (uint32_t i = 0; i < cells.size(); ++i) {
            if (!cells.pos_in(i, p0, p1)) {
                continue;
            }

            if (cells.seq_has(i, seq_id_src)) {
                cells.seq_add(i, seq_id_dst);
            }
        }

        return;
    }

    // cross-stream sequence copies require to copy the actual buffer data

    bool is_full = true;

    if (p0 > 0 && p0 + 1 < (int) get_size()) {
        is_full = false;
    }

    if (p1 > 0 && p1 + 1 < (int) get_size()) {
        is_full = false;
    }

    GGML_ASSERT(is_full && "seq_cp() is only supported for full KV buffers");

    // enqueue the copy operation - the buffer copy will be performed during the next update
    sc_info.ssrc.push_back(s0);
    sc_info.sdst.push_back(s1);

    v_cells[s1].reset();
    for (uint32_t i = 0; i < v_cells[s0].size(); ++i) {
        if (v_cells[s0].seq_has(i, seq_id_src)) {
            llama_pos pos   = v_cells[s0].pos_get(i);
            llama_pos shift = v_cells[s0].get_shift(i);

            llama_kv_cell_ext ext = v_cells[s0].ext_get(i);

            if (shift != 0) {
                pos -= shift;
                assert(pos >= 0);
            }

            v_cells[s1].pos_set(i, pos);
            v_cells[s1].seq_add(i, seq_id_dst);

            if (shift != 0) {
                v_cells[s1].pos_add(i, shift);
            }

            v_cells[s1].ext_set(i, ext);
        }
    }

    v_heads[s1] = v_heads[s0];

    //for (uint32_t s = 0; s < n_stream; ++s) {
    //    LLAMA_LOG_WARN("%s: seq %d: min = %d, max = %d\n", __func__, s, v_cells[s].seq_pos_min(s), v_cells[s].seq_pos_max(s));
    //}
}

void llama_kv_cache::seq_keep(llama_seq_id seq_id) {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return;
    }

    GGML_ASSERT(seq_id >= 0 && (size_t) seq_id < seq_to_stream.size());

    auto & cells = v_cells[seq_to_stream[seq_id]];
    auto & head  = v_heads[seq_to_stream[seq_id]];

    uint32_t new_head = cells.size();

    for (uint32_t i = 0; i < cells.size(); ++i) {
        if (cells.seq_keep(i, seq_id)) {
            if (new_head == cells.size()) {
                new_head = i;
            }
        }
    }

    // If we freed up a slot, set head to it so searching can start there.
    if (new_head != cells.size() && new_head < head) {
        head = new_head;
    }
}

void llama_kv_cache::seq_add(llama_seq_id seq_id, llama_pos p0, llama_pos p1, llama_pos shift) {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return;
    }

    GGML_ASSERT(seq_id >= 0 && (size_t) seq_id < seq_to_stream.size());
    GGML_ASSERT(hparams.n_pos_per_embd() == 1 && "seq_add() is only supported for n_pos_per_embd() == 1");

    auto & cells = v_cells[seq_to_stream[seq_id]];
    auto & head  = v_heads[seq_to_stream[seq_id]];

    if (shift == 0) {
        return;
    }

    uint32_t new_head = cells.size();

    if (p0 < 0) {
        p0 = 0;
    }

    if (p1 < 0) {
        p1 = std::numeric_limits<llama_pos>::max();
    }

    // If there is no range then return early to avoid looping over all cells.
    if (p0 == p1) {
        return;
    }

    for (uint32_t i = 0; i < cells.size(); ++i) {
        if (!cells.pos_in(i, p0, p1)) {
            continue;
        }

        if (cells.seq_has(i, seq_id)) {
            if (cells.pos_add(i, shift)) {
                if (new_head == cells.size()) {
                    new_head = i;
                }
            }
        }
    }

    // If we freed up a slot, set head to it so searching can start there.
    // Otherwise we just start the next search from the beginning.
    head = new_head != cells.size() ? new_head : 0;
}

void llama_kv_cache::seq_div(llama_seq_id seq_id, llama_pos p0, llama_pos p1, int d) {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return;
    }

    GGML_ASSERT(seq_id >= 0 && (size_t) seq_id < seq_to_stream.size());
    GGML_ASSERT(hparams.n_pos_per_embd() == 1 && "seq_div() is only supported for n_pos_per_embd() == 1");

    auto & cells = v_cells[seq_to_stream[seq_id]];

    if (d == 1) {
        return;
    }

    if (p0 < 0) {
        p0 = 0;
    }

    if (p1 < 0) {
        p1 = std::numeric_limits<llama_pos>::max();
    }

    // If there is no range then return early to avoid looping over the cache.
    if (p0 == p1) {
        return;
    }

    for (uint32_t i = 0; i < cells.size(); ++i) {
        if (!cells.pos_in(i, p0, p1)) {
            continue;
        }

        if (cells.seq_has(i, seq_id)) {
            cells.pos_div(i, d);
        }
    }
}

llama_pos llama_kv_cache::seq_pos_min(llama_seq_id seq_id) const {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return other->seq_pos_min(seq_id);
    }

    GGML_ASSERT(seq_id >= 0 && (size_t) seq_id < seq_to_stream.size());

    const auto & cells = v_cells[seq_to_stream[seq_id]];

    return cells.seq_pos_min(seq_id);
}

llama_pos llama_kv_cache::seq_pos_max(llama_seq_id seq_id) const {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return other->seq_pos_max(seq_id);
    }

    GGML_ASSERT(seq_id >= 0 && (size_t) seq_id < seq_to_stream.size());

    const auto & cells = v_cells[seq_to_stream[seq_id]];

    return cells.seq_pos_max(seq_id);
}

std::map<ggml_backend_buffer_type_t, size_t> llama_kv_cache::memory_breakdown() const {
    std::map<ggml_backend_buffer_type_t, size_t> ret;
    for (const auto & [ctx, buf] : ctxs_bufs) {
        ggml_backend_buffer_type_t buft = ggml_backend_buffer_get_type(buf.get());

        if (hparams.no_alloc) {
            GGML_ASSERT(ggml_backend_buffer_get_base(buf.get()) == nullptr);
            ret[buft] += ggml_backend_alloc_ctx_tensors_from_buft_size(ctx.get(), buft);
        } else {
            // GGML_ASSERT(ggml_backend_buffer_get_base(buf.get()) != nullptr); // multi_buffer does not have a defined base
            ret[buft] += ggml_backend_buffer_get_size(buf.get());
        }
    }

    return ret;
}

llama_memory_context_ptr llama_kv_cache::init_batch(
            llama_batch_allocr & balloc,
            uint32_t n_ubatch,
            bool embd_all) {
    GGML_UNUSED(embd_all);

    do {
        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            auto ubatch = n_stream == 1 ? balloc.split_simple(n_ubatch) : balloc.split_equal(n_ubatch, true, 0);

            if (ubatch.n_tokens == 0) {
                break;
            }

            ubatches.push_back(std::move(ubatch)); // NOLINT
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            // failed to find a suitable split
            break;
        }

        auto sinfos = prepare(ubatches);
        if (sinfos.empty()) {
            break;
        }

        return std::make_unique<llama_kv_cache_context>(
                this, std::move(sinfos), std::move(ubatches));
    } while (false);

    return std::make_unique<llama_kv_cache_context>(LLAMA_MEMORY_STATUS_FAILED_PREPARE);
}

llama_memory_context_ptr llama_kv_cache::init_full() {
    return std::make_unique<llama_kv_cache_context>(this);
}

llama_memory_context_ptr llama_kv_cache::init_update(llama_context * lctx, bool optimize) {
    GGML_UNUSED(optimize);

    bool do_shift = get_has_shift();

    return std::make_unique<llama_kv_cache_context>(this, lctx, do_shift, std::move(sc_info));
}

llama_kv_cache::slot_info_vec_t llama_kv_cache::prepare(const std::vector<llama_ubatch> & ubatches) {
    llama_kv_cache::slot_info_vec_t res;

    struct state_t {
        slot_info sinfo; // slot info for the ubatch

        std::vector<uint32_t> v_heads_old; // old positions of the heads, before placing the ubatch

        std::vector<llama_kv_cells> v_cells; // copy of the old cells, before placing the ubatch
    };

    // remember the old state of the cells so we can restore it in the end
    std::vector<state_t> states;

    bool success = true;

    for (const auto & ubatch : ubatches) {
        // only find a suitable slot for the ubatch. don't modify the cells yet
        const auto sinfo_new = find_slot(ubatch, false);
        if (sinfo_new.empty()) {
            success = false;
            break;
        }

        // remember the position that we found
        res.push_back(sinfo_new);

        // store the old state of the cells in the recovery stack
        {
            state_t state = { sinfo_new, v_heads, {} };

            for (uint32_t s = 0; s < sinfo_new.n_stream(); ++s) {
                auto & cells = v_cells[sinfo_new.strm[s]];

                state.v_cells.push_back(cells.cp(sinfo_new.idxs[s]));
            }

            states.push_back(std::move(state));
        }

        // now emplace the ubatch
        apply_ubatch(sinfo_new, ubatch);
    }

    GGML_ASSERT(!states.empty() || !success);

    // iterate backwards and restore the cells to their original state
    for (auto it = states.rbegin(); it != states.rend(); ++it) {
        const auto & sinfo = it->sinfo;

        for (uint32_t s = 0; s < sinfo.n_stream(); ++s) {
            auto & cells = v_cells[sinfo.strm[s]];
            auto & head  = v_heads[sinfo.strm[s]];

            cells.set(sinfo.idxs[s], it->v_cells[s]);
            head = it->v_heads_old[s];
        }
    }

    if (!success) {
        return {};
    }

    return res;
}

bool llama_kv_cache::update(llama_context * lctx, bool do_shift, const stream_copy_info & sc_info) {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return true;
    }

    bool updated = false;

    auto * sched = lctx->get_sched();

    if (!sc_info.empty()) {
        assert(n_stream > 1 && "stream copy should never happen with a single stream");

        llama_synchronize(lctx);

        const size_t n_copy = sc_info.ssrc.size();

        for (size_t i = 0; i < n_copy; ++i) {
            const auto ssrc = sc_info.ssrc[i];
            const auto sdst = sc_info.sdst[i];

            assert(ssrc < n_stream);
            assert(sdst < n_stream);

            LLAMA_LOG_DEBUG("%s: copying KV buffer: stream %d to stream %d\n", __func__, ssrc, sdst);

            assert(ssrc != sdst);

            for (uint32_t il = 0; il < layers.size(); ++il) {
                const auto & layer = layers[il];

                ggml_backend_tensor_copy(layer.k_stream[ssrc], layer.k_stream[sdst]);

                if (layer.v_stream[ssrc]) {
                    ggml_backend_tensor_copy(layer.v_stream[ssrc], layer.v_stream[sdst]);
                }
            }
        }
    }

    if (do_shift) {
        if (!get_can_shift()) {
            GGML_ABORT("The current KV cache / model configuration does not support K-shift");
        }

        LLAMA_LOG_DEBUG("%s: applying K-shift\n", __func__);

        // apply K-shift if needed
        if (hparams.rope_type != LLAMA_ROPE_TYPE_NONE) {
            ggml_backend_sched_reset(sched);

            auto * res = lctx->get_gf_res_reserve();

            res->reset();

            auto * gf = build_graph_shift(res, lctx);
            if (!ggml_backend_sched_alloc_graph(sched, gf)) {
                LLAMA_LOG_ERROR("%s: failed to allocate compute graph for K-shift\n", __func__);
                return updated;
            }

            res->set_inputs(nullptr);

            if (lctx->graph_compute(gf, false) != GGML_STATUS_SUCCESS) {
                LLAMA_LOG_ERROR("%s: failed to compute K-shift\n", __func__);
                return updated;
            }

            updated = true;
        }

        for (uint32_t s = 0; s < n_stream; ++s) {
            auto & cells = v_cells[s];

            cells.reset_shift();
        }
    }

    return updated;
}

llama_kv_cache::slot_info llama_kv_cache::find_slot(const llama_ubatch & ubatch, bool cont) const {

    if (debug > 0) {
        for (uint32_t s = 0; s < ubatch.n_seqs_unq; ++s) {
            const auto seq_id = ubatch.seq_id_unq[s];
            const auto stream_id = seq_to_stream[seq_id];
            const auto & cells = v_cells[stream_id];
            const uint32_t head_cur = v_heads[stream_id];

            LLAMA_LOG_DEBUG("%s: stream[%d], n = %5d, used = %5d, head = %5d, size = %5d, n_swa = %5d\n",
                    __func__, stream_id, cells.used_max_p1(), cells.get_used(), head_cur, get_size(), n_swa);

            if ((debug == 2 && n_swa > 0) || debug > 2) {
                std::string ss;
                for (uint32_t i = 0; i < cells.size(); ++i) {
                    if (cells.is_empty(i)) {
                        ss += '.';
                    } else {
                        assert(cells.seq_count(i) >= 1);

                        if (cells.seq_count(i) == 1) {
                            ss += std::to_string(cells.seq_get(i));
                        } else {
                            ss += 'M';
                        }
                    }
                    if (i%256 == 255) {
                        ss += " *";
                        ss += '\n';
                    }
                }
                LLAMA_LOG_DEBUG("\n%s\n", ss.c_str());
            }

            if ((debug == 2 && n_swa > 0) || debug > 2) {
                std::string ss;
                for (uint32_t i = 0; i < cells.size(); ++i) {
                    std::string cur;
                    if (cells.is_empty(i)) {
                        cur = '.';
                    } else {
                        cur = std::to_string(cells.pos_get(i));
                    }
                    const int n = cur.size();
                    for (int j = 0; j < 5 - n; ++j) {
                        cur += ' ';
                    }
                    ss += cur;
                    if (i%256 == 255) {
                        ss += " *";
                    }
                    if (i%64 == 63) {
                        ss += '\n';
                    }
                }
                LLAMA_LOG_DEBUG("\n%s\n", ss.c_str());
            }

            for (int s = 0; s < LLAMA_MAX_SEQ; ++s) {
                if (cells.seq_pos_min(s) < 0) {
                    continue;
                }

                LLAMA_LOG_DEBUG("%s: stream[%d] min[%d] = %5d, max[%d] = %5d\n", __func__, stream_id, s, cells.seq_pos_min(s), s, cells.seq_pos_max(s));
            }
        }
    }

    uint32_t n_tokens = ubatch.n_tokens;
    uint32_t n_seqs   = 1;

    if (n_stream > 1) {
        GGML_ASSERT(n_tokens % ubatch.n_seqs_unq == 0);

        n_seqs   = ubatch.n_seqs_unq;
        n_tokens = n_tokens / n_seqs;
    }

    slot_info res = {
        /*.s0   =*/ LLAMA_MAX_SEQ,
        /*.s1   =*/ 0,
        /*.strm =*/ { },
        /*.idxs =*/ { },
    };

    res.resize(n_seqs);

    for (uint32_t s = 0; s < n_seqs; ++s) {
        const auto seq_id = ubatch.seq_id_unq[s];

        if (n_stream > 1) {
            GGML_ASSERT(ubatch.n_seq_id[s*n_tokens]    == 1);
            GGML_ASSERT(ubatch.seq_id  [s*n_tokens][0] == seq_id);
        }

        res.s0 = std::min<uint32_t>(res.s0, seq_to_stream[seq_id]);
        res.s1 = std::max<uint32_t>(res.s1, seq_to_stream[seq_id]);

        res.strm[s] = seq_to_stream[seq_id];
        res.idxs[s].reserve(n_tokens);

        const auto & cells = v_cells[seq_to_stream[seq_id]];

        uint32_t head_cur = v_heads[seq_to_stream[seq_id]];

        // if we have enough unused cells before the current head ->
        //   better to start searching from the beginning of the cache, hoping to fill it
        if (head_cur > cells.get_used() + 2*n_tokens) {
            head_cur = 0;
        }

        if (n_tokens > cells.size()) {
            LLAMA_LOG_ERROR("%s: n_tokens = %d > size = %u\n", __func__, n_tokens, cells.size());
            return { };
        }

        uint32_t n_tested = 0;

        // for continuous slots, we test that all tokens in the ubatch fit, starting from the current head
        // for non-continuous slots, we test the tokens one by one
        const uint32_t n_test = cont ? n_tokens : 1;

        while (true) {
            if (head_cur + n_test > cells.size()) {
                n_tested += cells.size() - head_cur;
                head_cur = 0;
                continue;
            }

            for (uint32_t i = 0; i < n_test; i++) {
                const auto idx = head_cur;

                head_cur++;
                n_tested++;

                //const llama_pos    pos    = ubatch.pos[i];
                //const llama_seq_id seq_id = ubatch.seq_id[i][0];

                // can we use this cell? either:
                //  - the cell is empty
                //  - the cell is occupied only by one sequence:
                //    - (disabled) mask causally, if the sequence is the same as the one we are inserting
                //    - mask SWA, using current max pos for that sequence in the cache
                //                always insert in the cell with minimum pos
                bool can_use = cells.is_empty(idx);

                if (!can_use && cells.seq_count(idx) == 1) {
                    const llama_pos pos_cell = cells.pos_get(idx);

                    // (disabled) causal mask
                    // note: it's better to purge any "future" tokens beforehand
                    //if (cells.seq_has(idx, seq_id)) {
                    //    can_use = pos_cell >= pos;
                    //}

                    if (!can_use) {
                        const llama_seq_id seq_id_cell = cells.seq_get(idx);

                        // SWA mask
                        if (llama_hparams::is_masked_swa(n_swa, swa_type, pos_cell, cells.seq_pos_max(seq_id_cell) + 1)) {
                            can_use = true;
                        }
                    }
                }

                if (can_use) {
                    res.idxs[s].push_back(idx);
                } else {
                    if (cont) {
                        break;
                    }
                }
            }

            if (res.idxs[s].size() == n_tokens) {
                break;
            }

            if (cont) {
                res.idxs[s].clear();
            }

            if (n_tested >= cells.size()) {
                //LLAMA_LOG_ERROR("%s: failed to find a slot for %d tokens\n", __func__, n_tokens);
                return { };
            }
        }

        // we didn't find a suitable slot - return empty result
        if (res.idxs[s].size() < n_tokens) {
            return { };
        }
    }

    assert(res.s1 >= res.s0);

    return res;
}

void llama_kv_cache::apply_ubatch(const slot_info & sinfo, const llama_ubatch & ubatch) {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return;
    }

    // keep track of the max sequence position that we would overwrite with this ubatch
    // for non-SWA cache, this would be always empty
    llama_seq_id seq_pos_max_rm[LLAMA_MAX_SEQ];
    for (uint32_t s = 0; s < LLAMA_MAX_SEQ; ++s) {
        seq_pos_max_rm[s] = -1;
    }

    assert(ubatch.n_tokens == sinfo.n_stream()*sinfo.size());

    for (uint32_t s = 0; s < sinfo.n_stream(); ++s) {
        for (uint32_t ii = 0; ii < sinfo.size(); ++ii) {
            const uint32_t i = s*sinfo.size() + ii;

            auto & cells = v_cells[sinfo.strm[s]];

            const auto idx = sinfo.idxs[s][ii];

            if (!cells.is_empty(idx)) {
                assert(cells.seq_count(idx) == 1);

                const llama_seq_id seq_id = cells.seq_get(idx);
                const llama_pos    pos    = cells.pos_get(idx);

                seq_pos_max_rm[seq_id] = std::max(seq_pos_max_rm[seq_id], pos);

                cells.rm(idx);
            }

            cells.pos_set(idx, ubatch.pos[i]);

            if (ubatch.is_pos_2d() || ubatch.token || hparams.ple_n_heads > 0) {
                llama_kv_cell_ext ext;

                if (ubatch.is_pos_2d()) {
                    ext.x = ubatch.pos[i + ubatch.n_tokens*2];
                    ext.y = ubatch.pos[i + ubatch.n_tokens];
                }

                if (ubatch.token) {
                    ext.tok = ubatch.token[i];
                } else if (hparams.ple_n_heads > 0) {
                    // embd batch (multimodal input) has no token ids, need to pad it with the correct ID for PLE layers
                    // TODO @ngxson : check if we can do the same as gemma 3n / gemma 4
                    ext.tok = hparams.ple_image_token_id != 0
                        ? (llama_token) hparams.ple_image_token_id
                        : (llama_token) hparams.ple_eos_token_id;
                }

                cells.ext_set(idx, ext);
            }

            for (int32_t s = 0; s < ubatch.n_seq_id[i]; s++) {
                cells.seq_add(idx, ubatch.seq_id[i][s]);
            }
        }
    }

    // note: we want to preserve the invariant that all positions between [pos_min, pos_max] for each sequence
    //       will be present in the cache. so we have to purge any position which is less than those we would overwrite
    //       ref: https://github.com/ggml-org/llama.cpp/pull/13746#issuecomment-2916057092
    for (uint32_t s = 0; s < LLAMA_MAX_SEQ; ++s) {
        if (seq_pos_max_rm[s] == -1) {
            continue;
        }

        GGML_ASSERT(s < seq_to_stream.size());

        auto & cells = v_cells[seq_to_stream[s]];

        if (cells.seq_pos_min(s) <= seq_pos_max_rm[s]) {
            LLAMA_LOG_DEBUG("%s: purging positions [%d, %d] of sequence %d from KV cache\n",
                    __func__, cells.seq_pos_min(s), seq_pos_max_rm[s], s);

            seq_rm(s, cells.seq_pos_min(s), seq_pos_max_rm[s] + 1);
        }
    }

    // move the head at the end of the slot
    for (uint32_t s = 0; s < sinfo.n_stream(); ++s) {
        auto & head = v_heads[sinfo.strm[s]];

        head = sinfo.idxs[s].back() + 1;
    }
}

bool llama_kv_cache::get_can_shift() const {
    // Step35 uses per-layer RoPE dims; K-shift assumes a single global n_rot.
    if (model.arch == LLM_ARCH_STEP35) {
        return false;
    }
    if (hparams.n_pos_per_embd() > 1) {
        return false;
    }
    return true;
}

uint32_t llama_kv_cache::get_size() const {
    const auto & cells = v_cells[seq_to_stream[0]];

    return cells.size();
}

uint32_t llama_kv_cache::get_n_stream() const {
    return n_stream;
}

bool llama_kv_cache::get_has_shift() const {
    bool result = false;

    for (uint32_t s = 0; s < n_stream; ++s) {
        result |= v_cells[s].get_has_shift();
    }

    return result;
}

ggml_type llama_kv_cache::type_k() const {
    return layers[0].k->type;
}

ggml_type llama_kv_cache::type_v() const {
    return layers[0].v->type;
}

std::vector<uint32_t> llama_kv_cache::get_layer_ids() const {
    std::vector<uint32_t> res;
    res.reserve(layers.size());

    for (const auto & layer : layers) {
        res.push_back(layer.il);
    }

    return res;
}

ggml_tensor * llama_kv_cache::get_k_storage(int32_t il) const {
    const int32_t ikv = map_layer_ids.at(il);

    return layers[ikv].k;
}

const llama_kv_cells & llama_kv_cache::get_cells(llama_seq_id seq_id) const {
    GGML_ASSERT(seq_id >= 0 && (size_t) seq_id < seq_to_stream.size());

    return v_cells[seq_to_stream[seq_id]];
}

uint32_t llama_kv_cache::get_n_kv(const slot_info & sinfo) const {
    uint32_t result = 0;

    // pad the n_kv value so that the graph remains constant across batches and can be reused
    // note: this also helps some backends with performance (f.ex https://github.com/ggml-org/llama.cpp/pull/16812#issuecomment-3455112220)
    const uint32_t n_pad_cur = std::max(n_pad, 256u);

    for (uint32_t s = 0; s < sinfo.n_stream(); ++s) {
        const auto & cells = v_cells[sinfo.strm[s]];

        result = std::max(std::min(cells.size(), std::max(n_pad_cur, GGML_PAD(cells.used_max_p1(), n_pad_cur))), result);
    }

    return result;
}

ggml_tensor * llama_kv_cache::get_k(ggml_context * ctx, int32_t il, uint32_t n_kv, const slot_info & sinfo) const {
    const int32_t ikv = map_layer_ids.at(il);

    auto * k = layers[ikv].k;

    const uint64_t kv_size      = get_size();
    const uint64_t n_embd_k_gqa = k->ne[0];

    assert(n_embd_k_gqa == hparams.n_embd_k_gqa(il));

    const uint32_t ns = sinfo.s1 - sinfo.s0 + 1;

    return ggml_view_4d(ctx, k,
            hparams.n_embd_head_k(il), hparams.n_head_kv(il), n_kv, ns,
            ggml_row_size(k->type, hparams.n_embd_head_k(il)),
            ggml_row_size(k->type, n_embd_k_gqa),
            ggml_row_size(k->type, n_embd_k_gqa*kv_size),
            ggml_row_size(k->type, n_embd_k_gqa*kv_size)*sinfo.s0);
}

ggml_tensor * llama_kv_cache::get_v(ggml_context * ctx, int32_t il, uint32_t n_kv, const slot_info & sinfo) const {
    const int32_t ikv = map_layer_ids.at(il);

    auto * v = layers[ikv].v;

    const uint64_t kv_size      = get_size();
    const uint64_t n_embd_v_gqa = v->ne[0];

    // [TAG_V_CACHE_VARIABLE]
    assert(n_embd_v_gqa >= hparams.n_embd_v_gqa(il));

    const uint32_t ns = sinfo.s1 - sinfo.s0 + 1;

    if (!v_trans) {
        // note: v->nb[1] <= v->nb[2]
        return ggml_view_4d(ctx, v,
                hparams.n_embd_head_v(il), hparams.n_head_kv(il), n_kv, ns,
                ggml_row_size(v->type, hparams.n_embd_head_v(il)),          // v->nb[1]
                ggml_row_size(v->type, n_embd_v_gqa),                   // v->nb[2]
                ggml_row_size(v->type, n_embd_v_gqa*kv_size),           // v->nb[3]
                ggml_row_size(v->type, n_embd_v_gqa*kv_size)*sinfo.s0);
    }

    // note: v->nb[1] > v->nb[2]
    return ggml_view_4d(ctx, v,
            n_kv, hparams.n_head_kv(il), hparams.n_embd_head_v(il), ns,
            ggml_row_size(v->type, kv_size*hparams.n_embd_head_v(il)),  // v->nb[1]
            ggml_row_size(v->type, kv_size),                        // v->nb[2]
            ggml_row_size(v->type, kv_size*n_embd_v_gqa),           // v->nb[3]
            ggml_row_size(v->type, kv_size*n_embd_v_gqa)*sinfo.s0);
}

ggml_tensor * llama_kv_cache::cpy_k(ggml_context * ctx, ggml_tensor * k_cur, ggml_tensor * k_idxs, int32_t il, const slot_info & sinfo) const {
    GGML_UNUSED(sinfo);

    const int32_t ikv = map_layer_ids.at(il);

    ggml_tensor * k = layers[ikv].k;

    const int64_t n_embd_head = k_cur->ne[0];
    const int64_t n_head      = k_cur->ne[1];
    const int64_t n_tokens    = k_cur->ne[2];

    const int64_t n_embd_gqa = n_embd_head*n_head;

    // we can merge dims 0 and 1
    // TODO: add ggml helper function for this?
    GGML_ASSERT(ggml_row_size(k_cur->type, n_embd_head) == k_cur->nb[1]);

    k_cur = ggml_view_2d(ctx, k_cur, n_embd_gqa, n_tokens, k_cur->nb[2], 0);

    const int64_t n_stream = k->ne[2];

    if (n_stream > 1) {
        const int64_t kv_size = get_size();

        assert(n_embd_gqa == k->ne[0]);
        assert(kv_size    == k->ne[1]);

        // merge the buffer across all streams because the idxs are global
        k = ggml_reshape_2d(ctx, k, n_embd_gqa, kv_size*n_stream);
    }

    // store the current K values into the cache
    return ggml_set_rows(ctx, k, k_cur, k_idxs);
}

ggml_tensor * llama_kv_cache::cpy_v(ggml_context * ctx, ggml_tensor * v_cur, ggml_tensor * v_idxs, int32_t il, const slot_info & sinfo) const {
    GGML_UNUSED(sinfo);

    const int32_t ikv = map_layer_ids.at(il);

    auto * v = layers[ikv].v;

    const int64_t n_embd_head = v_cur->ne[0];
    const int64_t n_head      = v_cur->ne[1];
    const int64_t n_tokens    = v_cur->ne[2];

    const int64_t n_embd_gqa = n_embd_head*n_head;

    // we can merge dims 0 and 1
    GGML_ASSERT(ggml_row_size(v_cur->type, n_embd_head) == v_cur->nb[1]);

    const int64_t n_stream = v->ne[2];

    // take this branch when FA is enabled (the V cache is not transposed)
    if (!v_trans) {
        v_cur = ggml_view_2d(ctx, v_cur, n_embd_gqa, n_tokens, v_cur->nb[2], 0);

        if (n_stream > 1) {
            const int64_t kv_size = get_size();

            assert(n_embd_gqa == v->ne[0]);
            assert(kv_size    == v->ne[1]);

            // merge the buffer across all streams because the idxs are global
            v = ggml_reshape_2d(ctx, v, n_embd_gqa, kv_size*n_stream);
        }

        return ggml_set_rows(ctx, v, v_cur, v_idxs);
    }

    if (ggml_row_size(v_cur->type, n_embd_gqa) == v_cur->nb[2]) {
        // we can merge dims 0, 1 and 2
        v_cur = ggml_reshape_2d(ctx, v_cur, n_embd_gqa, n_tokens);
    } else {
        // otherwise -> make a copy to get contiguous data
        v_cur = ggml_cont_2d   (ctx, v_cur, n_embd_gqa, n_tokens);
    }

    // [TAG_V_CACHE_VARIABLE]
    if (n_embd_gqa < v->ne[0]) {
        v_cur = ggml_pad(ctx, v_cur, v->ne[0] - n_embd_gqa, 0, 0, 0);
    }

    // in this branch the v_idxs are constructed in such a way that each row is a single head element
    ggml_tensor * v_view = ggml_reshape_2d(ctx, v, 1, ggml_nelements(v));

    v_cur = ggml_reshape_2d(ctx, v_cur, 1, ggml_nelements(v_cur));

    return ggml_set_rows(ctx, v_view, v_cur, v_idxs);
}

ggml_tensor * llama_kv_cache::build_input_k_idxs(ggml_context * ctx, const llama_ubatch & ubatch) const {
    const uint32_t n_tokens = ubatch.n_tokens;

    ggml_tensor * k_idxs = ggml_new_tensor_1d(ctx, GGML_TYPE_I64, n_tokens);

    ggml_set_input(k_idxs);

    return k_idxs;
}

ggml_tensor * llama_kv_cache::build_input_v_idxs(ggml_context * ctx, const llama_ubatch & ubatch) const {
    const uint32_t n_tokens = ubatch.n_tokens;

    ggml_tensor * v_idxs;

    if (!v_trans) {
        v_idxs = ggml_new_tensor_1d(ctx, GGML_TYPE_I64, n_tokens);
    } else {
        v_idxs = ggml_new_tensor_1d(ctx, GGML_TYPE_I64, n_tokens*hparams.n_embd_v_gqa_max());
    }

    ggml_set_input(v_idxs);

    return v_idxs;
}

ggml_tensor * llama_kv_cache::build_input_k_rot(ggml_context * ctx) const {
    ggml_tensor * res = nullptr;

    if (attn_rot_k) {
        int nrot = 64;

        // TODO: investigate if using the smallest rotation matrix is beneficial also for K (similar as for V)
        // ref: https://github.com/ggml-org/llama.cpp/pull/21038#issuecomment-4141323088
        do {
            nrot *= 2;
        } while (n_embd_head_k_all % nrot == 0);
        nrot /= 2;

        res = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, nrot, nrot);
        ggml_set_input(res);
        ggml_set_name(res, "attn_inp_k_rot");
    }

    return res;
}

ggml_tensor * llama_kv_cache::build_input_v_rot(ggml_context * ctx) const {
    ggml_tensor * res = nullptr;

    if (attn_rot_v) {
        int nrot = 64;
        // using smaller rotation matrices for V seems beneficial
        // ref: https://github.com/ggml-org/llama.cpp/pull/21038#issuecomment-4146397570
        //do {
        //    nrot *= 2;
        //} while (hparams.n_embd_head_v() % nrot == 0);
        //nrot /= 2;

        res = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, nrot, nrot);
        ggml_set_input(res);
        ggml_set_name(res, "attn_inp_v_rot");
    }

    return res;
}

void llama_kv_cache::set_input_k_idxs(ggml_tensor * dst, const llama_ubatch * ubatch, const slot_info & sinfo) const {
    const uint32_t n_tokens = ubatch->n_tokens;
    GGML_ASSERT(n_tokens == (int64_t) sinfo.size()*sinfo.n_stream());

    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));
    int64_t * data = (int64_t *) dst->data;

    for (uint32_t s = 0; s < sinfo.n_stream(); ++s) {
        const int64_t offs = sinfo.strm[s]*get_size();

        for (uint32_t i = 0; i < sinfo.size(); ++i) {
            data[s*sinfo.size() + i] = offs + sinfo.idxs[s][i];
        }
    }
}

void llama_kv_cache::set_input_v_idxs(ggml_tensor * dst, const llama_ubatch * ubatch, const slot_info & sinfo) const {
    const uint32_t n_tokens = ubatch->n_tokens;
    GGML_ASSERT(n_tokens == (int64_t) sinfo.size()*sinfo.n_stream());

    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));
    int64_t * data = (int64_t *) dst->data;

    if (!v_trans) {
        for (uint32_t s = 0; s < sinfo.n_stream(); ++s) {
            const int64_t offs = sinfo.strm[s]*get_size();

            for (uint32_t i = 0; i < sinfo.size(); ++i) {
                data[s*sinfo.size() + i] = offs + sinfo.idxs[s][i];
            }
        }
    } else {
        // note: the V cache is transposed when not using flash attention
        const int64_t kv_size = get_size();

        const int64_t n_embd_v_gqa = hparams.n_embd_v_gqa_max();

        for (uint32_t s = 0; s < sinfo.n_stream(); ++s) {
            const int64_t offs = sinfo.strm[s]*kv_size*n_embd_v_gqa;

            for (uint32_t i = 0; i < sinfo.size(); ++i) {
                for (uint32_t j = 0; j < n_embd_v_gqa; ++j) {
                    data[s*sinfo.size()*n_embd_v_gqa + i*n_embd_v_gqa + j] = offs + j*kv_size + sinfo.idxs[s][i];
                }
            }
        }
    }
}

void llama_kv_cache::set_input_k_shift(ggml_tensor * dst) const {
    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));

    int32_t * data = (int32_t *) dst->data;

    for (uint32_t s = 0; s < n_stream; ++s) {
        const auto & cells = v_cells[s];

        for (uint32_t i = 0; i < cells.size(); ++i) {
            data[s*cells.size() + i] = cells.is_empty(i) ? 0 : cells.get_shift(i);
        }
    }
}

struct args_set_input_kq_mask {
    const llama_hparams & hparams;
    const llama_ubatch  * ubatch;

    const std::vector<llama_kv_cells> & v_cells;
    const std::vector<uint32_t>       & seq_to_stream;

    uint32_t       n_swa;
    llama_swa_type swa_type;

    int64_t n_kv;
    int64_t n_stream;
    int64_t n_tps;
};

template<typename T, bool causal, bool swa, bool is_2d, bool alibi>
static void set_input_kq_mask_impl(const args_set_input_kq_mask & args, T * data) {
  //const auto & hparams = args.hparams;
    const auto & ubatch  = args.ubatch;

    const auto & v_cells       = args.v_cells;
    const auto & seq_to_stream = args.seq_to_stream;

    const uint32_t       n_swa    = args.n_swa;
    const llama_swa_type swa_type = args.swa_type;

    const int64_t n_kv     = args.n_kv;
    const int64_t n_stream = args.n_stream;
    const int64_t n_tps    = args.n_tps;

    const T mask_keep = llama_cast<T>(0.0f);
    const T mask_drop = llama_cast<T>(-INFINITY);

    // the min position in the batch for each sequence
    llama_pos seq_pos_min[LLAMA_MAX_SEQ];
    std::fill(seq_pos_min, seq_pos_min + LLAMA_MAX_SEQ, INT32_MAX);

    for (uint32_t i = 0; i < ubatch->n_tokens; ++i) {
        const llama_seq_id seq_id = ubatch->seq_id[i][0];

        seq_pos_min[seq_id] = std::min(seq_pos_min[seq_id], ubatch->pos[i]);
    }

    for (uint32_t s = 0; s < n_stream; ++s) {
        // bookkeeping of the KQ mask cells that could change for other tokens of the same sequence
        std::unordered_map<llama_seq_id, uint32_t>              seq_srct;
        std::unordered_map<llama_seq_id, std::vector<uint32_t>> seq_idxs;

        for (uint32_t ii = 0; ii < n_tps; ++ii) {
            const uint32_t i = s*n_tps + ii;

            const llama_seq_id seq_id = ubatch->seq_id[i][0];

            const auto & cells = v_cells.at(seq_to_stream[seq_id]);

                  llama_pos p0 = -1;
            const llama_pos p1 = ubatch->pos[i];

            // for M-RoPE
            const llama_pos p1_x = is_2d ? ubatch->pos[i + ubatch->n_tokens*2] : 0;
            const llama_pos p1_y = is_2d ? ubatch->pos[i + ubatch->n_tokens]   : 0;

            const uint64_t idst = n_kv*i;

            // for tokens of the same sequence, the mask is mostly the same, so we can reuse it
            // the only cells that could change are the ones that are with similar positions as the
            //   ones in the batch (i.e. due to causal masking, SWA, etc.)
            // keep track of those cells and shortcut the loop to save time
            // note: this optimization is not compatible with Alibi position encoding
            // ref:  https://github.com/ggml-org/llama.cpp/pull/18842
            bool prev = false;

            auto & idxs = seq_idxs[seq_id];

            if (!alibi) {
                if (seq_srct.find(seq_id) != seq_srct.end()) {
                    const uint32_t srct = seq_srct[seq_id];

                    const uint64_t idst_prev = n_kv*srct;

                    std::copy(data + idst_prev, data + idst_prev + n_kv, data + idst);

                    prev = true;
                } else {
                    idxs.clear();
                    idxs.reserve(ubatch->n_tokens + n_swa + 32);

                    seq_srct[seq_id] = i;
                }
            }

            for (uint32_t jj = 0; jj < n_kv; ++jj) {
                uint32_t j = jj;

                // we have an exiting mask for this sequence -> update just seq_idxs
                if (!alibi) {
                    if (prev) {
                        if (jj >= idxs.size()) {
                            break;
                        }

                        j = idxs[jj];
                    }
                }

                if (cells.is_empty(j)) {
                    goto skip;
                }

                // mask the token if not the same sequence
                if (!cells.seq_has(j, seq_id)) {
                    goto skip;
                }

                p0 = cells.pos_get(j);

                if (!alibi) {
                    if (!prev) {
                        // record all cells for which: p0 >= seq_pos_min[seq_id] - n_swa - 32
                        if (p0 + (int32_t) (n_swa + 32) >= seq_pos_min[seq_id]) {
                            idxs.push_back(j);
                        }
                    }
                }

                if (causal) {
                    // mask future tokens
                    if (p0 > p1) {
                        goto skip;
                    }

                    // M-RoPE causal mask
                    if (is_2d) {
                        if (p0 == p1) {
                            const auto & p0_ext = cells.ext_get(j);

                            if (p0_ext.is_2d_gt(p1_x, p1_y)) {
                                goto skip;
                            }
                        }
                    }
                }

                // apply SWA if any
                if (swa) {
                    // see llama_non_causal_type
                    const bool in_span = !causal && args.hparams.non_causal_type == LLAMA_NON_CAUSAL_TYPE_SWA_FULL && p0 >= seq_pos_min[seq_id];
                    if (!in_span && llama_hparams::is_masked_swa(n_swa, swa_type, p0, p1)) {
                        goto skip;
                    }
                }

                if (alibi) {
                    data[idst + j] = llama_cast<T>(static_cast<float>(-std::abs(p0 - p1)));
                } else {
                    data[idst + j] = mask_keep;
                }

                continue;
skip:
                data[idst + j] = mask_drop;
            }
        }
    }
}

template<typename T, bool causal, bool swa, bool is_2d>
static void set_input_kq_mask_impl(const args_set_input_kq_mask & args, T * data) {
    const bool alibi = args.hparams.use_alibi;
    if (alibi) {
        set_input_kq_mask_impl<T, causal, swa, is_2d, true> (args, data);
    } else {
        set_input_kq_mask_impl<T, causal, swa, is_2d, false>(args, data);
    }
}

template<typename T, bool causal, bool swa>
static void set_input_kq_mask_impl(const args_set_input_kq_mask & args, T * data) {
    const bool is_2d = args.ubatch->is_pos_2d();
    if (is_2d) {
        set_input_kq_mask_impl<T, causal, swa, true> (args, data);
    } else {
        set_input_kq_mask_impl<T, causal, swa, false>(args, data);
    }
}

template<typename T, bool causal>
static void set_input_kq_mask_impl(const args_set_input_kq_mask & args, T * data) {
    const bool swa = args.swa_type != LLAMA_SWA_TYPE_NONE;
    if (swa) {
        set_input_kq_mask_impl<T, causal, true> (args, data);
    } else {
        set_input_kq_mask_impl<T, causal, false>(args, data);
    }
}

template<typename T>
static void set_input_kq_mask_impl(const args_set_input_kq_mask & args, T * data, bool causal_attn) {
    if (causal_attn) {
        set_input_kq_mask_impl<T, true> (args, data);
    } else {
        set_input_kq_mask_impl<T, false>(args, data);
    }
}

void llama_kv_cache::set_input_kq_mask(ggml_tensor * dst, const llama_ubatch * ubatch, bool causal_attn) const {
    const uint32_t n_tokens = ubatch->n_tokens;

    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));

    const int64_t n_kv     = dst->ne[0];
    const int64_t n_stream = dst->ne[3]; // num streams in the current ubatch

    GGML_ASSERT(n_tokens%n_stream == 0);

    // n_tps == n_tokens_per_stream
    const int64_t n_tps = n_tokens/n_stream;

    // see llama_non_causal_type
    // only the SWA cache (or the SWA layers of a single cache) become non-causal
    if (!causal_attn && hparams.non_causal_type == LLAMA_NON_CAUSAL_TYPE_SWA_ONLY) {
        causal_attn = swa_type == LLAMA_SWA_TYPE_NONE;
    }

    //const int64_t t_start = ggml_time_us();

    const args_set_input_kq_mask args = {
        /*.hparams          =*/ hparams,
        /*.ubatch           =*/ ubatch,
        /*.v_cells          =*/ v_cells,
        /*.seq_to_stream    =*/ seq_to_stream,
        /*.n_swa            =*/ n_swa,
        /*.swa_type         =*/ swa_type,
        /*.n_kv             =*/ n_kv,
        /*.n_stream         =*/ n_stream,
        /*.n_tps            =*/ n_tps,
    };

    if (dst->type == GGML_TYPE_F16) {
        set_input_kq_mask_impl<ggml_fp16_t>(args, (ggml_fp16_t *) dst->data, causal_attn);
    } else {
        set_input_kq_mask_impl<float>(args, (float *) dst->data, causal_attn);
    }

    //const int64_t t_end = ggml_time_us();

    //LLAMA_LOG_ERROR("%s: kq mask time: %0.3f ms\n", __func__, (t_end - t_start)/1000.0);
}

void llama_kv_cache::set_input_pos_bucket(ggml_tensor * dst, const llama_ubatch * ubatch) const {
    const int64_t n_tokens = ubatch->n_tokens;

    GGML_ASSERT(n_stream == 1 && "TODO: support multiple streams");
    const auto & cells = v_cells[0];

    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));
    GGML_ASSERT(!ubatch->equal_seqs()); // TODO: use ubatch->n_seqs instead of failing

    int32_t * data = (int32_t *) dst->data;

    const int32_t n_kv = dst->ne[0];

    for (int h = 0; h < 1; ++h) {
        for (int i = 0; i < n_tokens; ++i) {
            for (int j = 0; j < n_kv; ++j) {
                // the position when the cells is empty is irrelevant - it will be masked out later in the attention
                const llama_pos p0 = cells.is_empty(j) ? -1 : cells.pos_get(j);

                data[h*(n_kv*n_tokens) + i*n_kv + j] = llama_relative_position_bucket(p0, ubatch->pos[i], hparams.n_rel_attn_bkts, false);
            }
        }
    }
}

void llama_kv_cache::set_input_k_rot(ggml_tensor * dst) const {
    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));

    const auto n_rot = dst->ne[0];
    GGML_ASSERT(attn_rot_hadamard.count(dst->ne[0]));

    memcpy(dst->data, attn_rot_hadamard.at(n_rot).data(), ggml_nbytes(dst));
}

void llama_kv_cache::set_input_v_rot(ggml_tensor * dst) const {
    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));

    const auto n_rot = dst->ne[0];
    GGML_ASSERT(attn_rot_hadamard.count(dst->ne[0]));

    memcpy(dst->data, attn_rot_hadamard.at(n_rot).data(), ggml_nbytes(dst));
}

bool llama_kv_cache::has_cell_ext() const {
    // M-RoPE needs the 2D position, the PLE n-gram hash needs the token id
    return hparams.n_pos_per_embd() > 1 || hparams.ple_n_heads > 0;
}

void llama_kv_cache::get_prev_tokens(const llama_ubatch & ubatch, uint32_t n, std::vector<llama_token> & res) const {
    const uint32_t n_tokens = ubatch.n_tokens;

    res.clear();
    res.resize(n_tokens*n, LLAMA_TOKEN_NULL);

    if (n == 0) {
        return;
    }

    // note: apply_ubatch() has already stored the current ubatch, so the cells cover the tokens
    //       of this very ubatch as well, which is what we want
    // the nearest cell at or before a position also resolves M-RoPE gaps, where multiple tokens
    // share the same temporal pos

    // an embd (multimodal) ubatch can repeat one position for a whole image, so positions
    // do not encode the token order; resolve its predecessors by ubatch order instead
    std::vector<uint32_t> ord; // index among the ubatch tokens of the same seq
    std::unordered_map<llama_seq_id, std::vector<uint32_t>> seq_idx;

    if (!ubatch.token) {
        ord.resize(n_tokens);
        for (uint32_t i = 0; i < n_tokens; ++i) {
            auto & v = seq_idx[ubatch.seq_id[i][0]];
            ord[i] = v.size();
            v.push_back(i);
        }
    }

    for (uint32_t i = 0; i < n_tokens; ++i) {
        // TODO: a token that belongs to more than one sequence has an ambiguous history.
        //       the n-gram architectures have to reject such batches
        const llama_seq_id seq_id = ubatch.seq_id[i][0];

        for (uint32_t j = 0; j < n; ++j) {
            const llama_pos d = (llama_pos) (n - j);

            llama_pos p;
            if (!ubatch.token) {
                const auto & v = seq_idx[seq_id];
                const int64_t k = (int64_t) ord[i] - d;
                // k >= 0: an earlier token of this very ubatch; k < 0: before the chunk
                p = k >= 0 ? ubatch.pos[v[k]] : ubatch.pos[v[0]] + (llama_pos) k;
            } else {
                p = ubatch.pos[i] - d;
            }

            if (p < 0) {
                continue;
            }

            res[i*n + j] = v_cells[seq_to_stream[seq_id]].seq_pos_tok_le(seq_id, p);
        }
    }
}

size_t llama_kv_cache::total_size() const {
    size_t size = 0;

    for (const auto & [_, buf] : ctxs_bufs) {
        size += ggml_backend_buffer_get_size(buf.get());
    }

    return size;
}

size_t llama_kv_cache::size_k_bytes() const {
    size_t size_k_bytes = 0;

    for (const auto & layer : layers) {
        size_k_bytes += ggml_nbytes(layer.k);
    }

    return size_k_bytes;
}

size_t llama_kv_cache::size_v_bytes() const {
    size_t size_v_bytes = 0;

    for (const auto & layer : layers) {
        size_v_bytes += layer.v ? ggml_nbytes(layer.v) : 0;
    }

    return size_v_bytes;
}

ggml_tensor * llama_kv_cache::build_rope_shift(
        const llama_cparams & cparams,
               ggml_context * ctx,
                ggml_tensor * cur,
                ggml_tensor * shift,
                ggml_tensor * rot,
                ggml_tensor * factors,
                      float   freq_base,
                      float   freq_scale,
                   uint32_t   il) const {
    const auto & n_ctx_orig = cparams.n_ctx_orig_yarn;

    const auto & yarn_ext_factor  = cparams.yarn_ext_factor;
    const auto & yarn_beta_fast   = cparams.yarn_beta_fast;
    const auto & yarn_beta_slow   = cparams.yarn_beta_slow;
    const auto & yarn_attn_factor = cparams.yarn_attn_factor;

    const auto & n_rot     = hparams.n_rot(il);
    const auto & rope_type = hparams.rope_type == LLAMA_ROPE_TYPE_MROPE || hparams.rope_type == LLAMA_ROPE_TYPE_IMROPE
                                // @ngxson : this is a workaround
                                // for M-RoPE, we want to rotate the whole vector when doing KV shift
                                // a normal RoPE should work, we just need to use the correct ordering
                                // ref: https://github.com/ggml-org/llama.cpp/pull/13870
                                ? LLAMA_ROPE_TYPE_NEOX
                                : hparams.rope_type;
    ggml_tensor * tmp;

    if (ggml_is_quantized(cur->type)) {
        // dequantize to f32 -> RoPE -> quantize back
        tmp = ggml_cast(ctx, cur, GGML_TYPE_F32);

        // rotate back
        tmp = llama_mul_mat_hadamard(ctx, tmp, rot);

        tmp = ggml_rope_ext(ctx, tmp,
                shift, factors, n_rot, rope_type, n_ctx_orig, freq_base, freq_scale,
                yarn_ext_factor, yarn_attn_factor, yarn_beta_fast, yarn_beta_slow);

        // rotate fwd
        tmp = llama_mul_mat_hadamard(ctx, tmp, rot);

        tmp = ggml_cpy(ctx, tmp, cur);
    } else {
        // we rotate only the first n_rot dimensions
        tmp = ggml_rope_ext_inplace(ctx, cur,
                shift, factors, n_rot, rope_type, n_ctx_orig, freq_base, freq_scale,
                yarn_ext_factor, yarn_attn_factor, yarn_beta_fast, yarn_beta_slow);
    }

    return tmp;
}

class llm_graph_input_k_shift : public llm_graph_input_i {
public:
    llm_graph_input_k_shift(const llama_kv_cache * kv_self) : kv_self(kv_self) {}
    virtual ~llm_graph_input_k_shift() = default;

    void set_input(const llama_ubatch * ubatch) override;

    ggml_tensor * k_shift; // I32 [kv_size*n_stream]

    // note: assumes k_rot^2 == I
    ggml_tensor * k_rot = nullptr;

    const llama_kv_cache * kv_self;
};

void llm_graph_input_k_shift::set_input(const llama_ubatch * ubatch) {
    GGML_UNUSED(ubatch);

    if (k_shift) {
        kv_self->set_input_k_shift(k_shift);
    }

    if (k_rot && k_rot->buffer) {
        kv_self->set_input_k_rot(k_rot);
    }
}

ggml_cgraph * llama_kv_cache::build_graph_shift(llm_graph_result * res, llama_context * lctx) const {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    GGML_ASSERT(!other);

    auto * ctx = res->get_ctx();
    auto * gf  = res->get_gf();

    auto inp = std::make_unique<llm_graph_input_k_shift>(this);

    inp->k_shift = ggml_new_tensor_1d(ctx, GGML_TYPE_I32, (int64_t) get_size()*n_stream);
    ggml_set_input(inp->k_shift);

    inp->k_rot = build_input_k_rot(ctx);

    const auto & cparams = lctx->get_cparams();

    for (const auto & layer : layers) {
        const uint32_t il = layer.il;

        if (!hparams.has_rope(il)) {
            continue;
        }

        const int64_t n_head_kv    = hparams.n_head_kv(il);
        const int64_t n_embd_k_gqa = hparams.n_embd_k_gqa(il);

        const auto n_rot         = hparams.n_rot(il);
        const auto n_embd_head_k = hparams.n_embd_head_k(il);
        const auto n_embd_nope   = hparams.n_lora_kv > 0 ? n_embd_head_k - n_rot : 0;

        const float freq_base_l  = model.get_rope_freq_base (cparams, il);
        const float freq_scale_l = model.get_rope_freq_scale(cparams, il);

        ggml_tensor * rope_factors = model.get_rope_factors(cparams, il);

        ggml_tensor * k =
            ggml_view_3d(ctx, layer.k,
                n_rot, n_head_kv, get_size()*n_stream,
                ggml_row_size(layer.k->type, n_embd_head_k),
                ggml_row_size(layer.k->type, n_embd_k_gqa),
                ggml_row_size(layer.k->type, n_embd_nope));

        ggml_tensor * cur = build_rope_shift(cparams, ctx, k, inp->k_shift, inp->k_rot, rope_factors, freq_base_l, freq_scale_l, il);

        ggml_build_forward_expand(gf, cur);
    }

    res->add_input(std::move(inp));

    return gf;
}

void llama_kv_cache::state_write(llama_io_write_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) const {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return;
    }

    GGML_UNUSED(flags);

    io.write(&n_stream, sizeof(n_stream));

    for (uint32_t s = 0; s < n_stream; ++s) {
        cell_ranges_t cr { s, {} };

        uint32_t cell_count = 0;

        const auto & cells = v_cells[s];

        // Count the number of cells with the specified seq_id
        // Find all the ranges of cells with this seq id (or all, when -1)
        uint32_t cell_range_begin = cells.size();

        for (uint32_t i = 0; i < cells.size(); ++i) {
            bool add_cell = true;

            add_cell = add_cell && !cells.is_empty(i);
            add_cell = add_cell && (seq_id == -1 || cells.seq_has(i, seq_id));

            // check the cell is not SWA-masked
            if (add_cell && seq_id != -1) {
                const bool is_masked = llama_hparams::is_masked_swa(n_swa, swa_type, cells.pos_get(i), cells.seq_pos_max(seq_id));

                add_cell = !is_masked;
            }

            if (add_cell) {
                ++cell_count;
                if (cell_range_begin == cells.size()) {
                    cell_range_begin = i;
                }
            } else {
                if (cell_range_begin != cells.size()) {
                    cr.data.emplace_back(cell_range_begin, i);
                    cell_range_begin = cells.size();
                }
            }
        }

        if (cell_range_begin != cells.size()) {
            cr.data.emplace_back(cell_range_begin, cells.size());
        }

        // DEBUG CHECK: Sum of cell counts in ranges should equal the total cell count
        uint32_t cell_count_check = 0;
        for (const auto & range : cr.data) {
            cell_count_check += range.second - range.first;
        }
        GGML_ASSERT(cell_count == cell_count_check);

        io.write(&cell_count, sizeof(cell_count));

        // skip empty streams
        if (cell_count == 0) {
            continue;
        }

        state_write_meta(io, cr, seq_id);
        state_write_data(io, cr);
    }
}

void llama_kv_cache::state_read(llama_io_read_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) {
    state_read_sinfo(io, seq_id, flags, nullptr, nullptr);
}

void llama_kv_cache::state_read_sinfo(
        llama_io_read_i & io,
           llama_seq_id   seq_id,
  llama_state_seq_flags   flags,
      slot_info_vec_t *   sinfos_out,
const slot_info_vec_t *   sinfos_in) {
    // TODO: refactor [TAG_KV_CACHE_SHARE_CELLS]
    if (other) {
        return;
    }

    GGML_UNUSED(flags);

    // TODO: fix incosistent handling of `seq_id < 0` and `seq_id == -1` in the codebase [TAG_LLAMA_SEQ_ID_NEG]
    GGML_ASSERT(seq_id == -1 || (seq_id >= 0 && (size_t) seq_id < seq_to_stream.size()));

    if (sinfos_out) {
        sinfos_out->assign(n_stream, slot_info{});
    }

    if (sinfos_in && sinfos_in->size() != n_stream) {
        throw std::runtime_error("failed to restore kv cache: mirrored slot layout has the wrong stream count");
    }

    uint32_t n_stream_cur;
    io.read(&n_stream_cur, sizeof(n_stream_cur));
    if (n_stream_cur != n_stream) {
        throw std::runtime_error("n_stream mismatch");
    }

    // a whole-context restore replaces every stream, so the cache is emptied once here
    // clear() resets all streams at once, so doing it per stream below would keep only the last one
    if (seq_id == -1) {
        clear(true);
    }

    for (uint32_t s = 0; s < n_stream; ++s) {
        uint32_t cell_count;
        io.read(&cell_count, sizeof(cell_count));

        if (cell_count == 0) {
            // a mirrored cache must be empty here as well, or the two no longer agree cell for cell
            if (sinfos_in && !(*sinfos_in)[s].empty()) {
                throw std::runtime_error("failed to restore kv cache: mirrored cache holds cells this one does not");
            }
            continue;
        }

        const uint32_t strm = seq_id == -1 ? s : seq_to_stream[seq_id];

        slot_info sinfo;

        bool res = true;
        res = res && state_read_meta(io, strm, cell_count, sinfo, seq_id, sinfos_in ? &(*sinfos_in)[s] : nullptr);

        try {
            res = res && state_read_data(io, strm, cell_count, sinfo);
        } catch (...) {
            res = false;
        }

        if (!res) {
            if (seq_id == -1) {
                clear(true);
            } else {
                seq_rm(seq_id, -1, -1);
            }
            throw std::runtime_error("failed to restore kv cache");
        }

        if (sinfos_out) {
            (*sinfos_out)[s] = sinfo;
        }
    }
}

void llama_kv_cache::state_write_meta(llama_io_write_i & io, const cell_ranges_t & cr, llama_seq_id seq_id) const {
    const auto & cells = v_cells[cr.strm];

    for (const auto & range : cr.data) {
        for (uint32_t i = range.first; i < range.second; ++i) {
            std::vector<llama_seq_id> seq_ids;

            for (llama_seq_id cur = 0; cur < (int) n_seq_max; ++cur) {
                if (cur == seq_id || seq_id == -1) {
                    if (cells.seq_has(i, cur)) {
                        seq_ids.push_back(cur);
                    }
                }
            }

            const llama_pos pos     = cells.pos_get(i);
            const uint32_t n_seq_id = seq_ids.size();

            io.write(&pos,      sizeof(pos));
            io.write(&n_seq_id, sizeof(n_seq_id));

            if (has_cell_ext()) {
                const llama_kv_cell_ext ext = cells.ext_get(i);
                io.write(&ext, sizeof(ext));
            }

            for (const auto & seq_id : seq_ids) {
                io.write(&seq_id, sizeof(seq_id));
            }
        }
    }
}

void llama_kv_cache::state_write_data(llama_io_write_i & io, const cell_ranges_t & cr) const {
    const auto & cells = v_cells[cr.strm];

    const uint32_t v_trans = this->v_trans ? 1 : 0;
    const uint32_t n_layer = layers.size();

    io.write(&v_trans, sizeof(v_trans));
    io.write(&n_layer, sizeof(n_layer));

    // Iterate and write all the keys first, each row is a cell
    // Get whole range at a time
    for (const auto & layer : layers) {
        const uint32_t il = layer.il;

        const uint32_t n_embd_k_gqa = hparams.n_embd_k_gqa(il);

        auto * k = layer.k_stream[cr.strm];

        // Write key type
        const int32_t k_type_i = (int32_t) k->type;
        io.write(&k_type_i, sizeof(k_type_i));

        // Write row size of key
        const uint64_t k_size_row = ggml_row_size(k->type, n_embd_k_gqa);
        io.write(&k_size_row, sizeof(k_size_row));

        // Read each range of cells of k_size length and write out
        for (const auto & range : cr.data) {
            const size_t range_size = range.second - range.first;
            const size_t buf_size = range_size * k_size_row;
            io.write_tensor(k, range.first * k_size_row, buf_size);
        }
    }

    if (!v_trans) {
        for (const auto & layer : layers) {
            const uint32_t il = layer.il;

            const uint32_t n_embd_v_gqa = hparams.n_embd_v_gqa(il);

            auto * v = layer.v_stream[cr.strm];
            if (!v) {
                continue;
            }

            // Write value type
            const int32_t v_type_i = (int32_t) v->type;
            io.write(&v_type_i, sizeof(v_type_i));

            // Write row size of value
            const uint64_t v_size_row = ggml_row_size(v->type, n_embd_v_gqa);
            io.write(&v_size_row, sizeof(v_size_row));

            // Read each range of cells of v_size length and write out
            for (const auto & range : cr.data) {
                const size_t range_size = range.second - range.first;
                const size_t buf_size = range_size * v_size_row;
                io.write_tensor(v, range.first * v_size_row, buf_size);
            }
        }
    } else {
        // When v is transposed, we also need the element size and get the element ranges from each row
        const uint32_t kv_size = cells.size();

        for (const auto & layer : layers) {
            const uint32_t il = layer.il;

            const uint32_t n_embd_v_gqa = hparams.n_embd_v_gqa(il);

            auto * v = layer.v_stream[cr.strm];
            if (!v) {
                continue;
            }

            // Write value type
            const int32_t v_type_i = (int32_t) v->type;
            io.write(&v_type_i, sizeof(v_type_i));

            // Write element size
            const uint32_t v_size_el = ggml_type_size(v->type);
            io.write(&v_size_el, sizeof(v_size_el));

            // Write GQA embedding size
            io.write(&n_embd_v_gqa, sizeof(n_embd_v_gqa));

            // For each row, we get the element values of each cell
            for (uint32_t j = 0; j < n_embd_v_gqa; ++j) {
                // Read each range of cells of v_size_el length and write out
                for (const auto & range : cr.data) {
                    const size_t range_size = range.second - range.first;
                    const size_t src_offset = (range.first + j * kv_size) * v_size_el;
                    const size_t buf_size = range_size * v_size_el;
                    io.write_tensor(v, src_offset, buf_size);
                }
            }
        }
    }
}

bool llama_kv_cache::state_read_meta(llama_io_read_i & io, uint32_t strm, uint32_t cell_count, slot_info & sinfo, llama_seq_id dest_seq_id, const slot_info * sinfo_in) {
    auto & cells = v_cells[strm];
    auto & head  = v_heads[strm];

    if (dest_seq_id != -1) {
        // single sequence
        seq_rm(dest_seq_id, -1, -1);

        llama_batch_allocr balloc(hparams.n_pos_per_embd());

        llama_ubatch ubatch = balloc.ubatch_reserve(cell_count, 1);

        ubatch.seq_id_unq[0] = dest_seq_id;

        // the ext as it was saved, to put back after apply_ubatch()
        std::vector<llama_kv_cell_ext> exts;
        if (has_cell_ext()) {
            exts.resize(cell_count);
        }

        for (uint32_t i = 0; i < cell_count; ++i) {
            llama_pos pos;
            uint32_t n_seq_id;

            io.read(&pos,      sizeof(pos));
            io.read(&n_seq_id, sizeof(n_seq_id));

            if (n_seq_id != 1) {
                LLAMA_LOG_ERROR("%s: invalid seq_id-agnostic kv cell\n", __func__);
                return false;
            }

            if (has_cell_ext()) {
                llama_kv_cell_ext ext;
                io.read(&ext, sizeof(ext));

                if (hparams.n_pos_per_embd() > 1) {
                    ubatch.pos[i + ubatch.n_tokens]   = ext.y;
                    ubatch.pos[i + ubatch.n_tokens*2] = ext.x;
                }

                // apply_ubatch() below restores ext.tok from the ubatch tokens
                ubatch.token[i] = ext.tok;

                exts[i] = ext;
            }

            // read the sequence id, but directly discard it - we will use dest_seq_id instead
            {
                llama_seq_id seq_id;
                io.read(&seq_id, sizeof(seq_id));
            }

            ubatch.pos[i]      = pos;
            ubatch.n_seq_id[i] = n_seq_id;
            ubatch.seq_id[i]   = &dest_seq_id;
        }

        if (sinfo_in) {
            // this cache mirrors another one, so it takes that cache's layout instead of searching for its own cells
            if (sinfo_in->empty() || sinfo_in->n_stream() != 1 || sinfo_in->idxs[0].size() != cell_count) {
                LLAMA_LOG_ERROR("%s: mirrored slot layout holds %d cells, this cache restores %d\n", __func__,
                        sinfo_in->empty() ? 0 : (int) sinfo_in->idxs[0].size(), cell_count);
                return false;
            }

            sinfo = *sinfo_in;

            // the layout is cell indices, so it means the same in both caches only while their streams line up
            sinfo.s0 = strm;
            sinfo.s1 = strm;
            sinfo.strm[0] = strm;

            // seq_rm above freed exactly the cells this sequence held
            // anything else in the way is a cache that had already drifted, which this restore must not hide
            for (uint32_t i = 0; i < cell_count; ++i) {
                const uint32_t idx = sinfo.idxs[0][i];

                if (idx >= cells.size() || !cells.is_empty(idx)) {
                    LLAMA_LOG_ERROR("%s: cell %u of the mirrored slot layout is not free\n", __func__, idx);
                    return false;
                }
            }
        } else {
            sinfo = find_slot(ubatch, false);
            if (sinfo.empty()) {
                LLAMA_LOG_ERROR("%s: failed to find %d available cells in kv cache\n", __func__,  cell_count);
                return false;
            }
        }

        // note: apply_ubatch() rebuilds llama_kv_cell_ext from the ubatch
        //       only ext.tok and the M-RoPE 2D position round-trip through it
        //       see: https://github.com/ggml-org/llama.cpp/pull/16825#issuecomment-3460868350
        apply_ubatch(sinfo, ubatch);

        // apply_ubatch() takes the 2D position from the ubatch, and that ubatch is built with this
        // cache's own n_pos_per_embd. a cache that does not use M-RoPE itself but mirrors one that
        // does (the qwen4exp QSA indexer) would drop x and y. put the saved ext back instead, which
        // is what the whole-context path below already does.
        for (uint32_t i = 0; i < (uint32_t) exts.size(); ++i) {
            cells.ext_set(sinfo.idxs[0][i], exts[i]);
        }

        LLAMA_LOG_DEBUG("%s: cell_count = %d, dest_seq_id = %d\n", __func__, cell_count, dest_seq_id);

        // DEBUG CHECK: verify that all cells were allocated and have correct seq_id and pos values
        GGML_ASSERT(sinfo.n_stream() == 1);
        GGML_ASSERT(sinfo.idxs[0].size() == cell_count);
        for (uint32_t i = 0; i < cell_count; ++i) {
            const uint32_t idx = sinfo.idxs[0][i];
            GGML_ASSERT(cells.pos_get(idx) == ubatch.pos[i]);
            GGML_ASSERT(cells.seq_has(idx, dest_seq_id));
        }
    } else {
        // whole KV cache restore

        if (cell_count > cells.size()) {
            LLAMA_LOG_ERROR("%s: not enough cells in kv cache\n", __func__);
            return false;
        }

        // the cells go in from 0, so a mirrored cache lands on the same ones as long as it restores the same count. the layout itself carries no more information here
        if (sinfo_in && (sinfo_in->empty() || sinfo_in->n_stream() != 1 || sinfo_in->idxs[0].size() != cell_count)) {
            LLAMA_LOG_ERROR("%s: mirrored slot layout holds %d cells, this cache restores %d\n", __func__,
                    sinfo_in->empty() ? 0 : (int) sinfo_in->idxs[0].size(), cell_count);
            return false;
        }

        for (uint32_t i = 0; i < cell_count; ++i) {
            llama_pos pos;
            uint32_t  n_seq_id;

            io.read(&pos,      sizeof(pos));
            io.read(&n_seq_id, sizeof(n_seq_id));

            cells.pos_set(i, pos);

            if (has_cell_ext()) {
                llama_kv_cell_ext ext;
                io.read(&ext, sizeof(ext));
                cells.ext_set(i, ext);
            }

            for (uint32_t j = 0; j < n_seq_id; ++j) {
                llama_seq_id seq_id;
                io.read(&seq_id, sizeof(seq_id));

                if (seq_id < 0 || (uint32_t) seq_id >= n_seq_max) {
                    LLAMA_LOG_ERROR("%s: invalid seq_id, %d is out of range [0, %u)\n", __func__, seq_id, n_seq_max);
                    return false;
                }

                cells.seq_add(i, seq_id);
            }
        }

        // Create contiguous slot_info for whole cache restore
        sinfo.s0 = strm;
        sinfo.s1 = strm;
        sinfo.resize(1);
        sinfo.strm[0] = strm;
        sinfo.idxs[0].resize(cell_count);
        for (uint32_t i = 0; i < cell_count; ++i) {
            sinfo.idxs[0][i] = i;
        }

        head = 0;
    }

    return true;
}

bool llama_kv_cache::state_read_data(llama_io_read_i & io, uint32_t strm, uint32_t cell_count, const slot_info & sinfo) {
    auto & cells = v_cells[strm];

    // batch the scatter reads per contiguous run of destination indices
    // from inclusive, to exclusive - same convention as cell_ranges_t
    // contiguous cells yield a single run covering the whole block
    struct cell_run { uint32_t from; uint32_t to; };
    std::vector<cell_run> runs;
    if (cell_count > 0) {
        const auto & idxs = sinfo.idxs[0];
        uint32_t i0 = 0;
        while (i0 < cell_count) {
            uint32_t i1 = i0 + 1;
            while (i1 < cell_count && idxs[i1] == idxs[i1 - 1] + 1) {
                ++i1;
            }
            runs.push_back({idxs[i0], idxs[i1 - 1] + 1});
            i0 = i1;
        }
    }

    uint32_t v_trans;
    uint32_t n_layer;

    io.read(&v_trans, sizeof(v_trans));
    io.read(&n_layer, sizeof(n_layer));

    if (n_layer != layers.size()) {
        LLAMA_LOG_ERROR("%s: mismatched layer count (%u instead of %u)\n", __func__, n_layer, (uint32_t) layers.size());
        return false;
    }

    if (cell_count > cells.size()) {
        LLAMA_LOG_ERROR("%s: not enough cells in kv cache to restore state (%u > %u)\n", __func__, cell_count, cells.size());
        return false;
    }

    if (this->v_trans != (bool) v_trans) {
        LLAMA_LOG_ERROR("%s: incompatible V transposition\n", __func__);
        return false;
    }

    // For each layer, read the keys for each cell, one row is one cell, read as one contiguous block
    for (const auto & layer : layers) {
        const uint32_t il = layer.il;

        const uint32_t n_embd_k_gqa = hparams.n_embd_k_gqa(il);

        auto * k = layer.k_stream[strm];

        // Read type of key
        int32_t k_type_i_ref;
        io.read(&k_type_i_ref, sizeof(k_type_i_ref));
        const int32_t k_type_i = (int32_t) k->type;
        if (k_type_i != k_type_i_ref) {
            LLAMA_LOG_ERROR("%s: mismatched key type (%d != %d, layer %d)\n", __func__, k_type_i, k_type_i_ref, il);
            return false;
        }

        // Read row size of key
        uint64_t k_size_row_ref;
        io.read(&k_size_row_ref, sizeof(k_size_row_ref));
        const size_t k_size_row = ggml_row_size(k->type, n_embd_k_gqa);
        if (k_size_row != k_size_row_ref) {
            LLAMA_LOG_ERROR("%s: mismatched key row size (%zu != %zu, layer %d)\n", __func__, k_size_row, (size_t) k_size_row_ref, il);
            return false;
        }

        for (const auto & r : runs) {
            io.read_tensor(k, (size_t) r.from * k_size_row, (size_t) (r.to - r.from) * k_size_row);
        }
    }

    if (!this->v_trans) {
        for (const auto & layer : layers) {
            const uint32_t il = layer.il;

            const uint32_t n_embd_v_gqa = hparams.n_embd_v_gqa(il);

            auto * v = layer.v_stream[strm];
            if (!v) {
                continue;
            }

            // Read type of value
            int32_t v_type_i_ref;
            io.read(&v_type_i_ref, sizeof(v_type_i_ref));
            const int32_t v_type_i = (int32_t) v->type;
            if (v_type_i != v_type_i_ref) {
                LLAMA_LOG_ERROR("%s: mismatched value type (%d != %d, layer %d)\n", __func__, v_type_i, v_type_i_ref, il);
                return false;
            }

            // Read row size of value
            uint64_t v_size_row_ref;
            io.read(&v_size_row_ref, sizeof(v_size_row_ref));
            const size_t v_size_row = ggml_row_size(v->type, n_embd_v_gqa);
            if (v_size_row != v_size_row_ref) {
                LLAMA_LOG_ERROR("%s: mismatched value row size (%zu != %zu, layer %d)\n", __func__, v_size_row, (size_t) v_size_row_ref, il);
                return false;
            }

            for (const auto & r : runs) {
                io.read_tensor(v, (size_t) r.from * v_size_row, (size_t) (r.to - r.from) * v_size_row);
            }
        }
    } else {
        // For each layer, read the values for each cell (transposed)
        for (const auto & layer : layers) {
            const uint32_t il = layer.il;

            const uint32_t n_embd_v_gqa = hparams.n_embd_v_gqa(il);

            auto * v = layer.v_stream[strm];
            if (!v) {
                continue;
            }

            // Read type of value
            int32_t v_type_i_ref;
            io.read(&v_type_i_ref, sizeof(v_type_i_ref));
            const int32_t v_type_i = (int32_t) v->type;
            if (v_type_i != v_type_i_ref) {
                LLAMA_LOG_ERROR("%s: mismatched value type (%d != %d, layer %d)\n", __func__, v_type_i, v_type_i_ref, il);
                return false;
            }

            // Read element size of value
            uint32_t v_size_el_ref;
            io.read(&v_size_el_ref, sizeof(v_size_el_ref));
            const size_t v_size_el = ggml_type_size(v->type);
            if (v_size_el != v_size_el_ref) {
                LLAMA_LOG_ERROR("%s: mismatched value element size (%zu != %zu, layer %d)\n", __func__, v_size_el, (size_t) v_size_el_ref, il);
                return false;
            }

            // Read GQA embedding size
            uint32_t n_embd_v_gqa_ref;
            io.read(&n_embd_v_gqa_ref, sizeof(n_embd_v_gqa_ref));
            if (n_embd_v_gqa != n_embd_v_gqa_ref) {
                LLAMA_LOG_ERROR("%s: mismatched GQA embedding size (%u != %u, layer %d)\n", __func__, n_embd_v_gqa, n_embd_v_gqa_ref, il);
                return false;
            }

            for (uint32_t j = 0; j < n_embd_v_gqa; ++j) {
                for (const auto & r : runs) {
                    const size_t dst_offset = ((size_t) r.from + j * cells.size()) * v_size_el;
                    io.read_tensor(v, dst_offset, (size_t) (r.to - r.from) * v_size_el);
                }
            }
        }
    }

    return true;
}

//
// llama_kv_cache_context
//

llama_kv_cache_context::llama_kv_cache_context(llama_memory_status status) : status(status) {}

llama_kv_cache_context::llama_kv_cache_context(
        llama_kv_cache * kv) : status(LLAMA_MEMORY_STATUS_SUCCESS), kv(kv) {
    n_kv = kv->get_size();

    const uint32_t n_stream = kv->get_n_stream();

    // create a dummy slot info - the actual data is irrelevant. we just need to build the graph
    sinfos.resize(1);
    sinfos[0].s0 = 0;
    sinfos[0].s1 = n_stream - 1;
    sinfos[0].idxs.resize(n_stream);
    for (uint32_t s = 0; s < n_stream; ++s) {
        sinfos[0].strm.push_back(s);
        sinfos[0].idxs[s].resize(1, 0);
    }
}

llama_kv_cache_context::llama_kv_cache_context(
        llama_kv_cache * kv,
        llama_context * lctx,
        bool do_shift,
        stream_copy_info sc_info) : status(LLAMA_MEMORY_STATUS_SUCCESS), kv(kv), lctx(lctx), do_shift(do_shift), sc_info(std::move(sc_info)) {
    if (!do_shift && this->sc_info.empty()) {
        status = LLAMA_MEMORY_STATUS_NO_UPDATE;
    }
}

llama_kv_cache_context::llama_kv_cache_context(
        llama_kv_cache * kv,
        llama_kv_cache::slot_info_vec_t sinfos,
        std::vector<llama_ubatch> ubatches) : status(LLAMA_MEMORY_STATUS_SUCCESS), kv(kv), sinfos(std::move(sinfos)), ubatches(std::move(ubatches)) {
}

llama_kv_cache_context::~llama_kv_cache_context() = default;

bool llama_kv_cache_context::next() {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    if (++i_cur >= ubatches.size()) {
        return false;
    }

    return true;
}

bool llama_kv_cache_context::apply() {
    assert(!llama_memory_status_is_fail(status));

    // no ubatches -> this is a KV cache update
    if (ubatches.empty()) {
        kv->update(lctx, do_shift, sc_info);

        return true;
    }

    kv->apply_ubatch(sinfos[i_cur], ubatches[i_cur]);
    n_kv = kv->get_n_kv(sinfos[i_cur]);

    return true;
}

llama_memory_status llama_kv_cache_context::get_status() const {
    return status;
}

const llama_ubatch & llama_kv_cache_context::get_ubatch() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ubatches[i_cur];
}

uint32_t llama_kv_cache_context::get_n_kv() const {
    return n_kv;
}

ggml_type llama_kv_cache_context::type_k() const {
    return kv->type_k();
}

ggml_type llama_kv_cache_context::type_v() const {
    return kv->type_v();
}

ggml_tensor * llama_kv_cache_context::get_k(ggml_context * ctx, int32_t il) const {
    return kv->get_k(ctx, il, n_kv, sinfos[i_cur]);
}

ggml_tensor * llama_kv_cache_context::get_v(ggml_context * ctx, int32_t il) const {
    return kv->get_v(ctx, il, n_kv, sinfos[i_cur]);
}

ggml_tensor * llama_kv_cache_context::cpy_k(ggml_context * ctx, ggml_tensor * k_cur, ggml_tensor * k_idxs, int32_t il) const {
    return kv->cpy_k(ctx, k_cur, k_idxs, il, sinfos[i_cur]);
}

ggml_tensor * llama_kv_cache_context::cpy_v(ggml_context * ctx, ggml_tensor * v_cur, ggml_tensor * v_idxs, int32_t il) const {
    return kv->cpy_v(ctx, v_cur, v_idxs, il, sinfos[i_cur]);
}

ggml_tensor * llama_kv_cache_context::build_input_k_idxs(ggml_context * ctx, const llama_ubatch & ubatch) const {
    return kv->build_input_k_idxs(ctx, ubatch);
}

ggml_tensor * llama_kv_cache_context::build_input_v_idxs(ggml_context * ctx, const llama_ubatch & ubatch) const {
    return kv->build_input_v_idxs(ctx, ubatch);
}

ggml_tensor * llama_kv_cache_context::build_input_k_rot(ggml_context * ctx) const {
    return kv->build_input_k_rot(ctx);
}

ggml_tensor * llama_kv_cache_context::build_input_v_rot(ggml_context * ctx) const {
    return kv->build_input_v_rot(ctx);
}

void llama_kv_cache_context::set_input_k_shift(ggml_tensor * dst) const {
    kv->set_input_k_shift(dst);
}

void llama_kv_cache_context::set_input_k_idxs(ggml_tensor * dst, const llama_ubatch * ubatch) const {
    kv->set_input_k_idxs(dst, ubatch, sinfos[i_cur]);
}

void llama_kv_cache_context::set_input_v_idxs(ggml_tensor * dst, const llama_ubatch * ubatch) const {
    kv->set_input_v_idxs(dst, ubatch, sinfos[i_cur]);
}

void llama_kv_cache_context::set_input_kq_mask(ggml_tensor * dst, const llama_ubatch * ubatch, bool causal_attn) const {
    kv->set_input_kq_mask(dst, ubatch, causal_attn);
}

void llama_kv_cache_context::set_input_pos_bucket(ggml_tensor * dst, const llama_ubatch * ubatch) const {
    kv->set_input_pos_bucket(dst, ubatch);
}

void llama_kv_cache_context::set_input_k_rot(ggml_tensor * dst) const {
    kv->set_input_k_rot(dst);
}

void llama_kv_cache_context::set_input_v_rot(ggml_tensor * dst) const {
    kv->set_input_v_rot(dst);
}

void llama_kv_cache_context::get_prev_tokens(const llama_ubatch & ubatch, uint32_t n, std::vector<llama_token> & res) const {
    kv->get_prev_tokens(ubatch, n, res);
}

// --- llama-kv-cache-dsa-iswa.cpp ---
#include "llama-kv-cache-dsa-iswa.h"

#include "llama-impl.h"
#include "llama-batch.h"
#include "llama-model.h"

#include <algorithm>
#include <cassert>

//
// llama_kv_cache_dsa_iswa
//

llama_kv_cache_dsa_iswa::llama_kv_cache_dsa_iswa(
        const llama_model & model,
                ggml_type   type_k,
                ggml_type   type_v,
                     bool   v_trans,
                     bool   offload,
                     bool   swa_full,
                     bool   unified,
                 uint32_t   kv_size,
                 uint32_t   n_seq_max,
                 uint32_t   n_ubatch,
                 uint32_t   n_pad,
    const layer_filter_cb & filter_mla,
    const layer_filter_cb & filter_lid,
    const  layer_reuse_cb & reuse) : unified(unified) {

    const auto & hparams = model.hparams;

    // chain filters
    const layer_filter_cb filter_dsa = [&](int32_t il) {
        if (filter_mla && !filter_mla(il)) {
            return false;
        }

        return !hparams.is_swa(il);
    };

    const layer_filter_cb filter_swa = [&](int32_t il) {
        if (filter_mla && !filter_mla(il)) {
            return false;
        }

        return hparams.is_swa(il);
    };

    const uint32_t size_dsa = kv_size;

    // note: the SWA cache is always padded to 256 for performance
    //       https://github.com/ggml-org/llama.cpp/issues/17037
    uint32_t size_swa = GGML_PAD(std::min(size_dsa, hparams.n_swa*(unified ? n_seq_max : 1) + n_ubatch), 256);

    // when using full-size SWA cache, we set the SWA cache size to be equal to the base cache size
    if (swa_full) {
        LLAMA_LOG_WARN("%s: using full-size SWA cache (ref: %s)\n",
                __func__, "https://github.com/ggml-org/llama.cpp/pull/13194#issuecomment-2868343055");

        size_swa = size_dsa;
    }

    LLAMA_LOG_INFO("%s: creating DSA KV cache, size = %u cells\n", __func__, size_dsa);

    kv_dsa = std::make_unique<llama_kv_cache_dsa>(
            model, type_k, type_v,
            v_trans, offload, unified, size_dsa, n_seq_max, n_pad,
            0, LLAMA_SWA_TYPE_NONE, filter_dsa, filter_lid, reuse);

    LLAMA_LOG_INFO("%s: creating SWA KV cache, size = %u cells\n", __func__, size_swa);

    kv_swa = std::make_unique<llama_kv_cache>(
            model, hparams, type_k, type_v,
            v_trans, offload, unified, size_swa, n_seq_max, n_pad,
            hparams.n_swa, hparams.swa_type, nullptr, filter_swa, reuse, nullptr);
}

void llama_kv_cache_dsa_iswa::clear(bool data) {
    kv_dsa->clear(data);
    kv_swa->clear(data);
}

bool llama_kv_cache_dsa_iswa::seq_rm(llama_seq_id seq_id, llama_pos p0, llama_pos p1) {
    bool res = true;

    res = res & kv_dsa->seq_rm(seq_id, p0, p1);
    res = res & kv_swa->seq_rm(seq_id, p0, p1);

    return res;
}

void llama_kv_cache_dsa_iswa::seq_cp(llama_seq_id seq_id_src, llama_seq_id seq_id_dst, llama_pos p0, llama_pos p1) {
    kv_dsa->seq_cp(seq_id_src, seq_id_dst, p0, p1);
    kv_swa->seq_cp(seq_id_src, seq_id_dst, p0, p1);
}

void llama_kv_cache_dsa_iswa::seq_keep(llama_seq_id seq_id) {
    kv_dsa->seq_keep(seq_id);
    kv_swa->seq_keep(seq_id);
}

void llama_kv_cache_dsa_iswa::seq_add(llama_seq_id seq_id, llama_pos p0, llama_pos p1, llama_pos shift) {
    kv_dsa->seq_add(seq_id, p0, p1, shift);
    kv_swa->seq_add(seq_id, p0, p1, shift);
}

void llama_kv_cache_dsa_iswa::seq_div(llama_seq_id seq_id, llama_pos p0, llama_pos p1, int d) {
    kv_dsa->seq_div(seq_id, p0, p1, d);
    kv_swa->seq_div(seq_id, p0, p1, d);
}

llama_pos llama_kv_cache_dsa_iswa::seq_pos_min(llama_seq_id seq_id) const {
    // the DSA cache is a superset of the SWA cache, so we can just check the SWA cache
    return kv_swa->seq_pos_min(seq_id);
}

llama_pos llama_kv_cache_dsa_iswa::seq_pos_max(llama_seq_id seq_id) const {
    return kv_swa->seq_pos_max(seq_id);
}

std::map<ggml_backend_buffer_type_t, size_t> llama_kv_cache_dsa_iswa::memory_breakdown() const {
    std::map<ggml_backend_buffer_type_t, size_t> mb = kv_dsa->memory_breakdown();
    for (const auto & buft_size : kv_swa->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    return mb;
}

llama_memory_context_ptr llama_kv_cache_dsa_iswa::init_batch(llama_batch_allocr & balloc, uint32_t n_ubatch, bool embd_all) {
    GGML_UNUSED(embd_all);

    // first try simple split
    do {
        if (!unified) {
            // requires equal splits, so we skip the simple split
            break;
        }

        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            auto ubatch = balloc.split_simple(n_ubatch);

            if (ubatch.n_tokens == 0) {
                break;
            }

            ubatches.push_back(std::move(ubatch)); // NOLINT
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            // failed to find a suitable split
            break;
        }

        auto sinfos_mla = kv_dsa->get_mla()->prepare(ubatches);
        if (sinfos_mla.empty()) {
            break;
        }

        auto sinfos_lid = kv_dsa->get_lid()->prepare(ubatches);
        if (sinfos_lid.empty()) {
            break;
        }

        auto sinfos_swa = kv_swa->prepare(ubatches);
        if (sinfos_swa.empty()) {
            break;
        }

        assert(sinfos_mla.size() == sinfos_swa.size());

        return std::make_unique<llama_kv_cache_dsa_iswa_context>(
                this, std::move(sinfos_mla), std::move(sinfos_lid), std::move(sinfos_swa), std::move(ubatches));
    } while (false);

    // if it fails, try equal split
    do {
        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            auto ubatch = balloc.split_equal(n_ubatch, !unified, 0);

            if (ubatch.n_tokens == 0) {
                break;
            }

            ubatches.push_back(std::move(ubatch)); // NOLINT
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            // failed to find a suitable split
            break;
        }

        auto sinfos_mla = kv_dsa->get_mla()->prepare(ubatches);
        if (sinfos_mla.empty()) {
            break;
        }

        auto sinfos_lid = kv_dsa->get_lid()->prepare(ubatches);
        if (sinfos_lid.empty()) {
            break;
        }

        auto sinfos_swa = kv_swa->prepare(ubatches);
        if (sinfos_swa.empty()) {
            break;
        }

        assert(sinfos_mla.size() == sinfos_swa.size());

        return std::make_unique<llama_kv_cache_dsa_iswa_context>(
                this, std::move(sinfos_mla), std::move(sinfos_lid), std::move(sinfos_swa), std::move(ubatches));
    } while (false);

    return std::make_unique<llama_kv_cache_dsa_iswa_context>(LLAMA_MEMORY_STATUS_FAILED_PREPARE);
}

llama_memory_context_ptr llama_kv_cache_dsa_iswa::init_full() {
    return std::make_unique<llama_kv_cache_dsa_iswa_context>(this);
}

llama_memory_context_ptr llama_kv_cache_dsa_iswa::init_update(llama_context * lctx, bool optimize) {
    return std::make_unique<llama_kv_cache_dsa_iswa_context>(this, lctx, optimize);
}

bool llama_kv_cache_dsa_iswa::get_can_shift() const {
    return kv_dsa->get_can_shift() &&
           kv_swa->get_can_shift() &&
           kv_dsa->get_mla()->get_size() == kv_swa->get_size();
}

void llama_kv_cache_dsa_iswa::state_write(llama_io_write_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) const {
    if ((flags & LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) == 0) {
        kv_dsa->state_write(io, seq_id, flags);
    }

    kv_swa->state_write(io, seq_id, flags);
}

void llama_kv_cache_dsa_iswa::state_read(llama_io_read_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) {
    if ((flags & LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) == 0) {
        kv_dsa->state_read(io, seq_id, flags);
    }

    kv_swa->state_read(io, seq_id, flags);
}

llama_kv_cache_dsa * llama_kv_cache_dsa_iswa::get_dsa() const {
    return kv_dsa.get();
}

llama_kv_cache * llama_kv_cache_dsa_iswa::get_swa() const {
    return kv_swa.get();
}

//
// llama_kv_cache_dsa_iswa_context
//

llama_kv_cache_dsa_iswa_context::llama_kv_cache_dsa_iswa_context(llama_memory_status status) : status(status) {}

llama_kv_cache_dsa_iswa_context::llama_kv_cache_dsa_iswa_context(
        llama_kv_cache_dsa_iswa * kv) :
    ctx_dsa(kv->get_dsa()->init_full()),
    ctx_swa(kv->get_swa()->init_full()),
    status(llama_memory_status_combine(ctx_dsa->get_status(), ctx_swa->get_status())) {
}

llama_kv_cache_dsa_iswa_context::llama_kv_cache_dsa_iswa_context(
        llama_kv_cache_dsa_iswa * kv,
        llama_context * lctx,
        bool optimize) :
    ctx_dsa(kv->get_dsa()->init_update(lctx, optimize)),
    ctx_swa(kv->get_swa()->init_update(lctx, optimize)),
    status(llama_memory_status_combine(ctx_dsa->get_status(), ctx_swa->get_status())) {
}

llama_kv_cache_dsa_iswa_context::llama_kv_cache_dsa_iswa_context(
        llama_kv_cache_dsa_iswa * kv,
        slot_info_vec_t sinfos_mla,
        slot_info_vec_t sinfos_lid,
        slot_info_vec_t sinfos_swa,
        std::vector<llama_ubatch> ubatches) :
    ubatches(std::move(ubatches)),
    // note: here we copy the ubatches. not sure if this is ideal
    ctx_dsa(new llama_kv_cache_dsa_context(kv->get_dsa(), std::move(sinfos_mla), std::move(sinfos_lid), this->ubatches)),
    ctx_swa(new llama_kv_cache_context(kv->get_swa(), std::move(sinfos_swa), this->ubatches)),
    status(llama_memory_status_combine(ctx_dsa->get_status(), ctx_swa->get_status())) {
}

llama_kv_cache_dsa_iswa_context:: ~llama_kv_cache_dsa_iswa_context() = default;

bool llama_kv_cache_dsa_iswa_context::next() {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    ctx_dsa->next();
    ctx_swa->next();

    if (++i_next >= ubatches.size()) {
        return false;
    }

    return true;
}

bool llama_kv_cache_dsa_iswa_context::apply() {
    assert(!llama_memory_status_is_fail(status));

    bool res = true;

    res = res & ctx_dsa->apply();
    res = res & ctx_swa->apply();

    return res;
}

llama_memory_status llama_kv_cache_dsa_iswa_context::get_status() const {
    return status;
}

const llama_ubatch & llama_kv_cache_dsa_iswa_context::get_ubatch() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ubatches[i_next];
}

const llama_kv_cache_dsa_context * llama_kv_cache_dsa_iswa_context::get_dsa() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return static_cast<const llama_kv_cache_dsa_context *>(ctx_dsa.get());
}

const llama_kv_cache_context * llama_kv_cache_dsa_iswa_context::get_swa() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return static_cast<const llama_kv_cache_context *>(ctx_swa.get());
}

// --- llama-kv-cache-dsa.cpp ---
#include "llama-kv-cache-dsa.h"

#include "llama-impl.h"
#include "llama-batch.h"
#include "llama-model.h"

#include <algorithm>
#include <cassert>

//
// llama_kv_cache_dsa
//

llama_kv_cache_dsa::llama_kv_cache_dsa(
        const llama_model & model,
                ggml_type   type_k,
                ggml_type   type_v,
                     bool   v_trans,
                     bool   offload,
                     bool   unified,
                 uint32_t   kv_size,
                 uint32_t   n_seq_max,
                 uint32_t   n_pad,
                 uint32_t   n_swa,
           llama_swa_type   swa_type,
    const layer_filter_cb & filter_mla,
    const layer_filter_cb & filter_lid,
    const  layer_reuse_cb & reuse) :
    hparams_lid(model.hparams), n_stream(unified ? 1 : n_seq_max) {

    LLAMA_LOG_INFO("%s: creating main KV cache, size = %u cells\n", __func__, kv_size);

    kv_mla = std::make_unique<llama_kv_cache>(
            model, model.hparams, type_k, type_v,
            v_trans, offload, unified, kv_size, n_seq_max, n_pad,
            n_swa, swa_type, nullptr, filter_mla, reuse, nullptr);

    // we use llama_kv_cache for caching indexer keys
    // by hand-tweaking some hparams we fool it to create
    // indexer key cache tensors with correct dimensions
    // https://github.com/ggml-org/llama.cpp/pull/21149#discussion_r3015940823

    // DSA lightning indexer uses MQA with single key head
    std::fill(hparams_lid.n_head_kv_arr.begin(), hparams_lid.n_head_kv_arr.end(), 1);
    hparams_lid.n_embd_head_k_full = model.hparams.indexer_head_size;
    hparams_lid.rope_type          = LLAMA_ROPE_TYPE_NEOX;

    LLAMA_LOG_INFO("%s: creating indexer KV cache, size = %u cells\n", __func__, kv_size);

    kv_lid = std::make_unique<llama_kv_cache>(
            model, hparams_lid, type_k, type_v,
            v_trans, offload, unified, kv_size, n_seq_max, n_pad,
            n_swa, swa_type, nullptr, filter_lid, reuse, nullptr);
}

void llama_kv_cache_dsa::clear(bool data) {
    kv_mla->clear(data);
    kv_lid->clear(data);
}

bool llama_kv_cache_dsa::seq_rm(llama_seq_id seq_id, llama_pos p0, llama_pos p1) {
    bool res = true;

    res = res & kv_mla->seq_rm(seq_id, p0, p1);
    res = res & kv_lid->seq_rm(seq_id, p0, p1);

    return res;
}

void llama_kv_cache_dsa::seq_cp(llama_seq_id seq_id_src, llama_seq_id seq_id_dst, llama_pos p0, llama_pos p1) {
    kv_mla->seq_cp(seq_id_src, seq_id_dst, p0, p1);
    kv_lid->seq_cp(seq_id_src, seq_id_dst, p0, p1);
}

void llama_kv_cache_dsa::seq_keep(llama_seq_id seq_id) {
    kv_mla->seq_keep(seq_id);
    kv_lid->seq_keep(seq_id);
}

void llama_kv_cache_dsa::seq_add(llama_seq_id seq_id, llama_pos p0, llama_pos p1, llama_pos shift) {
    kv_mla->seq_add(seq_id, p0, p1, shift);
    kv_lid->seq_add(seq_id, p0, p1, shift);
}

void llama_kv_cache_dsa::seq_div(llama_seq_id seq_id, llama_pos p0, llama_pos p1, int d) {
    kv_mla->seq_div(seq_id, p0, p1, d);
    kv_lid->seq_div(seq_id, p0, p1, d);
}

llama_pos llama_kv_cache_dsa::seq_pos_min(llama_seq_id seq_id) const {
    return kv_mla->seq_pos_min(seq_id);
}

llama_pos llama_kv_cache_dsa::seq_pos_max(llama_seq_id seq_id) const {
    return kv_mla->seq_pos_max(seq_id);
}

std::map<ggml_backend_buffer_type_t, size_t> llama_kv_cache_dsa::memory_breakdown() const {
    std::map<ggml_backend_buffer_type_t, size_t> mb = kv_mla->memory_breakdown();
    for (const auto & buft_size : kv_lid->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    return mb;
}

llama_memory_context_ptr llama_kv_cache_dsa::init_batch(
            llama_batch_allocr & balloc,
            uint32_t n_ubatch,
            bool embd_all) {
    GGML_UNUSED(embd_all);

    do {
        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            auto ubatch = n_stream == 1 ? balloc.split_simple(n_ubatch) : balloc.split_equal(n_ubatch, true, 0);

            if (ubatch.n_tokens == 0) {
                break;
            }

            ubatches.push_back(std::move(ubatch)); // NOLINT
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            // failed to find a suitable split
            break;
        }

        auto sinfos_mla = kv_mla->prepare(ubatches);
        if (sinfos_mla.empty()) {
            break;
        }

        auto sinfos_lid = kv_lid->prepare(ubatches);
        if (sinfos_lid.empty()) {
            break;
        }

        assert(sinfos_mla.size() == sinfos_lid.size());

        return std::make_unique<llama_kv_cache_dsa_context>(
                this, std::move(sinfos_mla), std::move(sinfos_lid), std::move(ubatches));
    } while (false);

    return std::make_unique<llama_kv_cache_dsa_context>(LLAMA_MEMORY_STATUS_FAILED_PREPARE);
}

llama_memory_context_ptr llama_kv_cache_dsa::init_full() {
    return std::make_unique<llama_kv_cache_dsa_context>(this);
}

llama_memory_context_ptr llama_kv_cache_dsa::init_update(llama_context * lctx, bool optimize) {
    return std::make_unique<llama_kv_cache_dsa_context>(this, lctx, optimize);
}

bool llama_kv_cache_dsa::get_can_shift() const {
    return kv_mla->get_can_shift() &&
           kv_lid->get_can_shift() &&
           kv_mla->get_size() == kv_lid->get_size();
}

void llama_kv_cache_dsa::state_write(llama_io_write_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) const {
    kv_mla->state_write(io, seq_id, flags);
    kv_lid->state_write(io, seq_id, flags);
}

void llama_kv_cache_dsa::state_read(llama_io_read_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) {
    kv_mla->state_read(io, seq_id, flags);
    kv_lid->state_read(io, seq_id, flags);
}

llama_kv_cache * llama_kv_cache_dsa::get_mla() const {
    return kv_mla.get();
}

llama_kv_cache * llama_kv_cache_dsa::get_lid() const {
    return kv_lid.get();
}

//
// llama_kv_cache_dsa_context
//

llama_kv_cache_dsa_context::llama_kv_cache_dsa_context(llama_memory_status status) : status(status) {}

llama_kv_cache_dsa_context::llama_kv_cache_dsa_context(
        llama_kv_cache_dsa * kv) :
    ctx_mla(kv->get_mla()->init_full()),
    ctx_lid(kv->get_lid()->init_full()),
    status(llama_memory_status_combine(ctx_mla->get_status(), ctx_lid->get_status())) {
}

llama_kv_cache_dsa_context::llama_kv_cache_dsa_context(
        llama_kv_cache_dsa * kv,
        llama_context * lctx,
        bool optimize) :
    ctx_mla(kv->get_mla()->init_update(lctx, optimize)),
    ctx_lid(kv->get_lid()->init_update(lctx, optimize)),
    status(llama_memory_status_combine(ctx_mla->get_status(), ctx_lid->get_status())) {
}

llama_kv_cache_dsa_context::llama_kv_cache_dsa_context(
        llama_kv_cache_dsa * kv,
        slot_info_vec_t sinfos_mla,
        slot_info_vec_t sinfos_lid,
        std::vector<llama_ubatch> ubatches) :
    ubatches(std::move(ubatches)),
    // note: here we copy the ubatches. not sure if this is ideal
    ctx_mla(new llama_kv_cache_context(kv->get_mla(), std::move(sinfos_mla), this->ubatches)),
    ctx_lid(new llama_kv_cache_context(kv->get_lid(), std::move(sinfos_lid), this->ubatches)),
    status(llama_memory_status_combine(ctx_mla->get_status(), ctx_lid->get_status())) {
}

llama_kv_cache_dsa_context:: ~llama_kv_cache_dsa_context() = default;

bool llama_kv_cache_dsa_context::next() {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    ctx_mla->next();
    ctx_lid->next();

    if (++i_next >= ubatches.size()) {
        return false;
    }

    return true;
}

bool llama_kv_cache_dsa_context::apply() {
    assert(!llama_memory_status_is_fail(status));

    bool res = true;

    res = res & ctx_mla->apply();
    res = res & ctx_lid->apply();

    return res;
}

llama_memory_status llama_kv_cache_dsa_context::get_status() const {
    return status;
}

const llama_ubatch & llama_kv_cache_dsa_context::get_ubatch() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ubatches[i_next];
}

const llama_kv_cache_context * llama_kv_cache_dsa_context::get_mla() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return static_cast<const llama_kv_cache_context *>(ctx_mla.get());
}

const llama_kv_cache_context * llama_kv_cache_dsa_context::get_lid()  const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return static_cast<const llama_kv_cache_context *>(ctx_lid.get());
}

// --- llama-kv-cache-dsv4.cpp ---
#include "llama-kv-cache-dsv4.h"

#include "ggml-backend.h"
#include "llama-impl.h"
#include "llama-batch.h"
#include "llama-io.h"
#include "llama-model.h"

#include <algorithm>
#include <cassert>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <map>
#include <sstream>
#include <stdexcept>

static constexpr uint32_t DSV4_CSA_RATIO = 4;
static constexpr uint32_t DSV4_HCA_RATIO = 128;

static constexpr uint32_t DSV4_STATE_MAGIC         = 0x34565344; // DSV4
static constexpr uint32_t DSV4_STATE_VERSION       = 1;
static constexpr uint32_t DSV4_STATE_MODE_FULL     = 0;
static constexpr uint32_t DSV4_STATE_MODE_PARTIAL  = 1;
static constexpr uint32_t DSV4_K_CACHE_STATE_VER   = 2;
static constexpr uint32_t DSV4_COMP_STATE_VER      = 1;

static uint32_t dsv4_comp_size(uint32_t kv_size, uint32_t ratio) {
    return std::max<uint32_t>(1, (kv_size + ratio - 1)/ratio);
}

static void dsv4_clear_tensor_stream(ggml_tensor * tensor, uint32_t stream) {
    GGML_ASSERT(ggml_is_contiguous(tensor));
    GGML_ASSERT(tensor->ne[3] == 1);
    GGML_ASSERT(stream < (uint32_t) tensor->ne[2]);

    const size_t stream_size = tensor->nb[2];
    ggml_backend_tensor_memset(tensor, 0, stream*stream_size, stream_size);
}

static uint32_t dsv4_state_n_used_k_rows(llama_pos pos_max, uint32_t ratio, uint32_t kv_size) {
    if (pos_max < 0) {
        return 0;
    }

    const uint64_t n_rows = ((uint64_t) pos_max + 1)/ratio;

    return (uint32_t) std::min<uint64_t>(kv_size, n_rows);
}

static int64_t dsv4_stream_offset(uint32_t n_stream, llama_seq_id seq_id, uint32_t size) {
    if (n_stream <= 1) {
        return 0;
    }
    if (seq_id < 0 || (uint32_t) seq_id >= n_stream) {
        throw std::runtime_error("DSV4 sequence id out of stream range");
    }

    return (int64_t) seq_id*size;
}

static bool dsv4_ubatch_has_coupled(const llama_ubatch & ubatch) {
    for (uint32_t i = 0; i < ubatch.n_tokens; ++i) {
        if (ubatch.n_seq_id[i] > 1) {
            return true;
        }
    }

    return false;
}

static bool dsv4_token_has_seq(const llama_ubatch & ubatch, uint32_t i, llama_seq_id seq_id) {
    for (int32_t s = 0; s < ubatch.n_seq_id[i]; ++s) {
        if (ubatch.seq_id[i][s] == seq_id) {
            return true;
        }
    }

    return false;
}

static llama_ubatch dsv4_build_raw_write_ubatch(const llama_ubatch & ubatch) {
    if (!dsv4_ubatch_has_coupled(ubatch)) {
        return ubatch;
    }
    if (ubatch.embd) {
        throw std::runtime_error("DSV4 coupled embedding ubatches are not supported");
    }

    std::vector<uint32_t> counts(ubatch.n_seqs_unq, 0);
    uint32_t n_tokens = 0;
    for (uint32_t s = 0; s < ubatch.n_seqs_unq; ++s) {
        const llama_seq_id seq_id = ubatch.seq_id_unq[s];
        for (uint32_t i = 0; i < ubatch.n_tokens; ++i) {
            if (dsv4_token_has_seq(ubatch, i, seq_id)) {
                ++counts[s];
                ++n_tokens;
            }
        }
    }

    if (n_tokens == 0) {
        return ubatch;
    }

    const uint32_t n_seq_tokens = counts[0];
    for (uint32_t s = 1; s < counts.size(); ++s) {
        if (counts[s] != n_seq_tokens) {
            throw std::runtime_error("DSV4 coupled raw writes require equal sequence lengths");
        }
    }

    auto data = std::make_shared<llama_ubatch::data_t>();
    data->pos.resize((size_t) n_tokens*ubatch.n_pos);
    data->n_seq_id.reserve(n_tokens);
    data->seq_id.reserve(n_tokens);
    data->seq_id_data.reserve(n_tokens);
    data->seq_id_unq.assign(ubatch.seq_id_unq, ubatch.seq_id_unq + ubatch.n_seqs_unq);
    data->seq_idx.assign(LLAMA_MAX_SEQ, -1);
    data->output.assign(n_tokens, 0);
    if (ubatch.token) {
        data->token.reserve(n_tokens);
    }

    for (uint32_t s = 0; s < data->seq_id_unq.size(); ++s) {
        data->seq_idx[data->seq_id_unq[s]] = s;
    }

    for (uint32_t s = 0; s < ubatch.n_seqs_unq; ++s) {
        const llama_seq_id seq_id = ubatch.seq_id_unq[s];
        for (uint32_t i = 0; i < ubatch.n_tokens; ++i) {
            if (!dsv4_token_has_seq(ubatch, i, seq_id)) {
                continue;
            }

            const uint32_t dst = data->n_seq_id.size();
            if (ubatch.token) {
                data->token.push_back(ubatch.token[i]);
            }
            for (uint32_t p = 0; p < ubatch.n_pos; ++p) {
                data->pos[(size_t) p*n_tokens + dst] = ubatch.pos[(size_t) p*ubatch.n_tokens + i];
            }
            data->n_seq_id.push_back(1);
            data->seq_id_data.push_back(seq_id);
        }
    }

    for (uint32_t i = 0; i < n_tokens; ++i) {
        data->seq_id.push_back(&data->seq_id_data[i]);
    }

    llama_ubatch res {
        /*.b_equal_seqs =*/ true,
        /*.n_tokens     =*/ n_tokens,
        /*.n_seq_tokens =*/ n_seq_tokens,
        /*.n_seqs       =*/ ubatch.n_seqs_unq,
        /*.n_seqs_unq   =*/ ubatch.n_seqs_unq,
        /*.n_pos        =*/ ubatch.n_pos,
        /*.token        =*/ data->token.empty() ? nullptr : data->token.data(),
        /*.embd         =*/ nullptr,
        /*.pos          =*/ data->pos.data(),
        /*.n_seq_id     =*/ data->n_seq_id.data(),
        /*.seq_id       =*/ data->seq_id.data(),
        /*.seq_id_unq   =*/ data->seq_id_unq.data(),
        /*.seq_idx      =*/ data->seq_idx.data(),
        /*.output       =*/ data->output.data(),
        /*.data         =*/ data,
    };

    return res;
}

static std::vector<llama_ubatch> dsv4_build_raw_write_ubatches(const std::vector<llama_ubatch> & ubatches) {
    std::vector<llama_ubatch> res;
    res.reserve(ubatches.size());
    for (const llama_ubatch & ubatch : ubatches) {
        res.push_back(dsv4_build_raw_write_ubatch(ubatch));
    }
    return res;
}

static bool dsv4_batch_has_coupled(const llama_batch & batch) {
    if (!batch.n_seq_id) {
        return false;
    }

    for (int32_t i = 0; i < batch.n_tokens; ++i) {
        if (batch.n_seq_id[i] > 1) {
            return true;
        }
    }

    return false;
}

static int64_t dsv4_comp_graph_n_stream(const llama_ubatch & ubatch, uint32_t n_stream) {
    // Coupled sequence sets must stay in one graph stream because their
    // compressed state is shared. Independent per-seq state can fan out.
    if (n_stream <= 1 || ubatch.n_seqs_unq <= 1 || dsv4_ubatch_has_coupled(ubatch)) {
        return 1;
    }

    return ubatch.n_seqs_unq;
}

static void dsv4_state_src_stream_range(
        uint32_t       n_stream,
        llama_seq_id   seq_id,
        uint32_t     & s0,
        uint32_t     & ns) {
    if (seq_id >= 0 && n_stream > 1) {
        if ((uint32_t) seq_id >= n_stream) {
            throw std::runtime_error("DSV4 state sequence id out of stream range");
        }

        s0 = (uint32_t) seq_id;
        ns = 1;
        return;
    }

    s0 = 0;
    ns = seq_id >= 0 ? 1 : n_stream;
}

static void dsv4_state_dst_stream_range(
        uint32_t       n_stream,
        llama_seq_id   seq_id,
        uint32_t       ns,
        uint32_t     & s0) {
    if (seq_id >= 0) {
        if (ns != 1) {
            throw std::runtime_error("DSV4 sequence state stream count mismatch");
        }
        if (n_stream > 1 && (uint32_t) seq_id >= n_stream) {
            throw std::runtime_error("DSV4 state sequence id out of stream range");
        }

        s0 = n_stream > 1 ? (uint32_t) seq_id : 0;
        return;
    }

    if (ns != n_stream) {
        throw std::runtime_error("DSV4 full state stream count mismatch");
    }

    s0 = 0;
}

static void dsv4_state_write_tensor_streams(
        llama_io_write_i & io,
        ggml_tensor      * tensor,
        uint32_t           tensor_rows,
        uint32_t           n_rows,
        uint32_t           s0,
        uint32_t           ns,
        const std::vector<uint32_t> * stream_ids = nullptr) {
    const int32_t  type_i   = (int32_t) tensor->type;
    const uint64_t ne0      = tensor->ne[0];
    const uint64_t rows     = n_rows;
    const uint64_t row_size = ggml_row_size(tensor->type, tensor->ne[0]);

    if (n_rows > tensor_rows) {
        throw std::runtime_error("DSV4 state tensor row count exceeds storage");
    }

    io.write(&type_i,   sizeof(type_i));
    io.write(&ne0,      sizeof(ne0));
    io.write(&rows,     sizeof(rows));
    io.write(&row_size, sizeof(row_size));

    const size_t stream_stride = (size_t) tensor_rows*row_size;
    const size_t size          = (size_t) n_rows*row_size;
    if (size == 0) {
        return;
    }

    if (stream_ids && stream_ids->size() != ns) {
        throw std::runtime_error("DSV4 state tensor stream map size mismatch");
    }

    for (uint32_t s = 0; s < ns; ++s) {
        const uint32_t stream = stream_ids ? (*stream_ids)[s] : s0 + s;
        if ((int64_t) stream >= tensor->ne[2]) {
            throw std::runtime_error("DSV4 state tensor stream out of range");
        }
        const size_t offset = (size_t) stream*stream_stride;
        io.write_tensor(tensor, offset, size);
    }
}

static void dsv4_state_read_tensor_streams(
        llama_io_read_i & io,
        ggml_tensor     * tensor,
        uint32_t          tensor_rows,
        uint32_t          n_rows,
        uint32_t          s0,
        uint32_t          ns) {
    int32_t  type_i_ref;
    uint64_t ne0_ref;
    uint64_t rows_ref;
    uint64_t row_size_ref;

    io.read(&type_i_ref,   sizeof(type_i_ref));
    io.read(&ne0_ref,      sizeof(ne0_ref));
    io.read(&rows_ref,     sizeof(rows_ref));
    io.read(&row_size_ref, sizeof(row_size_ref));

    const int32_t  type_i   = (int32_t) tensor->type;
    const uint64_t ne0      = tensor->ne[0];
    const uint64_t rows     = n_rows;
    const uint64_t row_size = ggml_row_size(tensor->type, tensor->ne[0]);

    if (type_i != type_i_ref || ne0 != ne0_ref || rows != rows_ref || row_size != row_size_ref) {
        throw std::runtime_error("DSV4 state tensor metadata mismatch");
    }
    if (n_rows > tensor_rows) {
        throw std::runtime_error("DSV4 state tensor row count exceeds storage");
    }

    const size_t stream_stride = (size_t) tensor_rows*row_size;
    const size_t size          = (size_t) n_rows*row_size;
    if (size == 0) {
        return;
    }

    for (uint32_t s = 0; s < ns; ++s) {
        const size_t offset = (size_t) (s0 + s)*stream_stride;
        io.read_tensor(tensor, offset, size);
    }
}

static void dsv4_state_write_k_cache(
        llama_io_write_i    & io,
        const llama_kv_cache * kv,
        llama_seq_id          seq_id,
        llama_state_seq_flags flags,
        uint32_t              n_rows) {
    GGML_UNUSED(flags);

    uint32_t s0;
    uint32_t ns;
    dsv4_state_src_stream_range(kv->get_n_stream(), seq_id, s0, ns);

    const uint32_t version = DSV4_K_CACHE_STATE_VER;
    const uint32_t kv_size = kv->get_size();
    const auto layer_ids = kv->get_layer_ids();
    const uint32_t n_layer = layer_ids.size();

    if (n_rows > kv_size) {
        throw std::runtime_error("DSV4 K-cache state row count exceeds cache size");
    }

    io.write(&version, sizeof(version));
    io.write(&n_rows,  sizeof(n_rows));
    io.write(&ns,      sizeof(ns));
    io.write(&n_layer, sizeof(n_layer));

    for (uint32_t il : layer_ids) {
        io.write(&il, sizeof(il));
        dsv4_state_write_tensor_streams(io, kv->get_k_storage(il), kv_size, n_rows, s0, ns);
    }
}

static void dsv4_state_read_k_cache(
        llama_io_read_i  & io,
        llama_kv_cache   * kv,
        llama_seq_id       seq_id,
        llama_state_seq_flags flags) {
    GGML_UNUSED(flags);

    uint32_t version;
    uint32_t n_rows_ref;
    uint32_t ns;
    uint32_t n_layer_ref;

    io.read(&version,     sizeof(version));
    io.read(&n_rows_ref,  sizeof(n_rows_ref));
    io.read(&ns,          sizeof(ns));
    io.read(&n_layer_ref, sizeof(n_layer_ref));

    if (version != 1 && version != DSV4_K_CACHE_STATE_VER) {
        throw std::runtime_error("DSV4 K-cache state version mismatch");
    }

    const uint32_t kv_size = kv->get_size();
    if (version == 1 && n_rows_ref != kv_size) {
        LLAMA_LOG_INFO("kv size ref %d kv %d\n", n_rows_ref, kv_size);
        throw std::runtime_error("DSV4 K-cache state size mismatch");
    }
    if (n_rows_ref > kv_size) {
        LLAMA_LOG_INFO("kv rows ref %d kv %d\n", n_rows_ref, kv_size);
        throw std::runtime_error("DSV4 K-cache state size mismatch");
    }

    uint32_t s0;
    dsv4_state_dst_stream_range(kv->get_n_stream(), seq_id, ns, s0);

    const auto layer_ids = kv->get_layer_ids();
    if (n_layer_ref != layer_ids.size()) {
        throw std::runtime_error("DSV4 K-cache layer count mismatch");
    }

    for (uint32_t il : layer_ids) {
        uint32_t il_ref;
        io.read(&il_ref, sizeof(il_ref));
        if (il_ref != il) {
            throw std::runtime_error("DSV4 K-cache layer id mismatch");
        }

        dsv4_state_read_tensor_streams(io, kv->get_k_storage(il), kv_size, n_rows_ref, s0, ns);
    }
}

static std::string dsv4_plan_positions(const std::vector<int32_t> & values) {
    std::ostringstream ss;
    ss << "[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i > 0) {
            ss << ", ";
        }
        ss << values[i];
    }
    ss << "]";
    return ss.str();
}

static llama_kv_cache_dsv4_context::comp_plan dsv4_build_comp_plan(
        const llama_ubatch & ubatch,
        uint32_t ratio,
        bool overlap,
        uint32_t state_size,
        uint32_t kv_size,
        uint32_t n_stream,
        uint32_t n_rs_seq,
        const std::vector<uint32_t> & rs_idx) {
    llama_kv_cache_dsv4_context::comp_plan plan;
    plan.n_visible.resize(ubatch.n_tokens);
    plan.n_stream = dsv4_comp_graph_n_stream(ubatch, n_stream);

    // n_stream is the persistent cache/state layout; plan.n_stream is the
    // graph view for this ubatch and can be a subset of those streams.
    if (n_stream <= 1 && ubatch.n_seqs_unq > 1) {
        throw std::runtime_error("DSV4 single compressed stream cannot serve multiple sequences");
    }

    const int64_t state_rows = (int64_t) state_size*n_stream;

    struct persist_row {
        int32_t dst;
        int32_t src;
        llama_pos pos;
    };

    std::vector<persist_row> persist_rows;

    // For the overlap compressor, build_overlap_compressed_kv_from_state() consumes
    // state_read_idxs as two contiguous halves: the first ratio*n_blocks entries are
    // the "previous-window" gather indices for every block, followed by the
    // "current-window" indices for every block. Collect them separately here and
    // append cur after prev once the loop has visited all completed blocks
    std::vector<int32_t> overlap_prev_reads;
    std::vector<int32_t> overlap_cur_reads;

    std::map<std::pair<llama_seq_id, llama_pos>, int64_t> curr_token_idx_map;
    std::map<llama_seq_id, uint32_t> state_write_counts;

    for (uint32_t i = 0; i < ubatch.n_tokens; ++i) {
        for (int32_t s = 0; s < ubatch.n_seq_id[i]; ++s) {
            curr_token_idx_map[std::make_pair(ubatch.seq_id[i][s], ubatch.pos[i])] = i;
        }
    }

    const auto state_source_idx = [&](llama_seq_id seq_id, llama_pos pos) -> int32_t {
        if (pos < 0) {
            // The overlap compressor needs a zero/-inf source for the first
            // block's previous half. The graph appends that row after the
            // current-ubatch scratch rows.
            return (int32_t) (state_rows + ubatch.n_tokens);
        }

        const auto key = std::make_pair(seq_id, pos);
        if (curr_token_idx_map.find(key) != curr_token_idx_map.end()) {
            return (int32_t) (state_rows + curr_token_idx_map.at(key));
        }

        const int64_t stream_off = dsv4_stream_offset(n_stream, seq_id, state_size);
        return (int32_t) (stream_off + pos%state_size);
    };

    for (uint32_t i = 0; i < ubatch.n_tokens; ++i) {
        const llama_pos pos = ubatch.pos[i];

        if (pos < 0) {
            continue;
        }

        plan.state_pos.push_back((int32_t) (pos%ratio));

        const int64_t n_visible = (int64_t) (pos + 1)/ratio;
        plan.n_visible[i] = (int32_t) n_visible;
        plan.n_kv = std::max(plan.n_kv, n_visible);

        for (int32_t s = 0; s < ubatch.n_seq_id[i]; ++s) {
            const llama_seq_id seq_id = ubatch.seq_id[i][s];
            const int64_t stream_off = dsv4_stream_offset(n_stream, seq_id, state_size);
            const int32_t state_idx = (int32_t) (stream_off + pos%state_size);

            const auto it = std::find_if(persist_rows.begin(), persist_rows.end(),
                    [state_idx](const persist_row & row) {
                        return row.dst == state_idx;
                    });
            if (it == persist_rows.end()) {
                persist_rows.push_back({ state_idx, (int32_t) i, pos });
            } else if (pos > it->pos) {
                it->src = (int32_t) i;
                it->pos = pos;
            }

            if ((pos + 1) % ratio != 0) {
                continue;
            }

            const llama_pos source_start = pos + 1 - ratio;
            const int64_t cache_off = dsv4_stream_offset(n_stream, seq_id, kv_size);

            plan.state_write_idxs.push_back(cache_off + pos/ratio);
            plan.state_write_pos.push_back((int32_t) source_start);
            ++state_write_counts[seq_id];

            if (overlap) {
                const llama_pos prev_start = source_start - ratio;

                for (uint32_t j = 0; j < ratio; ++j) {
                    overlap_prev_reads.push_back(state_source_idx(seq_id, prev_start + j));
                }
                for (uint32_t j = 0; j < ratio; ++j) {
                    overlap_cur_reads.push_back(state_source_idx(seq_id, source_start + j));
                }
            } else {
                for (uint32_t j = 0; j < ratio; ++j) {
                    plan.state_read_idxs.push_back(state_source_idx(seq_id, source_start + j));
                }
            }
        }
    }

    if (ratio == DSV4_CSA_RATIO && !plan.state_pos.empty()) {
        assert(kv_size > 0);

        // Pad each stream to the reserve plan's block count.
        const auto append_dummy_block = [&](llama_seq_id seq_id, uint32_t i) {
            const int64_t cache_off = dsv4_stream_offset(n_stream, seq_id, kv_size);
            const int32_t source_idx = state_source_idx(seq_id, ubatch.pos[i]);

            plan.state_write_idxs.push_back(cache_off + kv_size - 1);
            plan.state_write_pos .push_back(0);

            if (overlap) {
                for (uint32_t j = 0; j < ratio; ++j) {
                    overlap_prev_reads.push_back(source_idx);
                    overlap_cur_reads .push_back(source_idx);
                }
            } else {
                for (uint32_t j = 0; j < ratio; ++j) {
                    plan.state_read_idxs.push_back(source_idx);
                }
            }
        };

        if (dsv4_ubatch_has_coupled(ubatch)) {
            if (plan.state_write_idxs.empty()) {
                uint32_t i = 0;
                while (i < ubatch.n_tokens && ubatch.pos[i] < 0) {
                    ++i;
                }
                assert(i < ubatch.n_tokens);
                append_dummy_block(ubatch.seq_id[i][0], i);
            }
        } else {
            const uint32_t n_blocks = (std::max<uint32_t>(1, ubatch.n_seq_tokens) + ratio - 1)/ratio;

            for (uint32_t s = 0; s < ubatch.n_seqs_unq; ++s) {
                const llama_seq_id seq_id = ubatch.seq_id_unq[s];
                const uint32_t n_writes = state_write_counts[seq_id];
                if (n_writes >= n_blocks) {
                    continue;
                }
                if (n_writes + 1 != n_blocks) {
                    throw std::runtime_error("DSV4 CSA sequence positions are not contiguous");
                }

                uint32_t i = 0;
                while (i < ubatch.n_tokens && (ubatch.pos[i] < 0 || !dsv4_token_has_seq(ubatch, i, seq_id))) {
                    ++i;
                }
                assert(i < ubatch.n_tokens);
                append_dummy_block(seq_id, i);
            }
        }
    }

    if (ratio == DSV4_HCA_RATIO && !plan.state_pos.empty() && plan.state_write_idxs.empty()) {
        assert(kv_size > 0);
        // the last slot must not be live, or the dummy write would corrupt it;
        // a full stream implies a completed block, which implies real writes
        assert(plan.n_kv < (int64_t) kv_size);

        // Keep the compress/write ops in the graph when no HCA block completes
        // in this ubatch. The dummy block writes to the last cache slot and is
        // masked out.
        uint32_t i = 0;
        while (i < ubatch.n_tokens && ubatch.pos[i] < 0) {
            ++i;
        }
        assert(i < ubatch.n_tokens);

        const llama_seq_id seq_id = ubatch.seq_id[i][0];
        const int64_t cache_off = dsv4_stream_offset(n_stream, seq_id, kv_size);
        const int32_t source_idx = state_source_idx(seq_id, ubatch.pos[i]);

        plan.state_write_idxs.push_back(cache_off + kv_size - 1);
        plan.state_write_pos .push_back(0);

        for (uint32_t j = 0; j < ratio; ++j) {
            plan.state_read_idxs.push_back(source_idx);
        }
    }

    if (overlap) {
        // [ all blocks' prev-window indices | all blocks' cur-window indices ]
        plan.state_read_idxs.reserve(overlap_prev_reads.size() + overlap_cur_reads.size());
        plan.state_read_idxs.insert(plan.state_read_idxs.end(),
                overlap_prev_reads.begin(), overlap_prev_reads.end());
        plan.state_read_idxs.insert(plan.state_read_idxs.end(),
                overlap_cur_reads.begin(), overlap_cur_reads.end());
    }

    // Keep the mask (and with it the compressed-attention branch) present even
    // before the first block is visible, so the graph topology never changes.
    // Padded slots are masked out; comp cache buffers are zero-initialized.
    plan.n_kv = std::max<int64_t>(GGML_PAD(plan.n_kv, 256u), 256);

    std::sort(persist_rows.begin(), persist_rows.end(),
            [](const persist_row & a, const persist_row & b) {
                return a.dst < b.dst;
            });

    for (const persist_row & row : persist_rows) {
        plan.state_persist_src_idxs.push_back(row.src);
        plan.state_persist_dst_idxs.push_back(row.dst);
    }

    if (n_rs_seq > 0) {
        // Emit restore/snapshot entries for all layout streams so that the
        // graph tensor sizes do not depend on the ubatch's sequence count.
        // Streams not present in the ubatch get no-op entries.
        for (uint32_t stream = 0; stream < n_stream; ++stream) {
            llama_seq_id seq_id = -1;
            if (n_stream == 1) {
                // a unified stream serves any single sequence
                seq_id = ubatch.n_seqs_unq > 0 ? ubatch.seq_id_unq[0] : -1;
            } else {
                for (uint32_t s = 0; s < ubatch.n_seqs_unq; ++s) {
                    if (ubatch.seq_id_unq[s] == (llama_seq_id) stream) {
                        seq_id = ubatch.seq_id_unq[s];
                        break;
                    }
                }
            }

            const int64_t stream_off = (int64_t) stream*state_size;
            const uint32_t rollback = seq_id >= 0 && (uint32_t) seq_id < rs_idx.size() ? rs_idx[seq_id] : 0;
            // Keep the restore graph fixed-width when no rollback is pending.
            const int64_t src_plane = rollback > 0 && rollback <= n_rs_seq ? (int64_t) rollback*state_rows : 0;
            for (uint32_t r = 0; r < state_size; ++r) {
                plan.state_restore_src_idxs.push_back((int32_t) (src_plane + stream_off + r));
                plan.state_restore_dst_idxs.push_back((int32_t) (stream_off + r));
            }

            std::vector<uint32_t> token_idxs;
            token_idxs.reserve(ubatch.n_tokens);
            if (seq_id >= 0) {
                for (uint32_t i = 0; i < ubatch.n_tokens; ++i) {
                    if (dsv4_token_has_seq(ubatch, i, seq_id)) {
                        token_idxs.push_back(i);
                    }
                }
            }

            const uint32_t n_seq_tokens = (uint32_t) token_idxs.size();
            const int64_t scratch_off = (int64_t) state_rows*(1 + n_rs_seq);
            for (uint32_t d = 1; d <= n_rs_seq; ++d) {
                const int64_t dst_plane = (int64_t) d*state_rows;
                const uint32_t prefix = d <= n_seq_tokens ? n_seq_tokens - d : 0;

                for (uint32_t r = 0; r < state_size; ++r) {
                    int32_t src = (int32_t) (stream_off + r);

                    for (uint32_t j = 0; j < prefix; ++j) {
                        const uint32_t i_tok = token_idxs[j];
                        if (ubatch.pos[i_tok] >= 0 && (uint32_t) (ubatch.pos[i_tok]%state_size) == r) {
                            src = (int32_t) (scratch_off + i_tok);
                        }
                    }

                    if (n_seq_tokens == 0) {
                        // no-op: copy the snapshot plane onto itself
                        src = (int32_t) (dst_plane + stream_off + r);
                    }

                    plan.state_snapshot_src_idxs.push_back(src);
                    plan.state_snapshot_dst_idxs.push_back((int32_t) (dst_plane + stream_off + r));
                }
            }
        }
    }

    static const bool debug = []() {
        const char * env = getenv("LLAMA_DSV4_COMPRESS_DEBUG");
        return env && atoi(env) > 0;
    }();

    if (debug) {
        LLAMA_LOG_DEBUG("%s: ratio=%u, n_tokens=%u, n_seqs_unq=%u, state_persist_dst=%s, state_write_pos=%s\n",
                __func__, ratio, ubatch.n_tokens, ubatch.n_seqs_unq,
                dsv4_plan_positions(plan.state_persist_dst_idxs).c_str(),
                dsv4_plan_positions(plan.state_write_pos).c_str());
        for (uint32_t s = 0; s < ubatch.n_seqs_unq; ++s) {
            const llama_seq_id seq_id = ubatch.seq_id_unq[s];
            const uint32_t rollback = seq_id >= 0 && (uint32_t) seq_id < rs_idx.size() ? rs_idx[seq_id] : 0;
            LLAMA_LOG_DEBUG("%s:   seq %d pos [%d, %d] rollback=%u\n", __func__, seq_id,
                    ubatch.pos[0], ubatch.pos[ubatch.n_tokens - 1], rollback);
        }
    }

    return plan;
}

static std::vector<llama_kv_cache_dsv4_context::comp_plan> dsv4_build_comp_plans(
        const std::vector<llama_ubatch> & ubatches,
        uint32_t ratio,
        bool overlap,
        uint32_t state_size,
        uint32_t kv_size,
        uint32_t n_stream,
        uint32_t n_rs_seq,
        const std::vector<uint32_t> & rs_idx) {
    std::vector<llama_kv_cache_dsv4_context::comp_plan> plans;
    plans.reserve(ubatches.size());

    // the first ubatch touching a seq consumes its rollback restore
    std::vector<uint32_t> rs(rs_idx);
    for (const llama_ubatch & ubatch : ubatches) {
        plans.push_back(dsv4_build_comp_plan(ubatch, ratio, overlap, state_size, kv_size, n_stream, n_rs_seq, rs));

        for (uint32_t s = 0; s < ubatch.n_seqs_unq; ++s) {
            const llama_seq_id seq_id = ubatch.seq_id_unq[s];
            if (seq_id >= 0 && (size_t) seq_id < rs.size()) {
                rs[seq_id] = 0;
            }
        }
    }

    return plans;
}

static llama_kv_cache::slot_info_vec_t dsv4_build_comp_sinfos(
        const std::vector<llama_ubatch> & ubatches,
        uint32_t n_stream) {
    llama_kv_cache::slot_info_vec_t sinfos;
    sinfos.reserve(ubatches.size());

    for (const llama_ubatch & ubatch : ubatches) {
        if (n_stream <= 1 && ubatch.n_seqs_unq > 1) {
            throw std::runtime_error("DSV4 single compressed stream cannot serve multiple sequences");
        }

        const uint32_t ns = (uint32_t) dsv4_comp_graph_n_stream(ubatch, n_stream);
        llama_kv_cache::slot_info sinfo;
        sinfo.s0 = n_stream > 1 ? LLAMA_MAX_SEQ : 0;
        sinfo.s1 = 0;
        sinfo.resize(ns);

        for (uint32_t s = 0; s < ns; ++s) {
            const llama_seq_id seq_id = n_stream > 1 ? ubatch.seq_id_unq[s] : 0;
            const uint32_t strm = (uint32_t) dsv4_stream_offset(n_stream, seq_id, 1);

            sinfo.s0 = std::min(sinfo.s0, strm);
            sinfo.s1 = std::max(sinfo.s1, strm);
            sinfo.strm[s] = strm;
            sinfo.idxs[s].resize(1, 0);
        }

        if (n_stream > 1 && sinfo.s1 - sinfo.s0 + 1 != ns) {
            throw std::runtime_error("DSV4 compressed streams are not contiguous in ubatch");
        }

        sinfos.push_back(std::move(sinfo));
    }

    return sinfos;
}

static llama_kv_cache::slot_info_vec_t dsv4_build_raw_read_sinfos(
        const llama_kv_cache::slot_info_vec_t & sinfos_write,
        const std::vector<llama_ubatch> & ubatches) {
    llama_kv_cache::slot_info_vec_t sinfos;
    sinfos.reserve(ubatches.size());

    for (size_t i = 0; i < ubatches.size(); ++i) {
        const llama_ubatch & ubatch = ubatches[i];
        const auto & sinfo_write = sinfos_write[i];

        if (!dsv4_ubatch_has_coupled(ubatch)) {
            sinfos.push_back(sinfo_write);
            continue;
        }

        const llama_seq_id seq_id = ubatch.seq_id[0][0];
        uint32_t i_stream = 0;
        for (; i_stream < sinfo_write.n_stream(); ++i_stream) {
            if (sinfo_write.strm[i_stream] == seq_id) {
                break;
            }
        }
        if (i_stream == sinfo_write.n_stream()) {
            throw std::runtime_error("DSV4 raw write stream not found for coupled read");
        }

        llama_kv_cache::slot_info sinfo;
        sinfo.s0 = sinfo_write.strm[i_stream];
        sinfo.s1 = sinfo_write.strm[i_stream];
        sinfo.resize(1);
        sinfo.strm[0] = sinfo_write.strm[i_stream];
        sinfo.idxs[0] = sinfo_write.idxs[i_stream];
        sinfos.push_back(std::move(sinfo));
    }

    return sinfos;
}

static llama_kv_cache_dsv4_context::comp_plan dsv4_build_reserve_comp_plan(
        const llama_ubatch & ubatch,
        uint32_t ratio,
        bool overlap,
        uint32_t state_size,
        uint32_t kv_size,
        uint32_t n_stream,
        uint32_t n_rs_seq) {
    llama_kv_cache_dsv4_context::comp_plan plan;
    plan.n_visible.resize(ubatch.n_tokens);
    plan.n_stream = dsv4_comp_graph_n_stream(ubatch, n_stream);
    plan.n_kv = kv_size;

    if (ubatch.n_tokens == 0) {
        return plan;
    }

    // worst case over every seq split: sum of per-seq ceil(tokens/ratio) is at
    // most floor(n_tokens/ratio) + n_seqs
    const uint32_t n_seqs = std::max<uint32_t>(1, ubatch.n_seqs);
    const size_t n_blocks = (size_t) ubatch.n_tokens/ratio + n_seqs;

    const uint64_t state_rows = (uint64_t) state_size*n_stream;
    const size_t n_persist = (size_t) std::min<uint64_t>(ubatch.n_tokens, state_rows);
    const size_t n_restore = n_rs_seq > 0 ? (size_t) state_size*n_stream : 0;
    const size_t n_snapshot = (size_t) n_rs_seq*state_size*n_stream;

    plan.state_pos .resize(ubatch.n_tokens);
    plan.state_persist_src_idxs.resize(n_persist);
    plan.state_persist_dst_idxs.resize(n_persist);
    plan.state_restore_src_idxs.resize(n_restore);
    plan.state_restore_dst_idxs.resize(n_restore);
    plan.state_snapshot_src_idxs.resize(n_snapshot);
    plan.state_snapshot_dst_idxs.resize(n_snapshot);
    plan.state_read_idxs .resize((overlap ? 2u : 1u)*ratio*n_blocks);
    plan.state_write_idxs.resize(n_blocks);
    plan.state_write_pos .resize(n_blocks);

    return plan;
}

static void dsv4_make_k_only(llama_hparams & hparams) {
    // llama_kv_cache uses hparams.is_mla() to allocate K-only storage.
    hparams.n_embd_head_k_mla_impl = hparams.n_embd_head_k();
    hparams.n_embd_head_v_mla_impl = hparams.n_embd_head_k();
}

//
// llama_dsv4_comp_state
//

llama_dsv4_comp_state::llama_dsv4_comp_state(
        const llama_model & model,
                bool        offload,
                bool        unified,
            uint32_t        n_seq_max,
            uint32_t        ratio,
            uint32_t        state_size,
            uint32_t        n_embd_state,
            uint32_t        n_rs_seq,
        const char    * name,
        const llama_memory_i::layer_filter_cb & filter) :
    ratio(ratio),
    state_size(state_size),
    n_embd_state(n_embd_state),
    n_stream(unified ? 1 : n_seq_max),
    n_rs_seq(n_rs_seq) {
    const llama_hparams & hparams = model.hparams;

    struct ggml_backend_buft_comparator {
        bool operator()(const ggml_backend_buffer_type_t & lhs, const ggml_backend_buffer_type_t & rhs) const {
            return strcmp(ggml_backend_buft_name(lhs), ggml_backend_buft_name(rhs)) < 0;
        }
    };

    std::map<ggml_backend_buffer_type_t, ggml_context_ptr, ggml_backend_buft_comparator> ctx_map;

    auto ctx_for_buft = [&](ggml_backend_buffer_type_t buft) -> ggml_context * {
        auto it = ctx_map.find(buft);
        if (it == ctx_map.end()) {
            ggml_init_params params = {
                /*.mem_size   =*/ size_t(2u*(1 + n_stream)*hparams.n_layer()*ggml_tensor_overhead()),
                /*.mem_buffer =*/ NULL,
                /*.no_alloc   =*/ true,
            };

            ggml_context * ctx = ggml_init(params);
            if (!ctx) {
                return nullptr;
            }

            ctx_map.emplace(buft, ctx);

            return ctx;
        }

        return it->second.get();
    };

    for (uint32_t il = 0; il < hparams.n_layer(); ++il) {
        if (filter && !filter(il)) {
            continue;
        }

        const char * dev_name = "CPU";

        ggml_backend_buffer_type_t buft = ggml_backend_cpu_buffer_type();

        if (offload) {
            auto * dev = model.dev_layer(il);
            buft = ggml_backend_dev_buffer_type(dev);

            dev_name = ggml_backend_dev_name(dev);
        }

        LLAMA_LOG_DEBUG("%s: layer %3d: dev = %s\n", __func__, il, dev_name);

        ggml_context * ctx = ctx_for_buft(buft);
        if (!ctx) {
            throw std::runtime_error("failed to create ggml context for DSV4 compressor state");
        }

        const uint32_t n_planes = n_stream*(1 + n_rs_seq);
        ggml_tensor * kv    = ggml_new_tensor_3d(ctx, GGML_TYPE_F32, n_embd_state, state_size, n_planes);
        ggml_tensor * score = ggml_new_tensor_3d(ctx, GGML_TYPE_F32, n_embd_state, state_size, n_planes);

        ggml_format_name(kv,    "dsv4_%s_state_kv_l%d",    name, il);
        ggml_format_name(score, "dsv4_%s_state_score_l%d", name, il);

        std::vector<ggml_tensor *> kv_stream;
        std::vector<ggml_tensor *> score_stream;

        for (uint32_t s = 0; s < n_stream; ++s) {
            kv_stream.push_back(ggml_view_2d(ctx, kv, n_embd_state, state_size, kv->nb[1], s*kv->nb[2]));
            score_stream.push_back(ggml_view_2d(ctx, score, n_embd_state, state_size, score->nb[1], s*score->nb[2]));
        }

        map_layer_ids[il] = layers.size();

        layers.push_back({ il, kv, score, std::move(kv_stream), std::move(score_stream) });
    }

    for (auto & [buft, ctx] : ctx_map) {
        ggml_backend_buffer_t buf = ggml_backend_alloc_ctx_tensors_from_buft(ctx.get(), buft);
        if (!buf) {
            throw std::runtime_error("failed to allocate buffer for DSV4 compressor state");
        }

        ggml_backend_buffer_clear(buf, 0);

        LLAMA_LOG_INFO("%s: %10s DSV4 %s state buffer size = %8.2f MiB\n",
                __func__, ggml_backend_buffer_name(buf), name, ggml_backend_buffer_get_size(buf)/1024.0/1024.0);

        ctxs_bufs.emplace_back(std::move(ctx), buf);
    }

    LLAMA_LOG_INFO("%s: %s ratio = %u, state = %u x %u, streams = %u, rs_seq = %u, layers = %zu, size = %7.2f MiB\n",
            __func__, name, ratio, state_size, n_embd_state, n_stream, n_rs_seq, layers.size(), total_size()/1024.0/1024.0);
}

void llama_dsv4_comp_state::clear(llama_seq_id seq_id, bool data) {
    if (!data) {
        return;
    }

    if (seq_id >= 0) {
        GGML_ASSERT((uint32_t) seq_id < n_stream);

        for (const auto & layer : layers) {
            for (uint32_t d = 0; d <= n_rs_seq; ++d) {
                const uint32_t stream = d*n_stream + (uint32_t) seq_id;
                dsv4_clear_tensor_stream(layer.kv,    stream);
                dsv4_clear_tensor_stream(layer.score, stream);
            }
        }
        return;
    }

    for (auto & [_, buf] : ctxs_bufs) {
        ggml_backend_buffer_clear(buf.get(), 0);
    }
}

void llama_dsv4_comp_state::seq_cp(llama_seq_id seq_id_src, llama_seq_id seq_id_dst) {
    GGML_ASSERT(seq_id_src >= 0 && (uint32_t) seq_id_src < n_stream);
    GGML_ASSERT(seq_id_dst >= 0 && (uint32_t) seq_id_dst < n_stream);

    if (seq_id_src == seq_id_dst) {
        return;
    }

    clear(seq_id_dst, true);

    sc_info.ssrc.push_back((uint32_t) seq_id_src);
    sc_info.sdst.push_back((uint32_t) seq_id_dst);
}

void llama_dsv4_comp_state::apply_copies(const stream_copy_info & sc_info) const {
    for (size_t i = 0; i < sc_info.ssrc.size(); ++i) {
        const uint32_t ssrc = sc_info.ssrc[i];
        const uint32_t sdst = sc_info.sdst[i];

        for (const auto & layer : layers) {
            ggml_backend_tensor_copy(layer.kv_stream[ssrc], layer.kv_stream[sdst]);
            ggml_backend_tensor_copy(layer.score_stream[ssrc], layer.score_stream[sdst]);
        }
    }
}

uint32_t llama_dsv4_comp_state::get_ratio() const {
    return ratio;
}

uint32_t llama_dsv4_comp_state::get_state_size() const {
    return state_size;
}

uint32_t llama_dsv4_comp_state::get_n_stream() const {
    return n_stream;
}

uint32_t llama_dsv4_comp_state::get_n_rs_seq() const {
    return n_rs_seq;
}

uint32_t llama_dsv4_comp_state::get_n_rows() const {
    return state_size*n_stream;
}

std::map<ggml_backend_buffer_type_t, size_t> llama_dsv4_comp_state::memory_breakdown() const {
    std::map<ggml_backend_buffer_type_t, size_t> ret;
    for (const auto & [_, buf] : ctxs_bufs) {
        ggml_backend_buffer_type_t buft = ggml_backend_buffer_get_type(buf.get());
        ret[buft] += ggml_backend_buffer_get_size(buf.get());
    }
    return ret;
}

void llama_dsv4_comp_state::state_write(
        llama_io_write_i & io,
        llama_seq_id seq_id,
        llama_state_seq_flags flags,
        const std::vector<uint32_t> & rs_idx) const {
    GGML_UNUSED(flags);

    uint32_t s0;
    uint32_t ns;
    dsv4_state_src_stream_range(n_stream, seq_id, s0, ns);

    std::vector<uint32_t> stream_ids(ns);
    for (uint32_t s = 0; s < ns; ++s) {
        const uint32_t seq = seq_id >= 0 ? (uint32_t) seq_id : s0 + s;
        if (seq >= rs_idx.size() || rs_idx[seq] > n_rs_seq) {
            throw std::runtime_error("DSV4 recurrent state rollback index out of range");
        }
        stream_ids[s] = rs_idx[seq]*n_stream + s0 + s;
    }

    const uint32_t version      = DSV4_COMP_STATE_VER;
    const uint32_t n_layer      = layers.size();

    io.write(&version,      sizeof(version));
    io.write(&ratio,        sizeof(ratio));
    io.write(&state_size,   sizeof(state_size));
    io.write(&n_embd_state, sizeof(n_embd_state));
    io.write(&ns,           sizeof(ns));
    io.write(&n_layer,      sizeof(n_layer));

    for (const auto & layer : layers) {
        io.write(&layer.il, sizeof(layer.il));

        dsv4_state_write_tensor_streams(io, layer.kv,    state_size, state_size, s0, ns, &stream_ids);
        dsv4_state_write_tensor_streams(io, layer.score, state_size, state_size, s0, ns, &stream_ids);
    }
}

void llama_dsv4_comp_state::state_read(llama_io_read_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) {
    GGML_UNUSED(flags);

    uint32_t version;
    uint32_t ratio_ref;
    uint32_t state_size_ref;
    uint32_t n_embd_state_ref;
    uint32_t ns;
    uint32_t n_layer_ref;

    io.read(&version,          sizeof(version));
    io.read(&ratio_ref,        sizeof(ratio_ref));
    io.read(&state_size_ref,   sizeof(state_size_ref));
    io.read(&n_embd_state_ref, sizeof(n_embd_state_ref));
    io.read(&ns,               sizeof(ns));
    io.read(&n_layer_ref,      sizeof(n_layer_ref));

    if (version != DSV4_COMP_STATE_VER) {
        throw std::runtime_error("DSV4 compressor state version mismatch");
    }
    if (ratio_ref != ratio || state_size_ref != state_size || n_embd_state_ref != n_embd_state) {
        throw std::runtime_error("DSV4 compressor state metadata mismatch");
    }
    if (n_layer_ref != layers.size()) {
        throw std::runtime_error("DSV4 compressor state layer count mismatch");
    }

    uint32_t s0;
    dsv4_state_dst_stream_range(n_stream, seq_id, ns, s0);

    for (const auto & layer : layers) {
        uint32_t il_ref;
        io.read(&il_ref, sizeof(il_ref));
        if (il_ref != layer.il) {
            throw std::runtime_error("DSV4 compressor state layer id mismatch");
        }

        dsv4_state_read_tensor_streams(io, layer.kv,    state_size, state_size, s0, ns);
        dsv4_state_read_tensor_streams(io, layer.score, state_size, state_size, s0, ns);
    }
}

ggml_tensor * llama_dsv4_comp_state::get_kv_all(ggml_context * ctx, int32_t il) const {
    const int32_t ids = map_layer_ids.at(il);
    ggml_tensor * state = layers[ids].kv;

    return ggml_view_2d(ctx, state, state->ne[0], get_n_rows()*(1 + n_rs_seq), state->nb[1], 0);
}

ggml_tensor * llama_dsv4_comp_state::get_score_all(ggml_context * ctx, int32_t il) const {
    const int32_t ids = map_layer_ids.at(il);
    ggml_tensor * state = layers[ids].score;

    return ggml_view_2d(ctx, state, state->ne[0], get_n_rows()*(1 + n_rs_seq), state->nb[1], 0);
}

ggml_tensor * llama_dsv4_comp_state::get_kv(ggml_context * ctx, int32_t il) const {
    ggml_tensor * state = get_kv_all(ctx, il);
    const size_t row_size = ggml_row_size(state->type, state->ne[0]);

    return ggml_view_2d(ctx, state, state->ne[0], get_n_rows(), state->nb[1], 0*row_size);
}

ggml_tensor * llama_dsv4_comp_state::get_score(ggml_context * ctx, int32_t il) const {
    ggml_tensor * state = get_score_all(ctx, il);
    const size_t row_size = ggml_row_size(state->type, state->ne[0]);

    return ggml_view_2d(ctx, state, state->ne[0], get_n_rows(), state->nb[1], 0*row_size);
}

ggml_tensor * llama_dsv4_comp_state::cpy_kv(ggml_context * ctx, ggml_tensor * cur, ggml_tensor * idxs, int32_t il) const {
    return ggml_set_rows(ctx, get_kv_all(ctx, il), cur, idxs);
}

ggml_tensor * llama_dsv4_comp_state::cpy_score(ggml_context * ctx, ggml_tensor * cur, ggml_tensor * idxs, int32_t il) const {
    return ggml_set_rows(ctx, get_score_all(ctx, il), cur, idxs);
}

size_t llama_dsv4_comp_state::total_size() const {
    size_t size = 0;

    for (const auto & [_, buf] : ctxs_bufs) {
        size += ggml_backend_buffer_get_size(buf.get());
    }

    return size;
}

//
// llama_kv_cache_dsv4
//

llama_kv_cache_dsv4::llama_kv_cache_dsv4(
        const llama_model & model,
                ggml_type   type_k,
                ggml_type   type_v,
                     bool   v_trans,
                     bool   offload,
                     bool   swa_full,
                     bool   unified,
                 uint32_t   kv_size,
                 uint32_t   n_seq_max,
                 uint32_t   n_ubatch,
                 uint32_t   n_pad,
                 uint32_t   n_rs_seq,
    const layer_filter_cb & filter,
    const  layer_reuse_cb & reuse) :
    hparams_raw(model.hparams),
    hparams_csa(model.hparams),
    hparams_hca(model.hparams),
    hparams_lid(model.hparams),
    n_seq_max(n_seq_max),
    n_rs_seq(n_rs_seq),
    rs_idx(n_seq_max, 0) {

    const layer_filter_cb filter_raw = [&](int32_t il) {
        if (filter && !filter(il)) {
            return false;
        }

        return true;
    };

    GGML_UNUSED(unified);

    // Keep DSV4 KV/state streams per sequence even when public KV mode is unified.
    const bool unified_raw = false;

    hparams_raw.n_layer_nextn = 0;
    hparams_csa.n_layer_nextn = 0;
    hparams_hca.n_layer_nextn = 0;
    hparams_lid.n_layer_nextn = 0;

    LLAMA_LOG_INFO("%s: creating DSV4 raw KV cache\n", __func__);

    dsv4_make_k_only(hparams_raw);

    kv_raw = std::make_unique<llama_kv_cache_iswa>(
            model, hparams_raw, type_k, type_v,
            v_trans, offload, swa_full, unified_raw, kv_size, n_seq_max, n_ubatch, n_pad,
            nullptr, filter_raw, reuse, nullptr);

    dsv4_make_k_only(hparams_csa);
    dsv4_make_k_only(hparams_hca);

    std::fill(hparams_lid.n_head_kv_arr.begin(), hparams_lid.n_head_kv_arr.end(), 1);
    hparams_lid.n_embd_head_k_full = model.hparams.indexer_head_size;
    hparams_lid.n_embd_head_v_full = model.hparams.indexer_head_size;
    hparams_lid.n_embd_head_k_swa  = model.hparams.indexer_head_size;
    hparams_lid.n_embd_head_v_swa  = model.hparams.indexer_head_size;
    hparams_lid.rope_type          = LLAMA_ROPE_TYPE_NEOX;
    dsv4_make_k_only(hparams_lid);

    const layer_filter_cb filter_csa = [&](int32_t il) {
        if (filter && !filter(il)) {
            return false;
        }

        return model.hparams.dsv4_compress_ratios[il] == DSV4_CSA_RATIO;
    };

    const layer_filter_cb filter_hca = [&](int32_t il) {
        if (filter && !filter(il)) {
            return false;
        }

        return model.hparams.dsv4_compress_ratios[il] == DSV4_HCA_RATIO;
    };

    const bool unified_compressed = false;

    LLAMA_LOG_INFO("%s: creating DSV4 CSA compressed KV cache, size = %u cells\n",
            __func__, dsv4_comp_size(kv_size, DSV4_CSA_RATIO));

    kv_csa = std::make_unique<llama_kv_cache>(
            model, hparams_csa, type_k, type_v,
            v_trans, offload, unified_compressed, GGML_PAD(dsv4_comp_size(kv_size, DSV4_CSA_RATIO), 256u), n_seq_max, n_pad,
            0, LLAMA_SWA_TYPE_NONE, nullptr, filter_csa, nullptr, nullptr);

    LLAMA_LOG_INFO("%s: creating DSV4 HCA compressed KV cache, size = %u cells\n",
            __func__, dsv4_comp_size(kv_size, DSV4_HCA_RATIO));

    kv_hca = std::make_unique<llama_kv_cache>(
            model, hparams_hca, type_k, type_v,
            v_trans, offload, unified_compressed, GGML_PAD(dsv4_comp_size(kv_size, DSV4_HCA_RATIO), 256u), n_seq_max, n_pad,
            0, LLAMA_SWA_TYPE_NONE, nullptr, filter_hca, nullptr, nullptr);

    LLAMA_LOG_INFO("%s: creating DSV4 lightning-indexer KV cache, size = %u cells\n",
            __func__, dsv4_comp_size(kv_size, DSV4_CSA_RATIO));

    kv_lid = std::make_unique<llama_kv_cache>(
            model, hparams_lid, type_k, type_v,
            v_trans, offload, unified_compressed, GGML_PAD(dsv4_comp_size(kv_size, DSV4_CSA_RATIO), 256u), n_seq_max, n_pad,
            0, LLAMA_SWA_TYPE_NONE, nullptr, filter_csa, nullptr, nullptr);

    LLAMA_LOG_INFO("%s: creating DSV4 CSA compressor state\n", __func__);

    csa_state = std::make_unique<llama_dsv4_comp_state>(
            model, offload, unified_compressed, n_seq_max, DSV4_CSA_RATIO, 2*DSV4_CSA_RATIO,
            2*model.hparams.n_embd_head_k(), n_rs_seq, "csa", filter_csa);

    LLAMA_LOG_INFO("%s: creating DSV4 HCA compressor state\n", __func__);

    hca_state = std::make_unique<llama_dsv4_comp_state>(
            model, offload, unified_compressed, n_seq_max, DSV4_HCA_RATIO, DSV4_HCA_RATIO,
            model.hparams.n_embd_head_k(), n_rs_seq, "hca", filter_hca);

    LLAMA_LOG_INFO("%s: creating DSV4 lightning-indexer compressor state\n", __func__);

    lid_state = std::make_unique<llama_dsv4_comp_state>(
            model, offload, unified_compressed, n_seq_max, DSV4_CSA_RATIO, 2*DSV4_CSA_RATIO,
            2*model.hparams.indexer_head_size, n_rs_seq, "lid", filter_csa);

    // DSV4 attention reads compressed-K / compressor-state rows that the current
    // graph does not necessarily overwrite; uninitialized buffer contents would
    // otherwise leak in (instance-specific garbage) and corrupt recall. Zero all
    // compressed buffers up front so reads of un-written rows are deterministic.
    clear_compressed(-1, true);
}

llama_memory_context_ptr llama_kv_cache_dsv4::init_batch(
            llama_batch_allocr & balloc,
            uint32_t n_ubatch,
            bool embd_all) {
    GGML_UNUSED(embd_all);

    const bool raw_per_seq  = kv_raw->get_base()->get_n_stream() != 1;
    const bool comp_per_seq = csa_state->get_n_stream() > 1;
    const bool has_coupled = dsv4_batch_has_coupled(balloc.get_batch());

    const auto make_context = [&](std::vector<llama_ubatch> ubatches) -> llama_memory_context_ptr {
        auto ubatches_raw = dsv4_build_raw_write_ubatches(ubatches);

        auto sinfos_raw_base_write = kv_raw->get_base()->prepare(ubatches_raw);
        if (sinfos_raw_base_write.empty()) {
            return nullptr;
        }

        auto sinfos_raw_swa_write = kv_raw->get_swa()->prepare(ubatches_raw);
        if (sinfos_raw_swa_write.empty()) {
            return nullptr;
        }

        auto sinfos_raw_swa_read = dsv4_build_raw_read_sinfos(sinfos_raw_swa_write, ubatches);

        return std::make_unique<llama_kv_cache_dsv4_context>(
                this,
                std::move(sinfos_raw_base_write),
                std::move(sinfos_raw_swa_write),
                std::move(sinfos_raw_swa_read),
                std::move(ubatches),
                std::move(ubatches_raw));
    };

    // Match llama_kv_cache_iswa splitting when DSV4 compressed state does not
    // require per-sequence graph layout.
    do {
        if (raw_per_seq || comp_per_seq) {
            break;
        }

        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            auto ubatch = balloc.split_simple(n_ubatch);
            if (ubatch.n_tokens == 0) {
                break;
            }
            ubatches.push_back(std::move(ubatch)); // NOLINT
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            break;
        }

        if (auto ctx = make_context(std::move(ubatches))) {
            return ctx;
        }
    } while (false);

    // When raw or compressed state is per-sequence, independent sequences can
    // share an equal-length ubatch. Coupled sequence sets still serialize until
    // DSV4 has explicit shared-state handling for compressed streams.
    do {
        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            llama_ubatch ubatch;
            if (has_coupled) {
                ubatch = balloc.split_seq(n_ubatch);
            } else {
                // [TAG_RECURRENT_ROLLBACK_SPLITS]
                // the trailing (1 + n_rs_seq) tokens of each seq must stay in the same ubatch
                ubatch = balloc.split_equal(n_ubatch, raw_per_seq || comp_per_seq, n_rs_seq > 0 ? n_rs_seq + 1 : 0);
            }

            if (ubatch.n_tokens == 0) {
                break;
            }
            ubatches.push_back(std::move(ubatch)); // NOLINT
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            break;
        }

        if (auto ctx = make_context(std::move(ubatches))) {
            return ctx;
        }
    } while (false);

    return std::make_unique<llama_kv_cache_dsv4_context>(LLAMA_MEMORY_STATUS_FAILED_PREPARE);
}

llama_memory_context_ptr llama_kv_cache_dsv4::init_full() {
    return std::make_unique<llama_kv_cache_dsv4_context>(this);
}

llama_memory_context_ptr llama_kv_cache_dsv4::init_update(llama_context * lctx, bool optimize) {
    return std::make_unique<llama_kv_cache_dsv4_context>(
            this,
            lctx,
            optimize,
            std::move(csa_state->sc_info),
            std::move(hca_state->sc_info),
            std::move(lid_state->sc_info));
}

bool llama_kv_cache_dsv4::get_can_shift() const {
    // Compressed row metadata uses block-derived positions. Keep shifting
    // disabled until DSV4 compressed-cache shift semantics are wired.
    return false;
}

void llama_kv_cache_dsv4::clear(bool data) {
    kv_raw->clear(data);
    clear_compressed(-1, true); // DSV4 compressed buffers must never expose stale/uninit rows
}

bool llama_kv_cache_dsv4::seq_rm(llama_seq_id seq_id, llama_pos p0, llama_pos p1) {
    if (p1 >= 0) {
        return false;
    }

    if (p0 > 0) {
        if (seq_id < 0 || (uint32_t) seq_id >= n_seq_max) {
            return false;
        }

        const llama_pos pos_max = kv_raw->seq_pos_max(seq_id);
        if (p0 > pos_max) {
            bool res = true;

            res = res & kv_raw->seq_rm(seq_id, p0, -1);
            res = res & kv_csa->seq_rm(seq_id, p0/DSV4_CSA_RATIO, -1);
            res = res & kv_hca->seq_rm(seq_id, p0/DSV4_HCA_RATIO, -1);
            res = res & kv_lid->seq_rm(seq_id, p0/DSV4_CSA_RATIO, -1);

            return res;
        }

        if (n_rs_seq == 0) {
            return false;
        }

        const llama_pos rollback = pos_max - (p0 - 1);
        if (rollback < 1 || rollback > (llama_pos) n_rs_seq) {
            return false;
        }

        // pending rollback is single-use: stacked partial removals don't compose
        if (rs_idx[seq_id] != 0) {
            return false;
        }

        const bool res = kv_raw->seq_rm(seq_id, p0, p1);
        if (res) {
            rs_idx[seq_id] = (uint32_t) rollback;
        }

        return res;
    }

    const bool res = kv_raw->seq_rm(seq_id, p0, p1);

    if (res) {
        clear_compressed(seq_id, true);
    }

    return res;
}

void llama_kv_cache_dsv4::seq_cp(llama_seq_id seq_id_src, llama_seq_id seq_id_dst, llama_pos p0, llama_pos p1) {
    GGML_ASSERT(p0 <= 0 && p1 < 0 && "DSV4 only supports full sequence copies");

    kv_raw->seq_cp(seq_id_src, seq_id_dst, p0, p1);
    kv_csa->seq_cp(seq_id_src, seq_id_dst, -1, -1);
    kv_hca->seq_cp(seq_id_src, seq_id_dst, -1, -1);
    kv_lid->seq_cp(seq_id_src, seq_id_dst, -1, -1);

    csa_state->seq_cp(seq_id_src, seq_id_dst);
    hca_state->seq_cp(seq_id_src, seq_id_dst);
    lid_state->seq_cp(seq_id_src, seq_id_dst);

    if (seq_id_src != seq_id_dst) {
        rs_idx[seq_id_dst] = 0;
    }
}

void llama_kv_cache_dsv4::seq_keep(llama_seq_id seq_id) {
    GGML_ASSERT(seq_id >= 0 && (uint32_t) seq_id < n_seq_max);

    kv_raw->seq_keep(seq_id);

    for (llama_seq_id id = 0; id < (llama_seq_id) n_seq_max; ++id) {
        if (id == seq_id) {
            continue;
        }

        kv_raw->seq_rm(id, -1, -1);
        clear_compressed(id, true);
    }
}

void llama_kv_cache_dsv4::seq_add(llama_seq_id seq_id, llama_pos p0, llama_pos p1, llama_pos shift) {
    kv_raw->seq_add(seq_id, p0, p1, shift);
}

void llama_kv_cache_dsv4::seq_div(llama_seq_id seq_id, llama_pos p0, llama_pos p1, int d) {
    kv_raw->seq_div(seq_id, p0, p1, d);
}

llama_pos llama_kv_cache_dsv4::seq_pos_min(llama_seq_id seq_id) const {
    if (seq_id < 0 || (uint32_t) seq_id >= n_seq_max) {
        return -1;
    }

    // The raw SWA cache may contain a wider window, but the compressed DSV4
    // state cannot be rolled back within that window. Report only the current
    // boundary so server-context uses checkpoints for rollback.
    return kv_raw->seq_pos_max(seq_id);
}

llama_pos llama_kv_cache_dsv4::seq_pos_max(llama_seq_id seq_id) const {
    if (seq_id < 0 || (uint32_t) seq_id >= n_seq_max) {
        return -1;
    }

    return kv_raw->seq_pos_max(seq_id);
}

std::map<ggml_backend_buffer_type_t, size_t> llama_kv_cache_dsv4::memory_breakdown() const {
    std::map<ggml_backend_buffer_type_t, size_t> mb = kv_raw->memory_breakdown();
    for (const auto & buft_size : kv_csa->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    for (const auto & buft_size : kv_hca->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    for (const auto & buft_size : kv_lid->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    for (const auto & buft_size : csa_state->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    for (const auto & buft_size : hca_state->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    for (const auto & buft_size : lid_state->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    return mb;
}

void llama_kv_cache_dsv4::state_write(llama_io_write_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) const {
    const bool partial_only = flags & LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY;

    const uint32_t magic   = DSV4_STATE_MAGIC;
    const uint32_t version = DSV4_STATE_VERSION;
    const uint32_t mode    = partial_only ? DSV4_STATE_MODE_PARTIAL : DSV4_STATE_MODE_FULL;

    io.write(&magic,   sizeof(magic));
    io.write(&version, sizeof(version));
    io.write(&mode,    sizeof(mode));

    kv_raw->state_write(io, seq_id, flags);

    if (!partial_only) {
        const llama_pos pos_max = seq_id >= 0 ? kv_raw->seq_pos_max(seq_id) : -1;

        //FIXME : note that we conflate token positions with rows, which is not true for multi-modal case.
        const uint32_t n_rows_csa = seq_id >= 0 ?
            dsv4_state_n_used_k_rows(pos_max, DSV4_CSA_RATIO, kv_csa->get_size()) : kv_csa->get_size();
        const uint32_t n_rows_hca = seq_id >= 0 ?
            dsv4_state_n_used_k_rows(pos_max, DSV4_HCA_RATIO, kv_hca->get_size()) : kv_hca->get_size();
        const uint32_t n_rows_lid = seq_id >= 0 ?
            dsv4_state_n_used_k_rows(pos_max, DSV4_CSA_RATIO, kv_lid->get_size()) : kv_lid->get_size();

        dsv4_state_write_k_cache(io, kv_csa.get(), seq_id, flags, n_rows_csa);
        dsv4_state_write_k_cache(io, kv_hca.get(), seq_id, flags, n_rows_hca);
        dsv4_state_write_k_cache(io, kv_lid.get(), seq_id, flags, n_rows_lid);
    }

    csa_state->state_write(io, seq_id, flags, rs_idx);
    hca_state->state_write(io, seq_id, flags, rs_idx);
    lid_state->state_write(io, seq_id, flags, rs_idx);
}

void llama_kv_cache_dsv4::state_read(llama_io_read_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) {
    uint32_t magic;
    uint32_t version;
    uint32_t mode = DSV4_STATE_MODE_FULL;

    io.read(&magic,   sizeof(magic));
    io.read(&version, sizeof(version));

    if (magic != DSV4_STATE_MAGIC) {
        throw std::runtime_error("DSV4 state magic mismatch");
    }
    if (version != DSV4_STATE_VERSION) {
        throw std::runtime_error("DSV4 state version mismatch");
    }

    io.read(&mode, sizeof(mode));
    if (mode != DSV4_STATE_MODE_FULL && mode != DSV4_STATE_MODE_PARTIAL) {
        throw std::runtime_error("DSV4 state mode mismatch");
    }

    const bool partial_only = mode == DSV4_STATE_MODE_PARTIAL;
    if (partial_only != !!(flags & LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY)) {
        throw std::runtime_error("DSV4 state flags mismatch");
    }

    kv_raw->state_read(io, seq_id, flags);

    if (!partial_only) {
        clear_compressed(seq_id, true);

        dsv4_state_read_k_cache(io, kv_csa.get(), seq_id, flags);
        dsv4_state_read_k_cache(io, kv_hca.get(), seq_id, flags);
        dsv4_state_read_k_cache(io, kv_lid.get(), seq_id, flags);
    }

    csa_state->state_read(io, seq_id, flags);
    hca_state->state_read(io, seq_id, flags);
    lid_state->state_read(io, seq_id, flags);

    if (seq_id >= 0) {
        GGML_ASSERT((uint32_t) seq_id < n_seq_max);
        rs_idx[seq_id] = 0;
    } else {
        std::fill(rs_idx.begin(), rs_idx.end(), 0);
    }
}

llama_kv_cache_iswa * llama_kv_cache_dsv4::get_raw() const {
    return kv_raw.get();
}

llama_kv_cache * llama_kv_cache_dsv4::get_csa() const {
    return kv_csa.get();
}

llama_kv_cache * llama_kv_cache_dsv4::get_hca() const {
    return kv_hca.get();
}

llama_kv_cache * llama_kv_cache_dsv4::get_lid() const {
    return kv_lid.get();
}

llama_dsv4_comp_state * llama_kv_cache_dsv4::get_csa_state() const {
    return csa_state.get();
}

llama_dsv4_comp_state * llama_kv_cache_dsv4::get_hca_state() const {
    return hca_state.get();
}

llama_dsv4_comp_state * llama_kv_cache_dsv4::get_lid_state() const {
    return lid_state.get();
}

uint32_t llama_kv_cache_dsv4::get_n_rs_seq() const {
    return n_rs_seq;
}

const std::vector<uint32_t> & llama_kv_cache_dsv4::get_rs_idx() const {
    return rs_idx;
}

void llama_kv_cache_dsv4::reset_rs_idx_for_ubatches(const std::vector<llama_ubatch> & ubatches) {
    if (n_rs_seq == 0) {
        return;
    }

    for (const llama_ubatch & ubatch : ubatches) {
        for (uint32_t i = 0; i < ubatch.n_tokens; ++i) {
            for (int32_t s = 0; s < ubatch.n_seq_id[i]; ++s) {
                const llama_seq_id seq_id = ubatch.seq_id[i][s];
                if (seq_id >= 0 && (uint32_t) seq_id < n_seq_max) {
                    rs_idx[seq_id] = 0;
                }
            }
        }
    }
}

void llama_kv_cache_dsv4::clear_compressed(llama_seq_id seq_id, bool data) {
    if (seq_id < 0) {
        kv_csa->clear(data);
        kv_hca->clear(data);
        kv_lid->clear(data);
    } else {
        GGML_ASSERT((uint32_t) seq_id < n_seq_max);

        const auto clear_seq = [seq_id, data](llama_kv_cache * kv) {
            kv->seq_rm(seq_id, -1, -1);

            if (data) {
                //TODO: do not clear the kv-cache during `seq_rm`, ref: https://github.com/ggml-org/llama.cpp/pull/26490#discussion_r3798143663
                for (uint32_t il : kv->get_layer_ids()) {
                    dsv4_clear_tensor_stream(kv->get_k_storage(il), (uint32_t) seq_id);
                }
            }
        };

        clear_seq(kv_csa.get());
        clear_seq(kv_hca.get());
        clear_seq(kv_lid.get());
    }

    csa_state->clear(seq_id, data);
    hca_state->clear(seq_id, data);
    lid_state->clear(seq_id, data);

    if (seq_id >= 0) {
        rs_idx[seq_id] = 0;
    } else {
        std::fill(rs_idx.begin(), rs_idx.end(), 0);
    }
}

//
// llama_kv_cache_dsv4_raw_context
//

static llama_kv_cache::slot_info dsv4_build_full_sinfo(const llama_kv_cache * kv) {
    const uint32_t n_stream = kv->get_n_stream();

    llama_kv_cache::slot_info sinfo;
    sinfo.s0 = 0;
    sinfo.s1 = n_stream - 1;
    sinfo.resize(n_stream);
    for (uint32_t s = 0; s < n_stream; ++s) {
        sinfo.strm[s] = s;
        sinfo.idxs[s].resize(1, 0);
    }

    return sinfo;
}

llama_kv_cache_dsv4_raw_context::llama_kv_cache_dsv4_raw_context(llama_kv_cache_iswa * kv) :
    kv_swa(kv->get_swa()),
    ctx_base_mem(nullptr),
    ctx_swa_mem(nullptr),
    n_kv(kv_swa->get_size()),
    status(LLAMA_MEMORY_STATUS_SUCCESS) {
    sinfos_read.push_back(dsv4_build_full_sinfo(kv_swa));
    sinfos_write = sinfos_read;
}

llama_kv_cache_dsv4_raw_context::llama_kv_cache_dsv4_raw_context(
        llama_kv_cache_iswa * kv,
        llama_context * lctx,
        bool optimize) :
    kv_swa(kv->get_swa()),
    ctx_base_mem(kv->get_base()->init_update(lctx, optimize)),
    ctx_swa_mem(kv->get_swa()->init_update(lctx, optimize)),
    n_kv(kv_swa->get_size()),
    status(llama_memory_status_combine(ctx_base_mem->get_status(), ctx_swa_mem->get_status())) {
}

llama_kv_cache_dsv4_raw_context::llama_kv_cache_dsv4_raw_context(
        llama_kv_cache_iswa * kv,
        slot_info_vec_t sinfos_base_write,
        slot_info_vec_t sinfos_swa_write,
        slot_info_vec_t sinfos_swa_read,
        std::vector<llama_ubatch> ubatches,
        std::vector<llama_ubatch> ubatches_write) :
    kv_swa(kv->get_swa()),
    sinfos_write(std::move(sinfos_swa_write)),
    sinfos_read(std::move(sinfos_swa_read)),
    ubatches(std::move(ubatches)),
    ubatches_write(std::move(ubatches_write)),
    ctx_base_mem(std::make_unique<llama_kv_cache_context>(
                kv->get_base(), std::move(sinfos_base_write), this->ubatches_write)),
    ctx_swa_mem(nullptr),
    n_kv(kv_swa->get_size()),
    status(LLAMA_MEMORY_STATUS_SUCCESS) {
}

bool llama_kv_cache_dsv4_raw_context::next() {
    if (ubatches.empty()) {
        return true;
    }

    if (ctx_base_mem) {
        ctx_base_mem->next();
    }

    if (++i_next >= ubatches.size()) {
        return false;
    }

    return true;
}

bool llama_kv_cache_dsv4_raw_context::apply() {
    bool res = true;

    if (ctx_base_mem) {
        res = res & ctx_base_mem->apply();
    }
    if (ctx_swa_mem) {
        res = res & ctx_swa_mem->apply();
    }
    if (!ubatches_write.empty()) {
        kv_swa->apply_ubatch(sinfos_write[i_next], ubatches_write[i_next]);
        n_kv = kv_swa->get_n_kv(sinfos_read[i_next]);
    }

    return res;
}

llama_memory_status llama_kv_cache_dsv4_raw_context::get_status() const {
    return status;
}

const llama_ubatch & llama_kv_cache_dsv4_raw_context::get_ubatch() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ubatches[i_next];
}

uint32_t llama_kv_cache_dsv4_raw_context::get_n_kv() const {
    return n_kv;
}

uint32_t llama_kv_cache_dsv4_raw_context::get_n_write() const {
    if (ubatches_write.empty()) {
        return 0;
    }

    return ubatches_write[i_next].n_tokens;
}

ggml_tensor * llama_kv_cache_dsv4_raw_context::get_k(ggml_context * ctx, int32_t il) const {
    return kv_swa->get_k(ctx, il, n_kv, sinfos_read[i_next]);
}

ggml_tensor * llama_kv_cache_dsv4_raw_context::cpy_k(ggml_context * ctx, ggml_tensor * k_cur, ggml_tensor * k_idxs, int32_t il) const {
    const auto & sinfo = sinfos_write[i_next];

    if (k_cur->ne[2] == k_idxs->ne[0]) {
        return kv_swa->cpy_k(ctx, k_cur, k_idxs, il, sinfo);
    }

    // k_idxs may be expanded to one block per stream while k_cur is only
    // the token block. Keep zero deps on all copies so each write executes.
    const int64_t n_fanout = (int64_t) sinfo.size()*sinfo.n_stream();

    GGML_ASSERT(sinfo.n_stream() > 1);
    GGML_ASSERT(k_cur->ne[2] == (int64_t) sinfo.size());
    GGML_ASSERT(k_idxs->ne[0] == n_fanout);

    ggml_tensor * res = nullptr;
    for (uint32_t s = 0; s < sinfo.n_stream(); ++s) {
        ggml_tensor * k_idxs_s = ggml_view_1d(ctx, k_idxs, sinfo.size(), s*sinfo.size()*ggml_element_size(k_idxs));
        ggml_tensor * cur = kv_swa->cpy_k(ctx, k_cur, k_idxs_s, il, sinfo);
        if (res == nullptr) {
            res = cur;
        } else {
            res = ggml_add(ctx, res, ggml_sub(ctx, cur, cur));
        }
    }

    return res;
}

ggml_tensor * llama_kv_cache_dsv4_raw_context::build_input_k_idxs(ggml_context * ctx, const llama_ubatch & ubatch) const {
    const uint32_t n_tokens = ubatches_write.empty() ? ubatch.n_tokens : ubatches_write[i_next].n_tokens;

    ggml_tensor * k_idxs = ggml_new_tensor_1d(ctx, GGML_TYPE_I64, n_tokens);
    ggml_set_input(k_idxs);

    return k_idxs;
}

ggml_tensor * llama_kv_cache_dsv4_raw_context::build_input_k_rot(ggml_context * ctx) const {
    return kv_swa->build_input_k_rot(ctx);
}

void llama_kv_cache_dsv4_raw_context::set_input_k_idxs(ggml_tensor * dst) const {
    kv_swa->set_input_k_idxs(dst, &ubatches_write[i_next], sinfos_write[i_next]);
}

void llama_kv_cache_dsv4_raw_context::set_input_kq_mask(ggml_tensor * dst, const llama_ubatch * ubatch, bool causal_attn) const {
    kv_swa->set_input_kq_mask(dst, ubatch, causal_attn);
}

void llama_kv_cache_dsv4_raw_context::set_input_k_rot(ggml_tensor * dst) const {
    kv_swa->set_input_k_rot(dst);
}

//
// llama_kv_cache_dsv4_comp_context
//

llama_kv_cache_dsv4_comp_context::llama_kv_cache_dsv4_comp_context(llama_kv_cache * kv) : kv(kv), n_kv(kv->get_size()) {
    const uint32_t n_stream = kv->get_n_stream();

    sinfos.resize(1);
    sinfos[0].s0 = 0;
    sinfos[0].s1 = n_stream - 1;
    sinfos[0].idxs.resize(n_stream);
    for (uint32_t s = 0; s < n_stream; ++s) {
        sinfos[0].strm.push_back(s);
        sinfos[0].idxs[s].resize(1, 0);
    }
}

llama_kv_cache_dsv4_comp_context::llama_kv_cache_dsv4_comp_context(
        llama_kv_cache * kv,
        slot_info_vec_t sinfos,
        std::vector<llama_ubatch> ubatches) :
    kv(kv),
    sinfos(std::move(sinfos)),
    ubatches(std::move(ubatches)),
    n_kv(kv->get_size()) {
}

bool llama_kv_cache_dsv4_comp_context::next() {
    if (ubatches.empty()) {
        return true;
    }

    if (++i_cur >= ubatches.size()) {
        return false;
    }

    return true;
}

uint32_t llama_kv_cache_dsv4_comp_context::get_n_kv() const {
    return n_kv;
}

ggml_tensor * llama_kv_cache_dsv4_comp_context::get_k(ggml_context * ctx, int32_t il) const {
    return kv->get_k(ctx, il, n_kv, sinfos[i_cur]);
}

ggml_tensor * llama_kv_cache_dsv4_comp_context::cpy_k(ggml_context * ctx, ggml_tensor * k_cur, ggml_tensor * k_idxs, int32_t il) const {
    return kv->cpy_k(ctx, k_cur, k_idxs, il, sinfos[i_cur]);
}

ggml_tensor * llama_kv_cache_dsv4_comp_context::build_input_k_rot(ggml_context * ctx) const {
    return kv->build_input_k_rot(ctx);
}

void llama_kv_cache_dsv4_comp_context::set_input_k_rot(ggml_tensor * dst) const {
    kv->set_input_k_rot(dst);
}

//
// llama_kv_cache_dsv4_context
//

llama_kv_cache_dsv4_context::llama_kv_cache_dsv4_context(llama_memory_status status) : status(status) {}

llama_kv_cache_dsv4_context::llama_kv_cache_dsv4_context(
        llama_kv_cache_dsv4 * kv) :
    ctx_raw(std::make_unique<llama_kv_cache_dsv4_raw_context>(kv->get_raw())),
    ctx_csa_mem(kv->get_csa()->init_full()),
    ctx_hca_mem(kv->get_hca()->init_full()),
    ctx_lid_mem(kv->get_lid()->init_full()),
    ctx_csa(std::make_unique<llama_kv_cache_dsv4_comp_context>(kv->get_csa())),
    ctx_hca(std::make_unique<llama_kv_cache_dsv4_comp_context>(kv->get_hca())),
    ctx_lid(std::make_unique<llama_kv_cache_dsv4_comp_context>(kv->get_lid())),
    csa_state(kv->get_csa_state()),
    hca_state(kv->get_hca_state()),
    lid_state(kv->get_lid_state()),
    reserve_plans(true),
    status(llama_memory_status_combine(
                llama_memory_status_combine(ctx_raw->get_status(), ctx_csa_mem->get_status()),
                llama_memory_status_combine(ctx_hca_mem->get_status(), ctx_lid_mem->get_status()))) {
}

llama_kv_cache_dsv4_context::llama_kv_cache_dsv4_context(
        llama_kv_cache_dsv4 * kv,
        llama_context * lctx,
        bool optimize,
        stream_copy_info sc_info_csa,
        stream_copy_info sc_info_hca,
        stream_copy_info sc_info_lid) :
    ctx_raw(std::make_unique<llama_kv_cache_dsv4_raw_context>(kv->get_raw(), lctx, optimize)),
    ctx_csa_mem(kv->get_csa()->init_update(lctx, optimize)),
    ctx_hca_mem(kv->get_hca()->init_update(lctx, optimize)),
    ctx_lid_mem(kv->get_lid()->init_update(lctx, optimize)),
    csa_state(kv->get_csa_state()),
    hca_state(kv->get_hca_state()),
    lid_state(kv->get_lid_state()),
    sc_info_csa(std::move(sc_info_csa)),
    sc_info_hca(std::move(sc_info_hca)),
    sc_info_lid(std::move(sc_info_lid)),
    status(llama_memory_status_combine(
                llama_memory_status_combine(
                    llama_memory_status_combine(ctx_raw->get_status(), ctx_csa_mem->get_status()),
                    llama_memory_status_combine(ctx_hca_mem->get_status(), ctx_lid_mem->get_status())),
                this->sc_info_csa.empty() && this->sc_info_hca.empty() && this->sc_info_lid.empty() ?
                    LLAMA_MEMORY_STATUS_NO_UPDATE : LLAMA_MEMORY_STATUS_SUCCESS)) {
}

llama_kv_cache_dsv4_context::llama_kv_cache_dsv4_context(
        llama_kv_cache_dsv4 * kv,
        slot_info_vec_t sinfos_raw_base_write,
        slot_info_vec_t sinfos_raw_swa_write,
        slot_info_vec_t sinfos_raw_swa_read,
        std::vector<llama_ubatch> ubatches,
        std::vector<llama_ubatch> ubatches_raw) :
    ubatches(std::move(ubatches)),
    plans_csa(dsv4_build_comp_plans(this->ubatches, DSV4_CSA_RATIO, true,
                kv->get_csa_state()->get_state_size(), kv->get_csa()->get_size(), kv->get_csa_state()->get_n_stream(),
                kv->get_n_rs_seq(), kv->get_rs_idx())),
    plans_hca(dsv4_build_comp_plans(this->ubatches, DSV4_HCA_RATIO, false,
                kv->get_hca_state()->get_state_size(), kv->get_hca()->get_size(), kv->get_hca_state()->get_n_stream(),
                kv->get_n_rs_seq(), kv->get_rs_idx())),
    plans_lid(dsv4_build_comp_plans(this->ubatches, DSV4_CSA_RATIO, true,
                kv->get_lid_state()->get_state_size(), kv->get_lid()->get_size(), kv->get_lid_state()->get_n_stream(),
                kv->get_n_rs_seq(), kv->get_rs_idx())),
    ctx_raw(std::make_unique<llama_kv_cache_dsv4_raw_context>(
                kv->get_raw(),
                std::move(sinfos_raw_base_write),
                std::move(sinfos_raw_swa_write),
                std::move(sinfos_raw_swa_read),
                this->ubatches,
                std::move(ubatches_raw))),
    ctx_csa_mem(nullptr),
    ctx_hca_mem(nullptr),
    ctx_lid_mem(nullptr),
    ctx_csa(std::make_unique<llama_kv_cache_dsv4_comp_context>(
                kv->get_csa(),
                dsv4_build_comp_sinfos(this->ubatches, kv->get_csa()->get_n_stream()),
                this->ubatches)),
    ctx_hca(std::make_unique<llama_kv_cache_dsv4_comp_context>(
                kv->get_hca(),
                dsv4_build_comp_sinfos(this->ubatches, kv->get_hca()->get_n_stream()),
                this->ubatches)),
    ctx_lid(std::make_unique<llama_kv_cache_dsv4_comp_context>(
                kv->get_lid(),
                dsv4_build_comp_sinfos(this->ubatches, kv->get_lid()->get_n_stream()),
                this->ubatches)),
    csa_state(kv->get_csa_state()),
    hca_state(kv->get_hca_state()),
    lid_state(kv->get_lid_state()),
    status(ctx_raw->get_status()) {
    kv->reset_rs_idx_for_ubatches(this->ubatches);
}

llama_kv_cache_dsv4_context::~llama_kv_cache_dsv4_context() = default;

bool llama_kv_cache_dsv4_context::next() {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    ctx_raw->next();
    ctx_csa->next();
    ctx_hca->next();
    ctx_lid->next();

    if (++i_next >= ubatches.size()) {
        return false;
    }

    return true;
}

bool llama_kv_cache_dsv4_context::apply() {
    assert(!llama_memory_status_is_fail(status));

    bool res = true;

    res = res & ctx_raw->apply();

    if (ctx_csa_mem) {
        res = res & ctx_csa_mem->apply();
        res = res & ctx_hca_mem->apply();
        res = res & ctx_lid_mem->apply();
    }

    if (ubatches.empty()) {
        csa_state->apply_copies(sc_info_csa);
        hca_state->apply_copies(sc_info_hca);
        lid_state->apply_copies(sc_info_lid);
    }

    return res;
}

llama_memory_status llama_kv_cache_dsv4_context::get_status() const {
    return status;
}

const llama_ubatch & llama_kv_cache_dsv4_context::get_ubatch() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ubatches[i_next];
}

const llama_kv_cache_dsv4_raw_context * llama_kv_cache_dsv4_context::get_raw() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ctx_raw.get();
}

const llama_kv_cache_dsv4_comp_context * llama_kv_cache_dsv4_context::get_csa() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ctx_csa.get();
}

const llama_kv_cache_dsv4_comp_context * llama_kv_cache_dsv4_context::get_hca() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ctx_hca.get();
}

const llama_kv_cache_dsv4_comp_context * llama_kv_cache_dsv4_context::get_lid() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ctx_lid.get();
}

const llama_dsv4_comp_state * llama_kv_cache_dsv4_context::get_csa_state() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return csa_state;
}

const llama_dsv4_comp_state * llama_kv_cache_dsv4_context::get_hca_state() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return hca_state;
}

const llama_dsv4_comp_state * llama_kv_cache_dsv4_context::get_lid_state() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return lid_state;
}

const llama_kv_cache_dsv4_context::comp_plan & llama_kv_cache_dsv4_context::get_csa_plan() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    static const comp_plan empty;
    if (plans_csa.empty()) {
        return empty;
    }

    return plans_csa[i_next];
}

const llama_kv_cache_dsv4_context::comp_plan & llama_kv_cache_dsv4_context::get_hca_plan() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    static const comp_plan empty;
    if (plans_hca.empty()) {
        return empty;
    }

    return plans_hca[i_next];
}

const llama_kv_cache_dsv4_context::comp_plan & llama_kv_cache_dsv4_context::get_lid_plan() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    static const comp_plan empty;
    if (plans_lid.empty()) {
        return empty;
    }

    return plans_lid[i_next];
}

const llama_kv_cache_dsv4_context::comp_plan & llama_kv_cache_dsv4_context::get_csa_plan(const llama_ubatch & ubatch) const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    if (!reserve_plans) {
        return get_csa_plan();
    }

    reserve_plan_csa = dsv4_build_reserve_comp_plan(
            ubatch, DSV4_CSA_RATIO, true,
            csa_state->get_state_size(), get_csa()->get_n_kv(), csa_state->get_n_stream(), csa_state->get_n_rs_seq());

    return reserve_plan_csa;
}

const llama_kv_cache_dsv4_context::comp_plan & llama_kv_cache_dsv4_context::get_hca_plan(const llama_ubatch & ubatch) const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    if (!reserve_plans) {
        return get_hca_plan();
    }

    reserve_plan_hca = dsv4_build_reserve_comp_plan(
            ubatch, DSV4_HCA_RATIO, false,
            hca_state->get_state_size(), get_hca()->get_n_kv(), hca_state->get_n_stream(), hca_state->get_n_rs_seq());

    return reserve_plan_hca;
}

const llama_kv_cache_dsv4_context::comp_plan & llama_kv_cache_dsv4_context::get_lid_plan(const llama_ubatch & ubatch) const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    if (!reserve_plans) {
        return get_lid_plan();
    }

    reserve_plan_lid = dsv4_build_reserve_comp_plan(
            ubatch, DSV4_CSA_RATIO, true,
            lid_state->get_state_size(), get_lid()->get_n_kv(), lid_state->get_n_stream(), lid_state->get_n_rs_seq());

    return reserve_plan_lid;
}

// --- llama-kv-cache-iswa.cpp ---
#include "llama-kv-cache-iswa.h"

#include "llama-impl.h"
#include "llama-batch.h"
#include "llama-model.h"

#include <algorithm>
#include <cassert>

//
// llama_kv_cache_iswa
//

llama_kv_cache_iswa::llama_kv_cache_iswa(
        const llama_model & model,
                ggml_type   type_k,
                ggml_type   type_v,
                     bool   v_trans,
                     bool   offload,
                     bool   swa_full,
                     bool   unified,
                 uint32_t   kv_size,
                 uint32_t   n_seq_max,
                 uint32_t   n_ubatch,
                 uint32_t   n_pad,
           llama_memory_t   mem_other,
    const layer_filter_cb & filter,
    const  layer_reuse_cb & reuse,
    const  layer_share_cb & share) :
    llama_kv_cache_iswa(model, model.hparams, type_k, type_v, v_trans, offload, swa_full, unified,
            kv_size, n_seq_max, n_ubatch, n_pad, mem_other, filter, reuse, share) {
}

llama_kv_cache_iswa::llama_kv_cache_iswa(
        const llama_model & model,
        const llama_hparams & hparams,
                ggml_type   type_k,
                ggml_type   type_v,
                     bool   v_trans,
                     bool   offload,
                     bool   swa_full,
                     bool   unified,
                 uint32_t   kv_size,
                 uint32_t   n_seq_max,
                 uint32_t   n_ubatch,
                 uint32_t   n_pad,
           llama_memory_t   mem_other,
    const layer_filter_cb & filter,
    const  layer_reuse_cb & reuse,
    const  layer_share_cb & share) : unified(unified) {

    // chain filters
    const layer_filter_cb filter_base = [&](int32_t il) {
        if (filter && !filter(il)) {
            return false;
        }

        return !model.hparams.is_swa(il);
    };

    const layer_filter_cb filter_swa  = [&](int32_t il) {
        if (filter && !filter(il)) {
            return false;
        }

        return  model.hparams.is_swa(il);
    };

    const uint32_t size_base = kv_size;

    // note: the SWA cache is always padded to 256 for performance
    //       https://github.com/ggml-org/llama.cpp/issues/17037
    uint32_t size_swa = GGML_PAD(std::min(size_base, hparams.n_swa*(unified ? n_seq_max : 1) + n_ubatch), 256);

    // when using full-size SWA cache, we set the SWA cache size to be equal to the base cache size
    if (swa_full) {
        LLAMA_LOG_WARN("%s: using full-size SWA cache (ref: %s)\n",
                __func__, "https://github.com/ggml-org/llama.cpp/pull/13194#issuecomment-2868343055");

        size_swa = size_base;
    }

    LLAMA_LOG_INFO("%s: creating non-SWA KV cache, size = %u cells\n", __func__, size_base);

    llama_memory_t mem_other_base = nullptr;
    if (mem_other) {
        mem_other_base = static_cast<llama_kv_cache_iswa *>(mem_other)->get_base();
    }

    llama_memory_t mem_other_swa = nullptr;
    if (mem_other) {
        mem_other_swa = static_cast<llama_kv_cache_iswa *>(mem_other)->get_swa();
    }

    kv_base = std::make_unique<llama_kv_cache>(
            model, hparams, type_k, type_v,
            v_trans, offload, unified, size_base, n_seq_max, n_pad,
            0, LLAMA_SWA_TYPE_NONE, mem_other_base, filter_base, reuse, share);

    LLAMA_LOG_INFO("%s: creating     SWA KV cache, size = %u cells\n", __func__, size_swa);

    kv_swa = std::make_unique<llama_kv_cache>(
            model, hparams, type_k, type_v,
            v_trans, offload, unified, size_swa, n_seq_max, n_pad,
            hparams.n_swa, hparams.swa_type, mem_other_swa, filter_swa, reuse, share);
}

void llama_kv_cache_iswa::clear(bool data) {
    kv_base->clear(data);
    kv_swa ->clear(data);
}

bool llama_kv_cache_iswa::seq_rm(llama_seq_id seq_id, llama_pos p0, llama_pos p1) {
    bool res = true;

    res = res & kv_base->seq_rm(seq_id, p0, p1);
    res = res & kv_swa ->seq_rm(seq_id, p0, p1);

    return res;
}

void llama_kv_cache_iswa::seq_cp(llama_seq_id seq_id_src, llama_seq_id seq_id_dst, llama_pos p0, llama_pos p1) {
    kv_base->seq_cp(seq_id_src, seq_id_dst, p0, p1);
    kv_swa ->seq_cp(seq_id_src, seq_id_dst, p0, p1);
}

void llama_kv_cache_iswa::seq_keep(llama_seq_id seq_id) {
    kv_base->seq_keep(seq_id);
    kv_swa ->seq_keep(seq_id);
}

void llama_kv_cache_iswa::seq_add(llama_seq_id seq_id, llama_pos p0, llama_pos p1, llama_pos shift) {
    kv_base->seq_add(seq_id, p0, p1, shift);
    kv_swa ->seq_add(seq_id, p0, p1, shift);
}

void llama_kv_cache_iswa::seq_div(llama_seq_id seq_id, llama_pos p0, llama_pos p1, int d) {
    kv_base->seq_div(seq_id, p0, p1, d);
    kv_swa ->seq_div(seq_id, p0, p1, d);
}

llama_pos llama_kv_cache_iswa::seq_pos_min(llama_seq_id seq_id) const {
    // the base cache is a superset of the SWA cache, so we can just check the SWA cache
    return kv_swa->seq_pos_min(seq_id);
}

llama_pos llama_kv_cache_iswa::seq_pos_max(llama_seq_id seq_id) const {
    return kv_swa->seq_pos_max(seq_id);
}

std::map<ggml_backend_buffer_type_t, size_t> llama_kv_cache_iswa::memory_breakdown() const {
    std::map<ggml_backend_buffer_type_t, size_t> mb = kv_base->memory_breakdown();
    for (const auto & buft_size : kv_swa->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    return mb;
}

llama_memory_context_ptr llama_kv_cache_iswa::init_batch(llama_batch_allocr & balloc, uint32_t n_ubatch, bool embd_all) {
    GGML_UNUSED(embd_all);

    // first try simple split
    do {
        if (!unified) {
            // requires equal splits, so we skip the simple split
            break;
        }

        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            auto ubatch = balloc.split_simple(n_ubatch);

            if (ubatch.n_tokens == 0) {
                break;
            }

            ubatches.push_back(std::move(ubatch)); // NOLINT
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            // failed to find a suitable split
            break;
        }

        auto sinfos_base = kv_base->prepare(ubatches);
        if (sinfos_base.empty()) {
            break;
        }

        auto sinfos_swa = kv_swa->prepare(ubatches);
        if (sinfos_swa.empty()) {
            break;
        }

        assert(sinfos_base.size() == sinfos_swa.size());

        return std::make_unique<llama_kv_cache_iswa_context>(
                this, std::move(sinfos_base), std::move(sinfos_swa), std::move(ubatches));
    } while (false);

    // if it fails, try equal split
    do {
        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            auto ubatch = balloc.split_equal(n_ubatch, !unified, 0);

            if (ubatch.n_tokens == 0) {
                break;
            }

            ubatches.push_back(std::move(ubatch)); // NOLINT
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            // failed to find a suitable split
            break;
        }

        auto sinfos_base = kv_base->prepare(ubatches);
        if (sinfos_base.empty()) {
            break;
        }

        auto sinfos_swa = kv_swa->prepare(ubatches);
        if (sinfos_swa.empty()) {
            break;
        }

        assert(sinfos_base.size() == sinfos_swa.size());

        return std::make_unique<llama_kv_cache_iswa_context>(
                this, std::move(sinfos_base), std::move(sinfos_swa), std::move(ubatches));
    } while (false);

    // TODO: if we fail again, we should attempt different splitting strategies
    //       but to do that properly, we first have to refactor the batches to be more flexible

    return std::make_unique<llama_kv_cache_iswa_context>(LLAMA_MEMORY_STATUS_FAILED_PREPARE);
}

llama_memory_context_ptr llama_kv_cache_iswa::init_full() {
    return std::make_unique<llama_kv_cache_iswa_context>(this);
}

llama_memory_context_ptr llama_kv_cache_iswa::init_update(llama_context * lctx, bool optimize) {
    return std::make_unique<llama_kv_cache_iswa_context>(this, lctx, optimize);
}

bool llama_kv_cache_iswa::get_can_shift() const {
    return kv_base->get_can_shift() &&
           kv_swa->get_can_shift() &&
           kv_base->get_size() == kv_swa->get_size();
}

void llama_kv_cache_iswa::state_write(llama_io_write_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) const {
    if ((flags & LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) == 0) {
        kv_base->state_write(io, seq_id, flags);
    }

    kv_swa->state_write(io, seq_id, flags);
}

void llama_kv_cache_iswa::state_read(llama_io_read_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) {
    if ((flags & LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY) == 0) {
        kv_base->state_read(io, seq_id, flags);
    }

    kv_swa->state_read(io, seq_id, flags);
}

llama_kv_cache * llama_kv_cache_iswa::get_base() const {
    return kv_base.get();
}

llama_kv_cache * llama_kv_cache_iswa::get_swa() const {
    return kv_swa.get();
}

//
// llama_kv_cache_iswa_context
//

llama_kv_cache_iswa_context::llama_kv_cache_iswa_context(llama_memory_status status) : status(status) {}

llama_kv_cache_iswa_context::llama_kv_cache_iswa_context(
        llama_kv_cache_iswa * kv) :
    ctx_base(kv->get_base()->init_full()),
    ctx_swa (kv->get_swa ()->init_full()),
    status(llama_memory_status_combine(ctx_base->get_status(), ctx_swa->get_status())) {
}

llama_kv_cache_iswa_context::llama_kv_cache_iswa_context(
        llama_kv_cache_iswa * kv,
        llama_context * lctx,
        bool optimize) :
    ctx_base(kv->get_base()->init_update(lctx, optimize)),
    ctx_swa (kv->get_swa ()->init_update(lctx, optimize)),
    status(llama_memory_status_combine(ctx_base->get_status(), ctx_swa->get_status())) {
}

llama_kv_cache_iswa_context::llama_kv_cache_iswa_context(
        llama_kv_cache_iswa * kv,
        slot_info_vec_t sinfos_base,
        slot_info_vec_t sinfos_swa,
        std::vector<llama_ubatch> ubatches) :
    ubatches(std::move(ubatches)),
    // note: here we copy the ubatches. not sure if this is ideal
    ctx_base(new llama_kv_cache_context(kv->get_base(), std::move(sinfos_base), this->ubatches)),
    ctx_swa (new llama_kv_cache_context(kv->get_swa (), std::move(sinfos_swa),  this->ubatches)),
    status(llama_memory_status_combine(ctx_base->get_status(), ctx_swa->get_status())) {
}

llama_kv_cache_iswa_context:: ~llama_kv_cache_iswa_context() = default;

bool llama_kv_cache_iswa_context::next() {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    ctx_base->next();
    ctx_swa ->next();

    if (++i_next >= ubatches.size()) {
        return false;
    }

    return true;
}

bool llama_kv_cache_iswa_context::apply() {
    assert(!llama_memory_status_is_fail(status));

    bool res = true;

    res = res & ctx_base->apply();
    res = res & ctx_swa ->apply();

    return res;
}

llama_memory_status llama_kv_cache_iswa_context::get_status() const {
    return status;
}

const llama_ubatch & llama_kv_cache_iswa_context::get_ubatch() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ubatches[i_next];
}

const llama_kv_cache_context * llama_kv_cache_iswa_context::get_base() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return static_cast<const llama_kv_cache_context *>(ctx_base.get());
}

const llama_kv_cache_context * llama_kv_cache_iswa_context::get_swa()  const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return static_cast<const llama_kv_cache_context *>(ctx_swa.get());
}

// --- llama-kv-cache-msa.cpp ---
#include "llama-kv-cache-msa.h"

#include "llama-impl.h"
#include "llama-batch.h"
#include "llama-model.h"

#include <algorithm>
#include <cassert>
#include <cmath>

// llama_kv_cache_msa

llama_kv_cache_msa::llama_kv_cache_msa(
        const llama_model & model,
                ggml_type   type_k,
                ggml_type   type_v,
                     bool   v_trans,
                     bool   offload,
                     bool   unified,
                 uint32_t   kv_size,
                 uint32_t   n_seq_max,
                 uint32_t   n_pad,
                 uint32_t   n_swa,
           llama_swa_type   swa_type,
    const layer_filter_cb & filter,
    const layer_filter_cb & filter_idx,
    const  layer_reuse_cb & reuse) :
    hparams_idx(model.hparams),
    n_stream(unified ? 1 : n_seq_max), n_seq_max(n_seq_max), n_pad(n_pad),
    n_swa(n_swa), swa_type(swa_type) {

    LLAMA_LOG_INFO("%s: creating main KV cache, size = %u cells\n", __func__, kv_size);

    kv_base = std::make_unique<llama_kv_cache>(
            model, model.hparams, type_k, type_v,
            v_trans, offload, unified, kv_size, n_seq_max, n_pad,
            n_swa, swa_type, nullptr, filter, reuse, nullptr);

    // the MSA indexer uses a single key head per layer
    std::fill(hparams_idx.n_head_kv_arr.begin(), hparams_idx.n_head_kv_arr.end(), 1);
    hparams_idx.n_embd_head_k_full = model.hparams.indexer_head_size;
    // the rope parameters are kept identical to the main cache

    LLAMA_LOG_INFO("%s: creating indexer KV cache, size = %u cells\n", __func__, kv_size);

    kv_idx = std::make_unique<llama_kv_cache>(
            model, hparams_idx, type_k, type_v,
            v_trans, offload, unified, kv_size, n_seq_max, n_pad,
            n_swa, swa_type, nullptr, filter_idx, reuse, nullptr);
}

void llama_kv_cache_msa::clear(bool data) {
    kv_base->clear(data);
    kv_idx ->clear(data);
}

bool llama_kv_cache_msa::seq_rm(llama_seq_id seq_id, llama_pos p0, llama_pos p1) {
    bool res = true;

    res = res & kv_base->seq_rm(seq_id, p0, p1);
    res = res & kv_idx ->seq_rm(seq_id, p0, p1);

    return res;
}

void llama_kv_cache_msa::seq_cp(llama_seq_id seq_id_src, llama_seq_id seq_id_dst, llama_pos p0, llama_pos p1) {
    kv_base->seq_cp(seq_id_src, seq_id_dst, p0, p1);
    kv_idx ->seq_cp(seq_id_src, seq_id_dst, p0, p1);
}

void llama_kv_cache_msa::seq_keep(llama_seq_id seq_id) {
    kv_base->seq_keep(seq_id);
    kv_idx ->seq_keep(seq_id);
}

void llama_kv_cache_msa::seq_add(llama_seq_id seq_id, llama_pos p0, llama_pos p1, llama_pos shift) {
    kv_base->seq_add(seq_id, p0, p1, shift);
    kv_idx ->seq_add(seq_id, p0, p1, shift);
}

void llama_kv_cache_msa::seq_div(llama_seq_id seq_id, llama_pos p0, llama_pos p1, int d) {
    kv_base->seq_div(seq_id, p0, p1, d);
    kv_idx ->seq_div(seq_id, p0, p1, d);
}

llama_pos llama_kv_cache_msa::seq_pos_min(llama_seq_id seq_id) const {
    return kv_base->seq_pos_min(seq_id);
}

llama_pos llama_kv_cache_msa::seq_pos_max(llama_seq_id seq_id) const {
    return kv_base->seq_pos_max(seq_id);
}

std::map<ggml_backend_buffer_type_t, size_t> llama_kv_cache_msa::memory_breakdown() const {
    std::map<ggml_backend_buffer_type_t, size_t> mb = kv_base->memory_breakdown();
    for (const auto & buft_size : kv_idx->memory_breakdown()) {
        mb[buft_size.first] += buft_size.second;
    }
    return mb;
}

llama_memory_context_ptr llama_kv_cache_msa::init_batch(
            llama_batch_allocr & balloc,
            uint32_t n_ubatch,
            bool embd_all) {
    GGML_UNUSED(embd_all);

    do {
        balloc.split_reset();

        std::vector<llama_ubatch> ubatches;
        while (true) {
            auto ubatch = n_stream == 1 ? balloc.split_simple(n_ubatch) : balloc.split_equal(n_ubatch, true, 0);

            if (ubatch.n_tokens == 0) {
                break;
            }

            ubatches.push_back(std::move(ubatch));
        }

        if (balloc.get_n_used() < balloc.get_n_tokens()) {
            // failed to find a suitable split
            break;
        }

        auto sinfos_base = kv_base->prepare(ubatches);
        if (sinfos_base.empty()) {
            break;
        }

        auto sinfos_idx = kv_idx->prepare(ubatches);
        if (sinfos_idx.empty()) {
            break;
        }

        assert(sinfos_base.size() == sinfos_idx.size());

        return std::make_unique<llama_kv_cache_msa_context>(
                this, std::move(sinfos_base), std::move(sinfos_idx), std::move(ubatches));
    } while (false);

    return std::make_unique<llama_kv_cache_msa_context>(LLAMA_MEMORY_STATUS_FAILED_PREPARE);
}

llama_memory_context_ptr llama_kv_cache_msa::init_full() {
    return std::make_unique<llama_kv_cache_msa_context>(this);
}

llama_memory_context_ptr llama_kv_cache_msa::init_update(llama_context * lctx, bool optimize) {
    return std::make_unique<llama_kv_cache_msa_context>(this, lctx, optimize);
}

bool llama_kv_cache_msa::get_can_shift() const {
    return kv_base->get_can_shift() &&
           kv_idx ->get_can_shift() &&
           kv_base->get_size() == kv_idx->get_size();
}

void llama_kv_cache_msa::state_write(llama_io_write_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) const {
    kv_base->state_write(io, seq_id, flags);
    kv_idx ->state_write(io, seq_id, flags);
}

void llama_kv_cache_msa::state_read(llama_io_read_i & io, llama_seq_id seq_id, llama_state_seq_flags flags) {
    kv_base->state_read(io, seq_id, flags);
    kv_idx ->state_read(io, seq_id, flags);
}

llama_kv_cache * llama_kv_cache_msa::get_base() const {
    return kv_base.get();
}

llama_kv_cache * llama_kv_cache_msa::get_idx() const {
    return kv_idx.get();
}

// llama_kv_cache_msa_context

llama_kv_cache_msa_context::llama_kv_cache_msa_context(llama_memory_status status) :
    kv(nullptr), status(status) {}

llama_kv_cache_msa_context::llama_kv_cache_msa_context(
        llama_kv_cache_msa * kv) :
    kv(kv),
    ctx_base(kv->get_base()->init_full()),
    ctx_idx (kv->get_idx ()->init_full()),
    status(llama_memory_status_combine(ctx_base->get_status(), ctx_idx->get_status())) {
}

llama_kv_cache_msa_context::llama_kv_cache_msa_context(
        llama_kv_cache_msa * kv,
        llama_context * lctx,
        bool optimize) :
    kv(kv),
    ctx_base(kv->get_base()->init_update(lctx, optimize)),
    ctx_idx (kv->get_idx ()->init_update(lctx, optimize)),
    status(llama_memory_status_combine(ctx_base->get_status(), ctx_idx->get_status())) {
}

llama_kv_cache_msa_context::llama_kv_cache_msa_context(
        llama_kv_cache_msa * kv,
        slot_info_vec_t sinfos_base,
        slot_info_vec_t sinfos_idx,
        std::vector<llama_ubatch> ubatches) :
    kv(kv),
    ubatches(std::move(ubatches)),
    // here we copy the ubatches. not sure if this is ideal
    ctx_base(new llama_kv_cache_context(kv->get_base(), std::move(sinfos_base), this->ubatches)),
    ctx_idx (new llama_kv_cache_context(kv->get_idx (), std::move(sinfos_idx),  this->ubatches)),
    status(llama_memory_status_combine(ctx_base->get_status(), ctx_idx->get_status())) {
}

llama_kv_cache_msa_context::~llama_kv_cache_msa_context() = default;

bool llama_kv_cache_msa_context::next() {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    ctx_base->next();
    ctx_idx ->next();

    if (++i_next >= ubatches.size()) {
        return false;
    }

    return true;
}

bool llama_kv_cache_msa_context::apply() {
    assert(!llama_memory_status_is_fail(status));

    bool res = true;

    res = res & ctx_base->apply();
    res = res & ctx_idx ->apply();

    return res;
}

llama_memory_status llama_kv_cache_msa_context::get_status() const {
    return status;
}

const llama_ubatch & llama_kv_cache_msa_context::get_ubatch() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return ubatches[i_next];
}

const llama_kv_cache_context * llama_kv_cache_msa_context::get_base() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return static_cast<const llama_kv_cache_context *>(ctx_base.get());
}

const llama_kv_cache_context * llama_kv_cache_msa_context::get_idx() const {
    assert(status == LLAMA_MEMORY_STATUS_SUCCESS);

    return static_cast<const llama_kv_cache_context *>(ctx_idx.get());
}

uint32_t llama_kv_cache_msa_context::get_n_pos() const {
    // pad the value so that the graph remains constant across batches and can be reused
    const uint32_t n_pad_cur = std::max(kv->get_n_pad(), 256u);

    llama_pos pos_max = -1;

    for (llama_seq_id seq_id = 0; seq_id < (llama_seq_id) kv->get_n_seq_max(); ++seq_id) {
        pos_max = std::max(pos_max, kv->seq_pos_max(seq_id));
    }

    return std::max(n_pad_cur, GGML_PAD((uint32_t) (pos_max + 1), n_pad_cur));
}

void llama_kv_cache_msa_context::set_input_cell_pos(ggml_tensor * dst, const llama_ubatch * ubatch, int32_t div) const {
    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));
    GGML_ASSERT(dst->type == GGML_TYPE_I32);
    GGML_ASSERT(div > 0);

    const int64_t n_tokens    = ubatch->n_tokens;
    const int64_t n_kv        = dst->ne[0];
    const int64_t n_stream_ub = dst->ne[1];

    GGML_ASSERT(n_tokens % n_stream_ub == 0);
    const int64_t n_tps = n_tokens/n_stream_ub;

    int32_t * data = (int32_t *) dst->data;

    for (int64_t s = 0; s < n_stream_ub; ++s) {
        const llama_seq_id seq_id = ubatch->seq_id[s*n_tps][0];

        const auto & cells = kv->get_base()->get_cells(seq_id);

        for (int64_t j = 0; j < n_kv; ++j) {
            // the value for empty or other-sequence cells is irrelevant as consumers mask them
            data[s*n_kv + j] =
                cells.is_empty(j) || !cells.seq_has(j, seq_id)
                    ? 0
                    : (int32_t) (cells.pos_get(j)/div);
        }
    }
}

void llama_kv_cache_msa_context::set_input_pos_slot(ggml_tensor * dst, const llama_ubatch * ubatch) const {
    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));
    GGML_ASSERT(dst->type == GGML_TYPE_I32 || dst->type == GGML_TYPE_F32);

    const int64_t n_tokens    = ubatch->n_tokens;
    const int64_t n_pos       = dst->ne[0];
    const int64_t n_stream_ub = dst->ne[1];

    GGML_ASSERT(n_tokens % n_stream_ub == 0);
    const int64_t n_tps = n_tokens/n_stream_ub;

    for (int64_t s = 0; s < n_stream_ub; ++s) {
        const llama_seq_id seq_id = ubatch->seq_id[s*n_tps][0];

        const auto & cells = kv->get_base()->get_cells(seq_id);

        std::vector<int32_t> map(n_pos, 0);

        for (uint32_t j = 0; j < cells.size(); ++j) {
            if (cells.is_empty(j) || !cells.seq_has(j, seq_id)) {
                continue;
            }

            const llama_pos p0 = cells.pos_get(j);

            if (p0 < 0 || p0 >= n_pos) {
                continue;
            }

            map[p0] = (int32_t) j;
        }

        if (dst->type == GGML_TYPE_I32) {
            int32_t * data = (int32_t *) dst->data + s*n_pos;
            std::copy(map.begin(), map.end(), data);
        } else {
            float * data = (float *) dst->data + s*n_pos;
            for (int64_t p = 0; p < n_pos; ++p) {
                data[p] = (float) map[p];
            }
        }
    }
}

void llama_kv_cache_msa_context::set_input_pos_mask(ggml_tensor * dst, const llama_ubatch * ubatch) const {
    GGML_ASSERT(ggml_backend_buffer_is_host(dst->buffer));
    GGML_ASSERT(dst->type == GGML_TYPE_F32);

    const int64_t n_tokens = ubatch->n_tokens;
    const int64_t n_pos    = dst->ne[0];

    GGML_ASSERT(dst->ne[1] == n_tokens);

    const uint32_t       n_swa    = kv->get_n_swa();
    const llama_swa_type swa_type = kv->get_swa_type();

    float * data = (float *) dst->data;

    std::fill(data, data + n_pos*n_tokens, -INFINITY);

    for (int64_t i = 0; i < n_tokens; ++i) {
        const llama_seq_id seq_id = ubatch->seq_id[i][0];

        const auto & cells = kv->get_base()->get_cells(seq_id);

        const llama_pos p1 = ubatch->pos[i];

        for (uint32_t j = 0; j < cells.size(); ++j) {
            if (cells.is_empty(j) || !cells.seq_has(j, seq_id)) {
                continue;
            }

            const llama_pos p0 = cells.pos_get(j);

            if (p0 < 0 || p0 >= n_pos) {
                continue;
            }

            // causal mask
            if (p0 > p1) {
                continue;
            }

            // apply SWA if any
            if (llama_hparams::is_masked_swa(n_swa, swa_type, p0, p1)) {
                continue;
            }

            data[i*n_pos + p0] = 0.0f;
        }
    }
}
