# platform-conditioned-native-runtime
ID
platform-conditioned-native-runtime

PURPOSE
Keep native C/C++ inference dependencies compatible with platform-neutral CI.

WHEN
An Apple-only native dependency is introduced into a Swift package.

RULE
Condition the native dependency to Apple platforms and retain a dedicated Apple build lane for native compilation and IPA production.

VERIFY
PR #39 reports Linux CI green, Apple native build/IPA verification, and native inference repair.

STATUS
CONFIRMED

SOURCE
PR #39 — M8.1 repair across Linux, Apple, and native inference gates