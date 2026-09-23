with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

bad_id = 'let identity = ProviderIdentity(id: ProviderID(rawValue: "observable-fallback"), displayName: "Observable Fallback")'
good_id = 'let identity = ProviderIdentity(id: ProviderID(rawValue: "observable-fallback"), displayName: "Observable Fallback", models: [ModelIdentity(id: ModelID(rawValue: "fallback-model"), displayName: "Fallback Model")])'

content = content.replace(bad_id, good_id)

with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
    f.write(content)

print("Fixed ProviderIdentity initialization in ObservableFallbackProvider")
