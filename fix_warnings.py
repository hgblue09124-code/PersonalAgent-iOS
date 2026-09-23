with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

content = content.replace("let callCount = await mockEngine.completeCallCount", "let callCount = mockEngine.completeCallCount")
content = content.replace("let lastReq = await mockEngine.lastGenerationRequest", "let lastReq = mockEngine.lastGenerationRequest")
content = content.replace("let streamCount = await mockEngine.streamCallCount", "let streamCount = mockEngine.streamCallCount")
content = content.replace("let unloadCalls = await mockEngine.unloadCallCount", "let unloadCalls = mockEngine.unloadCallCount")

with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
    f.write(content)

print("Cleaned up await warnings")
