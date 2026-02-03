# Implementation Plan: AMImport MusicKit-Only Migration

**Date:** 2026-02-03
**Design Doc:** Approved scope in chat (2026-02-03): MusicKit-only, library-first + catalog fallback, previews in Resolve, playlist + enqueue via MusicKit, auto-play, skip unavailable tracks.
**Estimated Tasks:** 20

## Overview
Replace AppleScript/Automation integration with MusicKit end-to-end for matching and export, while preserving AMImport’s existing import/resolve/export flow. Ship this incrementally with test-first slices and verifiable checkpoints.

## Tasks

### Task 1: Create a feature branch and capture baseline build state
**File:** `N/A`
**Time:** ~3 minutes

**Steps:**
1. Create branch `codex/musickit-only-migration`.
2. Run current build to ensure a known baseline.

**Code:**
```bash
git checkout -b codex/musickit-only-migration
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AMImport.xcodeproj -scheme AMImport -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

**Verify:**
```bash
git status --short
```

**Commit:** `chore: start musickit-only migration branch`

---

### Task 2: Add domain IDs for MusicKit-backed matching/export
**File:** `Sources/AMImport/Features/Import/ImportSessionViewModel.swift`
**Time:** ~5 minutes

**Steps:**
1. Extend `MatchDecisionSnapshot` with `catalogSongID: String?` and `librarySongID: String?`.
2. Keep backward compatibility by defaulting to `nil` where needed.

**Code:**
```swift
struct MatchDecisionSnapshot: Codable, Equatable {
    let rowID: String
    let status: MatchStatus
    let selectedTrackID: String?
    let catalogSongID: String?
    let librarySongID: String?
    let candidateTrackIDs: [String]
    let confidence: Double
    let rationale: String
}
```

**Verify:**
```bash
swift build
```

**Commit:** `feat: add catalog and library ids to match snapshots`

---

### Task 3: Add regression tests for snapshot encoding with new IDs
**File:** `Tests/AMImportTests/Features/ImportToExportFlowTests.swift`
**Time:** ~5 minutes

**Steps:**
1. Add a test that creates `MatchDecisionSnapshot` with both IDs.
2. Encode/decode and assert values round-trip.

**Code:**
```swift
func test_matchSnapshot_roundTripsCatalogAndLibraryIDs() throws {
    let snapshot = MatchDecisionSnapshot(
        rowID: "row-1",
        status: .autoMatched,
        selectedTrackID: "sel-1",
        catalogSongID: "cat-1",
        librarySongID: "lib-1",
        candidateTrackIDs: ["sel-1"],
        confidence: 0.98,
        rationale: "exact"
    )
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(MatchDecisionSnapshot.self, from: data)
    XCTAssertEqual(decoded.catalogSongID, "cat-1")
    XCTAssertEqual(decoded.librarySongID, "lib-1")
}
```

**Verify:**
```bash
swift test --filter ImportToExportFlowTests
```

**Commit:** `test: cover snapshot id serialization`

---

### Task 4: Introduce MusicKit search/result abstractions
**File:** `Sources/AMImport/Services/MusicKitClient.swift` (new)
**Time:** ~5 minutes

**Steps:**
1. Create protocol `MusicCatalogSearching` with library and catalog search methods.
2. Define `ResolvedSong` DTO containing IDs + preview metadata.

**Code:**
```swift
struct ResolvedSong: Equatable {
    let catalogSongID: String?
    let librarySongID: String?
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let durationSeconds: Int?
}

