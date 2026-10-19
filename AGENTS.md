# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## Project

Corplex is a notes and literature review app for iPadOS, iOS, Android and
macOS, built from a single Flutter codebase. It combines rich-text note taking, PDF import
and annotation, and citation management, so a researcher can read a paper,
annotate it, pull highlights into notes, and generate citations without
leaving the app.

## Design principles

The human doing academic work is the center of this app — every design
choice is judged by whether it makes reading, thinking, and writing feel
easier and more seamless. Concretely:

- **No distractions.** Default screens stay minimal — no chrome, badges,
  or prompts that aren't part of the reading/writing/annotating task at
  hand. Prefer hiding UI until needed over adding settings to turn it off.
- **Fast, mixed-format capture.** Creating a quick note must be one or two
  taps away, and a single note can freely mix text, images, and pen/stylus
  input (especially on iPad) in the same flow — the user should never have
  to pick a "note type" up front or switch tools to mix formats.
- **Attachments live with the note/paper, not in a separate app.**
  Attaching a NotebookLM-style podcast, a source paper, or an image to a
  note or paper record should be as fast as capturing the note itself —
  a couple of taps, no exporting/importing round-trips through other apps.

When a feature adds a step, a mode switch, or visual noise to the core
read → annotate → note → cite loop, reconsider it before building it.

## Tech stack

- **Framework**: Flutter (Dart) — one codebase for iPadOS, iOS, Android and
  macOS (see "macOS app" below).
- **Data**: Offline-first. All data lives in a local on-device SQLite
  database via `drift` (chosen over raw `sqflite` for type-safe schema,
  compile-time query checking, and reactive `Stream` queries) and the app
  must be fully usable with no network connection. Tables live in
  `lib/data/tables/`, the database class in `lib/data/database.dart`.
  After changing a table, regenerate with: `dart run build_runner build`.
  `lib/data/database.g.dart` is generated and committed to the repo so the
  app builds without an extra codegen step.
- **Sync**: Cross-device sync is a planned feature layered on top of the local
  DB, not a hard dependency of core functionality. Do not build features that
  assume a live backend connection. Decided approach: **hosted Supabase**
  (Postgres + Auth) with **email/password** auth and a small hand-written,
  last-write-wins sync engine over the existing drift database. PowerSync
  was considered and dropped: it wants to own the local SQLite database,
  which fights drift. See the Sync engine status entry below.
- **State management**: Riverpod (`flutter_riverpod`), chosen for its
  natural fit with drift's `Stream`-based reactive queries. `AppDatabase`
  is exposed via `databaseProvider` (`lib/data/database_provider.dart`);
  feature-specific providers live next to their feature, e.g.
  `lib/features/notes/notes_providers.dart`. Root widget must stay wrapped
  in `ProviderScope` (see `lib/main.dart`).

## Core v1 features

v1 is the smallest release that completes the read → annotate → note → cite
loop *and* cannot lose a user's data. Items marked **(built)** exist today;
the rest are the remaining v1 work, in priority order.

1. **Rich-text notes (built)** — folders/tags, Quill rich-text editor,
   links between notes (`[[`) with "Linked from" backlinks, Markdown
   export via the share sheet.
2. **PDF import & annotation (built)** — text-selection highlights with
   comments, "Quote to note" (quote + tappable page link), a per-paper
   Highlights list, resume at last-read page; freeform ink as a second
   mode.
3. **Citation management (built)** — APA/MLA/BibTeX with structured
   authors, DOI/arXiv lookup (Crossref/arXiv; optional online), identifier
   extraction from imported PDFs, duplicate detection, BibTeX
   import/export.
4. **Paper & note attachments (built)** — audio (e.g. NotebookLM audio
   overviews) with an in-app player and tap-to-seek timestamps in notes,
   podcast links, images, arbitrary files.
5. **Library tab & search (built)** — searchable Library, reading status,
   and an app-wide full-text search (SQLite FTS5) over notes, papers and
   highlights.
6. **Projects/collections (built)** — a named group of papers and notes
   (one per literature review or thesis chapter); invisible until one is
   created.
7. **Capture from other apps (built; iOS untested on a device)** —
   share-sheet/Open-with import for PDFs, audio, DOIs/arXiv links, links and
   text. iOS uses the `ShareExtension` target — see v1.6.
8. **Data safety (built)** — trash with undo (swipe a card, or ⋮ → Move
   to trash), full backup/restore as a zip, and data-preserving
   migrations (the destructive v3 migration must not be repeated).
9. **Cross-device sync (built; verified on local and hosted Supabase)** —
   Supabase + drift, last-write-wins. Metadata and files (PDFs, images,
   audio) sync; see the Sync engine entry under Status. Needs a real
   Supabase project before it can run.

### Adding a new synced table

Every table that syncs needs: an `updatedAt` column, an entry in
`syncTables` (`lib/data/sync_schema.dart`, parents before children), and a
matching table in a new Supabase migration under `supabase/migrations/`
(user_id, deleted_at, synced_at, RLS, `sync_guard` trigger — copy an
existing table). Local-only columns (file paths) stay out of the spec.

### Open decisions (resolve before implementing)

- **Clock skew** (decided: accepted): last-write-wins trusts each
  device's clock. A badly wrong clock can lose or win edits it shouldn't;
  we don't compensate.
- **Handwriting to text** (decided: later): sketches stay drawings.
  iPadOS Scribble works in plain `TextField`s (note/paper titles) for
  free, but not inside the Quill body; converting ink to text would need
  on-device recognition (e.g. ML Kit Digital Ink).

## TODO

Small, specific items to pick up next (remove when done):

(Nothing queued.)

## Later releases

Ordered roughly by value to the core loop. None of these should add UI to
the default screens until the user opts in by using the feature.

### v1.1 — Literature review depth (built, except as noted)
- **Citations**: every paper can get a stable `citekey` (`Papers.citekey`,
  synced; `ensureCitekey` in `features/library/citations.dart` assigns
  `vaswani2017`, `…a` on collision, once, never changed). In a note, type
  `[@`, `/` → "Cite a paper", or ⋮ → "Cite a paper". Citations are
  *stored* as plain-text `[@key]` (also `[@a; @b]`) but the editor shows
  them as chips reading "(Vaswani et al., 2017)" (`citation_embed.dart`):
  `citationsToEmbeds` turns markers into inline `cite` embeds on load and
  `citationEmbedsToText` turns them back on save, so export, bibliography,
  search, sync and merge only ever see text. The editor's `_stored()` /
  `_editable()` are the only crossing points; anything reading the live
  controller must use `textWithCitations` (as `insertBibliography`
  does), since a chip is one `\uFFFC` in `toPlainText()`. Unknown keys
  show as written, in the error tone; tap a chip to open its paper.
  ⋮ → "Add bibliography" writes/rewrites a "References" H2 at
  the end in a chosen style (`note_bibliography.dart`). Styles come from
  the CSL engine (v1.6), with the original hand-written formatters
  (`citation_formatter.dart`) as fallbacks and for BibTeX.
- **Synthesis matrix** (`features/projects/matrix*.dart`, tables
  `matrix_columns` / `matrix_cells`, schema v10): long-press a project chip
  → "Synthesis matrix". Papers × themes; tap a cell to write or pull a
  passage from that paper's highlights; copy/share as a Markdown table.
  Invisible until a column is added. Deleting a column cascades its cells.
- **Literature-note template**: note ⋮ → "Literature note template"
  (summary / method / findings / critique headings).
- **Import**: Library ⋮ → "Import references" reads BibTeX, RIS and CSL
  JSON (`reference_import.dart`, format sniffed from content), so Zotero,
  Mendeley and EndNote exports work.
- **Project bibliography**: project chip menu → "Bibliography".
- Highlight-to-quote blocks already existed ("Quote to note").
- Server side: `20261003000000_literature_review.sql` (papers.citekey,
  papers.rating, matrix tables). **Apply it before schema-v10 data syncs.**

### v1.2 — Writing output (built, except CSL)
- Note ⋮ → "Export" and project chip → "Export project" produce Markdown,
  Word (.docx) or PDF (`features/export/`). One intermediate `ExportDoc`
  (blocks + runs) feeds all three renderers, so `[@key]` citations become
  in-text citations and one reference list is appended exactly once (a
  hand-inserted "References" section is replaced, not doubled). A project
  exports its notes as chapters under one bibliography.
- DOCX is hand-written OOXML (headings, lists, quotes, bold/italic/strike;
  links as `text (url)`). PDF uses the `pdf` package with Roboto embedded
  from `assets/fonts/` (curly quotes and accents render), including the
  Italic and BoldItalic faces, so italics print as italics. Sketches
  export as "[Sketch]".
- CSL styles: done in v1.6 (a subset of CSL 1.0.2; see there).

