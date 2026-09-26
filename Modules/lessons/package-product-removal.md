# package-product-removal

ID
package-product-removal

PURPOSE
Keep Swift package and Apple project ownership synchronized when a package product is removed.

WHEN
A Swift package product or target is removed from Package.swift.

RULE
Inspect both Package.swift and PersonalAgent.xcodeproj/project.pbxproj for stale package-product, dependency, or build-file references.

VERIFY
Apple Native Build passes after stale Xcode references are removed.

STATUS
CONFIRMED

SOURCE
L-001 / PR #98
