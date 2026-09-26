# gguf-document-type
ID
gguf-document-type

PURPOSE
Make iOS receive .gguf files through the system document flow.

WHEN
The app must import GGUF files from Files or other document providers.

RULE
Register the GGUF UTI/document type in Info.plist and restrict the importer to the .gguf content type.

VERIFY
PR #65 records Info.plist registration, Xcode wiring, importer restriction, and evidence documentation.

STATUS
CONFIRMED

SOURCE
PR #65 — register GGUF document type