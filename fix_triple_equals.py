with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "r") as f:
    content = f.read()

bad_eq = """        let e2 = try #require(engine2)
        let e1 = try #require(engine1)
        #expect(e2 === e1)"""

good_eq = """        let mock1 = try #require(engine1 as? ObservableMockEngine)
        let mock2 = try #require(engine2 as? ObservableMockEngine)
        #expect(mock2 === mock1)"""

content = content.replace(bad_eq, good_eq)

with open("Tests/PersonalAgentTests/LocalModelStorageTests.swift", "w") as f:
    f.write(content)

print("Fixed === object comparison in testAcceptanceF")
