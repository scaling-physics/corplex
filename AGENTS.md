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

1. **Rich-text notes (built)** — folders/tags, Quill rich-text editor.
   Remaining: `[[wikilinks]]` with a backlinks panel, and Markdown export.
2. **PDF import & annotation (built, needs rework)** — freeform ink
   highlighting exists. Remaining: **text-selection highlights** using
   pdfrx's text layer, each anchored to a page with an optional comment, so
   "extract to note" inserts the quoted text plus a link back to the paper
   and page rather than a screenshot. Ink stays as a second mode. Also:
   resume at last-read page, and a per-paper Highlights list.
3. **Citation management (partly built)** — APA/MLA/BibTeX formatting
   exists. Remaining: BibTeX import, **metadata lookup from DOI/arXiv ID**
   (Crossref/arXiv; strictly optional online, manual entry always works),
   title/DOI extraction from an imported PDF, duplicate-paper detection, and
   structured author names (needed for correct citation styles).
4. **Paper & note attachments (built)** — audio (e.g. NotebookLM audio
   overviews) with an in-app player and tap-to-seek timestamps in notes,
   podcast links, images, arbitrary files.
5. **Library tab (built)** — remaining: full-text search (SQLite FTS5) over
   notes, highlights, and paper metadata; reading status (to read /
   reading / done).
6. **Projects/collections** — a named group of papers and notes (one per
   literature review or thesis chapter). Must stay invisible until the user
   creates one, like folders/tags.
7. **Capture from other apps** — iOS/Android share-sheet import for PDFs
   and links, so adding a paper is a couple of taps.
8. **Data safety** — full export/backup (database + files as a zip), trash
   with undo instead of immediate delete, and data-preserving schema
   migrations (the destructive v3 migration must not be repeated once real
   users exist).
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

- **File storage limits**: files upload whole, unconditionally, and
  download eagerly (fully in memory) on every device. Decide size limits,
  Wi-Fi-only transfer, lazy download-on-open, and cleanup of storage
  objects orphaned when a paper/attachment is deleted (none today).
- **Clock skew**: last-write-wins trusts each device's clock. A device with
  a badly wrong clock can lose (or win) edits it shouldn't.
- **Handwriting to text**: sketches stay drawings. iPadOS Scribble works
  in plain `TextField`s (note/paper titles) for free, but not inside the
  Quill body; converting ink to text would need on-device recognition
  (e.g. ML Kit Digital Ink) — undecided.

## Later releases

Ordered roughly by value to the core loop. None of these should add UI to
the default screens until the user opts in by using the feature.

### v1.1 — Literature review depth
- Synthesis matrix: a table of papers × user-defined themes (method,
  sample, findings), filled from notes/highlights.
- Inline citations in notes (`[@citekey]`) with stable citekeys, and a
  generated bibliography per note or project.
- Highlight-to-quote blocks; literature-note templates (summary / method /
  findings / critique).
- Import from RIS and Zotero/Mendeley exports.

### v1.2 — Writing output
- Export a note or project to Markdown, DOCX, or PDF with the bibliography
  resolved.
- Real citation styles via CSL (citeproc) rather than hand-written
  formatters.

### v1.3 — iPad & pen
- Split view: PDF beside note, as a first-class layout.
- Pen input in notes is built (sketch blocks, see Status). Still to do:
  handwriting-to-text, Apple Pencil double-tap to switch tools, hover.
- Multiple windows, drag and drop between apps, hardware keyboard
  shortcuts. Android stylus support.

### v1.4 — Reading comfort
- Dark/sepia reading mode, PDF outline/table of contents, cross-paper
  Highlights view, ratings/priority.
- App-wide dark mode, Dynamic Type/accessibility audit, localization.

### Exploratory (needs a decision before any work)
- AI assistance (summarize a paper, ask questions across the library). This
  conflicts with offline-first, so it would be strictly additive and
  opt-in, like sync. Not committed.

### Engineering (ongoing, start now)
- CI running `flutter analyze` and `flutter test` on every push.
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
- **Primary actions**: each tab's main action is one labelled extended FAB
  owned by `HomeShell` (`New note` / `Import PDF`), morphing between tabs.
  The actions themselves are top-level functions (`createNote`,
  `importPaper`) next to their screens.

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
  as a "Referenced in notes" list on the paper detail screen.
- **Citations**: `lib/features/library/citation_formatter.dart` formats a
  `Paper` as APA/MLA/BibTeX (pure function, no widget dependency — easy to
  unit test). Paper detail screen has a style picker and a copy-to-clipboard
  button. Author name parsing is intentionally naive (uses the raw
  `authors` string as-is); revisit if per-author formatting is needed.

- **PDF viewing & annotation**: `lib/features/library/pdf_viewer_screen.dart`
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
  free instead of us reimplementing a transform. "Extract to note"
  screenshots the whole viewer (`RepaintBoundary` + `toImage`), saves it
  as a note image attachment, and auto-links the note to the paper — it
  captures whatever's currently visible on screen, not a precisely
  cropped single page.
- **Note attachments UI**: the note editor now renders its own
  attachments (`lib/features/notes/note_attachments_providers.dart`) as
  image thumbnails or file chips below the linked-paper chips — added
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
  * **Conflicts** are last-write-wins per row on client `updated_at`,
    enforced on both ends (server `sync_guard` trigger; client `_apply`).
    Two devices editing the same note offline: the later edit wins
    wholesale — no merging. Device clocks are trusted for this.
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
  playback stops, so don't await it. Not built yet: background/lock-screen
  playback controls (`just_audio_background`), share-sheet import.
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
- **Rich text**: notes use `flutter_quill` instead of a plain `TextField`.
  `lib/features/notes/note_content.dart` is the single place that
  encodes/decodes a note's `content` column: it's Quill Delta JSON now,
  with `decodeNoteContent` falling back to treating the string as plain
  text if it isn't valid JSON (covers notes created before rich text
  existed, or any malformed content) so nothing crashes on old data.
  `notePlainTextPreview` extracts a flattened one-line preview for the
  Notes list without spinning up a full `QuillController`. The toolbar
  (`QuillSimpleToolbar` in `note_editor_screen.dart`, pinned to
  `bottomNavigationBar` rather than above the content, so it sits near
  the keyboard) is deliberately pared down from Quill's defaults — no
  font/size/color pickers, alignment, code block, or link button — to
  match the "no distractions" principle; only bold/italic/underline/
  strikethrough, headers, lists, and quote are exposed. **Important**:
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

Not yet built: hand-testing sync through the app UI on two devices, storage
cleanup for deleted files, and BibTeX *import*. Update the sections above as those decisions are made,
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