protocol MusicCatalogSearching {
    @MainActor
    func searchLibrary(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong]
    @MainActor
    func searchCatalog(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong]
}
```

**Verify:**
```bash
swift build
```

**Commit:** `feat: add musickit search abstractions`

---

### Task 5: Add stubbed MusicKit client tests (red first)
**File:** `Tests/AMImportTests/Services/MusicKitClientTests.swift` (new)
**Time:** ~5 minutes

**Steps:**
1. Add tests for empty query handling and deterministic mapping.
2. Use a fake provider to avoid network in unit tests.

**Code:**
```swift
func test_searchLibrary_emptyTitle_returnsEmpty() async throws {
    let client = FakeMusicCatalogSearcher()
    let songs = try await client.searchLibrary(title: "", artist: "", album: nil, limit: 5)
    XCTAssertTrue(songs.isEmpty)
}
```

**Verify:**
```bash
swift test --filter MusicKitClientTests
```

**Commit:** `test: add musickit client baseline tests`

---

### Task 6: Implement concrete MusicKit client
**File:** `Sources/AMImport/Services/MusicKitClient.swift`
**Time:** ~5 minutes

**Steps:**
1. Add `MusicKitClient` implementation using MusicKit requests.
2. Map library and catalog songs into `ResolvedSong`.
3. Guard against empty terms and cap limits.

**Code:**
```swift
final class MusicKitClient: MusicCatalogSearching {
    @MainActor
    func searchLibrary(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong] {
        // MusicLibraryRequest<Song> + filtering
    }

