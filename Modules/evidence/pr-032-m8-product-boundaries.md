# m8-product-boundaries
ID
m8-product-boundaries

PURPOSE
Keep iOS product boundaries explicit around session, local model, device capability, and persistence.

WHEN
Connecting the product application layer to local-model and device infrastructure.

RULE
Expose narrow application boundaries and compose them through M8CompositionRoot instead of letting UI own runtime infrastructure.

VERIFY
M8 foundation introduced dedicated boundaries plus comprehensive tests and documentation.

STATUS
CONFIRMED

SOURCE
PR #32 — M8 product architecture foundation