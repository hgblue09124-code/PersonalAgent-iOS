# app-provider-dependency
ID
app-provider-dependency

PURPOSE
Make the real local inference dependency graph explicit at the application composition boundary.

WHEN
The app composition root needs to construct a real local provider.

RULE
Declare the PAComposition → PAProvidersLocal dependency in Package.swift and architecture import rules; wire LocalModelProviderAdapter through composition rather than direct engine access.

VERIFY
PR #41 reports the compiled dependency chain and real-inference test reporting repair.

STATUS
CONFIRMED

SOURCE
PR #41 — app dependency graph and real-inference test reporting