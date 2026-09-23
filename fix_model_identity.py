with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

bad_id = 'ModelIdentity(id: ModelID(rawValue: "fallback-model"), displayName: "Fallback Model")'
good_id = 'ModelIdentity(id: ModelID(rawValue: "fallback-model"), displayName: "Fallback Model", contextTokenLimit: 4096)'

content = content.replace(bad_id, good_id)

with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
    f.write(content)

print("Fixed ModelIdentity initialization")
