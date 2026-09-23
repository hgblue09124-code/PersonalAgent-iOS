with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

bad_v1 = """        let fileURL = root.appendingPathComponent("v1.gguf")
        var data = Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
        var version: UInt32 = 1 // unsupported version 1
        data.append(Data(bytes: &version, count: MemoryLayout<UInt32>.size))
        try data.write(to: fileURL)"""

good_v1 = """        let fileURL = root.appendingPathComponent("v1.gguf")
        var data = Data([0x47, 0x47, 0x55, 0x46]) // "GGUF"
        var version: UInt32 = 1 // unsupported version 1
        data.append(Data(bytes: &version, count: MemoryLayout<UInt32>.size))
        var tensorCount: UInt64 = 0
        data.append(Data(bytes: &tensorCount, count: MemoryLayout<UInt64>.size))
        var metadataCount: UInt64 = 0
        data.append(Data(bytes: &metadataCount, count: MemoryLayout<UInt64>.size))
        try data.write(to: fileURL)"""

if bad_v1 in content:
    updated = content.replace(bad_v1, good_v1)
    with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
        f.write(updated)
    print("Fixed v1 test file size")
else:
    print("Error: bad_v1 not found")
