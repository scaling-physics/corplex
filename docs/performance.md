# Performance

Measured on a library of 1,500 papers, 3,000 notes (3-6 paragraphs, 1 in 8
with a drawing, 1 in 10 with a table, citations), 20,000 highlights, 25
folders, 40 tags, 8 projects, and generated PDFs (one of 300 pages, three of
30). Seeded by `test/perf/seed_library.dart`.

## How to measure

- **Queries and indexes (any machine):** `flutter test test/perf/query_perf_test.dart`
  prints `PERF <name> <ms>` lines. It asserts only generous ceilings. The
  numbers below are an M-series Mac, debug VM, file-backed SQLite.
  `PERF_SMALL=1` runs a tenth of the data.
- **On a device:** `integration_test/perf_test.dart` seeds the same library
  into a temporary database, runs the real app on it and prints `PERFDEV`
  lines (startup, frame build/raster times while scrolling, PDF open, PDF
  indexing, search as you type).
  `flutter test` has no `--profile`, so use
  `flutter drive --driver=integration_test/perf_driver.dart --target=integration_test/perf_test.dart -d emulator-5554 --profile`
  (add `--dart-define=PERF_ONLY=startup|pdf|search` for one group).
  A Mac window that is not on screen gets no frames, so on macOS only the
  PDF group runs unattended; the UI groups need a visible window.

## Results

### Queries (Mac, ms)

| What | Before | After |
|---|---|---|
| Search index, first build (24,500 rows) | 79,672 | 1,253 |
| Search refresh, nothing changed | 85 | 0.1 |
| Search refresh after editing one note | 96 | 12 |
| Search query "neur" (incl. refresh) | 104 | 34 |
| All highlights list | 171 | 77 |
| 100 x "highlights of one paper" | 109 | 7 |
| Trash 20 papers (13 highlights each) | 114 | 46 |
| Previews of 40 notes scrolled back to | ~4 | 0.4 |
| Notes list (all, pinned first) | 40 | 37 (unchanged) |
| Notes list per folder / tag / project | 5 / 4 / 1 | 3 / 4 / 1 |
| Library list, filtered list | 9, 3 | 7, 4 |
| Sidebar counts (folders / projects) | 3 / 1 | 2 / 1 |
| Attachments browser | 21 | 19 (see below) |
| `pendingChanges()`, one edit with triggers | 0.6, 6.8 | 0.3, 1.3 |
| Trash a 227 KB note | 21 | 6 |

Most of these queries were never slow at this size on a Mac; the two that
were (the search index, per-paper highlights) were quadratic or full scans.
The gaps grow on a phone: SQLite runs in a background isolate, so every
statement costs a message round trip.

### macOS (profile build, PDF group only)

| What | Before | After |
|---|---|---|
| 300-page PDF: open / text of page 151 / render | 52 / 1.2 / 3.0 ms | 52 / 2.0 / 4.5 ms (noise) |
| PDF full-text index, 1,470 pages | 4.64 ms/page | 4.20 ms/page |

On a Mac the indexer is bound by pdfium text extraction, so batching the
writes barely shows. Startup and scrolling were not measured on macOS: the
window was not on screen during this session.

### On the Android emulator (profile build; emulator speed varies run to run by up to 5x, so compare within one table only)

| What | Before | After |
|---|---|---|
| Search index, first build | 188,000 - 518,000 ms | 11,000 - 14,500 ms |
| Search refresh, nothing changed | 540 - 990 ms | 0.2 - 3.6 ms |
| `index.search("neural cortex")` | 1,121 ms | 152 - 188 ms |
| Type 13 characters until results are on screen | 2.8 s | 2.3 s (1.6 s of it is the typing) |
| PDF full-text index, 1,470 pages | 53-61 ms/page | 29-32 ms/page |
| 300-page PDF: open / page text / render | 80-460 / 2-12 / 4-32 ms | same (pdfrx, untouched) |
| Startup to first note card | 0.3 - 2.0 s | 0.08 - 0.4 s |
| Scroll Notes list (build p50 / p99) | 1.5 / 12.9 ms | 1.4 / 11.6 ms |
| Scroll Library list (build p50 / p99) | 2.0 / 7.5 ms | 1.8 / 8.0 ms |

List scrolling is raster-bound on the emulator (raster p50 about 16 ms in
every run, before and after); the emulator's software GPU says little about
a real device, so this pass left the paint side alone. Build time was
already small. Verify on a real iPad/phone.

Not measured: macOS UI (no visible window in this session), a real iOS
device, the PDF viewer's own scroll and zoom.

## What changed and why