### v1.3 — iPad & pen (built, except as noted)
- **Split view**: on wide windows (≥ 840 px) the paper screen shows "Read
  with a note" — PDF left, note right (`split_reader.dart`). It picks the
  most recent note linked to the paper or makes one. "Quote to note" in the
  reader goes straight into that open note through `NoteEditorHandle`
  (never via the database: the editor's autosave would overwrite it). Below
  the breakpoint it falls back to the plain reader; nothing extra shows on
  phones.
- **Pen**: hover ring that previews the mark (Apple Pencil on M2 iPads,
  Android styluses); the barrel button erases (S Pen); **Pencil
  double-tap** follows the iPadOS preference (`SceneDelegate.swift` →
  `corplex/pencil` channel → `pencil_taps.dart`; iOS build verified, the tap
  itself needs a real Pencil 2 to try). Android stylus uses the same
  `PointerDeviceKind.stylus` path as before.
- **Hardware keyboard**: Cmd/Ctrl+N new note, +O import PDF, +F search,
  +1/+2 tabs (HomeShell); Cmd/Ctrl+Z / +Shift+Z in the sketch editor.
- **Not done**: multiple windows (needs iPadOS scene support Flutter
  doesn't offer stably), drag and drop between apps (the usual plugin needs
  a Rust toolchain in the build), handwriting-to-text (decided: later).

### v1.4 — Reading comfort (built, except as noted)
- **Reading mode**: PDF viewer ⋮ → Paper / Sepia / Night page
  (`settings/appearance_settings.dart`). A `ColorFilter` over the page and
  the marks on it; Night inverts and rotates the hue back so highlights
  keep their color. Per-device (shared_preferences), not synced.
- **Contents**: PDF viewer ⋮ → Contents shows the PDF's own outline
  (`ContentsSheet`), tap to jump; says so if the PDF has none.
- **All highlights**: Library ⋮ → "All highlights" — every passage across
  papers, grouped by paper, searchable (quote, comment, paper title); tap
  opens the PDF at the page, long-press edits.
- **Ratings**: five stars beside the reading-status chips on the paper
  screen (tap the current rating to clear); `★★★★` shows on the Library
  card once rated. `Papers.rating`, synced.
- **App-wide dark mode**: the dark scheme already followed the system; the
  account sheet now has Auto / Light / Dark (per-device).
- **Accessibility**: a test renders both tabs at 2× text scale with no
  overflow. That is a smoke check, not a full Dynamic Type/VoiceOver audit.
- **Not done: localization.** All strings are still inline English; doing
  it means moving them to ARB files (`flutter gen-l10n`) and is a
  cross-cutting change best done as its own pass.

### v1.5 — Reading flow, overview & platform (built, except as noted)
- **Reading progress** (`reading_progress.dart`, schema v12):
  `Papers.pageCount` (synced; server file `20261004000000_page_count.sql`,
  **apply it before schema-v12 data syncs**) is set on import
  (`readPdfStart` opens the PDF once) and when the viewer is ready
  (`savePageCountIfChanged` writes only on change, so reopening a paper
  isn't a synced edit). A Library card shows a thin bar only for a
  started, unfinished paper with a known count.
- **Viewer navigation** (`viewer_navigation.dart`): a "3 / 24" pill or
  ⋮ → Page strip slides up a lazy thumbnail row (dots = highlight inks);
  ticks on the right edge mark highlights at (page−1+y)/pageCount
  (assumes equal page heights) and only the ticks take touches. **Focus
  mode** (tap bare page, or ⋮ → Focus) collapses the bars and, on phones
  only, goes `immersiveSticky`, restoring `edgeToEdge` on exit and
  dispose. `PdfViewerScreen.viewerBuilder` lets tests drive
  `onGeneralTap` without the PDF engine. Reflowed text: not possible with
  pdfrx; not done.
- **Note editor extras** (`note_stats.dart`, `paste_citation.dart`):
  ⋮ → "Typewriter scrolling" (per-device `AppearanceSettings.typewriter`;
  the page `ListView` scrolls, not Quill, so `_followCursor` measures the
  caret via `editorKey` and eases it to ~40% height, only on controller
  changes with a collapsed selection and focus). Long-press a citation
  chip, or hover a pointer 500 ms, for a card with the paper and its top
  highlights. ⋮ → "Word count" counts via `textWithCitations` (chips are
  citations, not words; sketches ignored). Pasting a whole DOI/arXiv id
  or link (one insert, `wholeIdentifier`) offers "Add this paper and cite
  it?" → `paperIdForIdentifier` (lookup + duplicate detection, no UI or
  navigation) → `ensureCitekey` → `insertCitation` at the pasted text.
- **Project page** (`projects/project_page.dart`): project chip
  long-press → "Open project" (first item): progress (papers done /
  total), papers with covers, notes, and Matrix / Bibliography / Export /
  Map actions; empty sections and pointless actions hidden. Pages pushed
  over home open items via `openNoteFromPage`/`openPaperFromPage`, which
  pop to home first when a detail pane exists.
- **Map** (`features/graph/`): Search → Map, or a project's Map.
  `buildGraph` joins note→note links (regex on stored content),
  `NotePaperRefs` and `[@key]` citations (by citekey); `layoutGraph` is a
  bounded, deterministic Fruchterman-Reingold over connected nodes only
  (runs on the main isolate after a frame — isolates don't run under the
  test clock; all-pairs repulsion, fine to ~500 nodes). Unconnected
  nodes are hidden until toggled. Nothing ticks after layout.
- **Revisit highlights** (`features/review/`): All highlights → Revisit.
  One at a time; Keep walks 1, 3, 7, 14, 30, 90 days, Skip asks again
  tomorrow, never-reviewed highlights are due a day after creation.
  Schedule is per-device in shared_preferences, never the DB. The
  `ReviewPrompt` line above the home tabs is invisible unless the user
  turned on "Remind me on the home screen" and something is due; × hides
  it for the day.
- **Shortcuts & home-screen widget** (`features/platform/`):
  `PlatformCoordinator` (inside `ShareCoordinator` in `app.dart`) handles
  app-icon shortcuts (New note, Import PDF) and widget taps, which reuse
  `corplex://` links (`new-note`, `paper/<id>?page=N`) through
  `openWidgetLink`. The default seams (`quickActionSourceProvider`,
  `homeWidgetBridgeProvider`) are inert no-ops because the plugins throw
  `MissingPluginException` under `flutter test`; `main()` installs the
  real ones — don't make the defaults real. The widget shows "Continue
  reading" (newest `reading` paper, else newest with a `lastPage`),
  republished on a 2 s debounce only when it changes. Android widget
  resources must be listed in `res/raw/keep.xml`. The iOS widget is the
  `CorplexWidget` extension (v1.6).
- **Pointer hover**: a mouse/trackpad lifts an `OpenCard` slightly
  (`OpenCard.hoverLift`); touch and pen don't.
- Untested on devices: the widget, shortcuts, thumbnails and the
  page-count hook (pdfium doesn't run under `flutter test`).

### v1.6 — Research gaps & capture (built; untested on devices)
- **Find in document** (`library/pdf_search.dart`): viewer search icon,
  ⋮ → Find, or Cmd/Ctrl+F (wins over the shell's app search because the
  viewer is a pushed route with its own `CallbackShortcuts`). "3 of 41",
  Enter/Shift+Enter, 250 ms debounce, wrap-around; opening leaves focus
  mode. `SearchMarks` paints matches via `pageOverlaysBuilder` only while
  open. `DocumentSearch` reads through the `PageTextSource` seam
  (`find(page, query)` → 0..1 rects); `PdfrxTextSource` is the text layer.
  Test hooks: `searchSourceBuilder`, `onSearchReveal`, `textProbe`.
- **Scanned PDFs / OCR** (`features/ocr/`, schema v13): `OcrEngine` is
  on-device — Apple Vision in `AppDelegate.swift`, ML Kit Latin in
  `OcrChannel.kt` (channel `corplex/ocr`). **No google_mlkit plugins**:
  iOS builds use Swift Package Manager and CocoaPods isn't installed. Text
  lives in local-only `ocr_pages`/`ocr_papers` (derived: not synced, not
  backed up). `readPdfStart` OCRs pages 1–2 only when both lack a text
  layer (`pageLacksTextLayer`), so identifier lookup works on scans;
  `OcrService` queues the rest page by page and resumes via
  `ocrStartupProvider` (read in `HomeShell`; inert with no scanned
  papers). In the viewer (`ocr_search.dart`, `ocr_selection.dart`): Find
  uses `OcrFallbackSource` (text layer first, OCR words where it has
  none; "+" while OCR runs); long-press-and-drag on a scanned page selects
  words → Highlight / Quote to note / Copy, creating ordinary `Highlights`
  rows (`createOcrHighlight`); ⋮ → "Recognise text" only when the page has
  no text layer and the paper isn't marked scanned; a quiet "Reading
  text… N%" line while it runs.
- **Export with highlights** (`library/annotated_pdf*.dart`): paper ⋮,
  only with a local PDF and marks. A hand-written PDF *incremental update*
  (not pdfium — pdfrx doesn't expose its annotation API, and this is
  testable): `/Highlight` (QuadPoints, colour, comment as `/Contents`,
  Multiply `/AP`) and `/Ink` annotations; classic xref tables, xref
  streams and object streams; `PageGeometry` handles CropBox and /Rotate;
  encrypted/damaged PDFs are refused. Verified with macOS PDFKit only.
- **References / Cited by** (`library/openalex.dart`,
  `citation_network_section.dart`): a collapsed row on papers with a DOI;
  OpenAlex is asked only when it's opened (https, no personal data, no
  `mailto`). `CitationCache`: one JSON per DOI in the cache folder,
  30-day freshness, stale copy used offline. In-library items open; others
  Add via `addPaperFromMetadata`. The Map draws dashed "cites" edges from
  cached reference lists only (`GraphData.citationEdges`).
- **Maths** (`notes/math_markers.dart`, `math_embed.dart`,
  `math_render.dart`): stored as plain text — inline `$x$`, display as a
  paragraph that is exactly `$$ … $$` — so search, preview, sync merge,
  Markdown and old app versions see the source. The editor shows `math` /
  `mathblock` embeds (flutter_math_fork); `mathToEmbeds`/`mathEmbedsToText`
  wrap the citation conversions in `_editable()`/`_stored()`. Pandoc rules
  (`findInlineMath`), so "$5 and $10" stays text. PDF export rasterises
  (`renderMathPng`, falls back to source); DOCX writes the source in
  Consolas (no OMML).
- **Voice notes** (`features/voice/`): `/` → Voice note or the attach
  sheet's "Record audio". `record` (AAC m4a) → podcast attachment +
  `▸ 0:00 Voice note` link + transcript. iOS transcribes the file on
  device (`SFSpeechURLRecognitionRequest`, `requiresOnDeviceRecognition`,
  `corplex/speech` channel in `SceneDelegate.swift`). Android has no
  on-device file transcription: Voice note is audio only, and `/` →
  "Dictate" (`speech_to_text`, live, no audio) is offered instead. Seams:
  `VoiceRecorder` / `Transcriber` / `Dictation`.
- **Markdown vault export** (`export/vault_export.dart`, account sheet):
  `Corplex/Notes/<Folder>/<Title>.md`, `Papers/@<citekey> <title>.md`
  (frontmatter, highlights by page), `Attachments/`, `references.bib` with
  citekeys as keys. Note links → `[[Title]]`, citations and page links →
  `[[@key Title|@key]]` (rewritten in the Delta before `noteToMarkdown`,
  which flattens internal links). PDFs only if the dialog switch is on.
  Filenames sanitised and deduplicated oldest-first, stable between
  exports. Built in memory.
- **CSL styles** (`features/csl/`, `assets/csl/`): a hand-written CSL
  1.0.2 processor (no Dart citeproc exists) with APA 7, MLA 9, Chicago
  author-date, Harvard (Cite Them Right), IEEE, Vancouver (NLM), Nature,
  Science, ACM and Elsevier Harvard (CC BY-SA 3.0, unmodified, see
  `assets/csl/ATTRIBUTION.txt`; en-US locale only). `CitationStyle` is a
  class; `formatCitation` stays sync and uses the hand-written formatter
  until a style's CSL file has loaded (`ensureLoaded()`).
  `pickCitationStyle` is the one picker (note and project bibliography,
  export, the paper screen's "More…" chip) and "Add a style…" imports a
  `.csl` per device. Exports follow the style (`buildStyledExportDoc`).
  Not done: collapse by year, subsequent-author-substitute, locators,
  other locales; editor citation chips stay author-year.
- **iOS extensions** (`ios/ShareExtension`, `ios/CorplexWidget`, targets
  added by `tool/ios/add_extensions.rb` with the `xcodeproj` gem — rerun
  it rather than editing the pbxproj by hand). Both use App Group
  `group.com.corplex.corplex` (entitlements on Runner and each
  extension); Runner's `Info.plist` has `AppGroupId` and URL schemes
  `corplex` (missing before — iOS widget/shortcut links couldn't open the
  app) and `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`. The Share Extension
  is a self-contained controller (SPM links the plugin only into Runner).
  The embed phase must sit before "Thin Binary" or Xcode reports a cycle.
  **Sideloading**: a free Apple ID allows 3 app IDs and each extension
  uses one; AltStore may strip extensions and App Groups are unreliable on
  free accounts, so without them the app works minus sharing and the
  widget.

### v1.7 — Thesis writing (built; not yet on a device)
- **Thesis outline** (`projects/chapters*.dart`, schema v14, server file
  `20261005000000_thesis_outline.sql`, **apply it before schema-v14 data
  syncs**): a project's notes are its chapters. `ProjectNotes` gains
  `position`, `status` (`ChapterStatus`: outline, draft, withSupervisor,
  revised, finished — `final` is a Dart keyword; shown as "Final") and
  `wordTarget`; `Projects` gains `dueDate` — all synced. `dueDate` is the
  first nullable synced date, so the engine's `syncDateTimeColumns`
  conversions are null-safe. `position` stays null until the first
  reorder; order is stored positions, then unplaced notes by creation
  date (`compareChapterRows`). The project page shows "Chapters"
  (drag to reorder, status menu, words vs target, "Add chapter") and a
  header summary ("12,400 / 40,000 words · 2 of 5 chapters final · Due
  14 March · 152 days"); nothing new for a project with no notes.
  `projectChaptersProvider(id)` is the ordered list; Export project uses
  `orderedProjectNotes`. The Notes-tab project filter still sorts by
  last edit.
- **Coverage & writing to-dos** (`projects/coverage.dart`, `todos.dart`,
  `todos_request.dart`), under the chapter list and invisible when empty:
  `ChapterCoverageSection` — papers each chapter cites, "Read but not
  cited" (project papers and highlighted papers linked to its notes that
  no chapter cites, ranked by highlights; untouched "To read" papers are
  left out), and citations to papers outside the project.
  `ProjectTodosSection` — `TODO` (whole word, case-sensitive), `[@?]`
  (needs a citation; stays plain text, never a chip) and `[fig: …]` /
  `[FIG]` markers by chapter. `findTodos` measures offsets on the document
  the editor shows (chips, maths and sketches are one character each);
  a tap opens the note with the marker selected via
  `NoteEditorScreen.initialSelection`, or, in the ≥ 900 px pane, via
  `pendingNoteSelectionProvider`, which the editor takes and clears.

### v1.8 — Study details (built; emulator-checked)
- **Study details** (`library/study_details.dart` — the shared
  `StudyField` enum and helpers — and `study_details_section.dart`;
  schema v15, server file `20261006000000_study_details.sql`, **apply it
  before schema-v15 data syncs**): optional species, brain regions,
  techniques (lists stored `a; b`), sample size and paradigm on a paper,
  synced. The paper screen shows only "Add study details" until a paper
  has any; then a compact card with chip inputs. Suggestions:
  `studyLibraryValuesProvider` (values used in the library, most used
  first), then `studySuggestions` (neuroscience-leaning). Fields absorb
  outside changes only when the reader hasn't edited them. Search
  indexes the values; the Markdown vault writes them to paper
  frontmatter when set.
- **Study filter** (`library/study_filter.dart`): a "Study" chip in the
  Library filter row, only once some paper has details
  (`anyStudyDetailsProvider`). OR within a field, AND across fields, a
  minimum n drops papers without one; combined with search, status and
  project in `filteredPapersProvider`. Per session, never synced.
- **Bound matrix columns**: `MatrixColumns.paperField` (a
  `StudyField.key`) makes a column read the paper (`matrixCellText`) and
  write it through `setStudyValue`, never `matrix_cells`. Added from the
  matrix "+" sheet ("Add study columns" skips fields already present);
  deleting one leaves papers untouched; Markdown copy includes it.

### v1.9 — Thesis writing II (built; emulator-checked)
- **Page locators** (`library/citations.dart`, `csl/`,
  `notes/citation_embed.dart`): pandoc locators in the stored marker —
  `[@key, p. 42]`, `[@a, pp. 3–5; @b]`, `[@key, chap. 2]`; a bare number is
  a page, unrecognised text a label-less free-text locator.
  `parseCitationGroup` → `CiteItem {key, locator, label}` is the one parser;
  `citedKeys` ignores locators and `[@?]` stays a to-do. Output: APA
  "(Kandel et al., 2013, p. 42)", MLA "(Smith 42)", IEEE "[1, p. 42]"; CSL
  gets them through `CslCite` clusters (`CslProcessor.process(cites:)`,
  `CslContext.locatorLabel`, `<if locator=…>`); styles without locator rules
  (Nature) ignore them. The chip shows the locator; its long-press card has
  "Page…"/"Change page" (`replaceCitationMarker`, no pop-in). The cite
  picker deliberately has no page field (it would add a step). Vault:
  `[[@key Title|@key]], p. 42`.
- **Chapter versions** (`notes/note_versions*.dart`, table `note_versions`,
  schema v16, synced; server file `20261007000000_note_versions.sql`,
  **apply it before schema-v16 data syncs**): an immutable copy of a note's
  title and body (only the label changes), cascading with the note.
  `setChapterStatus` saves "Sent to supervisor" when a chapter becomes
  "With supervisor" (skipped if the newest version is identical). Note ⋮ →
  Versions (`showNoteVersions`, which flushes the editor's `_save` first):
  newest first with words and change since, "Save a version now" (optional
  name), rename/delete with Undo. A version opens a compare view (line LCS
  over plain text, citations as `[@key]`, sketches as "[Sketch]"); Restore
  saves the current text as "Before restoring", then rewrites the note — the
  open editor takes it as a clean replace because it was flushed. In trash
  snapshots and backups; not in search or the vault.
- **Figures and tables** (`notes/figure_markers.dart`, `figure_embed.dart`,
  `projects/figures.dart`): stored as text — a caption is a paragraph
  starting `{#fig:LABEL}` / `{#tbl:LABEL}` (LABEL a short random id), a
  reference is `{@fig:LABEL}` / `{@tbl:LABEL}`; numbers are never stored.
  The editor shows chips via `editorDocument`/`storedFromEditor`
  (`notes/editor_document.dart` — the single stored↔editor crossing point;
  to-dos and abbreviations measure offsets with it). A number is
  `chapter.n` (chapter = position in `projectChaptersProvider`, n = same-kind
  captions in the note, live from the document via `FigureScope`, told once
  per document change); outside a project just `n`; a note in several
  projects uses the first by `createdAt`. Unknown label → "Figure ??".
  `/` → Figure caption, Table caption, Refer to a figure or table. Exports:
  `BlockKind.caption` with bold "Figure 3.2."; project exports open with
  lists of figures and tables (`exportFrontMatter`, plus
  `extraFrontMatter`); single-note exports use `figureIndexForNote` so
  numbers match the editor; Markdown share and the vault number per note.
  List previews and search read markers as words (`notePlainTextPreview`).
- **Abbreviations** (`projects/abbreviations*.dart`, nothing stored):
  `findAbbreviationDefinitions` runs Schwartz & Hearst over the editor text
  ("medial prefrontal cortex (mPFC)", also "mPFC (medial prefrontal
  cortex)"; plural short forms define the singular), with citations, figure
  markers, maths and URLs blanked at equal length so offsets match
  `editorDocument`. `analyzeAbbreviations` flags, per chapter, a short form
  defined anywhere in the project whose first use in that chapter isn't its
  definition; one long form per short form (most common across chapters,
  tie → first); undefined abbreviation-like tokens go under a collapsed
  "Never spelled out" (ignores Roman numerals, panel labels like 2A, `TODO`,
  all-caps headings). `ProjectAbbreviationsSection` sits on the project page
  under the to-dos, invisible without definitions or issues; "List" copies
  Markdown or tab-separated text. Project exports get an "Abbreviations"
  front-matter section (`abbreviationBlocks`, via `extraFrontMatter` in
  `project_menu.dart`).

### 1.10–1.11 — Notes parity (built)
- **Checklists**: Quill's own checked lists (`Attribute.unchecked`). Mac
  toolbar button and Format → Checklist ⇧⌘L (`MenuCommand.checklist`);
  phones use `/` → Checklist (the phone format row must fit 360 px, and a
  sixth button doesn't).
- **Pinned notes** (`Notes.pinned`, schema v18, synced; server file
  `20261009000000_pinned_notes.sql`, **apply it before schema-v18 data
  syncs**): every notes list orders `pinned DESC, updatedAt DESC`;
  ⋮ / right-click → Pin to top / Unpin (`setNotePinned`); a pin before the
  title. The first synced boolean: the server column is an `integer` 0/1,
  like SQLite, because sync copies values through unconverted — a
  Postgres `boolean` would reject 0/1 on push.
- **Find in note** (`notes/note_find.dart`, `NoteFindBar`): ⌘F/⌘G/⇧⌘G on a
  Mac (the editor's `MenuCommandHandler` now takes `find`, so ⌘F in a note
  no longer opens app search), ⋮ → Find in note everywhere. Case-insensitive
  matches over `document.toPlainText()`, whose offsets equal document
  offsets (embeds are one character); Replace / Replace all (back to
  front). It sits in the editor's bottom bar. It must request focus itself:
  `autofocus` won't take focus from the editor that still has it.
- **Paste and drop files** (`notes/note_drop.dart`): pasting files copied
  in Finder or a picture (screenshot, Preview), or dragging files from
  Finder onto a note (Mac, `desktop_drop` — a plain channel plugin, not the
  Rust one), attaches them like the attach sheet: images/audio/other files
  as the note's attachments, a PDF as a Library paper (`importPdfAt`, with
  the usual lookup) linked to the note. Paste is Quill's experimental
  `onClipboardPaste` → `pasteFilesIntoNote`; text on the clipboard wins
  over a picture (apps put a picture of copied text beside it). The
  clipboard goes through `NoteClipboard` (`noteClipboardProvider`,
  quill_native_bridge — Quill's own plugin). Dropped Finder files carry a
  security-scoped bookmark that is opened before copying.
- **Date groups**: both notes lists show Notes' headers — Pinned, Today,
  Yesterday, Previous 7 Days, Previous 30 Days, then month or year
  (`noteDateSection`, `noteSectionHeaders` in `notes_screen.dart`); the
  header rides inside the first item of its group, so list indices and
  `ListItemMotion` are unchanged.
- **Duplicate and Print** (`notes/note_file_actions.dart`): ⋮ / right-click
  → Duplicate, File → Duplicate Note ⌘D: same title, folder, tags, linked
  papers and attachments (files copied; audio timestamp links remapped to
  the copy's attachments), not pinned, not in projects; a locked body is
  re-encrypted under the copy's id (needs the notes unlocked). File →
  Print… ⌘P (Mac): the PDF export (APA) through PDFKit's print panel
  (`MacWindow.printPdf` → `printPdf` on `corplex/window`; needs the
  `com.apple.security.print` entitlement). Both act on the focused editor,
  else on the note open in the pane (`HomeShell._onCommand`).
- **Spell check** (`features/spell/`): the `corplex/spell` channel
  (NSSpellChecker in macOS `AppDelegate.swift`, UITextChecker in iOS
  `AppDelegate.swift`, none on Android) behind the `SpellChecker` seam;
  the default provider is inert and `main()` installs `ChannelSpellChecker`
  on macOS/iOS. `NoteSpell` plugs into the body editor's `textSpanBuilder`
  (red wavy underline merged with the leaf's own decoration, recognizer
  kept) and `contextMenuBuilder` (up to 5 guesses, Learn / Ignore Spelling;
  a guess is one `replaceText`). Results are cached per paragraph text
  (LRU), checked 400 ms after the last request, embeds counted as one
  space so offsets match. Skips the caret's word, links, code, words with
  digits, ALL-CAPS and URLs. Settings → "Check spelling while typing"
  (`AppearanceSettings.spellCheck`, hidden without a checker); off means
  no channel calls. Titles aren't checked.
- **Highlight and Monospaced** (`notes/note_highlight.dart`): a highlight
  is Quill's `background` attribute holding one of five pastel hexes
  (`NoteHighlight`), so it syncs and merges as part of the Delta; text on
  a highlight is drawn in dark ink via `customStyleBuilder: noteStyleFor`
  in both schemes. Mac: highlighter menu in the format bar, Format →
  Highlight ⇧⌘E toggles the last-used colour (per session); phones: **Aa**
  → Highlight. Monospaced is Quill's `codeBlock` (⇧⌘M, **Aa**), styled from
  the theme. `_desktopShortcuts` routes ⇧⌘E/⇧⌘M to the editor. Exports:
  Markdown `==text==` and fenced blocks (also share and vault via
  `note_markdown.dart`); DOCX `w:shd` fill (Word's named highlights lack
  pink/purple) and Consolas; PDF background and Courier, falling back to
  Roboto for a line with non-Latin-1 characters (`BlockKind.code`,
  `Run.highlight`). Citations inside a code block are still resolved.
- **Attachments browser** (`features/attachments/`): Mac sidebar →
  Attachments, View → Attachments ⌘3, or Search → Attachments (phones and
  tablets). `allAttachmentsProvider` is a live join, newest first; it
  leaves out attachments of locked notes until their key is unlocked
  (the files aren't encrypted, so the browser must not show them). Filter
  chips and the search box appear only when useful; images are a
  thumbnail grid (tap to zoom), other kinds rows: tap plays audio, opens a
  link, shares a file (there is no in-app file viewer). Right-click /
  long-press: Show in note/paper (`openNoteFromPage`/`openPaperFromPage`),
  Share, Copy name. Attachments on both a note and a paper list under the
  note.
- **Quick capture (macOS)** (`features/capture/`, native in
  `MainFlutterWindow.swift`): a global ⌃⌥N (Carbon `RegisterEventHotKey`,
  no Accessibility permission) registered only while the per-device
  `AppearanceSettings.quickNoteHotKey` is on (default on; `HomeShell`
  sends `setQuickNoteHotKey` at startup and on change; false if the key is
  taken). Services → "New Corplex Note" (`NSServices` in Info.plist; the
  window is `NSApp.servicesProvider`) and the Dock menu's New Note
  (`AppDelegate.applicationDockMenu`) arrive as `MacWindow.captures`
  (`NewNoteCapture` / `TextCapture`); text is classified like a share
  (DOI → paper, link → link note, else note). A cold start through
  Services delivers text before Dart listens: native queues captures until
  Dart sends `captureReady`, and `ChannelMacWindow` buffers until
  `HomeShell` subscribes. New Services entries may need a logout or
  `/System/Library/CoreServices/pbs -update` to appear. No Mac share
  extension (no team id / App Group with ad-hoc signing).
- **Not done**: collapsible headings (flutter_quill can restyle a line but
  not hide one — needs a fork) and a note in its own window (Flutter's
  multi-window API is private and debug-only in 3.47; a second engine
  would mean a second database connection whose streams don't see the
  first's writes).

### 1.13 — Drawings, papers and thesis tools (built; emulator-checked)
- **Pen tools** (`lib/features/ink/`): *shapes* — holding the pen still
  500 ms (`shapeHoldDelay`) at the end of a stroke snaps it via the pure
  `recognizeShape` (`shape_recognizer.dart`: line (level/plumb within 5°),
  ellipse, rectangle, triangle, arrow), in `InkCanvas` and in `InkCatcher`
  strokes that open a drawing. *Lasso* — `InkToolKind.lasso` selects strokes
  with > 50% of their points inside the loop; the selection lives in the
  canvas, clears when another drawing is chosen; move / Copy / Duplicate /
  Colour / Delete are single writes, Paste via `inkClipboard`.
  *Handwriting* — `InkSession` reads drawings written this session 2 s after
  the pen idles (or when put away) through `inkOcrEngineProvider` (inert by
  default; `main()` installs the on-device OCR, `renderSketchPng` on white),
  storing `Sketch.text` (JSON `t`) via a history-ignoring write only if the
  strokes are unchanged; changing strokes drops it. ⋯ → Convert to text
  replaces the drawing with its text (one undo). Shared rendering:
  `sketch_render.dart` (`renderSketchPng`, `sketchToSvg`).
- **Mark up images** (`features/markup/`): the full-screen image view (note
  and paper attachments, Attachments browser) has Mark up; an `InkCanvas`
  over the fitted image (image-width units). Done writes a native-resolution
  composite PNG and repoints the same attachment row (`storage_key` cleared);
  a sidecar `<composite>.markup.json` keeps the original's path and the
  strokes, so marks stay editable on this device (other devices get the
  composite only). Trash purge deletes the sidecar and original with the
  composite (`purgeTrash`).
- **Tables** (`notes/table_embed.dart`, `note_table.dart`): a block embed
  `table` holding `NoteTable.encode()` on its own line (`/` → Table, Aa →
  Table, Format → Table ⌥⌘T). `_EditableTable` owns a controller/focus node
  per cell so writes (`replaceText`, `ignoreFocus`) never recreate them;
  300 ms debounce, flushed on leaving a cell; `didUpdateWidget` absorbs undo
  and sync. Tab/Return/arrows move between cells (Tab in the last cell adds
  a row); the editor's formatting keys do nothing in a cell. Structure menu
  (handle, right-click, long-press). Word count includes cells.
- **Exports** (`features/export/`): `ExportDoc` has `image` and `table`
  blocks. PDF draws drawings as vector paths; DOCX embeds PNGs
  (`exportToDocxWithImages`, `descr` = handwriting) and `<w:tbl>`; Markdown
  share inlines an SVG data URI (alt = handwriting); the vault writes
  `Attachments/<note>-sketch-N.svg`; tables are pipe tables / `pw.Table`.
  **LaTeX (Overleaf)** (`latex_export.dart`, `ExportFormat.latex`, a zip of
  `main.tex`, `references.bib`, `figures/*.png`): natbib with
  `\citep[p.~42]{key}` / `\citealp` for mixed locators, `figure`/`table`
  environments with `\label`/`\ref`, `tabularx`, `report` + `\chapter` for
  projects, bib style from the citation style; built from `buildExportDoc`
  (`Run.source` keeps raw markers). Checked: DOCX opens in macOS's reader;
  LaTeX not compiled here (no TeX installed). Note image attachments are
  exported since 1.14.
- **Search inside PDFs** (`search/pdf_text_index.dart`): local FTS5
  `pdf_pages_index` (one row per page) + `pdf_index_state` (stamp =
  path|size|mtime, `done_pages`), raw SQL, derived, not synced, dropped from
  backups. Text from `PdfPages.text`, `ocr_pages` for scanned pages (waits
  while OCR runs). Background, a page at a time with a yield
  (`pdfIndexStartupProvider`, also kicked by Search); resumes, re-indexes
  changed PDFs, drops deleted papers. Results under "In papers" (page +
  snippet, 3 pages per paper); tapping opens the PDF at the page with Find
  started on the query (`PdfViewerScreen.initialQuery`). `noteSearchText`
  adds drawing handwriting and table cells to note search (locked notes
  stay title-only).
- **PubMed** (`library/pubmed.dart`): `parseIdentifier` knows labelled PMIDs
  and PMC ids (never a bare number); E-utilities `esummary` and the PMC ID
  converter (`pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/`), https,
  `tool=corplex`; a DOI in the result goes to Crossref. The PMID is stored
  since 1.14 (`Papers.pmid`). **Retractions** (`library/retraction*.dart`): Crossref
  `works?filter=updates:<doi>` (retraction, withdrawal, expression of
  concern, correction), cached per DOI in `<cache>/retractions` (30 days,
  stale offline; no cache folder → no request), checked when a paper opens
  and after import; `RetractionNotice` on the paper screen,
  `RetractionMarker` (cache only) on Library rows for retractions.
- **Zotero import** (`features/zotero/`, Library ⋮): user ID + API key in
  secure storage on this device only; collections (nested) or everything;
  Web API v3 (paged, `Backoff`/`Retry-After`, 50 MB file cap). Items →
  papers (`findDuplicate`; existing papers only gain missing fields),
  collections → projects ("Parent / Child"), PDFs downloaded, highlight /
  underline annotations → `Highlights` (rects to page fractions via the
  `PageSizeReader` seam, y flipped), child notes → "Zotero notes: <title>".
  Re-imports don't duplicate; each paper commits in one transaction. Not
  run against the real API.
- **Read aloud** (`features/read_aloud/`, PDF viewer ⋮): `cleanPagesForListening`
  (repeated headers/footers, page numbers, hyphenation, nothing after the
  last References heading), `splitSentences`, `ReadAloudController` queues
  3 sentences on the `Speaker` seam (inert default; `main()` installs
  `ChannelSpeaker`, channel `corplex/speak`: AVSpeechSynthesizer on
  iOS/macOS with a spoken-audio session on iOS, Android `TextToSpeech`
  created lazily — the manifest needs the `TTS_SERVICE` `<queries>` entry).
  The viewer follows the spoken page unless the reader scrolls away ("Back
  to reading"). Android pause restarts the sentence. **Not `flutter_tts`**:
  it has no Swift Package Manager support. Smoke test speaks a sentence.
- **Comments** (`features/comments/`, table `note_comments`, schema v19,
  synced; server file `20261010000000_note_comments.sql`, **apply it before
  schema-v19 data syncs**): a comment keeps the passage's `quote` and an
  editor-document `anchor` hint; `locateQuote` re-finds it (exact nearest
  the anchor, else case-insensitive, else "Passage changed" — kept).
  Add from the selection menu, Format → Add Comment ⌥⌘K or the panel's +.
  `CommentMarks.wrap` tints open comments by composing with
  `NoteSpell.spanBuilder` (document untouched); tapping a passage opens a
  popover. ⋮ → Comments: side panel ≥ 900 pt, sheet below. Project chapter
  rows show "N open comments". Locked notes: `quote`/`body` are encrypted
  envelopes (`lockNote`/`removeLock` convert them; read via
  `CommentStore.view`). Comments travel with trash.

### 1.14 — Performance, photos in exports, paper links (built; emulator-checked)
- **Performance** (`docs/performance.md`, `test/perf/`,
  `integration_test/perf_test.dart`): measured on 1,500 papers, 3,000
  notes, 20,000 highlights and a 300-page PDF. `flutter test test/perf`
  prints `PERF` lines; on a device `flutter drive
  --driver=integration_test/perf_driver.dart
  --target=integration_test/perf_test.dart -d <device> --profile` prints
  `PERFDEV` lines (a Mac window must be on screen for the UI groups).
  `SearchIndex` now diffs against a plain local `search_state` table (kind,
  ref, stamp, FTS rowid) inside SQLite and re-reads only changed rows, in
  batches of 40 with a yield; a dirty flag from drift's `tableUpdates`
  skips the comparison when nothing was written (so **writes to notes,
  papers or highlights must go through drift or `notifyUpdates`**, as the
  sync engine's raw SQL does). If `search_index` or `search_state` is
  missing (backups drop the index) it rebuilds. First build went from 80 s
  to 1.3 s on a Mac, minutes to ~12 s on the emulator. Local indexes are
  `performanceIndexStatements` (`CREATE INDEX IF NOT EXISTS` in
  `beforeOpen`, no schema bump; a test checks they're used and don't touch
  the sync triggers). `PdfTextIndex.kickIfIncomplete()` for frequent
  callers, `kick()` at startup (after 4 s); pages written 8 per batch.
  `notePlainTextPreview` is an LRU; `paperCoverProvider` is `autoDispose`
  with a 120-entry memory cache. Known gap: the Notes list still loads full
  note bodies (37 ms on a Mac at 3,000 notes); fixing it needs a stored
  preview column.
- **Photos in exports** (`export/export_images.dart`): `ExportNote.images`
  (`noteExportImages`: the note's image attachments with a local file, in
  attachment order) become `BlockKind.photo` blocks after the note body —
  the end of each chapter in a project export, before References. Files
  are sniffed by magic bytes; PNG/JPEG go in as they are, anything else is
  re-encoded to PNG via `dart:ui`; missing or undecodable files are
  skipped. Caption = attachment title unless it is camera-style
  (`isCameraStyleName`: `IMG_1234`, "Pasted image", timestamps). PDF/Print
  full text width, ≤ 70% of the page height; DOCX media parts (`jpg`
  default content type); LaTeX `figures/image-N.<ext>` in a `figure`;
  Markdown export writes "*[Image not included: name]*"; the vault already
  embedded them (`![[…]]`). Marked-up images export the composite. Locked
  notes export images only when the body was readable. "Share as
  Markdown" still leaves images out. HEIC/WebP/GIF conversion is untested
  (`dart:ui` decoding is unreliable under `flutter test`).
- **Paper links** (schema v20, server file
  `20261011000000_paper_links.sql`, **apply it before schema-v20 data
  syncs**): `Papers.pmid`, `url` and `abstract`, synced. Every metadata
  source fills them only into empty fields (`PaperMetadata`,
  `fillMissingMetadata`): Crossref (link = doi.org; JATS abstract →
  plain text with paragraph breaks, `plainTextFromMarkup`), PubMed
  (`esummary` + `efetch` abstract with section labels; an `efetch`
  failure just means no abstract), arXiv (`abs` link, summary), Zotero
  (`url`, `abstractNote`, `PMID:` in `extra`), BibTeX, RIS and CSL JSON
  import (a `url` that is only the doi.org link is dropped). A PMC lookup
  via Crossref keeps the PMID but fetches no PubMed abstract. The paper
  screen shows Abstract (4 lines, More/Less, editable), PubMed ID and Link
  (each with an open button) only once they have a value, and a section
  stays once shown. BibTeX export writes `pmid`/`url`/`abstract`; CSL
  items get `URL`, `PMID`, `abstract`; search indexes the abstract in the
  paper's body column (below titles in rank). OpenAlex abstracts aren't
  used.

### Locked notes (built; biometrics untested on real hardware)
Decided with the user: **real encryption** (a forgotten password loses the
locked notes — said plainly when the password is set), **one notes
password** for all locked notes, optional Face ID / Touch ID / fingerprint,
and **titles stay plain** (list shows the title, a lock and "Locked").
- **Crypto** (`features/lock/note_crypto.dart`, pure): a random 256-bit
  notes key; bodies AES-256-GCM with the note id as associated data, stored
  in `notes.content` / `note_versions.content` as
  `corplex-locked:v1:<keyId>:<b64>` — **check `isLockedContent` before
  parsing any content**. The password → PBKDF2-HMAC-SHA256, 600k, salted →
  wraps the notes key; only the wrapped key is stored and synced
  (`NoteKeys`, schema v17, server file `20261008000000_note_keys.sql`,
  **apply it before schema-v17 data syncs**). The KDF input is base64 of
  the password's UTF-8 (`kdfInput`, recorded as `pbkdf2-sha256-b64utf8`):
  Android derives natively (cryptography_flutter, javax.crypto) and must
  match Dart byte for byte for non-ASCII passwords —
  `integration_test/kdf_parity_test.dart` checks it on a device (passed on
  the emulator). Elsewhere PBKDF2 is pure Dart in `Isolate.run` (~1.8 s on
  an M-series Mac); tests pass `inlineKdf: true` (isolates don't run under
  the fake clock) and `NoteCrypto(iterations: 1000)`.
- **Service** (`note_lock_service.dart`, `noteLockServiceProvider`): keys in
  memory only; locks on app pause, after 5 min idle (`touch()`), or "Lock
  now" / File → Close All Locked Notes. `lockNote`/`removeLock` convert a
  note and its versions in one transaction. The newest `NoteKeys` row is the
  current key (a new key's `createdAt` is forced past the newest: the column
  has one-second resolution). "Reset password" adds a new key; notes under
  the old one stay locked until it's entered. The database runs with
  `PRAGMA secure_delete = ON`.
- **Sync**: a locked body is never line-merged; if exactly one side is
  locked the **lock wins regardless of timestamps**, and a plain edit it
  beats is saved as a new note "<title> (edit made before it was locked)".
  `lockNote` and the engine **redact** the merge base instead of deleting it
  (`corplex-base-sha256:<hex>`, `redactedBody`): deleting it skipped the
  merge, so an older lock could lose to a newer plain edit and silently
  unlock the note.
- **Editor** (`notes/note_editor_screen.dart`): `NoteEditorScreen` is a gate
  — `NoteLockScreen` when `canRead` is false, else `_NoteEditorBody`, which
  decrypts on load/absorb and encrypts every save (echo detection on
  decrypted bodies; saves serialised; 150 ms debounce when locked). The save
  path writes plain text only with a conditional UPDATE that can't match a
  locked row, so a lock from elsewhere can never be overwritten in the
  clear; if the key is gone, typing is held in memory (`LockedEditRescue`)
  and saved encrypted on the next unlock. `decodeNoteContent` returns an
  empty document for an envelope, so nothing shows ciphertext as text.
  Unlock prompts: `ensureNotesUnlocked` (for locking — may set a password),
  `requestNotesUnlock` (read-only uses; `export/unlock_for_export.dart`'s
  `requestUnlock`/`readableForAction` wrap it).
- **Rest of the app** reads bodies via `readableNoteContent` /
  `unlockedContents` (`projects/readable_content.dart`) or `decryptBody`:
  search indexes locked notes by title only (the stamp's low bit marks
  locked, so locking evicts old plain text); the Map shows them without
  content edges; projects use decrypted chapters while unlocked and show
  "Locked" otherwise; project export asks to unlock (declining cancels);
  the Markdown vault always writes a `locked: true` placeholder and skips
  their attachments; versions compare/restore need the key; Quote to note
  decrypts, appends and re-encrypts. Backups and trash carry envelopes, and
  backups include `note_keys`.
- **Not encrypted**: titles, attachment *files* (images, audio, PDFs — the
  lock dialog says so), links between notes and papers, and the hint.
- **Biometrics** (`lock/biometric_store.dart`, `PluginBiometricKeyStore`;
  inert `NoBiometrics` default under test): stores the unlocked keys in the
  keychain/keystore (this device only, never iCloud), released after a
  `local_auth` prompt that also accepts the device passcode. The gate is
  app-level (prompt, then read), not a keychain access-control flag. macOS
  uses the legacy file keychain (an ad-hoc signed app has no team id; the
  data-protection keychain fails with -34018) — expect a "Corplex wants to
  use the keychain" prompt after a rebuild changes the ad-hoc signature.
  Android: `MainActivity : AudioServiceFragmentActivity` (local_auth needs a
  FragmentActivity), AppCompat parents for LaunchTheme/NormalTheme,
  `USE_BIOMETRIC`; iOS: `NSFaceIDUsageDescription`.

### macOS app (built; checked in widget tests and a release launch, not by hand on a Mac)
- **Build**: `tool/macos/make_dmg.sh` → `build/dmg/Corplex-<version>.dmg`
  (drag-to-Applications; `--no-build` packages the existing build). Without
  a Developer ID it is ad-hoc signed: fine on the Mac that built it, blocked
  by Gatekeeper elsewhere until right-click → Open; set
  `CODESIGN_IDENTITY` to sign (then notarise). Icon: `tool/branding/macos_icon.py`
  (Apple's 824/1024 squircle grid — macOS boxes full-bleed icons in a grey
  tile). Sandbox entitlements: network client, user-selected and Downloads
  read-write, audio input. Deployment target 12.0 (`#available` for newer
  Vision/Speech APIs).
- **Everything is keyed on the theme's platform** (`isMac(context)` /
  `isDesktop(context)` in `features/platform/mac_window.dart`,
  `isDesktopPlatform` in `app_theme.dart`), so iOS/Android are unchanged and
  Mac tests run with `variant: macOnly` (`test/support/mac_screenshot.dart`;
  flutter_quill reads `defaultTargetPlatform` lazily, so a Mac editor test
  *must* use the variant). The desktop theme is denser (compact density,
  shrink-wrapped targets, 52 pt app bars, smaller headings, body 15/13.5,
  radius 12, no sheet drag handles, fade page transitions); swipe-to-trash
  is off for a mouse.
- **Window** (`macos/Runner/MainFlutterWindow.swift`): transparent title bar
  with full-size content and an **empty unified `NSToolbar`**, min 720×520,
  first size proportional to the screen (~1320×860 on a laptop, ~2100×1180
  on a 38" ultrawide), frame remembered. The toolbar makes the title bar a
  52 pt band (`macToolbarHeight`) with the traffic lights in its middle,
  like Notes; **clicks in the band still reach Flutter** (checked natively:
  `hitTest` there returns the Flutter view, only the lights are AppKit's),
  so the home window draws its toolbar row there and empty space drags the
  window through `MacWindowDragArea` (`startDrag`/`zoom` on
  `corplex/window`). Pages pushed over home (PDF viewer, project, trash…)
  hide the toolbar for the slim title bar (32 pt on macOS 26+, 28 before):
  `MacToolbarRouteObserver` (in `app.dart`, page routes only — dialogs,
  sheets and menus don't count) calls `setToolbar`, which answers the
  band's real height (`titleBandHeight`: twice the lights' centre);
  `macHomeOnTopProvider` / `macTitleBandProvider` hold the state.
  `MacWindowFrame` (`MaterialApp.builder`) adds the band to the top of
  `MediaQuery.padding`, so a pushed page's AppBar/SafeArea clears the
  lights and a strip over the band drags the window; home removes that
  padding (`MediaQuery.removePadding` in `_macScaffold`). Full screen
  collapses the band (`macFullScreenProvider`).
- **Interface size** (Settings, View → Interface Size, ⌥⌘+/⌥⌘−/⌥⌘0;
  `AppearanceSettings.interfaceScale`, per device, 90–160%): `MacWindowFrame`
  lays the app out at 1/scale and draws it scaled (a `FittedBox`, so text
  stays sharp and hit testing works), with MediaQuery size and
  devicePixelRatio adjusted. Note text zoom (⌘+/⌘− in a note,
  `noteZoomProvider`) is separate and multiplies with it.
- **Layout**: `HomeShell._macScaffold`, `home/mac_sidebar.dart` and
  `home/mac_toolbar.dart`, laid out like Apple Notes. **One toolbar row**
  across the window, each column drawing its part (`MacToolbarRow`,
  `MacToolbarButton`): the sidebar's (lights, then New Folder and Hide
  Sidebar), the list's (folder/project/tag title — `notesFilterTitle` — with
  its count under it, and a ⋯ menu: Show Attachments; in Library the Library
  menu, `LibraryMenuButton(onShowAttachments:)`), and the pane's (New note /
  Import PDF first, then the note's formatting and actions, the search field
  last). The pane's screens take the two ends from `MacPaneChrome`
  (`NoteEditorScreen`, `PaperDetailScreen`'s SliverAppBar, the empty pane via
  `macPaneBar`) and size their app bar to the row; elsewhere they keep
  their usual bar. When the pane is under 820 pt (or there is none) the
  search field moves to the list's row so a 13" pane keeps all its
  formatting buttons; with the sidebar hidden the list's row starts after
  the lights with a Show Sidebar button. **Search** (`MacToolbarSearch`,
  View → Search, ⌘F outside a note): typing shows `SearchResultsView`
  (`search_screen.dart`) in the list column over the list (an
  `IndexedStack`, so the list keeps its place); a note or paper opens in the
  pane and the results stay; Escape or × clears. **Attachments** (list ⋯ →
  Show Attachments, View → Attachments ⌘3): the browser
  (`AttachmentsBrowserScreen(embedded: true)`) replaces list and pane under
  its own row with Done; choosing a sidebar row or searching leaves it. The
  sidebar (`MacSidebar`): Notes (All Notes and every folder, live counts from
  `folderNoteCountsProvider`), Library (All Papers), Projects
  (`projectNoteCountsProvider`) and Tags, each foldable and the last two only
  once one exists, then Trash and Settings at the bottom. Choosing a folder,
  project or tag sets `notesFilterProvider`; right-click renames/deletes a
  folder, opens a project's page or its menu, deletes a tag; dragging a note
  row (`Draggable<DraggedNote>`) onto a row files it there (All Notes =
  unfiled). The Notes filter chip row and Library's own search field are
  hidden on the Mac. Folded sections: `macSidebarCollapsedProvider`, per
  session. Sidebar toggled by ⌃⌘S
  (`macSidebarVisibleProvider`, `MacSidebarSlot`; slot = 232 + 1 pt divider,
  change both). ≥ 900 pt: sidebar | list (drag `ColumnDivider`, 280–520,
  `mac.listWidth`; the pane keeps ≥ 360) | pane. Lists are Notes-style
  `MacListRow`s (`theme/mac_list_row.dart`; no `onDoubleTap` — it delays
  single clicks ~300 ms). Panes **fill their width like Notes**:
  `macPanePadding` gives 24/40 pt margins, but beyond `macMaxMeasure`
  (1,600 pt — a 38" ultrawide's note pane is > 3,000) the content centres
  at that width. Note editor: one 52 pt toolbar (format controls left,
  actions right, `_DesktopFormatBar` in `AppBar.title`), a centred edit date,
  `_desktopStyles`; `/` commands open as a dialog. Paper screen: two
  columns at ≥ 1000 pt (shared `e0…eN` widget lists). Settings and the `/`
  sheet are dialogs on desktop.
- **Menu bar & keyboard**: the native menus (File with Duplicate ⌘D / Print ⌘P, Edit → Find, Format with
  Apple Notes' shortcuts, View, Go → Back ⌘[, Help → Keyboard Shortcuts ⌘/)
  send `MenuCommand`s on `corplex/window`. **Key equivalents reach Flutter
  first**; only keys Flutter leaves unhandled reach the menu. A command is
  then offered to the nearest `MenuCommandHandler` above the primary focus
  (`dispatchMenuCommand`, a responder chain — not `Actions`, which stops at
  a disabled action) and only then to `HomeShell._onCommand`. So never bind
  a menu key in Flutter *and* handle its command elsewhere (double fire);
  on Mac the shell leaves ⌘N/⌘O/⌘1/⌘2 to the menu and keeps ⌘F (the PDF
  viewer's Find must win). The note editor's `_desktopShortcuts` overrides
  flutter_quill's clashing macOS keys (⌘K → note link, ⇧⌘B → Body, ⌘'
  quote; ⌘0–6, ⌘F, ⌘G, ⌘M, ⌘` pass through via `DoNothingAction(consumesKey:
  false)`). The viewer's `MenuCommandHandler` (Find/Next/Previous/zoom)
  sits above its Focus. Lists: ↑/↓ select and open in the pane, Return
  opens (note body / PDF), Tab moves sidebar → list → pane
  (`FocusTraversalGroup`s; the editor takes Tab itself). ⌘⌫: notes via the
  list's `MenuCommandHandler`, papers via `_TrashKey` (a `HardwareKeyboard`
  handler, so it also works from the pane — no-op when a text field has
  focus or the tab is offscreen), Move to Trash in the menu via the shell.
  `keyboard_shortcuts.dart`'s `shortcutSections` must match the Swift menus.
- **Pointer**: right-click menus via `ContextMenuRegion`
  (`theme/context_menu.dart`) on cards, rows, chips and highlights
  (`highlightContextActions`); mouse draws in sketches
  (`InkInputPolicy.mouseAlwaysDraws`) and PDF ink; trackpad two-finger
  scroll scrolls. Split reader is resizable (`ResizableSplit`,
  `splitFractionProvider`). Share sheets anchor with `shareOrigin(context)`
  (`platform/share_origin.dart`) — without it macOS opens the picker in
  the window corner.
- **Native channels** (`registerNativeChannels` in `AppDelegate.swift`):
  `corplex/ocr` (Vision) and `corplex/speech` (on-device
  `SFSpeechURLRecognitionRequest`), same contracts as iOS, created lazily.
  No share extension, quick actions or home widget on macOS: `main()`
  installs `NoShareIntentSource`/`ChannelMacWindow` there and leaves the
  inert seams. `ChannelMacWindow` must only be installed on macOS.
- **Looking at it without a screen**: `MAC_SCREENSHOTS=<dir> flutter test
  test/mac` renders the whole app at `macWindowSizes` (13"/16" laptops,
  27", 38" ultrawide at 1× and HiDPI, minimum) with real fonts.
- **Untested on a real Mac session**: the menu bar and key routing order,
  title-bar dragging, OCR/speech output and permission prompts, recording,
  share-sheet anchoring, pdfrx scrolling/pinch/selection.

### Exploratory (needs a decision before any work)
- AI assistance (summarize a paper, ask questions across the library). This
  conflicts with offline-first, so it would be strictly additive and
  opt-in, like sync. Not committed.

### Engineering (ongoing, start now)
- CI (`.github/workflows/ci.yml`, on every push and PR): `flutter
  analyze`, a stale-`database.g.dart` check, `flutter test`, a guard
  against plain-`http://` requests in `lib/` (Android release builds block
  them), and an Android **release** build that checks the notification
  drawables survived resource shrinking — release-only failures are
  otherwise invisible to the tests.
- Integration tests on real devices. The performance pass with 1,000+
  papers and large PDFs is done (1.14, `docs/performance.md`); rerun it
  after changing search, list queries or indexes.
- App Store / Play Store release setup; privacy-respecting crash reporting.

## Visual design

- **Palette**: sage green is the single accent on warm, paper-like
  neutrals, with a soft clay tertiary used sparingly. Both schemes are
  hand-tuned, explicit `ColorScheme`s in `lib/theme/app_theme.dart` (not
  `fromSeed`, which drifted too saturated). Widgets read
  `Theme.of(context).colorScheme` and never hard-code colors; the only
  literal colors outside the theme are the PDF highlighter inks
  (`pdf_viewer_screen.dart`), kept soft/pastel on purpose.
- **Component defaults live in the theme** (cards, chips, sheets with
  drag handles, dialogs, filled inputs, navigation bar), so screens stay
  free of styling code. Note: the input theme is *filled* — borderless
  in-page fields (note/paper titles) must set `filled: false` and the
  `none` borders explicitly, or they render as grey boxes.
- **Motion**: shared durations/curves in `AppMotion` (short, decelerating,
  never bouncy). `lib/theme/motion_widgets.dart` has the reusable pieces:
  `FadeThroughIndexedStack` (tab switching that keeps each tab's state),
  `EntranceTransition` (staggered list-item fade/slide), `StateSwitcher`
  (cross-fade between loading/empty/content) and `EmptyState`. Page
  routes use predictive-back on Android and Cupertino slides on iOS/macOS
  via `pageTransitionsTheme`, so plain `MaterialPageRoute`s get them.
  Every animation honours the system's reduce-motion setting through
  `AppMotion.of(context, d)` / `AppMotion.reduced(context)` (jump to the
  end state; loops don't run). Haptics go through `AppHaptics`
  (`theme/haptics.dart`: `confirm`, `threshold`, `selection`) and stay
  sparse: highlight/snapshot created, rating set, swipe-to-trash
  threshold, Pencil tool switch, audio Mark.
- **Motion details** (what each piece does and its traps):
  * **Cards → pages** (`home/open_card.dart`): below 900 px on Android a
    Notes/Library card is an `OpenContainer` that grows into its page;
    its route is a plain `ModalRoute` (no predictive-back animation;
    system back still pops). On iOS/macOS it pushes a normal page instead,
    because the container route has no edge swipe-back. At 900+ it fills
    the detail pane, which cross-fades. The closed card sits in a
    transparent `Card`: the transform re-hosts it outside any `Material`.
  * **Lists**: `NewItemScope(ids:)` + `ListItemMotion` make an id that
    joins an already-shown list (Undo, a new note) unfold in place; items
    present at first build keep `EntranceTransition`. `SwipeToTrash`
    grows its icon with drag progress and ticks once per crossing into
    "will trash".
  * **Covers** (`library/paper_cover.dart`): first page rendered at 360 px,
    one at a time, cached as PNG in the OS cache folder (derived — not in
    backups or sync), keyed by path + size + mtime. `coverRendererProvider`
    is the test seam; in widget tests the real renderer never finishes and
    the placeholder shows.
  * **Paper screen**: a `CustomScrollView` with a pinned `SliverAppBar`;
    a compact title fades into the bar once the large title field scrolls
    under it (measured post-frame; not built while hidden, so tests never
    see two titles). The cover is an `OpenContainer` into the same
    `PdfViewerScreen` as "Open PDF" (plain picture without a local PDF).
    Status chips stay `ChoiceChip`s (tests find them by type).
  * **PDF marks**: only highlights made this session sweep in — they
    register in `FreshHighlights` (`highlight_sweep.dart`) and the owning
    `PageOverlay` claims them; each animates on its own `RepaintBoundary`
    while the static painter skips it, so zoom cost is unchanged.
    `ReadingFilter` tweens the 4×5 colour matrix between reading themes,
    outside the snapshot boundary. Quote/snapshot flights (`flight.dart`,
    `flyAcross`) use the root overlay and land on the note pane in split
    view (`pairedPaneKeyProvider`), else the bottom of the screen.
  * **Citation chips** pop in only when `insertCitation` marked the Quill
    node (`FreshCitations`, an `Expando`). Don't key this on marker text or
    `initState`: Flutter reuses chip state across different chips, so
    loaded/synced chips would animate.
  * **Audio bar** rises in and slides out (it keeps the last attachment
    until the exit ends). Its level bars glide once per position update,
    never `repeat()`, so `pumpAndSettle` settles. `AnimatedSize` must not
    get a zero duration (assertion), so reduced motion uses 1 ms.
  * **Sync ring** (`sync/sync_ring.dart`): a thin arc around the account
    icon only while `syncingProvider` is true; static under reduced
    motion, never shown without a backend.
- **Tablet / iPad layout** (`lib/features/home/adaptive.dart`): the home
  screen adapts to its window, so an iPad never gets a stretched phone.
  Under 600 px wide: phone layout (bottom tabs, full-screen pages). 600–899
  (iPad portrait, Split View): a `NavigationRail` (primary action on top)
  instead of bottom tabs; lists centred at `readableWidth` (720); notes and
  papers open as pages. 900+ (iPad landscape, 13" portrait): rail, list and
  a detail pane side by side; `openNote`/`openPaper` fill the pane
  (`selectedNoteProvider`/`selectedPaperProvider`) instead of pushing, the
  open card is tinted, and the pane shows a placeholder when empty or when
  its item is deleted. Screens shown in the pane take `embedded: true`
  (no back arrow) and `onClose` (trash clears the pane instead of popping
  home). The editor and paper screens pad their content to
  `readablePadding` of the space they actually get (LayoutBuilder, not
  screen width); Search, Trash and All highlights use `ReadableColumn`; the
  audio bar and editor toolbar keep to the reading width. The tablet
  audio bar lives in the body, not `bottomNavigationBar` (a Scaffold bottom
  bar strips the bottom safe-area inset from nested scaffolds). Widget tests
  default to an 800×600 screen, which is the *tablet* layout:
  `test/widget_test.dart` pins a phone size; tablet behaviour is covered in
  `test/features/home/tablet_layout_test.dart`.
- **App icon**: a watercolour painted in code by
  `tool/branding/watercolor_icon.py` (numpy/scipy/Pillow: transparent
  glazes, edge pooling, granulation, blooms; the page is left as unpainted
  paper). It writes `assets/branding/icon.png` (full-bleed, iOS/README),
  `icon_background.png` + `icon_foreground.png` (Android adaptive layers;
  the foreground is painted to the safe zone, so
  `adaptive_icon_foreground_inset: 0`) and `icon_monochrome.png` (themed
  icon); then `dart run flutter_launcher_icons`. The iOS launch image is
  the rounded icon.
- **Primary actions**: each tab's main action is one labelled extended FAB
  owned by `HomeShell` (`New note` / `Import PDF`), morphing between tabs.
  The actions themselves are top-level functions (`createNote`,
  `importPaper`) next to their screens.
- **Note commands**: typing `/` at the start of a line or after a space
  opens a sheet of the note's less obvious actions (cite, link a note,
  draw, heading, attach, literature template, bibliography); "and/or"
  doesn't trigger it, and dismissing leaves the `/`.
- **First launch**: while there are no notes and no papers
  (`isFreshStartProvider`), both tabs show `GettingStarted` — three steps
  and "Import your first paper" — instead of the plain empty states. It
  goes away by itself once anything exists; nothing to dismiss or store.
  Anything it starts must not rely on its own `WidgetRef` afterwards: it
  disappears the moment a paper is inserted (`enrichImportedPaper` reads
  its providers up front for this reason).
- **Readable names**: stored authors (`Vaswani, Ashish; …`) display via
  `displayAuthors` / `authorsSummary` ("Ashish Vaswani, Noam Shazeer,
  Niki Parmar + 5 more"; the paper screen shows the raw field on tap).
  Files become titles via `titleFromFileName`; attachments display through
  `Attachment.label` (`data/attachment_label.dart`), which also feeds the
  lock screen.

## Conventions

- Prefer Flutter/Dart idioms and the standard `lib/`, `test/` project layout
  once the app is scaffolded (`flutter create`).
- Keep platform-specific code behind clear abstractions; avoid `Platform.is*`
  checks scattered through feature code.
- iPad layouts should take advantage of larger screens (split views, side
  panels for PDF + notes) rather than simply stretching the phone layout.
- Write tests alongside new features (`flutter test`); do not let the test
  suite bit-rot as features are added.
- Do not introduce a cloud backend dependency for features that can work
  offline — sync is additive, not required.

## Status

Local DB (`drift`) and state management (`flutter_riverpod`) are decided
(see Tech stack). Both tabs are wired end-to-end:

- **Notes**: list, create, and autosaving edit, backed by the `Notes` table.
- **Library**: PDF import (`file_picker`) creates a `Papers` row; search
  filters by title/authors (`lib/features/library/papers_providers.dart`);
  paper detail screen has autosaving title/authors and an attachments
  section (`lib/features/library/paper_detail_screen.dart`,
  `add_attachment_sheet.dart`) supporting podcast links, images
  (`image_picker`), and arbitrary files, all copied into app-managed
  storage via `lib/data/local_files.dart`.

- **Linking**: a note's AppBar has a link icon opening a searchable sheet
  (`lib/features/notes/link_paper_sheet.dart`) to attach/detach papers via
  the `NotePaperRefs` join table (`lib/features/notes/note_papers_providers.dart`
  for the note→papers side, `notesForPaperProvider` in
  `lib/features/library/papers_providers.dart` for the reverse). Linked
  papers show as chips in the note editor (tap to open, × to unlink) and
  as a "Referenced in notes" list on the paper detail screen. The sheet's
  first row, "Import a PDF", picks a PDF with the same `importPaperFile` the
  Library uses (background DOI/arXiv lookup included) and links the new
  paper to the note in one step.
- **Citations**: `citation_formatter.dart` formats a `Paper` as
  APA/MLA/BibTeX (pure, unit-tested). Authors stay a single string in the
  DB but are parsed by `authors.dart` (`parseAuthors`: `A B; C D`, `and`,
  BibTeX `Family, Given`, comma lists, particles like "van der Berg",
  "et al.") into `Author{family, given}`, then rendered per style (APA
  initials + `&`, MLA `et al.` from 3 authors, BibTeX `and others`). The
  canonical stored form is `Family, Given; Family, Given`
  (`authorsToStored`), what BibTeX import and lookups write. Existing raw
  "Vaswani et al." strings keep their old output.
- **Metadata & BibTeX** (`metadata_lookup.dart`, `bibtex.dart`,
  `library_actions.dart`): `parseIdentifier` recognizes DOIs, doi.org
  links, arXiv ids/links; `MetadataLookup` (injected `http.Client`, so
  tests use `MockClient`) queries Crossref and arXiv — verified against
  the live services — and distinguishes "not found" (null) from "couldn't
  reach" (`LookupFailed`). Importing a PDF reads its first two pages for a
  printed DOI/arXiv id, looks it up, and `fillMissingMetadata` fills only
  empty fields (the title is replaced only if it's still the file name),
  then says "Found the details for …". With no id printed,
  `searchByFirstPage` queries Crossref with the first page's text and
  accepts a result only if its title (4+ words) *and* an author's family
  name are printed on the page, it has a journal/conference, and — when
  the page prints years — its year is one of them: Crossref holds
  re-posted copies of famous papers (same title and authors, another
  publisher, no venue, a recent year). arXiv lookups must use **https**:
  Android release builds block cleartext http, which made arXiv lookups
  fail silently on phones while passing in debug and tests. arXiv papers
  get arXiv's DOI (`10.48550/arXiv.<id>`) when the feed names no journal
  DOI, and "Look up" falls back to an arXiv id in the venue field. `findDuplicate` matches by DOI or normalized
  title (+ compatible year) and is used by add-by-ID, BibTeX import and
  PDF enrichment. `parseBibtex` is a real tokenizer (nested braces,
  `"…"`, `@string`, LaTeX accents, DOI from `url`); `exportBibtex` makes
  keys unique. Library ⋮ menu: Add by DOI/arXiv ID, Import BibTeX, Export.
  The paper screen has editable Details (DOI, venue, year) with "Look up",
  and it *absorbs outside changes* into fields the reader hasn't touched
  (`_absorbOutsideChanges`), so a background lookup or a sync shows up
  without clobbering typing.
- **Reading status**: `Papers.readingStatus` (`ReadingStatus`), chips on
  the paper screen (tap again to clear); the Library filter row appears
  only once some paper has a status.

- **Text highlights** (`lib/features/library/highlights.dart`,
  `pdf_viewer_screen.dart`, `quote_to_note.dart`): selecting text in the
  PDF adds "Highlight" and "Quote to note" to pdfrx's own selection menu
  (via `customizeContextMenuItems`, so Copy/Select all stay native).
  A `Highlights` row keeps the passage's real `quote` (cleaned of PDF line
  breaks/hyphenation), its page, a comment, and one box per line as
  fractions of the page (`lineRects` merges pdfrx's per-character rects,
  converted with `PdfRect.toRect(page:)`). A selection spanning pages
  becomes one highlight per page. Tap a highlight for its sheet
  (recolor, comment, quote, copy, delete). Quoting appends a block quote
  plus "— p. N" linked to `corplex://paper/<id>?page=N` (`appendQuote` in
  `note_content.dart`) and links the note to the paper; tapping that link
  in the editor reopens the PDF at the page. `Papers.lastPage` (synced)
  reopens the viewer where you left off. Both kinds of marks live in one
  per-page overlay (`_PageOverlay`); ink mode disables text selection.
- **PDF viewing & annotation (ink)**: `lib/features/library/pdf_viewer_screen.dart`
  uses `pdfrx`'s `PdfViewer` (normal pan/zoom) with freeform highlighter
  annotation — chosen over Syncfusion's text-layer highlighting to stay
  fully open-source and to fit the pen-input design principle; it works on
  any PDF regardless of text layer, at the cost of "highlights" being
  pixel strokes rather than selected text. Strokes are stored per-page in
  the `Annotations` table (`lib/data/tables/annotations_table.dart`) as
  normalized (0..1) points via `lib/features/library/annotations_providers.dart`,
  so they scale correctly at any zoom/render resolution. Drawing uses
  pdfrx's `pageOverlaysBuilder` hook, which hands back each page's
  on-screen `Rect` — this is what lets the overlay track zoom/pan for
  free instead of us reimplementing a transform. **Snapshot to a note**
  (viewer ⋮, `snapshot.dart`): drag a box around a figure or table (or
  "Whole view"); the viewer is captured (`RepaintBoundary` + `toImage` at
  2–3×) and cropped to the box, saved as a note image attachment with a
  "From p. N" link back to the page, and the note is linked to the paper.
  The reading-theme filter sits *outside* the boundary, so a snapshot
  keeps the figure's real colours. Drags starting at the screen edge are
  Android's back gesture, not a box.
- **Note attachments UI**: the note editor now renders its own
  attachments (`lib/features/notes/note_attachments_providers.dart`) as
  image previews in their own aspect ratio (up to 220 px high; tap for a
  full-screen, zoomable view) or file chips below the linked-paper chips — added
  specifically so extracted highlight screenshots are visible, since the
  `Attachments` table supported `noteId` from the start but nothing
  rendered it in the note editor until now.

- **UUID primary keys**: every table's primary key (and every foreign key
  referencing it) is a client-generated UUID string (via `package:uuid`'s
  `clientDefault`), not an autoincrement int. This was done *before* any
  real sync backend exists, specifically so IDs created offline on two
  different devices can never collide once sync is wired up. `drift`'s
  `.insert()` always returns the row's internal SQLite `rowid` (an int)
  regardless of the declared primary key type, so it's useless as "the
  id" here — every insert call generates its own UUID up front (e.g.
  `final id = const Uuid().v4();`) and passes it explicitly via
  `SomeCompanion.insert(id: Value(id), ...)`, then uses that same `id` for
  navigation/lookups. Schema v3's migration is destructive (drops and
  recreates every table) since this changed primary key *types*, not just
  added a column — acceptable because there's no production data yet;
  a future breaking migration will need a real data-preserving strategy.
- **Auth**: `lib/features/auth/auth_service.dart` defines the
  `AuthService` interface that screens depend on. Two implementations:
  `StubAuthService` (in-memory, any well-formed email + 6+ char password
  "succeeds") is the default when Supabase isn't configured, and
  `SupabaseAuthService` (`supabase_auth_service.dart`, persisted session)
  replaces it via provider overrides in `supabase_setup.dart`. Sign in/up
  screens live in the same folder; the account icon in `HomeShell`'s
  AppBar is the entry point.
- **Supabase config**: credentials come from `--dart-define=SUPABASE_URL`
  and `--dart-define=SUPABASE_PUBLISHABLE_KEY` (`lib/config/supabase_config.dart`),
  never the repo. Without both, `main()` installs no overrides and the
  app runs offline exactly as before (tests rely on this). To stand up a
  backend: create a Supabase project, run
  `supabase/migrations/20260929000000_sync_schema.sql` in its SQL editor,
  then launch with the two defines (also run
  `20260930000000_file_sync.sql`, and turn off "Confirm email" in the
  project's Auth settings or sign-up stops at a confirmation step).
  **Verified** against a local Supabase stack (`supabase start`, needs
  Docker; `supabase/config.toml` is committed) by
  `test/integration/supabase_sync_test.dart`, which runs the real engine,
  auth, PostgREST and Storage: two-device sync of every table plus files,
  edits, deletes, server-side LWW rejection, and row-level-security
  isolation between users. Run it with:
  `flutter test test/integration --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<from supabase status>`
  (skipped without the defines, so plain `flutter test` stays offline).
  The same test also passes against a hosted project (with "Confirm
  email" off); with confirmation on, `SupabaseAuthService.signUp` reports
  "check your email" but the app has no deep-link handling to finish the
  flow. The unit tests still use
  `test/support/fake_sync_remote.dart`.
- **Sync engine**: `SyncEngine` (`lib/features/sync/sync_engine.dart`)
  pushes then pulls through the narrow `SyncRemote` interface
  (`sync_remote.dart`; `SupabaseSyncRemote` is the real one). Design:
  * **Change tracking lives in SQLite triggers** (`lib/data/sync_schema.dart`),
    not in app code, so no feature query needed changing: inserts/updates
    enqueue the row in `sync_dirty`, updates bump `updated_at` if the
    writer didn't, deletes (including FK cascades) write `sync_tombstones`.
    All are suppressed while `sync_meta.applying = 1` (pulling), so
    applied rows never echo back. Triggers use delete-then-insert, not
    `INSERT OR REPLACE`: an outer statement's conflict clause (e.g. an FK
    `SET NULL`) overrides a trigger's own.
  * **Push uses the dirty queue, not a timestamp cursor**: `updated_at`
    has one-second resolution, and a cursor version let a device's echo
    push resurrect a row deleted in the same second.
  * **Pull** uses per-table server `synced_at` cursors (immune to device
    clock skew), applies parents-before-children inside a transaction,
    skips rows that lose to a newer local edit or whose parent is gone.
    The cursor is the *max* `synced_at` of the fetched rows, computed —
    never "the last row": postgrest-dart's `.order()` defaults to
    **descending**, which once pinned every cursor at its first value and
    made each sync re-download everything since. `SupabaseSyncRemote`
    now passes `ascending: true` explicitly; `FakeSyncRemote.newestFirst`
    and an integration test guard both halves.
  * **What counts as an edit**: update triggers fire only when a
    *synced* column changes (`NEW.c IS NOT OLD.c` over the spec's
    columns), so setting a device-local path never syncs the row. The
    automatic stamp is `MAX(now, OLD.updated_at + 1)` and also applies
    when a writer's own `updatedAt` isn't newer than the stored one — an
    edit can't lose to older data because another device's clock ran
    ahead. Trigger changes reach existing installs only when a migration
    step re-runs `_createSyncSchema()`; `syncSchemaStatements` takes the
    set of existing tables because earlier steps run before later tables
    exist.
  * **A server behind the app**: after an app update the hosted project
    may lack the newest `supabase/migrations` (a missing table or column
    answers PGRST205/PGRST204/42P01/42703 → `SyncServerOutdated`). The
    engine *skips just those tables* (`_unlessOutdated`) — their changes
    stay queued in `sync_dirty`/tombstones and their cursors don't move —
    syncs everything else, and only then reports "Your sync server needs a
    database update". So an un-migrated `projects` table never blocks
    notes. **Every new migration file must be applied to the hosted
    project by its owner before the matching app version's data syncs.**
  * **Conflicts** are last-write-wins per row on client `updated_at`,
    enforced on both ends (server `sync_guard` trigger; client `_apply`),
    *except* that concurrent edits to the same row are merged first
    (schema v11). The first local edit of a row since it last synced saves
    its old version in `sync_base` (update trigger, rows with an `id` key
    only). Before pushing such a row, `_mergeConcurrentEdits` fetches the
    server copy (`SyncRemote.fetchRows`); if it changed since the base,
    `mergeRow` (`merge.dart`) merges field by field — a field only one side
    changed takes that change; a note body both changed is merged by lines
    (diff3 over Delta lines, formatting kept; where both rewrote the same
    paragraph, both versions are kept, this device's first); any other
    field both changed keeps the later edit. The merged row is stamped
    newer than the server's and pushed; the base is dropped after the push
    (or replaced by the pushed version if the row was edited mid-push).
    A delete on one side vs an edit on the other is still plain LWW.
    Device clocks are trusted for this. **An open note editor absorbs
    outside changes** (`_absorbOutsideChange`): a pulled or merged body is
    merged with whatever was typed since the last save, so the next
    autosave can't write stale text back — this matters most on iPad,
    where a note stays open in the detail pane. The editor ignores echoes
    of its own recent saves (`_ownContents`) and compares bodies in
    normalised Delta form.
  * **Accounts**: a database syncs for exactly one user. Data created
    signed-out uploads to whoever signs in first; a *different* account
    then gets `SyncAccountMismatch` rather than mixing libraries. Two
    account-sheet actions resolve this, both via `eraseLocalData()`:
    "Use this account on this device" (mismatch) and "Sign out and clear
    this device". Both warn with the count of unsynced changes
    (`pendingChanges()`), which are lost for good.
  * **Files** (`file_sync.dart`): `FileSync` uploads before the metadata
    push (so `storage_key` goes out in the same round) and downloads after
    the pull. Objects are keyed by row id (`<user>/papers/<id>.pdf`,
    `<user>/attachments/<id><ext>`), so retries are idempotent. Local paths
    never sync; a downloaded path is written with tracking suppressed so
    it doesn't look like an edit. A file whose local copy is missing (e.g.
    after a reinstall) is re-downloaded. Per-file failures don't block
    metadata; they surface as `SyncFilesIncomplete` and retry next sync.
    Needs `20260930000000_file_sync.sql` (Storage bucket + policies).
    **Size limit**: files over `defaultMaxUploadBytes` (50 MB) stay on the
    device — skipped, not failed, and not counted as pending changes.
    **Orphan cleanup**: at the end of a fully successful sync (no skipped
    tables, no file failures) `removeOrphans` deletes storage objects that
    no live *server* row names (`SyncRemote.liveStorageKeys`, so a row this
    device hasn't applied can't make its file look orphaned), that no local
    row names (unpushed), and that are over a day old (`orphanGrace`:
    another device may have uploaded a file and not pushed its row yet).
    **Transfer settings** (`transfer_settings.dart`, per-device, in
    shared_preferences, not synced; two switches in the account sheet):
    "Send files on Wi-Fi only" (default on: uploads and background
    downloads only on Wi-Fi/Ethernet; metadata always syncs) and "Download
    files when opened" (default off: never download in the background).
    Opening always downloads, on any network (`SyncService.downloadFile`
    → `FileSync.fetchPaper/fetchAttachment`): the paper screen shows
    "Download PDF", an audio attachment downloads then plays. A connectivity
    change triggers a sync so waiting files move when Wi-Fi returns. Files
    are still read fully into memory on download.
    Restoring from trash clears `storage_key` when the file is still on
    disk, so it uploads again if cleanup removed the object.
  * **Watchers**: pull applies rows with raw SQL, which drift can't see, so
    the engine calls `notifyUpdates` itself — only when something really
    changed (rows are compared by content first), otherwise the inclusive
    cursor would re-wake every watcher on every sync. Local-change syncs
    are also skipped unless `pendingChanges() > 0`, so pulls/downloads
    can't retrigger a sync loop.
  * `EngineSyncService` schedules it: on start, ~5 s after any local
    write (debounced), and every 5 minutes. `SyncCoordinator` starts/stops
    it from auth state. The only UI is a "Sync now" row in the account
    sheet — no badges or banners, per the no-distractions principle.
  * Schema v6 added `storage_key` to papers and attachments. Schema v5 added `updated_at` to every table (migration backfills from
    `created_at`; `ALTER TABLE` can't default to "now", so migrated DBs have
    `DEFAULT 0` while fresh ones rely on drift's `clientDefault`) and the
    `sync_*` tables/triggers. `test/data/v4_schema.dart` is the real v4
    schema, used to test the v4→v5 migration.

- **Audio & NotebookLM**: there is no public NotebookLM API for consumer
  accounts (only a Pre-GA Enterprise API on Google Cloud; unofficial
  libraries drive a logged-in browser session and must not ship), so the
  "connector" works with what NotebookLM allows: download the audio
  overview, then attach it (`Audio` in the attach sheet, available on
  notes *and* papers — `showAddAttachmentSheet(noteId:/paperId:)`,
  UI-free `insertAttachment`). Audio is an `AttachmentType.podcast` row
  with a local `path` (so it syncs via file sync); a podcast row with only
  a `url` streams if it's a direct audio file, otherwise (e.g. a
  NotebookLM share page) opens in the browser. `audio_link.dart` decides
  playability (`audioSourceOf`). Playback is one app-wide
  `AudioPlayback` (`audio_playback.dart`, behind an `AudioEngine`
  interface so tests use `FakeAudioEngine` instead of just_audio's
  plugin; widget tests must override `audioEngineProvider`).
  `AudioPlayerBar` shows on home, paper and note screens; in a note its
  **Mark** button inserts `▸ 12:34` linked to
  `corplex://audio/<attachmentId>?t=<seconds>` — plain Quill links, so
  they sync/copy/export untouched. The note editor's
  `customRecognizerBuilder` makes those links play on a single tap (Quill
  otherwise only opens links on long-press while editing). Gotchas: use
  `▸` not `▶` (Android renders ▶ as an emoji); just_audio's `playing`
  stays true after a track completes, so `JustAudioEngine` derives it
  from `playerStateStream`; its `play()` future only completes when
  playback stops, so don't await it. **Background playback**:
  `just_audio_background` (`JustAudioEngine.initBackground()` in `main`)
  keeps audio going with the screen off and shows lock-screen /
  notification controls with the recording's title (`load(title:)`);
  closing the player `stop()`s, which clears them. Android needs
  `MainActivity : AudioServiceActivity`, the `AudioService` service and
  `MediaButtonReceiver` in the manifest, the foreground-service
  permissions, the monochrome `drawable/ic_stat_corplex` notification
  icon, and `res/raw/keep.xml` — release resource shrinking otherwise
  strips audio_service's button icons (looked up by name) and the
  notification fails to build. iOS needs `UIBackgroundModes: audio`.
  Verified on the Android emulator; untested on a real iPhone/iPad.
  The player bar uses `Center(heightFactor: 1)`: as a Scaffold's
  `bottomNavigationBar` it is offered the full screen height, and a plain
  `Center` once took all of it and hid the page.
- **Android manifest**: `INTERNET` is declared in the *main* manifest.
  Debug/profile manifests add it implicitly, so leaving it out breaks
  sync and streaming only in release builds.
- **Release-only crashes (1.5.0 shipped one)**: `OcrChannel.register`
  called ML Kit's `TextRecognition.getClient()` inside
  `MainActivity.configureFlutterEngine`; in the R8-shrunk release build
  ML Kit's component lookup failed and the app crashed at launch for
  everyone, while every test and the debug build were fine. Rules: native
  channel code must never initialise an SDK at registration — create it
  lazily on the first call and turn failures into a channel error; keep
  rules for reflection-heavy SDKs go in `android/app/proguard-rules.pro`
  (wired in `build.gradle.kts`). **Before every release**, install the
  release APK on the emulator *over the previous release with data in it*
  and launch it, and run the on-device smoke test
  (`integration_test/smoke_test.dart`: PDF engine, covers, OCR, annotated
  export, maths, CSL assets, recorder, Markdown export through the real
  plugins; `adb shell pm grant com.corplex.corplex
  android.permission.RECORD_AUDIO` first, then `flutter test
  integration_test/smoke_test.dart -d <device>`; a fresh debug install resets the grant, so re-grant in a loop while it runs: `(for i in $(seq 60); do adb shell pm grant com.corplex.corplex android.permission.RECORD_AUDIO; sleep 3; done) &`). To install and launch: (`adb install -r …; adb shell am start -W -n
  com.corplex.corplex/.MainActivity; adb logcat -b crash`); retrace
  obfuscated traces with `cmdline-tools/latest/bin/retrace` and
  `build/app/outputs/mapping/release/mapping.txt` (needs
  `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`).
- **Flutter deep linking is off** (`flutter_deeplinking_enabled` in the
  manifest, `FlutterDeepLinkingEnabled` in Info.plist): the app routes
  links itself (share plugin, `home_widget`, shortcuts), and Flutter's
  router was pushing every opened PDF / `corplex://` link as an unknown
  route. iOS widget links carry a `homeWidget` query item (`widgetLink`
  in `CorplexWidget.swift`) — `home_widget` ignores taps without it.
- **Pen input** (`lib/features/ink/`), redesigned in 1.12 to work like
  Apple Notes: drawings sit **inline** among the paragraphs and are drawn
  on in place — no separate screen. A drawing is a Quill
  `CustomBlockEmbed('sketch', json)` on a line of its own, so it lives in
  the note's `content` and syncs, versions and merges with it (no table).
  **Insert `CustomBlockEmbed` directly**, never `BlockEmbed.custom(...)`
  (its type would be `custom`), and **add the newlines yourself**: Quill's
  `InsertEmbedsRule` only adds them around videos, so `insertDrawing`
  composes `\n` + embed + `\n` as needed (the old Draw button left a
  drawing sharing a line with text).
  * `InkSession` (`ink_session.dart`, one per open note, extends the
    shared `InkTools` — tool, inks, thickness, Pencil double-tap) writes
    every stroke straight into the document (`write`, one Quill edit, so
    the editor's undo/⌘Z take strokes back), inserts drawings
    (`insertDrawing`, `insertAtCursor` for Draw and `/` → Draw), and
    tracks the *chosen* drawing (`active`), which shows the floating
    `InlineInkToolbar` (pen/highlighter/eraser, inks, widths, undo/redo;
    ⋯ → Expand (full-screen `SketchEditorScreen`) and fingers draw/scroll,
    pinned beside Done so they stay in reach on a 360 px phone). A chosen
    drawing left empty is removed with its line. Pen writes pass
    `ignoreFocus: true` (no keyboard), and **on that path Quill doesn't
    rebuild the editor** — `onQuietEdit` makes the editor `setState`, or
    new ink stays invisible.
  * `InlineSketch` (`sketch_embed.dart`) is the drawing in the note: a
    pen always draws on it; a finger or mouse only once it's chosen (tap
    it), so fingers scroll past drawings; a grip under a chosen drawing
    resizes it (never cutting ink). Without an `InkSessionScope`
    (read-only views) a drawing is a picture that opens full screen.
  * `InkCatcher` (`ink_catcher.dart`) wraps the body editor plus 160 pt of
    blank space under it (a finger tap there types at the end). A pen
    stroke that starts on the text or in that space opens a new drawing
    after that line (`RenderEditor.getPositionForOffset`, line bottom via
    `getLocalRectForCaret`), keeping the stroke where it was drawn when it
    can; starting within 56 pt below a drawing extends it instead. Its
    recognizer accepts after 3 px of pen movement — before text selection
    or scrolling — and lets a still tap through, so a pen tap still places
    the cursor.
  * **Gestures**: `InkCanvas` claims a pointer it draws with on touch-down
    (`InkClaimRecognizer`, eager accept), so Quill's selection and the
    page's scrolling never see a stroke; it commits an eraser swipe once,
    at the end. A finger tap on a drawing also reaches Quill, which focuses
    the editor with the cursor at the drawing — the tools close only when
    the cursor lands elsewhere (`_leaveDrawingIfTyping`), and the keyboard
    is hidden after the tap.
  * Strokes (`ink_model.dart`) are in canvas-width units with per-point
    pressure, so they render identically at any width; `Sketch.encode`
    rounds to 4 decimals. **Palm rejection** (`inkPolicy`, app-wide): fingers
    draw until a stylus is seen, then only the pen draws; a pen's eraser
    end (`invertedStylus`) or barrel button erases; on desktop a mouse
    draws on a chosen drawing. Paper is light in both themes (borderless on
    a light page). Test with real stylus events: `adb shell input stylus
    swipe …` on the emulator, `startGesture(kind: PointerDeviceKind.stylus)`
    in widget tests (`test/features/ink/inline_ink_test.dart` checks what's
    on screen, not just the saved content — reset `inkPolicy` in `setUp`).
- **Note links & export** (`note_links.dart`, `note_link_sheet.dart`,
  `note_markdown.dart`): a link to another note is a plain Quill link
  `corplex://note/<id>` whose text is the target's title when linked.
  Typing `[[` (detected from the document change itself, not the
  cursor) or ⋮ → "Link to a note" opens a searchable picker that can
  also create the note. Backlinks are found by `LIKE` on the link text in
  `content` — no index table to keep consistent — and render as "Linked
  from" chips only when there are any. All `corplex://` links (note,
  paper page, audio) open on a single tap through the editor's
  `customRecognizerBuilder`. "Share as Markdown" converts the Delta
  (`noteToMarkdown`): headings shift down one level under the title,
  app-internal links become plain text, sketches become `[Sketch]`.
- **Search** (`lib/features/search/`): a magnifier in the home app bar
  opens `SearchScreen` (results as you type; notes / papers / highlights;
  a highlight opens its PDF at the page). `SearchIndex` keeps an FTS5
  virtual table `search_index` (tokenizer `unicode61 remove_diacritics 2`,
  title weighted 2× in bm25) *outside* the synced schema — it is derived,
  each device builds its own. `refresh()` runs before every search and
  diffs each row's `updated_at` against the stamp it was indexed at, so
  edits, deletes, new rows *and rows applied by a sync* are all picked up,
  and only changed rows are re-read (note text must be extracted from Quill
  JSON in Dart, which is why SQL triggers can't maintain it). Queries are
  reduced to words and matched as prefixes joined by AND, so FTS syntax
  characters can never cause an error (operators like AND are just words).
  If FTS5 isn't compiled into the platform's SQLite, `search` falls back to
  a substring scan (`available` reports it) — FTS5 is present in the test
  and Android builds.
- **Projects** (`lib/features/projects/`, schema v8): `Projects` plus two
  join tables `ProjectPapers` / `ProjectNotes` (FKs with cascade, so
  deleting a paper/note leaves its projects and deleting a project leaves
  its papers/notes — the grouping only). A paper/note can be in several,
  unlike a note's single folder. **Hidden until created**: the only way
  in is "Add to project" on a paper (chip row) or a note (⋮ menu), whose
  picker also creates projects (`findOrCreateProject` is case-insensitive).
  Once any exists, project chips join the Notes filter bar
  (`ProjectFilter`) and the Library filter row (`libraryProjectFilterProvider`);
  long-press a chip to rename/delete. A note created while filtering by a
  project joins it. There is deliberately no project *page* yet — the
  filtered lists are the view; the synthesis matrix (v1.1) is the natural
  first thing to give it one. Server side: `20261002000000_projects.sql`.
- **Share-sheet import** (`lib/features/share/`): `ShareCoordinator`
  (wrapped around `HomeShell`, invisible) listens to the launch share and
  later ones through a `ShareIntentSource` seam (`receive_sharing_intent`
  in production; tests override `shareIntentSourceProvider`, since the
  plugin has no implementation under `flutter test`). `classifyShared`
  sorts items: PDF → paper (copied to app storage, then the same
  background DOI/arXiv enrichment as a manual import); audio → asks what to
  attach it to (new note / recent notes / papers); DOI/arXiv id, bare or
  inside a shared page → `addPaperFromIdentifier`; other URL → a note whose
  body is the link; other text → a note. Every outcome ends in a snackbar
  with an Open action. Android: intent filters for `SEND`
  (`application/pdf`, `audio/*`, `text/plain`) and `VIEW` on PDFs, and the
  activity is `singleTask` (required so a share reaches the running app).
  iOS: the `ShareExtension` target (v1.6) writes the plugin's
  `ShareKey` format into the App Group; untested on a device.
  **Testing IO in widget tests**: real file IO never completes under the
  fake clock, and each awaited step needs its own round trip — see
  `settle()` in `test/features/share/share_test.dart` (alternate `pump()`
  with `runAsync` delays), and fake `PathProviderPlatform.instance`.
- **Trash** (`lib/data/trash.dart`, `lib/features/trash/`, schema v9):
  before this, *nothing* could delete a note or paper. Swiping a card or
  ⋮ → "Move to trash" snapshots the item — the row plus attachments, tag /
  paper / project links, highlights and ink — as JSON in `TrashItems`, then
  hard-deletes it (so the delete syncs normally). Undo (snackbar, 6 s) and
  the Trash screen call `restoreFromTrash`, which re-inserts everything,
  dropping links to things deleted meanwhile (a folder, tag, paper…) and
  **stamping every row `updatedAt = now`** — otherwise the restored rows
  would lose to the server's delete marker on last-write-wins and never
  sync. `TrashItems` is local-only (not in `syncTables`): trash isn't
  shared between devices. Files stay on disk until `purgeTrash` (30 days,
  run at startup; Empty trash purges now), which deletes a file only if no
  row or other trash entry still points at it. Editors leave *before*
  trashing so a pending autosave can't resurrect the item.
- **Backup & restore** (`lib/data/backup.dart`, `features/home/data_actions.dart`):
  the account button opens one sheet (signed in or out) with Sync, Trash,
  Back up to a file, Restore, Sign out. A backup zip holds `manifest.json`,
  a `VACUUM INTO` snapshot (consistent while the app runs) and every file
  under the documents folder that the data references. Stored file paths
  are absolute and device-specific (an iOS container path even changes
  between installs), so the snapshot rewrites them to `@docs/…` and
  restore rewrites them back. The snapshot also drops the trash, the
  search index, tombstones and the sync identity (`sync_meta`), so a
  restored device doesn't think it belongs to the old device's account.
  **Restore is staged, then applied at next launch**: `stageRestore`
  extracts into `restore_staging/` (ignoring `../` entries) and
  `applyPendingRestore` — called in `_openConnection` *before* the database
  opens — swaps files, keeps the old database as `corplex.sqlite.before-restore`
  (one level of undo), and fixes paths; the user is told to reopen the app.
  Backups from a newer schema, or that aren't backups, are refused with a
  message. Restoring into a signed-in library: the next sync merges by
  last-write-wins, so newer cloud edits will win over restored older ones.
- **Rich text**: notes use `flutter_quill` instead of a plain `TextField`.
  `lib/features/notes/note_content.dart` is the single place that
  encodes/decodes a note's `content` column: it's Quill Delta JSON now,
  with `decodeNoteContent` falling back to treating the string as plain
  text if it isn't valid JSON (covers notes created before rich text
  existed, or any malformed content) so nothing crashes on old data.
  `notePlainTextPreview` extracts a flattened one-line preview for the
  Notes list without spinning up a full `QuillController`. The toolbar
  (`_FormatBar` in `note_editor_screen.dart`, pinned to
  `bottomNavigationBar` rather than above the content, so it sits near
  the keyboard) is deliberately small — no font/size/color pickers,
  alignment, code block, or link button — to match the "no distractions"
  principle: Draw, bold, italic, underline, bullet and numbered lists
  (Quill's `QuillToolbarToggleStyleButton`s), and **Aa**, a menu for
  Title/Heading/Subheading/Body text, Quote and Strikethrough. It fits a
  360 px phone on one row (`test/features/ui_polish_test.dart`). Titles
  wrap (`maxLines: null` with a text keyboard, so Return moves to the body
  instead of adding a newline). **Important**:
  `flutter_quill` requires `FlutterQuillLocalizations.delegate` (and the
  standard Flutter ones) registered in `MaterialApp.localizationsDelegates`
  (see `lib/app.dart`) — omitting it throws
  `MissingFlutterQuillLocalizationException` at runtime the moment any
  toolbar button builds, including in widget tests.
- **Folders & tags**: both exist (per explicit user choice over
  folders-only or tags-only). A note has at most one folder
  (`Notes.folderId`, nullable, `ON DELETE SET NULL` so deleting a folder
  unfiles its notes rather than deleting them) and any number of tags via
  the `NoteTags` join table. Providers/actions in
  `lib/features/notes/folders_providers.dart` and `tags_providers.dart`;
  `findOrCreateTag` reuses an existing tag case-insensitively rather than
  creating near-duplicates. The Notes screen shows a horizontal filter
  chip row (`_FilterBar` in `notes_screen.dart`) mixing folders and
  `#tags` as one mutually-exclusive filter dimension (never both at
  once, to keep the UI a simple chip row instead of a filter builder) —
  **it only appears once at least one folder or tag exists**, so an
  unorganized notebook stays exactly as uncluttered as before this
  feature. The note editor exposes a folder picker and tag picker via
  AppBar icons (`folder_picker_sheet.dart`, `tag_picker_sheet.dart`).

Not yet built: hand-testing sync through the app UI on two devices. Update the sections above as those decisions are made,
so this file stays accurate for future agent sessions.

### Testing gotchas (drift + Riverpod + flutter_test)

- Any widget test that renders a `TextField` must set
  `EditableText.debugDeterministicCursor = true` in `setUp` (and reset to
  `false` in `tearDown`) — otherwise the cursor-blink `Timer` is still
  armed when the test ends and trips flutter_test's pending-timer check.
- A test that tears down a widget tree containing a drift `Stream` query
  (e.g. via a Riverpod `StreamProvider`) must explicitly dispose the tree
  itself and pump with a non-zero duration afterwards (see `_disposeTree`
  in `test/widget_test.dart`) — disposing the query schedules a
  zero-duration `Timer` that needs a real elapse to flush, which
  flutter_test's automatic end-of-test teardown doesn't give it.
- When testing an `autoDispose` provider with a `ProviderContainer`
  directly (no widget tree), insert/seed data *before* calling
  `container.listen`/`container.read` on it. Subscribing first and then
  writing races the provider's first stream emission against the write —
  `.future` can resolve on an early emission and silently miss later
  writes. Pin autoDispose providers alive for the test with
  `container.listen(provider, (_, _) {})` (see
  `test/features/library/papers_providers_test.dart`).
- To assert a live update *after* a write you've already subscribed to
  (e.g. "linking a paper updates the note's chip list"), don't call bare
  `container.read(provider)` then `container.listen(...)` — the gap
  between them lets autoDispose tear the provider down mid-load and
  reject with "disposed during loading state". Use a single
  `container.listen(provider, callback, fireImmediately: true)` and
  resolve a `Completer` once the callback sees the value you're waiting
  for (see `waitFor` in `test/features/notes/note_papers_providers_test.dart`).
- **Never `ref.read` an `autoDispose` provider that owns a resource and
  keep the result** (a recorder, a player, a controller). With no listener
  Riverpod disposes it right after the read, running its `onDispose` —
  1.5.0/1.5.1 shipped a voice recorder that was disposed before it could
  record. Hold it with `ref.listenManual(...)` (closed automatically with
  the widget) or `ref.watch`. Test overrides must mirror production
  disposal (`overrideWith((ref) { ref.onDispose(fake.dispose); … })`),
  not `overrideWithValue`, or the bug can't show up in tests.
- **Always create test databases via `AppDatabase.inMemoryForTesting()`**,
  never `AppDatabase.forTesting(NativeDatabase.memory())` directly. SQLite
  has foreign key enforcement off by default *per connection*; without
  turning it on, `ON DELETE SET NULL`/`CASCADE` silently don't fire and a
  test asserting that behavior passes for the wrong reason (or, as
  happened here, fails because the FK action never ran). The factory
  enables `PRAGMA foreign_keys = ON` in its `setup` callback so every test
  gets real FK behavior by default.
