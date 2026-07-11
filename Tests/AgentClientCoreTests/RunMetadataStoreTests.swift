import XCTest
@testable import AgentClientCore

// MARK: - InMemoryRunMetadataStore Tests

final class InMemoryRunMetadataStoreTests: XCTestCase {
    private var store: InMemoryRunMetadataStore!

    override func setUp() {
        super.setUp()
        store = InMemoryRunMetadataStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Save / Load

    func testSaveAndLoad() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "Hello")
        let metadata = RunMetadata(run: run, sessionID: "s1")

        try store.save(metadata)

        let loaded = try store.load(runID: "run-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.run.id, "run-1")
        XCTAssertEqual(loaded?.sessionID, "s1")
    }

    func testLoadNonexistentReturnsNil() throws {
        let loaded = try store.load(runID: "nonexistent")
        XCTAssertNil(loaded)
    }

    // MARK: - Update

    func testUpdateMutatesExistingMetadata() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        let metadata = RunMetadata(run: run, sessionID: "s1")
        try store.save(metadata)

        try store.update(runID: "run-1") { meta in
            meta = RunMetadata(
                run: meta.run,
                sessionID: meta.sessionID,
                tags: ["updated": "true"]
            )
        }

        let loaded = try store.load(runID: "run-1")
        XCTAssertEqual(loaded?.tags["updated"], "true")
    }

    func testUpdateThrowsForNonexistentRun() {
        XCTAssertThrowsError(try store.update(runID: "nonexistent") { _ in })
    }

    // MARK: - List

    func testListRunsBySession() throws {
        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        let run2 = AgentRun(id: "run-2", sessionID: "s1", runtime: .codex)
        let run3 = AgentRun(id: "run-3", sessionID: "s2", runtime: .codex)

        try store.save(RunMetadata(run: run1, sessionID: "s1"))
        try store.save(RunMetadata(run: run2, sessionID: "s1"))
        try store.save(RunMetadata(run: run3, sessionID: "s2"))

        let s1Runs = try store.listRuns(sessionID: "s1")
        XCTAssertEqual(s1Runs.count, 2)
        XCTAssertTrue(s1Runs.allSatisfy { $0.sessionID == "s1" })

        let s2Runs = try store.listRuns(sessionID: "s2")
        XCTAssertEqual(s2Runs.count, 1)
    }

    func testListRunsSortedByCreatedAt() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_001)

        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, createdAt: t1)
        let run2 = AgentRun(id: "run-2", sessionID: "s1", runtime: .codex, createdAt: t0)

        try store.save(RunMetadata(run: run1, sessionID: "s1"))
        try store.save(RunMetadata(run: run2, sessionID: "s1"))

        let runs = try store.listRuns(sessionID: "s1")
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].run.id, "run-2")  // t0 is earlier
        XCTAssertEqual(runs[1].run.id, "run-1")  // t1 is later
    }

    func testListRunsEmptyForUnknownSession() throws {
        let runs = try store.listRuns(sessionID: "unknown")
        XCTAssertTrue(runs.isEmpty)
    }

    // MARK: - Delete

    func testDeleteRemovesMetadata() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try store.save(RunMetadata(run: run, sessionID: "s1"))

        XCTAssertTrue(store.exists(runID: "run-1"))

        try store.delete(runID: "run-1")

        XCTAssertFalse(store.exists(runID: "run-1"))
        XCTAssertNil(try store.load(runID: "run-1"))
    }

    func testDeleteNonexistentDoesNotThrow() {
        XCTAssertNoThrow(try store.delete(runID: "nonexistent"))
    }

    // MARK: - Exists

    func testExistsReturnsTrueForSavedRun() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try store.save(RunMetadata(run: run, sessionID: "s1"))

        XCTAssertTrue(store.exists(runID: "run-1"))
        XCTAssertFalse(store.exists(runID: "run-2"))
    }

    // MARK: - Overwrite

    func testSaveOverwritesExistingMetadata() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "v1")
        try store.save(RunMetadata(run: run, sessionID: "s1"))

        let updatedRun = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "v2")
        try store.save(RunMetadata(run: updatedRun, sessionID: "s1", tags: ["version": "2"]))

        let loaded = try store.load(runID: "run-1")
        XCTAssertEqual(loaded?.run.input, "v2")
        XCTAssertEqual(loaded?.tags["version"], "2")
    }
}

// MARK: - FileRunMetadataStore Tests

