import Testing
import Foundation
import PAFoundation
import PAStorage
import PAMemory
import PAKernel
import PAComposition
import PAArchitecture

@Suite("M0–M5 Architectural Integrity Audit Tests")
struct M5ArchitecturalAuditTests {

    // 1. Local-First Behavior Audit
    @Test func testLocalFirstBehaviorWhenCloudIsOfflineOrFailing() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("M5LocalFirstAudit_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileBackedStore = try FileBackedMemoryStore(directoryURL: tempDir)
        let inMemoryStore = InMemoryMemoryStore()

        // Verify local stores allow full read/write when cloud provider is non-existent/offline
        let rec1 = MemoryRecord(
            id: MemoryRecordID(rawValue: "local-first-1"),
            kind: .fact,
            content: "Offline local-first memory record",
            provenance: Provenance(source: "user"),
            version: 1
        )
        let storageRec1 = MemoryStorageRecord(rec1)

        try await fileBackedStore.upsert(storageRec1)
        try await inMemoryStore.upsert(storageRec1)

        let fetchedFB = try await fileBackedStore.fetch(id: "local-first-1")
        let fetchedIM = try await inMemoryStore.fetch(id: "local-first-1")

        #expect(fetchedFB?.record.content == "Offline local-first memory record")
        #expect(fetchedIM?.record.content == "Offline local-first memory record")

        // Verify local sync queue functions 100% offline
        let offlineProvider = AbstractCloudStorageProvider(identifier: "offline-provider", isAvailable: false)
        let offlineCloud = InMemoryCloudStore<MemoryStorageRecord>(provider: offlineProvider)
        let queue = PASyncQueue(storageURL: tempDir.appendingPathComponent("sync-queue.json"))
        let engine = PASyncEngine(localStore: fileBackedStore, cloudStore: offlineCloud, queue: queue)

        try await engine.enqueueLocalChange(id: "local-first-1")
        #expect(await queue.count() == 1)

        // Attempt sync fails closed cleanly without wiping or corrupting local data
        do {
            try await engine.synchronize()
            Issue.record("Expected offline synchronize to throw")
        } catch let err as CloudStorageError {
            if case .unavailable = err {
                // Expected
            } else {
                Issue.record("Expected unavailable error, got \(err)")
            }
        }

        // Verify local data and queued change remained 100% intact after offline failure
        #expect(await queue.count() == 1)
        #expect(try await fileBackedStore.fetch(id: "local-first-1") != nil)
    }

    // 2. PAMemory Cloud Independence Audit
    @Test func testPAMemoryCloudIndependenceBoundary() throws {
        let root = repositoryRoot()
        let memorySourcesDir = root.appendingPathComponent("Sources").appendingPathComponent("Memory")
        let memoryFiles = try files(under: memorySourcesDir, suffix: ".swift")

        #expect(!memoryFiles.isEmpty)

        for file in memoryFiles {
            let content = try String(contentsOf: file, encoding: .utf8)
            let imports = importedModules(in: content)

            // Verify PAMemory imports only allowed modules
            for imported in imports {
                if imported.hasPrefix("PAProviders") {
                    Issue.record("PAMemory file \(file.lastPathComponent) illegally imports provider module \(imported)")
                }
                if imported == "URLSession" || imported == "Network" {
                    Issue.record("PAMemory file \(file.lastPathComponent) illegally imports network component \(imported)")
                }
            }

            // Verify PAMemory contains no cloud endpoint URLs or vendor auth tokens
            #expect(!content.contains("https://"), "PAMemory file \(file.lastPathComponent) contains cloud URL")
            #expect(!content.contains("api.openai.com"), "PAMemory contains OpenAI endpoint")
            #expect(!content.contains("api.x.ai"), "PAMemory contains Grok endpoint")
        }
    }

    // 3. Kernel Cloud Isolation Audit
    @Test func testKernelCloudIsolationAndNoProviderImports() throws {
        let root = repositoryRoot()
        let kernelSourcesDir = root.appendingPathComponent("Kernel")
        let kernelFiles = try files(under: kernelSourcesDir, suffix: ".swift")

        #expect(!kernelFiles.isEmpty)

        for file in kernelFiles {
            let content = try String(contentsOf: file, encoding: .utf8)
            let imports = importedModules(in: content)

            for imported in imports {
                if ArchitectureManifest.kernelMustNotImport.contains(imported) {
                    Issue.record("Kernel file \(file.lastPathComponent) illegally imports forbidden module \(imported)")
                }
                if imported == "PAStorage" {
                    Issue.record("Kernel file \(file.lastPathComponent) illegally imports PAStorage directly")
                }
            }

            // Verify Kernel does not mention concrete cloud or sync types
            #expect(!content.contains("PASyncEngine"), "Kernel file \(file.lastPathComponent) mentions concrete PASyncEngine")
            #expect(!content.contains("PASyncQueue"), "Kernel file \(file.lastPathComponent) mentions concrete PASyncQueue")
            #expect(!content.contains("CloudStore"), "Kernel file \(file.lastPathComponent) mentions CloudStore")
        }
    }

    // 4. Explicit Dependency Injection Audit
    @Test func testCompositionRootsAndRuntimesUseExplicitDependencyInjection() throws {
        let root = repositoryRoot()
        let compositionDir = root.appendingPathComponent("Sources").appendingPathComponent("Composition")
        let compositionFiles = try files(under: compositionDir, suffix: ".swift")

        #expect(!compositionFiles.isEmpty)

        for file in compositionFiles {
            let content = try String(contentsOf: file, encoding: .utf8)

            // Ensure no usage of global singletons in composition roots
            #expect(!content.contains(".shared"), "Composition root \(file.lastPathComponent) accesses global .shared singleton")
            #expect(!content.contains("ServiceLocator"), "Composition root \(file.lastPathComponent) uses ServiceLocator anti-pattern")
        }
    }

    // 5. Actor Isolation & Sendable Conformance Audit
    @Test func testActorIsolationAndSendableConformance() {
        // Verify key sync and storage primitives conform to Sendable
        func checkSendable<T: Sendable>(_ type: T.Type) {
            #expect(Bool(type == type))
        }
        checkSendable(PASyncQueue.self)
        checkSendable(CloudStorageError.self)
        checkSendable(ConflictResolution.self)
        checkSendable(MemoryStorageRecord.self)
        checkSendable(LineageProofResult.self)
    }

    // 6. No Vendor / Auth Leakage Audit
    @Test func testNoVendorSDKsOrHardcodedAuthCredentialsInSources() throws {
        let root = repositoryRoot()
        let sourcesDir = root.appendingPathComponent("Sources")
        let allSourceFiles = try files(under: sourcesDir, suffix: ".swift")

        #expect(!allSourceFiles.isEmpty)

        let secretPatterns = [
            "sk-proj-",
            "xai-api-key-",
            "Bearer sk-",
            "ghp_",
            "AKIA"
        ]

        let forbiddenImports = [
            "Firebase",
            "FirebaseApp",
            "Supabase",
            "SupabaseClient"
        ]

        for file in allSourceFiles {
            let content = try String(contentsOf: file, encoding: .utf8)

            // Secret leakage check
            for secretPattern in secretPatterns {
                #expect(!content.contains(secretPattern), "Source file \(file.lastPathComponent) contains secret pattern: \(secretPattern)")
            }

            // Vendor SDK import check
            let imports = importedModules(in: content)
            for imp in imports {
                for forbiddenImp in forbiddenImports {
                    #expect(imp != forbiddenImp, "Source file \(file.lastPathComponent) illegally imports vendor SDK \(imp)")
                }
            }
        }
    }
}
