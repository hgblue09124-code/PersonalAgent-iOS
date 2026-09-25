# Memory Architecture

Memory owns information semantics: what constitutes memory, classification, retrieval, ranking and delivery to runtime.

Target semantic domains:

- Working memory
- Conversation memory
- Long-term memory
- Retrieval/indexing

These are semantic domains, not mandatory physical databases.

```text
Runtime → Memory semantics → Storage contract → Storage implementation
```

Memory may depend on storage contracts, but does not own file/database/cloud implementation details.

Persistence failures remain distinguishable from successful memory operations. Do not create additional memory layers merely because folders look complex; introduce a boundary only when ownership or dependency evidence requires it.
