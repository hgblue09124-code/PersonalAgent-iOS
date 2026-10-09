import XCTest
@testable import PAKernel

final class AgentPermissionTests: XCTestCase {
    func testAuthorizationDeniesByDefault() {
        let authorizer = AgentAuthorizer()

        XCTAssertFalse(authorizer.permissions.allows(.writeWorkspace))
        XCTAssertThrowsError(try authorizer.require(.writeWorkspace)) { error in
            XCTAssertEqual(error as? AgentAuthorizationError, .denied(.writeWorkspace))
        }
    }

    func testExplicitPermissionsAreGrantedWithoutGrantingOthers() throws {
        let authorizer = AgentAuthorizer(
            permissions: AgentPermissionSet([.readWorkspace, .executeSkill])
        )

        XCTAssertNoThrow(try authorizer.require(.readWorkspace))
        XCTAssertNoThrow(try authorizer.require(.executeSkill))
        XCTAssertThrowsError(try authorizer.require(.writeWorkspace))
    }

    func testRequireAllFailsClosedAtFirstMissingPermission() {
        let authorizer = AgentAuthorizer(
            permissions: AgentPermissionSet([.readWorkspace])
        )

        XCTAssertThrowsError(
            try authorizer.requireAll([.readWorkspace, .writeWorkspace, .network])
        ) { error in
            XCTAssertEqual(error as? AgentAuthorizationError, .denied(.writeWorkspace))
        }
    }
}