- **Search index** (`search/search_index.dart`). `refresh()` read every
  note's full body from SQLite on each search, then deleted each stale row
  with a scan of the FTS table (`DELETE ... WHERE ref = ?` is a full scan
  of unindexed columns): a first build was quadratic (80 s on a Mac, 8 min
  on the emulator). Now a plain `search_state` table (kind, ref, stamp, FTS
  rowid) records what is indexed; SQLite itself finds the rows whose stamp
  moved, only those are re-read (in chunks of 40, yielding to the UI) and
  rewritten by rowid, in one batch message each. A dirty flag set by drift's
  `tableUpdates` (notes, papers, highlights) makes a search with no edits in
  between skip even the comparison. Concurrent callers share a pass. The
  state table is derived and local like the index: if `search_index` is
  missing (backup restore drops it) or `search_state` is (older install),
  the index is rebuilt. Hit bodies are no longer returned just to test
  emptiness.
- **Note text extraction** decodes a note's Quill JSON once instead of
  twice (`noteSearchText`), and `notePlainTextPreview` keeps a bounded LRU
  (600 entries, 4M characters) keyed by the body, so list rows that scroll
  back in, and every rebuild after a sync, don't re-decode.
- **PDF text index** (`search/pdf_text_index.dart`). A search used to start
  a full pass (stat every PDF, one state query per paper, an FTS scan to
  forget removed papers) on every query; now it starts one only when some
  paper isn't fully indexed (`kickIfIncomplete`), states come from one
  query, the FTS delete runs only when a paper actually lost its PDF, and
  pages are written eight at a time in one batch with the progress marker.
  The startup pass waits four seconds so the first screen's queries and
  frames come first.
- **Local indexes** (`AppDatabase.beforeOpen`, `performanceIndexStatements`;
  `CREATE INDEX IF NOT EXISTS`, no schema bump, not synced, harmless in
  backups): notes(folder_id), notes(pinned, updated_at), papers(created_at),
  the second column of every join table (note_tags.tag_id,
  project_notes.note_id, project_papers.paper_id,
  note_paper_refs.paper_id), attachments(note_id | paper_id),
  highlights(paper_id, page_number), annotations(paper_id, page_number),
  note_versions(note_id, created_at), note_comments(note_id),
  matrix_cells(paper_id). They also remove a table scan from every
  `ON DELETE CASCADE`. `test/data/performance_indexes_test.dart` checks they
  exist, are used and leave the sync triggers and tombstones alone.
- **All highlights** loads papers and highlights separately and joins them
  in Dart (a SQL join repeated each paper, abstract included, on 20,000
  rows) and reloads on a table-update signal.
- **Attachments browser** selects the note title and the first 120
  characters of its body (enough for the locked-key check) instead of whole
  note and paper rows.
- **Sidebar counts** (`folderNoteCountsProvider`, `projectNoteCountsProvider`)
  `.distinct(mapEquals)`: a note save re-runs the count but no longer
  rebuilds the sidebar when the counts are the same.
- **Covers** (`library/paper_cover.dart`): the provider is `autoDispose`
  (it kept every cover ever scrolled past, 360 px PNGs, for the whole
  session) with a 120-entry in-memory LRU in front of the disk cache, so
  scrolling back doesn't flash; renders for covers scrolled away before
  their turn in the (still one-at-a-time) queue are skipped; the image is
  decoded at the size shown (`cacheWidth`) instead of 360 px for a 44 px
  thumbnail.

## Found, not fixed

- **The Notes list holds every note's full body.** `visibleNotesProvider`
  selects whole rows, and any note save re-runs it (3,000 notes: 37 ms and
  several MB on a Mac; about 40 ms extra per save on the emulator while the
  list is alive, e.g. under the editor on a phone or beside it on an iPad).
  A list projection without `content` would need a stored preview column
  (schema change) or a second query for the visible rows.
- **Indexing `noteSearchText` runs on the main isolate** (chunked, yielding;
  about 0.1 ms/note on a Mac, 3-5 ms on the emulator). Moving it to
  `Isolate.run` is possible but isolates don't run under the fake clock in
  tests.
- **Library cards read the retraction cache per DOI** (`RetractionMarker`,
  one small file read per visible card, autoDispose, so again on scroll
  back). Cheap, but a single in-memory set of retracted DOIs would avoid it.
- **`SearchIndex.search`** still ranks every prefix match (bm25) and builds
  snippets for 20 per kind: 20-35 ms on a Mac, 120-240 ms on the emulator.
  A shorter prefix ("ne") is the worst case.
- Raster cost of the lists on a real device; the 300-page PDF viewer's own
  scrolling.