    @MainActor
    func searchCatalog(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong] {
        // MusicCatalogSearchRequest with fallback query strings
    }
}
```

**Verify:**
```bash
swift build
```

**Commit:** `feat: implement musickit library and catalog search client`

---

### Task 7: Add resolver service for library-first then catalog-fallback
**File:** `Sources/AMImport/Services/TrackResolutionService.swift` (new)
**Time:** ~5 minutes

**Steps:**
1. Add `TrackResolving` protocol.
2. Implement resolver that searches library first, then catalog if unresolved/low-confidence.
3. Return ranked candidates + selected item.

**Code:**
```swift
protocol TrackResolving {
    @MainActor
    func resolve(row: ImportTrackRow, options: MatchingOptions) async throws -> MatchDecisionSnapshot
}
```

**Verify:**
```bash
swift build
```

**Commit:** `feat: add library-first catalog-fallback resolver`

---

### Task 8: Unit test fallback behavior
**File:** `Tests/AMImportTests/Services/TrackResolutionServiceTests.swift` (new)
**Time:** ~5 minutes

**Steps:**
1. Add test: no library hit -> catalog match selected.
2. Add test: good library hit -> catalog not used.

**Code:**
```swift
func test_resolver_usesCatalogFallbackWhenLibraryMisses() async throws {
    // fake searcher returns empty library + one catalog candidate
    // assert selected candidate has catalogSongID
}
```

**Verify:**
```bash
swift test --filter TrackResolutionServiceTests
```

**Commit:** `test: verify library-first and catalog-fallback resolution`

---

### Task 9: Wire import flow to async resolver service
**File:** `Sources/AMImport/Features/Import/ImportSessionViewModel.swift`
**Time:** ~5 minutes

**Steps:**
1. Inject `TrackResolving` into `ImportSessionViewModel`.
2. Replace in-memory snapshot matching loop with async resolver calls per row.
3. Fill `catalogSongID`/`librarySongID` in snapshots.

**Code:**
```swift
for (index, row) in rows.enumerated() {
    let snapshot = try await resolver.resolve(row: row, options: options)
    snapshots.append(snapshot)
    state = .matching(progress: index + 1, total: rows.count)
}
```

**Verify:**
```bash
swift test --filter ImportToExportFlowTests
```

**Commit:** `feat: use async musickit resolver in import flow`

---

### Task 10: Remove AppleScript library provider from runtime wiring
**File:** `Sources/AMImport/App/RootView.swift`
**Time:** ~5 minutes

**Steps:**
1. Replace `MusicAppLibraryProvider` wiring with `MusicKitClient + TrackResolutionService`.
2. Delete provider + AppleScript-specific errors from this file.

**Code:**
```swift
@StateObject private var importViewModel = ImportSessionViewModel(
    authorizer: MusicAuthorizationService(),
    resolver: TrackResolutionService(searcher: MusicKitClient())
)
```

**Verify:**
```bash
swift build
```

**Commit:** `refactor: remove applescript library dependency from root wiring`

---

### Task 11: Add candidate preview model for Resolve
**File:** `Sources/AMImport/Features/Resolve/ResolveMatchesView.swift`
**Time:** ~5 minutes

**Steps:**
1. Extend candidate rendering to include artwork URL, album, duration.
2. Show compact preview row per candidate.

**Code:**
```swift
HStack {
    AsyncImage(url: candidate.artworkURL) { image in image.resizable() } placeholder: { Color.gray }
        .frame(width: 36, height: 36)
    VStack(alignment: .leading) {
        Text(candidate.title)
        Text("\(candidate.artist) • \(candidate.album ?? "-")").font(.caption)
    }
    Spacer()
    Text(formatDuration(candidate.durationSeconds)).font(.caption.monospacedDigit())
}
```

**Verify:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AMImport.xcodeproj -scheme AMImport -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

**Commit:** `feat: add resolve candidate previews`

---

### Task 12: Add UI test/logic test coverage for resolve preview data mapping
**File:** `Tests/AMImportTests/Features/ResolveMatchesViewModelTests.swift` (new or existing test file)
**Time:** ~5 minutes

**Steps:**
1. Add test ensuring preview fields are populated from resolver candidates.
2. Assert fallback placeholders for missing artwork/album/duration.

**Code:**
```swift
XCTAssertEqual(previewRows.first?.subtitle, "Artist • Album")
XCTAssertEqual(previewRows.first?.durationLabel, "3:42")
```

**Verify:**
```bash
swift test --filter Resolve
```

**Commit:** `test: validate resolve preview mapping`

---

### Task 13: Introduce MusicKit exporter abstraction
**File:** `Sources/AMImport/Export/MusicKitExporter.swift` (new)
**Time:** ~5 minutes

**Steps:**
1. Create `MusicKitExporting` with `createPlaylist` and `enqueue` methods.
2. Operate primarily on `catalogSongID` values (library ID optional).

**Code:**
```swift
protocol MusicKitExporting {
    @MainActor
    func createPlaylist(name: String, catalogSongIDs: [String]) async throws
    @MainActor
    func enqueueAndPlay(catalogSongIDs: [String]) async throws -> ExportExecutionSummary
}
```

**Verify:**
```bash
swift build
```

**Commit:** `feat: add musickit exporter abstraction`

---

### Task 14: Implement playlist creation via MusicKit
**File:** `Sources/AMImport/Export/MusicKitExporter.swift`
**Time:** ~5 minutes

**Steps:**
1. Implement playlist create/fill call path with user library APIs.
2. Return per-track success/skip info.

**Code:**
```swift
// Create user playlist then append playable song ids.
// Build ExportExecutionSummary(requested:..., added:..., skipped:...)
```

**Verify:**
```bash
swift build
```

**Commit:** `feat: implement musickit playlist export`

---

### Task 15: Implement enqueue into system Music app + autoplay
**File:** `Sources/AMImport/Export/MusicKitExporter.swift`
**Time:** ~5 minutes

**Steps:**
1. Build `SystemMusicPlayer` queue from resolved IDs.
2. Skip unavailable storefront items and continue.
3. Start playback when at least one track was queued.

**Code:**
```swift
try await SystemMusicPlayer.shared.queue.insert(items, position: .tail)
if queuedCount > 0 { try await SystemMusicPlayer.shared.play() }
```

**Verify:**
```bash
swift build
```

**Commit:** `feat: implement musickit enqueue with autoplay and skip policy`

---

### Task 16: Switch ExportViewModel from AppleScript bridge to MusicKit exporter
**File:** `Sources/AMImport/Features/Export/ExportView.swift`
**Time:** ~5 minutes

**Steps:**
1. Replace `MusicAppControlling` dependency with `MusicKitExporting`.
2. Use `catalogSongID` list from selected decisions.
3. Show summary message with requested/succeeded/skipped counts.

**Code:**
```swift
statusMessage = "Enqueued \(summary.succeeded)/\(summary.requested). Skipped \(summary.skipped)."
```

**Verify:**
```bash
swift test --filter ImportToExportFlowTests
```

**Commit:** `refactor: route export flow through musickit exporter`

---

### Task 17: Remove AppleScript bridge from active app path
**File:** `Sources/AMImport/Export/MusicAppBridge.swift` and `Sources/AMImport/App/RootView.swift`
**Time:** ~5 minutes

**Steps:**
1. Remove runtime wiring to `MusicAppBridge`.
2. Either delete bridge file or leave deprecated with no references.

**Code:**
```swift
// RootView export VM uses MusicKitExporter(), not MusicAppBridge().
```

**Verify:**
```bash
rg -n "MusicAppBridge\(|NSAppleScript|Apple events" Sources
```

**Commit:** `refactor: remove applescript export runtime path`

---

### Task 18: Clean permission surface and settings UX
**File:** `AMImport/Support/Info.plist`, `Sources/AMImport/Features/Import/ImportView.swift`, `Sources/AMImport/Features/Import/ImportSessionViewModel.swift`
**Time:** ~5 minutes

**Steps:**
1. Remove `NSAppleEventsUsageDescription`.
2. Remove Automation-specific error messages/buttons.
3. Keep Media & Apple Music guidance only.

**Code:**
```xml
<!-- remove NSAppleEventsUsageDescription -->
```

**Verify:**
```bash
plutil -p AMImport/Support/Info.plist
```

**Commit:** `chore: remove automation permission surface`

---

### Task 19: Add full integration test for skip-and-continue export
**File:** `Tests/AMImportTests/Features/ImportToExportFlowTests.swift`
**Time:** ~5 minutes

**Steps:**
1. Add test with mixed available/unavailable IDs.
2. Assert enqueue summary: `requested != succeeded`, `skipped > 0`, no hard fail.

**Code:**
```swift
XCTAssertEqual(summary.requested, 3)
XCTAssertEqual(summary.succeeded, 2)
XCTAssertEqual(summary.skipped, 1)
```

**Verify:**
```bash
swift test --filter ImportToExportFlowTests
```

**Commit:** `test: enforce skip-and-continue enqueue behavior`

---

### Task 20: Final project verification and docs refresh
**File:** `README.md`
**Time:** ~5 minutes

**Steps:**
1. Update README permission section to MusicKit-only.
2. Document fallback matching behavior and enqueue semantics.
3. Run final build/test verification.

**Code:**
```markdown
Permissions: Media & Apple Music only.
Matching: library-first, catalog fallback.
Enqueue: system Music queue, autoplay, unavailable tracks skipped.
```

**Verify:**
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AMImport.xcodeproj -scheme AMImport -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

**Commit:** `docs: update musickit-only behavior and permissions`

---

## Progress Tracker

- [x] Task 1: Create branch and baseline build
- [x] Task 2: Add catalog/library IDs to snapshots
- [x] Task 3: Add snapshot serialization regression test
- [x] Task 4: Add MusicKit search abstractions
- [x] Task 5: Add MusicKit client tests
- [x] Task 6: Implement MusicKit client
- [x] Task 7: Add track resolution service
- [x] Task 8: Add resolver fallback tests
- [ ] Task 9: Wire import flow to async resolver
- [ ] Task 10: Remove AppleScript library provider wiring
- [ ] Task 11: Add resolve candidate previews
- [ ] Task 12: Add preview mapping tests
- [ ] Task 13: Add MusicKit exporter abstraction
- [ ] Task 14: Implement MusicKit playlist export
- [ ] Task 15: Implement MusicKit enqueue + autoplay
- [ ] Task 16: Switch export VM wiring to MusicKit
- [ ] Task 17: Remove AppleScript bridge runtime path
- [ ] Task 18: Remove Automation permission UX
- [ ] Task 19: Add skip-and-continue integration test
- [ ] Task 20: Final docs + verification

## Notes
- Execute in order; each task is intentionally small and reversible.
- Prefer test-first for behavior changes (Tasks 3, 5, 8, 12, 19).
- If MusicKit API surface differs by SDK minor version, keep adapters in `MusicKitClient`/`MusicKitExporter` so UI/view models stay stable.
- If system queue APIs are partially unavailable, keep autoplay guarded and report actionable summary in UI.
