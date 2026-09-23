with open("Sources/Composition/M8CompositionRoot.swift", "r") as f:
    content = f.read()

bad_coord_init = """    public init(
        storage: any LocalModelStorage,
        deviceCapabilityProvider: any DeviceCapabilityProviding
    ) {
        self.storage = storage
        self.deviceCapabilityProvider = deviceCapabilityProvider
    }"""

good_coord_init = """    private let engineFactory: (@Sendable (LocalModelIdentity, any DeviceCapabilityProviding) -> any LocalModelEngine)?

    public init(
        storage: any LocalModelStorage,
        deviceCapabilityProvider: any DeviceCapabilityProviding,
        engineFactory: (@Sendable (LocalModelIdentity, any DeviceCapabilityProviding) -> any LocalModelEngine)? = nil
    ) {
        self.storage = storage
        self.deviceCapabilityProvider = deviceCapabilityProvider
        self.engineFactory = engineFactory
    }"""

bad_new_engine = """        let newEngine = LlamaCPPModelEngine(
            identity: identity,
            deviceCapabilityProvider: deviceCapabilityProvider
        )"""

good_new_engine = """        let newEngine: any LocalModelEngine
        if let factory = engineFactory {
            newEngine = factory(identity, deviceCapabilityProvider)
        } else {
            newEngine = LlamaCPPModelEngine(
                identity: identity,
                deviceCapabilityProvider: deviceCapabilityProvider
            )
        }"""

bad_m8_init = """        localModelStorage: (any LocalModelStorage)? = nil,
        deviceCapabilityProvider: (any DeviceCapabilityProviding)? = nil,"""

good_m8_init = """        localModelStorage: (any LocalModelStorage)? = nil,
        deviceCapabilityProvider: (any DeviceCapabilityProviding)? = nil,
        localModelEngineFactory: (@Sendable (LocalModelIdentity, any DeviceCapabilityProviding) -> any LocalModelEngine)? = nil,"""

bad_coordinator_call = """        let coordinator = LocalModelRuntimeCoordinator(
            storage: resolvedStorage,
            deviceCapabilityProvider: resolvedDeviceCapability
        )"""

good_coordinator_call = """        let coordinator = LocalModelRuntimeCoordinator(
            storage: resolvedStorage,
            deviceCapabilityProvider: resolvedDeviceCapability,
            engineFactory: localModelEngineFactory
        )"""

content = content.replace(bad_coord_init, good_coord_init)
content = content.replace(bad_new_engine, good_new_engine)
content = content.replace(bad_m8_init, good_m8_init)
content = content.replace(bad_coordinator_call, good_coordinator_call)

with open("Sources/Composition/M8CompositionRoot.swift", "w") as f:
    f.write(content)

print("Updated M8CompositionRoot.swift with engineFactory seam")
