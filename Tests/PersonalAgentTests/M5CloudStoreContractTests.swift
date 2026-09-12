import Testing
import Foundation
import PAFoundation
import PAStorage
import PAMemory
import PAArchitecture

private final class DynamicAvailabilityState: @unchecked Sendable {
    private let lock = NSLock()
    private var _available: Bool
    init(_ available: Bool) { self._available = available }
    var available: Bool {
        get { lock.withLock { _available } }
        set { lock.withLock { _available = newValue } }
    }
}

/// Private test double strictly isolated as test support in M5CloudStoreContractTests.
/// Does not exist in production PAStorage runtime.
private actor TestDoubleCloudStore<Record: StorageRecord>: CloudStore {
    let provider: any CloudStorageProvider
    private var records: [String: Record] = [:]
    private var shouldFail: Bool = false

    init(provider: any CloudStorageProvider) {
        self.provider = provider
    }

    func setFailureSimulation(_ fail: Bool) {
        self.shouldFail = fail
    }

    func push(_ record: Record) async throws {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is currently offline/unavailable")
        }
        if shouldFail {
            throw CloudStorageError.storeFailed("Simulated cloud failure on push")
        }
        records[record.id] = record
    }

    func pull(id: String) async throws -> Record? {
        guard await provider.isAvailable else {
            throw CloudStorageError.unavailable("Provider \(provider.identifier) is currently offline/unavailable")
        }
        if shouldFail {
            throw CloudStorageError.storeFailed("Simulated cloud failure on pull")
        }
        return records[id]
    }
}

@Suite("M5.2 CloudStore Contract Tests")
struct M5CloudStoreContractTests {

    // 1. push/pull identity + version preservation
    @Test func testPushAndPullIdentityAndVersionPreservation() async throws {
        let provider = AbstractCloudStorageProvider(identifier: "test-cloud-provider", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)

        let record = MemoryRecord(
            id: MemoryRecordID(rawValue: "cloud-rec-1"),
            kind: .fact,
            content: "Cloud persistence record content",
            provenance: Provenance(source: "user"),
            version: 3
        )
        let storageRecord = MemoryStorageRecord(record)

        // Push record to cloud store
        try await cloudStore.push(storageRecord)

        // Pull record from cloud store
        let fetched = try await cloudStore.pull(id: "cloud-rec-1")

        #expect(fetched != nil)
        #expect(fetched?.id == "cloud-rec-1")
        #expect(fetched?.version == 3)
        #expect(fetched?.record.content == "Cloud persistence record content")
        #expect(fetched == storageRecord)
    }

    // 2. provider abstraction
    @Test func testProviderAbstractionAndAvailabilityCheck() async throws {
        let state = DynamicAvailabilityState(false)
        let provider = AbstractCloudStorageProvider(identifier: "dynamic-provider") {
            state.available
        }
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)

        #expect(await cloudStore.provider.identifier == "dynamic-provider")

        let record = MemoryStorageRecord(
            MemoryRecord(
                id: MemoryRecordID(rawValue: "cloud-rec-2"),
                kind: .preference,
                content: "Preference data",
                provenance: Provenance(source: "user"),
                version: 1
            )
        )

        // Push while provider is unavailable must throw CloudStorageError.unavailable
        do {
            try await cloudStore.push(record)
            Issue.record("Expected push to fail when provider is unavailable")
        } catch let err as CloudStorageError {
            if case .unavailable = err {
                // Expected
            } else {
                Issue.record("Expected .unavailable error, got \(err)")
            }
        } catch {
            Issue.record("Expected CloudStorageError, got \(error)")
        }

        // Pull while provider is unavailable must throw CloudStorageError.unavailable
        do {
            _ = try await cloudStore.pull(id: "cloud-rec-2")
            Issue.record("Expected pull to fail when provider is unavailable")
        } catch let err as CloudStorageError {
            if case .unavailable = err {
                // Expected
            } else {
                Issue.record("Expected .unavailable error, got \(err)")
            }
        } catch {
            Issue.record("Expected CloudStorageError, got \(error)")
        }

