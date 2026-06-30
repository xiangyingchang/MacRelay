import XCTest
@testable import AgentClientMacShell

final class WorkspaceSessionGrouperTests: XCTestCase {
    func test_savedWorkspacePullsRuntimeSessionsFromSameCWDIntoWorkspace() {
        let grouper = WorkspaceSessionGrouper(
            workspaceCWD: "/Users/example/project",
            savedSessionIDs: ["saved-1"],
            archivedSessionIDs: [],
            runtimeSessionCWDs: [
                "saved-1": "/Users/example/project",
                "runtime-same-cwd": "/Users/example/project/.",
                "runtime-other-cwd": "/Users/example/other"
            ]
        )

        XCTAssertTrue(grouper.isWorkspaceSession("saved-1"))
        XCTAssertTrue(grouper.isWorkspaceSession("runtime-same-cwd"))
        XCTAssertFalse(grouper.isWorkspaceSession("runtime-other-cwd"))
    }

    func test_runtimeSessionsStayActiveUntilWorkspaceGroupingExists() {
        let grouper = WorkspaceSessionGrouper(
            workspaceCWD: "/Users/example/project",
            savedSessionIDs: [],
            archivedSessionIDs: [],
            runtimeSessionCWDs: [
                "runtime-same-cwd": "/Users/example/project"
            ]
        )

        XCTAssertFalse(grouper.isWorkspaceSession("runtime-same-cwd"))
    }

    func test_archivedSessionsAlwaysBelongToWorkspace() {
        let grouper = WorkspaceSessionGrouper(
            workspaceCWD: "/Users/example/project",
            savedSessionIDs: [],
            archivedSessionIDs: ["archived-1"],
            runtimeSessionCWDs: [:]
        )

        XCTAssertTrue(grouper.isWorkspaceSession("archived-1"))
    }
}
