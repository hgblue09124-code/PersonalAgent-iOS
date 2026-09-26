# provider-vertical-slice
ID
provider-vertical-slice

PURPOSE
Keep remote provider execution explicit and fail closed on invalid completion output.

WHEN
A provider path is being proven independently from local inference.

RULE
Verify the provider requirements end-to-end and reject empty completion text instead of fabricating a successful response.

VERIFY
PR #66 added P1–P7 coverage and changed ChatCompletionsCodec to fail closed on empty completion text.

STATUS
CONFIRMED

SOURCE
PR #66 — M9 parallel real provider vertical slice