<p align="center">
  <img src="assets/branding/icon.png" width="112" alt="Corplex icon: a folded, annotated page on sage green">
</p>

<h1 align="center">Corplex</h1>

<p align="center">
  <b>Read, annotate, take notes and cite — in one calm place.</b><br>
  A notes and literature-review app for iPad, iPhone and Android.
</p>

---

Research tends to scatter: the PDF in one app, highlights in another, your
thoughts in a third, and the reference list rebuilt by hand at the end.
Corplex keeps that whole loop together. You read a paper, mark what
matters, pull it into your notes with a link back to the page, and cite it
— and the bibliography writes itself.

It works fully offline. Sync across your devices is there if you want it,
never required.

## How it works

<table>
<tr>
<td width="50%" align="center"><img src="docs/demo/capture.gif" width="300" alt="Creating a note"></td>
<td width="50%">

### Capture a thought in seconds

Tap **New note**, give it a title and start writing. There's no save
button and no note "type" to pick — it saves as you type, and you can mix
text, headings, lists, quotes, images, audio and drawings in the same
note.

</td>
</tr>
<tr>
<td width="50%">

### Bring in a paper

In **Library**, tap **Import PDF** and pick the file. Type its DOI or
arXiv ID and tap **Look up** — Corplex fills in the authors, venue and
year, and every citation style (APA, MLA, Chicago, Harvard, IEEE,
BibTeX) is ready to copy.

You can also share a PDF or a link *into* Corplex from other apps on
Android, or import a whole reference library from Zotero, Mendeley or
EndNote (BibTeX, RIS or CSL JSON).

</td>
<td width="50%" align="center"><img src="docs/demo/import.gif" width="300" alt="Importing a paper and looking up its details"></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/demo/quote.gif" width="300" alt="Selecting text in a PDF and quoting it into a note"></td>
<td width="50%">

### Read, highlight, quote

Open the PDF, press and hold to select a passage, then choose
**Highlight** or **Quote to note**. The quote lands in your note with a
**p. 1** link — tap it later to jump straight back to that page. The
paper reopens where you stopped reading.

On a big screen, **Read with a note** puts the PDF and your note side by
side, and quotes drop straight into the open note.

</td>
</tr>
<tr>
<td width="50%">

### Cite as you write

Type **[@** anywhere in a note to cite a paper from your library. When
you're done, choose **More → Add bibliography** and pick a style — the
reference list is written for you, and updated if you run it again.

**More → Export** turns a note (or a whole project) into Markdown, Word
or PDF with the citations and references resolved.

</td>
<td width="50%" align="center"><img src="docs/demo/cite.gif" width="300" alt="Citing a paper and adding a bibliography"></td>
</tr>
<tr>
<td width="50%" align="center"><img src="docs/demo/sketch.gif" width="300" alt="Drawing a sketch inside a note"></td>
<td width="50%">

### Think with a pen

Tap **Draw** to add a sketch anywhere in a note — with Apple Pencil, a
stylus, or your finger. Pen, highlighter and eraser, a few calm inks,
undo and redo. Once a pen touches the screen, your resting palm is
ignored. On iPad, Pencil double-tap follows your iPadOS setting.

</td>
</tr>
</table>

## And quietly, when you need them

- **Projects** — group the papers and notes for one review or chapter.
  Each project has a **synthesis matrix** (papers × themes like method,
  sample, findings) that you can fill from your highlights.
- **Search everything** — notes, papers and highlights, as you type.
- **Audio** — attach a NotebookLM audio overview or a lecture recording,
  play it while you read, and drop tappable timestamps into your notes.
- **Reading comfort** — sepia and night pages, the PDF's table of
  contents, star ratings, reading status, dark mode.
- **Your data is safe** — deleted items go to a trash you can undo from,
  and you can back up everything to a single file and restore it.

None of this adds clutter until you use it: no badges, no banners, no
setup screens.

## Install

Corplex is in active development and not yet in the app stores.

- **Android** — test builds are published as APKs on the
  [Releases](../../releases) page when available; open one on your device
  (you may need to allow installing apps from your browser). Or build it
  yourself (below).
- **iPad and iPhone** — each release also has an unsigned `.ipa`. Install
  it with a free sideloading tool such as [Sideloadly](https://sideloadly.io)
  or AltStore, which signs it with your own Apple ID (the release notes
  walk through it). On iPad, Corplex uses a proper tablet layout: a side
  rail, and in landscape your list and the open note or paper side by
  side. An App Store release is planned.

## Sync between devices (optional)

Everything works without an account. To keep your library in step
across devices, Corplex can sync to your own free
[Supabase](https://supabase.com) project — your notes, papers and files
stay in a database you control. Sign in from the account button in the
top right; the setup for the server side is in
[`AGENTS.md`](AGENTS.md#status) under *Supabase config*.

## Build it yourself

You'll need [Flutter](https://docs.flutter.dev/get-started/install)
(3.47 or newer).

```sh
git clone https://github.com/scaling-physics/corplex.git
cd corplex
flutter pub get
flutter run                  # on a connected device or emulator
flutter build apk --release  # an installable Android build
```

To build with sync, add your project's URL and publishable key:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<your publishable key>
```

`flutter test` runs the test suite. How the app is built — the design
principles, architecture and decisions — is written up in
[`AGENTS.md`](AGENTS.md).