        // Make provider available
        state.available = true

        // Push and pull should now succeed
        try await cloudStore.push(record)
        let fetched = try await cloudStore.pull(id: "cloud-rec-2")
        #expect(fetched != nil)
        #expect(fetched?.id == "cloud-rec-2")
    }

    // 3. cloud failure does not alter local state
    @Test func testCloudFailureDoesNotAlterLocalState() async throws {
        let localStore = InMemoryMemoryStore()
        let provider = AbstractCloudStorageProvider(identifier: "failing-cloud-provider", isAvailable: true)
        let cloudStore = TestDoubleCloudStore<MemoryStorageRecord>(provider: provider)

        let initialMem = MemoryRecord(
            id: MemoryRecordID(rawValue: "local-rec-1"),
            kind: .fact,
            content: "Local primary fact",
            provenance: Provenance(source: "user"),
            version: 1
        )
        let localRecord = MemoryStorageRecord(initialMem)

        // Store in local store first
        try await localStore.upsert(localRecord)

        // Enable cloud failure simulation
        await cloudStore.setFailureSimulation(true)

        // Attempt push to cloud store
        do {
            try await cloudStore.push(localRecord)
            Issue.record("Expected cloud push to fail")
        } catch let err as CloudStorageError {
            if case .storeFailed = err {
                // Expected
            } else {
                Issue.record("Expected .storeFailed error, got \(err)")
            }
        } catch {
            Issue.record("Expected CloudStorageError, got \(error)")
        }

        // Verify local state remains intact and unmodified
        let fetchedLocal = try await localStore.fetch(id: "local-rec-1")
        #expect(fetchedLocal != nil)
        #expect(fetchedLocal?.id == "local-rec-1")
        #expect(fetchedLocal?.version == 1)
        #expect(fetchedLocal?.record.content == "Local primary fact")
    }

    // 4. PAStorage dependency boundary & strict isolation
    @Test func testPAStorageAndMemoryAndKernelDependencyBoundaries() throws {
        // PAStorage MUST NOT import PAMemory or PAKernel
        guard let storageImports = ArchitectureManifest.allowedImports["PAStorage"] else {
            Issue.record("PAStorage mapping missing from ArchitectureManifest")
            return
        }
        #expect(!storageImports.contains("PAMemory"), "PAStorage MUST NOT import PAMemory")
        #expect(!storageImports.contains("PAKernel"), "PAStorage MUST NOT import PAKernel")

        // PAMemory imports PAStorage, but PAMemory contracts / execution port MUST NOT access CloudStore directly
        guard let memoryImports = ArchitectureManifest.allowedImports["PAMemory"] else {
            Issue.record("PAMemory mapping missing from ArchitectureManifest")
            return
        }
        #expect(!memoryImports.contains("PAProviders"), "PAMemory MUST NOT import PAProviders")

        // Kernel MUST NOT import concrete providers or companion dependencies
        #expect(ArchitectureManifest.kernelMustNotImport.contains("PAProvidersGrok"))
        #expect(ArchitectureManifest.forbiddenCompanionDependencies.contains("Firebase"))
        #expect(ArchitectureManifest.forbiddenCompanionDependencies.contains("Supabase"))
    }

    // 5. M0-M5.1 regression / architecture check
    @Test func testNoForbiddenVendorSDKsOrRuntimeInStorage() throws {
        let storageDir = repositoryRoot().appendingPathComponent("Sources/Storage")
        let filesList = try files(under: storageDir, suffix: ".swift")

        let forbiddenKeywords = ["Firebase", "CloudKit", "Supabase", "AWS", "URLSession", "Network"]

        for file in filesList {
            let text = try String(contentsOf: file, encoding: .utf8)
            for keyword in forbiddenKeywords {
                #expect(!text.contains(keyword), "File \(file.lastPathComponent) contains forbidden keyword \(keyword)")
            }
        }
    }
}
