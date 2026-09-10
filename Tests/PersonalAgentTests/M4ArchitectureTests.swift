import Testing
import Foundation
import PAArchitecture
import PAFoundation
import PAMemory
import PAKernel
import PAComposition

@Suite("M4 Architecture & Isolation Tests")
struct M4ArchitectureTests {
    @Test func memoryModuleHasNoSingletonsOrGlobalMutableState() throws {
        let memoryDir = repositoryRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Memory")
        let files = try files(under: memoryDir, suffix: ".swift")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("static var instance"), "Memory file \(file.lastPathComponent) contains global mutable instance")
            #expect(!text.contains("static let shared ="), "Memory file \(file.lastPathComponent) contains singleton shared instance")
        }
    }

    @Test func memoryModuleDoesNotImportProvidersSkillsOrUI() throws {
        let memoryDir = repositoryRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Memory")
        let files = try files(under: memoryDir, suffix: ".swift")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let imports = importedModules(in: text)
            #expect(!imports.contains("PAProviders"), "PAMemory must not import PAProviders")
            #expect(!imports.contains("PAProvidersGrok"), "PAMemory must not import PAProvidersGrok")
            #expect(!imports.contains("PASkills"), "PAMemory must not import PASkills")
            #expect(!imports.contains("PATools"), "PAMemory must not import PATools")
            #expect(!imports.contains("SwiftUI"), "PAMemory must not import SwiftUI")
            #expect(!imports.contains("UIKit"), "PAMemory must not import UIKit")
        }
    }

    @Test func skillsToolsAndProvidersDoNotImportPAMemory() throws {
        let sourcesDir = repositoryRoot().appendingPathComponent("Sources")
        let forbiddenDirs = ["Skills", "Tools", "Providers"]

        for subDir in forbiddenDirs {
            let dir = sourcesDir.appendingPathComponent(subDir)
            let filesList = try files(under: dir, suffix: ".swift")
            for file in filesList {
                let text = try String(contentsOf: file, encoding: .utf8)
                let imports = importedModules(in: text)
                #expect(!imports.contains("PAMemory"), "\(subDir) file \(file.lastPathComponent) must not import PAMemory")
            }
        }
    }

    @Test func kernelInteractsWithMemoryStrictlyViaProtocol() throws {
        let kernelDir = repositoryRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Core")
            .appendingPathComponent("Agent")
        let filesList = try files(under: kernelDir, suffix: ".swift")

        for file in filesList {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("FileBackedMemoryStore"), "Kernel must not mention FileBackedMemoryStore")
            #expect(!text.contains("InMemoryMemoryStore"), "Kernel must not mention InMemoryMemoryStore")
        }
    }
}
