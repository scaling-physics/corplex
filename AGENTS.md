# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## Project

Corplex is a notes and literature review app for iPadOS, iOS, and Android, built
from a single Flutter codebase. It combines rich-text note taking, PDF import
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

- **Framework**: Flutter (Dart) — one codebase for iPadOS, iOS, and Android.
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
- Integration tests on real devices; a performance pass with 1,000+ papers
  and large PDFs.
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
- **Pen input** (`lib/features/ink/`): a note can hold any number of
  sketch blocks between its paragraphs — the "Draw" button (first in the
  editor's bottom toolbar) inserts one at the cursor and opens
  `SketchEditorScreen`; tap a sketch to draw on it again. A sketch is a
  Quill `CustomBlockEmbed('sketch', json)` rendered by
  `SketchEmbedBuilder`, so it lives in the note's `content` and syncs
  with it (no new table). **Insert `CustomBlockEmbed` directly**, never
  `BlockEmbed.custom(...)`, which wraps it as type `custom` that the
  builder's key won't match. Strokes (`ink_model.dart`) are stored in
  canvas-width units with per-point pressure, so they render identically
  at any size; `Sketch.encode` rounds to 4 decimals to keep synced notes
  small. Apple Pencil and Android pens both arrive as
  `PointerDeviceKind.stylus` with pressure. **Palm rejection**
  (`InkInputPolicy`): fingers draw until a stylus is seen, then fingers
  scroll and never draw (toggle in the editor's app bar); a pen's
  eraser end (`invertedStylus`) always erases. Eraser removes whole
  strokes; one gesture = one undo step (`onGestureStart`). The canvas
  keeps its own working copy while erasing, since pointer moves can
  outrun parent rebuilds. Sketch paper is light in both themes so ink
  colors read the same everywhere. Test with real stylus events:
  `adb shell input stylus swipe …` on the emulator,
  `startGesture(kind: PointerDeviceKind.stylus)` in widget tests.
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
- **Always create test databases via `AppDatabase.inMemoryForTesting()`**,
  never `AppDatabase.forTesting(NativeDatabase.memory())` directly. SQLite
  has foreign key enforcement off by default *per connection*; without
  turning it on, `ON DELETE SET NULL`/`CASCADE` silently don't fire and a
  test asserting that behavior passes for the wrong reason (or, as
  happened here, fails because the FK action never ran). The factory
  enables `PRAGMA foreign_keys = ON` in its `setup` callback so every test
  gets real FK behavior by default.
