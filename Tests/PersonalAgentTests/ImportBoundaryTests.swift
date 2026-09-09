import Foundation
import Testing
import PAArchitecture

@Suite("Dependency direction")
struct ImportBoundaryTests {
    @Test func sourceImportsStayWithinAllowList() throws {
        let root = repositoryRoot()
        let sources = try files(under: root.appendingPathComponent("Sources"), suffix: ".swift")
        #expect(!sources.isEmpty)

        var violations: [String] = []
        for file in sources {
            let module = moduleName(for: file, sourcesRoot: root.appendingPathComponent("Sources"))
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
        let kernelDir = repositoryRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Core")
            .appendingPathComponent("Agent")
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

func moduleName(for file: URL, sourcesRoot: URL) -> String {
    let relative = file.path.replacingOccurrences(of: sourcesRoot.path + "/", with: "")
    if relative.hasPrefix("Foundation/") { return "PAFoundation" }
    if relative.hasPrefix("Observability/") { return "PAObservability" }
    if relative.hasPrefix("Events/") { return "PAEvents" }
    if relative.hasPrefix("Security/") { return "PASecurity" }
    if relative.hasPrefix("Storage/") { return "PAStorage" }
    if relative.hasPrefix("Memory/") { return "PAMemory" }
    if relative.hasPrefix("Providers/Contracts/") { return "PAProviders" }
    if relative.hasPrefix("Providers/Grok/") { return "PAProvidersGrok" }
    if relative.hasPrefix("Providers/OpenAICompatible/") { return "PAProvidersOpenAICompatible" }
    if relative.hasPrefix("Providers/OpenAI/") { return "PAProvidersOpenAI" }
    if relative.hasPrefix("Providers/Local/") { return "PAProvidersLocal" }
    if relative.hasPrefix("Core/Policy/") { return "PAPolicy" }
    if relative.hasPrefix("Tools/") { return "PATools" }
    if relative.hasPrefix("Modules/") { return "PAModules" }
    if relative.hasPrefix("Skills/") { return "PASkills" }
    if relative.hasPrefix("Core/Cognition/") { return "PACognition" }
    if relative.hasPrefix("Core/Agency/") { return "PAAgency" }
    if relative.hasPrefix("Core/Agent/") { return "PAKernel" }
    if relative.hasPrefix("Architecture/") { return "PAArchitecture" }
    if relative.hasPrefix("Composition/") { return "PAComposition" }
    return "UNKNOWN"
}
