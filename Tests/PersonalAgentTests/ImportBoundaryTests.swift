import Foundation
import Testing

@Suite("Dependency direction")
struct ImportBoundaryTests {
    @Test func sourceImportsStayWithinAllowList() throws {
        let root = repositoryRoot()
        // Scan every production source root declared by Package.swift, not only
        // Sources/. The latter misses Kernel, providers, storage and composition.
        let sourceRoots = [
            "Kernel", "Runtime", "Composition", "Providers", "Storage", "Sources"
        ].map { root.appendingPathComponent($0) }
        var sources: [URL] = []
        for sourceRoot in sourceRoots where FileManager.default.fileExists(atPath: sourceRoot.path) {
            sources.append(contentsOf: try files(under: sourceRoot, suffix: ".swift"))
        }
        #expect(!sources.isEmpty)

        var violations: [String] = []
        for file in sources {
            let module = moduleName(for: file, repositoryRoot: root)
            guard let allowed = ArchitectureManifest.allowedImports[module] else {
                violations.append("Unknown module mapping for \(file.path) -> \(module)")
                continue
            }
            let contents = try String(contentsOf: file, encoding: .utf8)
            for imported in importedModules(in: contents) {
                if imported.hasPrefix("PA") || imported == "SwiftUI" || imported == "UIKit" || imported == "AppKit" {
                    if imported == module { continue }
                    if !allowed.contains(imported) {
                        violations.append("\(module) imports \(imported) (\(file.lastPathComponent))")
                    }
                }
                if module == "PAKernel" && ArchitectureManifest.kernelMustNotImport.contains(imported) {
                    violations.append("Kernel forbidden import \(imported)")
                }
            }
        }
        #expect(violations.isEmpty)
    }

    @Test func kernelDoesNotImportConcreteStorageCloudOrUI() throws {
        let kernelDir = repositoryRoot().appendingPathComponent("Kernel")
        let forbiddenImports: Set<String> = [
            "PAProvidersGrok",
            "PAProvidersOpenAI",
            "PAProvidersOpenAICompatible",
            "PAProvidersLocal",
            "PAStorage",
            "SwiftUI",
            "UIKit",
            "AppKit",
            "URLSession",
            "Supabase",
            "Firebase"
        ]

        let swiftFiles = try files(under: kernelDir, suffix: ".swift")
        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let imports = Set(importedModules(in: contents))
            let intersection = imports.intersection(forbiddenImports)
            #expect(intersection.isEmpty, "Kernel file \(file.lastPathComponent) contains forbidden imports: \(intersection)")
        }
    }

    @Test func packageDoesNotDependOnCompanionRepos() throws {
        let package = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        for forbidden in ArchitectureManifest.forbiddenCompanionDependencies {
            #expect(!package.contains(forbidden), "Package.swift mentions \(forbidden)")
        }
    }

    @Test func kernelSourcesDoNotMentionConcreteProviders() throws {
        let kernelDir = repositoryRoot().appendingPathComponent("Kernel")
        let files = try files(under: kernelDir, suffix: ".swift")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("PAProvidersGrok"))
            #expect(!text.contains("OpenAIProvider"))
            #expect(!text.contains("living-data-ocean"))
            #expect(!text.contains("Firebase"))
        }
    }
}

func repositoryRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    let fm = FileManager.default
    for _ in 0..<8 {
        url.deleteLastPathComponent()
        if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            return url
        }
    }
    return URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func files(under root: URL, suffix: String) throws -> [URL] {
    let fm = FileManager.default
    var result: [URL] = []
    if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
        for case let url as URL in enumerator where url.path.hasSuffix(suffix) {
            result.append(url)
        }
    }
    if result.isEmpty {
        result = try walk(root, suffix: suffix)
    }
    return result
}

private func walk(_ root: URL, suffix: String) throws -> [URL] {
    let fm = FileManager.default
    let contents = (try? fm.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: []
    )) ?? []
    var result: [URL] = []
    for url in contents {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            result.append(contentsOf: try walk(url, suffix: suffix))
        } else if url.path.hasSuffix(suffix) {
            result.append(url)
        }
    }
    return result
}

func importedModules(in source: String) -> [String] {
    source.split(whereSeparator: \.isNewline).compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("import ") else { return nil }
        let name = trimmed.dropFirst("import ".count).trimmingCharacters(in: .whitespaces)
        return String(name.split(separator: " ").first ?? Substring(name))
    }
}

func moduleName(for file: URL, repositoryRoot: URL) -> String {
    let path = file.path
    let rootPath = repositoryRoot.path + "/"

    guard path.hasPrefix(rootPath) else { return "UNKNOWN" }

    let relative = String(path.dropFirst(rootPath.count))

    if relative.hasPrefix("Kernel/Events/") { return "PAEvents" }
    if relative.hasPrefix("Kernel/Ports/Providers/") { return "PAProviders" }
    if relative.hasPrefix("Kernel/") { return "PAKernel" }

    if relative.hasPrefix("Runtime/") { return "PARuntime" }

    if relative.hasPrefix("Composition/") { return "PAComposition" }

    if relative.hasPrefix("Providers/Remote/Grok/") { return "PAProvidersGrok" }
    if relative.hasPrefix("Providers/Remote/OpenAICompatible/") {
        return "PAProvidersOpenAICompatible"
    }
    if relative.hasPrefix("Providers/Remote/OpenAI/") { return "PAProvidersOpenAI" }
    if relative.hasPrefix("Providers/Remote/Shared/") { return "PAProvidersRemote" }
    if relative.hasPrefix("Providers/Local/") { return "PAProvidersLocal" }

    if relative.hasPrefix("Storage/Memory/") { return "PAStorageMemory" }
    if relative.hasPrefix("Storage/Models/") { return "PAStorageModels" }
    if relative.hasPrefix("Storage/") { return "PAStorage" }

    if relative.hasPrefix("Sources/ImportGateway/") { return "PAImportGateway" }
    if relative.hasPrefix("Sources/Observability/") { return "PAObservability" }
    if relative.hasPrefix("Sources/Events/") { return "PAEvents" }
    if relative.hasPrefix("Sources/Security/") { return "PASecurity" }
    if relative.hasPrefix("Sources/Memory/") { return "PAMemory" }
    if relative.hasPrefix("Sources/Workspace/") { return "PAWorkspace" }
    if relative.hasPrefix("Sources/Terminal/") { return "PATerminal" }

    if relative.hasPrefix("Sources/Capabilities/Tools/") { return "PATools" }
    if relative.hasPrefix("Sources/Capabilities/Modules/") { return "PAModules" }
    if relative.hasPrefix("Sources/Capabilities/Skills/") { return "PASkills" }

    if relative.hasPrefix("cllama/") { return "cllama" }

    return "UNKNOWN"
}
