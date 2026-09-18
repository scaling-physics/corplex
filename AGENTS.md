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
  assume a live backend connection.
- **State management**: Riverpod (`flutter_riverpod`), chosen for its
  natural fit with drift's `Stream`-based reactive queries. `AppDatabase`
  is exposed via `databaseProvider` (`lib/data/database_provider.dart`);
  feature-specific providers live next to their feature, e.g.
  `lib/features/notes/notes_providers.dart`. Root widget must stay wrapped
  in `ProviderScope` (see `lib/main.dart`).

## Core v1 features

1. Rich-text note taking — folders/tags, markdown or rich-text editor,
   backlinks between notes.
2. PDF import & annotation — import papers as PDF, highlight/annotate,
   extract highlights into notes.
3. Citation management — store metadata (authors, year, journal, DOI),
   generate citations (APA/MLA/etc.), BibTeX import/export.
4. Cross-device sync — notes and library sync across iPhone/iPad/Android
   (design so local-first storage remains the source of truth).
5. Paper attachments — attach external media to a paper's record, e.g. a
   NotebookLM-style audio/podcast summary, links, or other files, so all
   material related to a paper lives in one place.
6. Library tab — a dedicated, searchable tab that automatically aggregates
   every paper referenced across notes/citations, giving quick access to
   each paper and its attachments without hunting through individual notes.

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

Not yet built: BibTeX *import* and the sync backend. Update the sections
above as those decisions are made, so this file stays accurate for
future agent sessions.

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