final class FileRunMetadataStoreTests: XCTestCase {
    private var store: FileRunMetadataStore!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunMetadataStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = FileRunMetadataStore(baseDirectory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        store = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Save / Load Round-Trip

    func testSaveAndLoadRoundTrip() throws {
        let run = AgentRun(
            id: "run-1",
            sessionID: "session-1",
            runtime: .claudeCode,
            input: "Fix the bug",
            tracePath: "/tmp/trace.jsonl",
            resultSummary: "Done"
        )
        let metadata = RunMetadata(
            run: run,
            sessionID: "session-1",
            tracePath: "/tmp/trace.jsonl",
            tags: ["priority": "high", "source": "ios"]
        )

        try store.save(metadata)

        let loaded = try store.load(runID: "run-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.run.id, "run-1")
        XCTAssertEqual(loaded?.run.sessionID, "session-1")
        XCTAssertEqual(loaded?.run.runtime, .claudeCode)
        XCTAssertEqual(loaded?.run.input, "Fix the bug")
        XCTAssertEqual(loaded?.run.status, .created)  // default status
        XCTAssertEqual(loaded?.sessionID, "session-1")
        XCTAssertEqual(loaded?.tracePath, "/tmp/trace.jsonl")
        XCTAssertEqual(loaded?.tags["priority"], "high")
        XCTAssertEqual(loaded?.tags["source"], "ios")
    }

    func testSaveCreatesDirectoryStructure() throws {
        let run = AgentRun(id: "run-abc", sessionID: "s1", runtime: .codex)
        try store.save(RunMetadata(run: run, sessionID: "s1"))

        let expectedDir = tempDirectory.appendingPathComponent("run-abc")
        let expectedFile = expectedDir.appendingPathComponent("metadata.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile.path))
    }

    func testSaveIsAtomic() throws {
        // Save should not leave partial files on success
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try store.save(RunMetadata(run: run, sessionID: "s1"))

        let runDir = tempDirectory.appendingPathComponent("run-1")
        let contents = try FileManager.default.contentsOfDirectory(atPath: runDir.path)
        XCTAssertEqual(contents, ["metadata.json"])  // no .tmp left behind
    }

    // MARK: - Update

    func testUpdateModifiesExistingMetadata() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "original")
        try store.save(RunMetadata(run: run, sessionID: "s1"))

        try store.update(runID: "run-1") { meta in
            meta = RunMetadata(
                run: meta.run,
                sessionID: meta.sessionID,
                tags: ["updated": "true"]
            )
        }

        let loaded = try store.load(runID: "run-1")
        XCTAssertEqual(loaded?.tags["updated"], "true")
        XCTAssertEqual(loaded?.run.input, "original")  // unchanged
    }

    // MARK: - List

    func testListRunsFiltersBySession() throws {
        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        let run2 = AgentRun(id: "run-2", sessionID: "s1", runtime: .codex)
        let run3 = AgentRun(id: "run-3", sessionID: "s2", runtime: .codex)

        try store.save(RunMetadata(run: run1, sessionID: "s1"))
        try store.save(RunMetadata(run: run2, sessionID: "s1"))
        try store.save(RunMetadata(run: run3, sessionID: "s2"))

        let s1Runs = try store.listRuns(sessionID: "s1")
        XCTAssertEqual(s1Runs.count, 2)

        let s2Runs = try store.listRuns(sessionID: "s2")
        XCTAssertEqual(s2Runs.count, 1)
    }

    func testListRunsEmptyForNoSessions() throws {
        let runs = try store.listRuns(sessionID: "s1")
        XCTAssertTrue(runs.isEmpty)
    }

    // MARK: - Delete

    func testDeleteRemovesDirectory() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try store.save(RunMetadata(run: run, sessionID: "s1"))

        let runDir = tempDirectory.appendingPathComponent("run-1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: runDir.path))

        try store.delete(runID: "run-1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: runDir.path))
    }

    // MARK: - Exists

    func testExistsAfterSave() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        XCTAssertFalse(store.exists(runID: "run-1"))

        try store.save(RunMetadata(run: run, sessionID: "s1"))
        XCTAssertTrue(store.exists(runID: "run-1"))
    }

    // MARK: - Error Handling

    func testLoadReturnsNilForMissingFile() throws {
        let loaded = try store.load(runID: "nonexistent")
        XCTAssertNil(loaded)
    }

    func testUpdateThrowsForMissingRun() {
        XCTAssertThrowsError(try store.update(runID: "nonexistent") { _ in })
    }
}
