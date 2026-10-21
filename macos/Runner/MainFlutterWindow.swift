import Cocoa
import FlutterMacOS
import PDFKit
import Carbon.HIToolbox

// MARK: Menu titles

/// German menu titles, picked by the system's first language. A table in
/// code rather than .strings files: no project-file changes, and the Dart
/// side (`shortcutSections`, lib/features/home/keyboard_shortcuts.dart) uses
/// the same wording. English is the key.
private let germanMenuTitles: [String: String] = [
  "File": "Ablage", "Edit": "Bearbeiten", "Format": "Format", "View": "Darstellung",
  "Go": "Gehe zu", "Window": "Fenster", "Help": "Hilfe",
  "Settings…": "Einstellungen…",
  "New Note": "Neue Notiz", "New Note from Template…": "Neue Notiz aus Vorlage…",
  "Today's Note": "Heutige Notiz", "Import PDF…": "PDF importieren…",
  "Import References…": "Literaturangaben importieren…",
  "Duplicate Note": "Notiz duplizieren", "Back Up to a File…": "In Datei sichern…",
  "Import Markdown…": "Markdown importieren…",
  "Export as Markdown…": "Als Markdown exportieren…", "Lock Note": "Notiz sperren",
  "Close All Locked Notes": "Alle gesperrten Notizen schließen",
  "Move to Trash": "In den Papierkorb legen", "Show Trash": "Papierkorb anzeigen",
  "Print…": "Drucken…", "Close Window": "Fenster schließen",
  "Close Pane": "Bereich schließen",
  "Find": "Suchen", "Find…": "Suchen…", "Find Next": "Nächster Treffer",
  "Find Previous": "Vorheriger Treffer",
  "Title": "Titel", "Heading": "Überschrift", "Subheading": "Zwischenüberschrift",
  "Body": "Fließtext", "Monospaced": "Monospace", "Bulleted List": "Aufzählung",
  "Numbered List": "Nummerierte Liste", "Checklist": "Checkliste",
  "Block Quote": "Zitatblock", "Table": "Tabelle", "Bold": "Fett", "Italic": "Kursiv",
  "Underline": "Unterstrichen", "Strikethrough": "Durchgestrichen", "Highlight": "Markieren",
  "Link to Note…": "Mit Notiz verknüpfen…", "Cite Paper…": "Paper zitieren…",
  "Add Comment…": "Kommentar hinzufügen…", "Footnote": "Fußnote",
  "Notes": "Notizen", "Library": "Bibliothek", "Attachments": "Anhänge", "Search": "Suchen",
  "Toggle Sidebar": "Seitenleiste ein-/ausblenden",
  "Outline": "Gliederung",
  "Collapse All Sections": "Alle Abschnitte einklappen",
  "Expand All Sections": "Alle Abschnitte ausklappen", "Zoom In": "Vergrößern",
  "Zoom Out": "Verkleinern", "Actual Size": "Originalgröße",
  "Interface Size": "Oberflächengröße", "Larger": "Größer", "Smaller": "Kleiner",
  "Default Size": "Standardgröße", "Back": "Zurück", "Forward": "Vorwärts",
  "Keyboard Shortcuts": "Tastaturkurzbefehle",
  "Go to…": "Gehe zu…", "Previous Heading": "Vorherige Überschrift",
  "Next Heading": "Nächste Überschrift", "Open Link": "Link öffnen",
]

private let usesGerman: Bool =
  Locale.preferredLanguages.first.map { $0.hasPrefix("de") } ?? false

/// [english] in the system language (English unless it is German).
func menuTitle(_ english: String) -> String {
  usesGerman ? (germanMenuTitles[english] ?? english) : english
}

/// The one Corplex window. Content runs under a transparent title bar (the
/// Flutter side leaves a `macTitleBarHeight` strip at the top of each
/// column, so the traffic lights sit on the sidebar and the strip still
/// drags the window), the window remembers where it was, and the menu bar
/// carries the app's commands. Menu items and window events reach Dart on
/// the `corplex/window` channel (`lib/features/platform/mac_window.dart`).
class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var channel: FlutterMethodChannel?

  /// Captures (Quick Note hotkey, Services, Dock menu) that arrived before
  /// Dart said it was listening: a cold start through the Services menu
  /// delivers the text before the first frame. Each is a method name and
  /// its argument for the `corplex/window` channel.
  private var pendingCaptures: [(String, Any?)] = []
  private var dartReady = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    styleMask.insert(.fullSizeContentView)
    // An empty unified toolbar makes the title bar the height of Notes'
    // toolbar row (the traffic lights move down to its middle); Flutter
    // draws the toolbar's controls in that band and still gets the clicks.
    // Pages pushed over home hide it (`setToolbar`), back to the slim bar.
    let toolbar = NSToolbar(identifier: "CorplexToolbar")
    toolbar.showsBaselineSeparator = false
    self.toolbar = toolbar
    toolbarStyle = .unified
    tabbingMode = .disallowed
    minSize = NSSize(width: 720, height: 520)
    // A first launch opens at a comfortable size for reading beside notes,
    // in proportion to the screen: ~1320×860 on a laptop, about 2100×1180
    // on a 38" 3840×1600 ultrawide. After that the saved frame wins.
    if !setFrameUsingName("CorplexMainWindow") {
      let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
      let size = NSSize(
        width: min(max(1320, screen.width * 0.55), screen.width - 80, 2400),
        height: min(max(860, screen.height * 0.75), screen.height - 60))
      setFrame(NSRect(origin: .zero, size: size), display: false)
      center()
    }
    setFrameAutosaveName("CorplexMainWindow")
    delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    registerNativeChannels(messenger)

    let channel = FlutterMethodChannel(name: "corplex/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "startDrag":
        if let event = self.currentEvent { self.performDrag(with: event) }
        result(nil)
      case "zoom":
        self.performZoom(nil)
        result(nil)
      case "setToolbar":
        // Shows or hides the toolbar row; answers the band's new height.
        self.toolbar?.isVisible = call.arguments as? Bool ?? true
        result(self.titleBandHeight())
      case "titleBandHeight":
        result(self.titleBandHeight())
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      case "captureReady":
        // Dart is listening: hand over anything that arrived before.
        self.dartReady = true
        let queued = self.pendingCaptures
        self.pendingCaptures = []
        for (method, argument) in queued { self.channel?.invokeMethod(method, arguments: argument) }
        result(nil)
      case "setQuickNoteHotKey":
        result(QuickNoteHotKey.shared.set(enabled: call.arguments as? Bool ?? false))
      case "printPdf":
        // File → Print…: the note rendered by the PDF exporter, through
        // the standard print panel as a sheet on this window.
        guard let args = call.arguments as? [String: Any],
          let data = (args["pdf"] as? FlutterStandardTypedData)?.data,
          let document = PDFDocument(data: data),
          let operation = document.printOperation(
            for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
        else { return result(false) }
        operation.jobTitle = args["title"] as? String ?? "Corplex"
        operation.runModal(for: self, delegate: nil, didRun: nil, contextInfo: nil)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    buildMenus()

    // Services → "New Corplex Note" (the NSServices entry in Info.plist
    // names `newCorplexNote`), and the hotkey's callback.
    NSApp.servicesProvider = self
    NSUpdateDynamicServices()
    QuickNoteHotKey.shared.onPress = { [weak self] in self?.capture("capture", "newNote") }

    super.awakeFromNib()
  }

  // MARK: Quick capture

  /// Brings the app and this window forward (from the background, the Dock
  /// or a minimised state).
  func bringForward() {
    NSApp.activate(ignoringOtherApps: true)
    if isMiniaturized { deminiaturize(nil) }
    makeKeyAndOrderFront(nil)
  }

  /// Activates Corplex and tells Dart, or queues the message until Dart is
  /// listening.
  func capture(_ method: String, _ argument: Any?) {
    bringForward()
    if dartReady {
      channel?.invokeMethod(method, arguments: argument)
    } else {
      pendingCaptures.append((method, argument))
    }
  }

  /// The Services entry: the selected text in any app becomes a note (or a
  /// paper or link, by what it looks like) through the same path as the
  /// share sheet.
  @objc func newCorplexNote(
    _ pboard: NSPasteboard, userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    let text =
      pboard.string(forType: .string)
      ?? pboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
    guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      error.pointee = "There was no text to save." as NSString
      return
    }
    capture("capture", ["text": text])
  }

  @objc func dockNewNote(_ sender: Any?) { capture("capture", "newNote") }

  // MARK: Full screen (the title bar strip collapses there)

  /// The height of the title-bar band Flutter must leave for the traffic
  /// lights: twice the distance from the top to the buttons' middle, which
  /// holds for the slim title bar and the toolbar row on every macOS.
  func titleBandHeight() -> Double {
    contentView?.superview?.layoutSubtreeIfNeeded()
    guard let button = standardWindowButton(.closeButton) else { return 28 }
    let rect = button.convert(button.bounds, to: nil)
    return Double((frame.height - rect.midY) * 2).rounded()
  }

  func windowWillEnterFullScreen(_ notification: Notification) {
    channel?.invokeMethod("fullScreen", arguments: true)
  }

  func windowWillExitFullScreen(_ notification: Notification) {
    channel?.invokeMethod("fullScreen", arguments: false)
  }

  // MARK: Menus

  @objc private func menuCommand(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    channel?.invokeMethod("menu", arguments: id)
  }

  private func item(
    _ title: String, _ id: String, key: String = "",
    modifiers: NSEvent.ModifierFlags = .command
  ) -> NSMenuItem {
    let item = NSMenuItem(
      title: menuTitle(title), action: #selector(menuCommand(_:)), keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.representedObject = id
    item.target = self
    return item
  }

  private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let top = NSMenuItem(title: menuTitle(title), action: nil, keyEquivalent: "")
    let menu = NSMenu(title: menuTitle(title))
    items.forEach(menu.addItem)
    top.submenu = menu
    return top
  }

  /// Rewires the template's menu bar: Settings… and the File, Format and
  /// Go menus reach Dart; the Edit menu keeps what Flutter text fields
  /// answer to plus Find; View gains the spaces, sidebar and zoom. Shortcuts
  /// follow Apple's apps (Format matches Notes). Every item sends its id on
  /// `corplex/window`; Dart offers it to the focused widget first.
  private func buildMenus() {
    guard let main = NSApp.mainMenu else { return }
    let shift: NSEvent.ModifierFlags = [.command, .shift]
    let backspace = String(Character(UnicodeScalar(NSBackspaceCharacter)!))

    if let appMenu = main.items.first?.submenu,
      let prefs = appMenu.items.first(where: { $0.keyEquivalent == "," })
    {
      prefs.title = menuTitle("Settings…")
      prefs.action = #selector(menuCommand(_:))
      prefs.target = self
      prefs.representedObject = "settings"
    }

    let file = menu(
      "File",
      [
        item("New Note", "newNote", key: "n"),
        item("New Note from Template…", "newNoteFromTemplate"),
        item("Today's Note", "todaysNote", key: "t"),
        item("Import PDF…", "importPdf", key: "o"),
        item("Import References…", "importReferences"),
        item("Duplicate Note", "duplicateNote", key: "d"),
        .separator(),
        item("Back Up to a File…", "backup"),
        item("Import Markdown…", "importMarkdown"),
        item("Export as Markdown…", "exportMarkdown"),
        .separator(),
        item("Lock Note", "lockNote"),
        item("Close All Locked Notes", "lockAllNotes"),
        .separator(),
        item("Move to Trash", "moveToTrash", key: backspace),
        item("Show Trash", "trash"),
        .separator(),
        item("Print…", "printNote", key: "p"),
        .separator(),
        item("Close Pane", "closePane", key: "w"),
        {
          let closeWindow = NSMenuItem(
            title: menuTitle("Close Window"), action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
          closeWindow.keyEquivalentModifierMask = [.command, .shift]
          return closeWindow
        }(),
      ])
    main.insertItem(file, at: 1)

    // The template's menus are found by what they contain, not by title:
    // AppKit may already have translated the titles.
    let editItem = main.items.first {
      $0.submenu?.items.contains { $0.action == #selector(NSText.copy(_:)) } ?? false
    }
    if let edit = editItem?.submenu {
      editItem?.title = menuTitle("Edit")
      edit.title = menuTitle("Edit")
      // Spelling, substitutions, transformations and speech act on AppKit
      // text views, which Flutter's editors aren't; AppKit's Find is
      // replaced by ours, which reaches the focused document. All of them
      // (and only they) are submenus.
      for found in edit.items where found.hasSubmenu { edit.removeItem(found) }
      while let last = edit.items.last, last.isSeparatorItem { edit.removeItem(last) }
      edit.addItem(.separator())
      edit.addItem(
        menu(
          "Find",
          [
            item("Find…", "find", key: "f"),
            item("Find Next", "findNext", key: "g"),
            item("Find Previous", "findPrevious", key: "g", modifiers: shift),
          ]))
    }

    let format = menu(
      "Format",
      [
        item("Title", "title", key: "t", modifiers: shift),
        item("Heading", "heading", key: "h", modifiers: shift),
        item("Subheading", "subheading", key: "j", modifiers: shift),
        item("Body", "body", key: "b", modifiers: shift),
        item("Monospaced", "monospaced", key: "m", modifiers: shift),
        .separator(),
        item("Bulleted List", "bulletList", key: "7", modifiers: shift),
        item("Numbered List", "numberedList", key: "9", modifiers: shift),
        item("Checklist", "checklist", key: "l", modifiers: shift),
        item("Block Quote", "blockQuote", key: "'"),
        item("Table", "insertTable", key: "t", modifiers: [.command, .option]),
        .separator(),
        item("Bold", "bold", key: "b"),
        item("Italic", "italic", key: "i"),
        item("Underline", "underline", key: "u"),
        item("Strikethrough", "strikethrough", key: "x", modifiers: shift),
        item("Highlight", "highlight", key: "e", modifiers: shift),
        .separator(),
        item("Link to Note…", "linkNote", key: "k"),
        item("Cite Paper…", "citePaper", key: "k", modifiers: shift),
        item("Add Comment…", "addComment", key: "k", modifiers: [.command, .option]),
        item("Footnote", "footnote", key: "f", modifiers: [.command, .option]),
        item("Open Link", "openLink", key: "l"),
      ])
    let viewItem = main.items.first {
      $0.submenu?.items.contains { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }
        ?? false
    }
    if let viewItem = viewItem, let viewIndex = main.items.firstIndex(of: viewItem) {
      main.insertItem(format, at: viewIndex)
    }

    if let view = viewItem?.submenu {
      viewItem?.title = menuTitle("View")
      view.title = menuTitle("View")
      let entries = [
        item("Notes", "showNotes", key: "1"),
        item("Library", "showLibrary", key: "2"),
        item("Attachments", "showAttachments", key: "3"),
        item("Search", "search", key: "f", modifiers: shift),
        .separator(),
        item("Toggle Sidebar", "toggleSidebar", key: "s", modifiers: [.command, .control]),
        .separator(),
        item("Outline", "outline", key: "o", modifiers: [.command, .control]),
        item("Collapse All Sections", "collapseSections"),
        item("Expand All Sections", "expandSections"),
        .separator(),
        item("Zoom In", "zoomIn", key: "+"),
        item("Zoom Out", "zoomOut", key: "-"),
        item("Actual Size", "actualSize", key: "0"),
        menu(
          "Interface Size",
          [
            item("Larger", "interfaceLarger", key: "+", modifiers: [.command, .option]),
            item("Smaller", "interfaceSmaller", key: "-", modifiers: [.command, .option]),
            item("Default Size", "interfaceDefault", key: "0", modifiers: [.command, .option]),
          ]),
        .separator(),
      ]
      for (i, entry) in entries.enumerated() { view.insertItem(entry, at: i) }
    }

    let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    let go = menu(
      "Go",
      [
        item("Back", "back", key: "["), item("Forward", "forward", key: "]"),
        .separator(),
        item("Go to…", "goTo", key: "k"),
        item("Previous Heading", "previousHeading", key: up, modifiers: [.command, .option]),
        item("Next Heading", "nextHeading", key: down, modifiers: [.command, .option]),
      ])
    let windowItem = main.items.first { $0.submenu === NSApp.windowsMenu }
    if let windowItem = windowItem, let windowIndex = main.items.firstIndex(of: windowItem) {
      main.insertItem(go, at: windowIndex)
      windowItem.title = menuTitle("Window")
      windowItem.submenu?.title = menuTitle("Window")
    }

    if let help = main.items.first(where: { $0.submenu === NSApp.helpMenu }) {
      help.title = menuTitle("Help")
      let menu = NSMenu(title: menuTitle("Help"))
      menu.addItem(item("Keyboard Shortcuts", "keyboardShortcuts", key: "/"))
      help.submenu = menu
      NSApp.helpMenu = menu
    }
  }
}

/// The global Quick Note hotkey, ⌃⌥N. Carbon's `RegisterEventHotKey` needs
/// no Accessibility permission and works in the sandbox. Registered only
/// while Dart asks (the per-device setting).
final class QuickNoteHotKey {
  static let shared = QuickNoteHotKey()

  var onPress: (() -> Void)?
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?

  /// Registers or unregisters the hotkey. False if it's wanted but taken.
  func set(enabled: Bool) -> Bool {
    if !enabled {
      if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
      hotKey = nil
      return false
    }
    if hotKey != nil { return true }
    if handler == nil {
      var spec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let status = InstallEventHandler(
        GetApplicationEventTarget(),
        { _, _, _ in
          DispatchQueue.main.async { QuickNoteHotKey.shared.onPress?() }
          return noErr
        }, 1, &spec, nil, &handler)
      if status != noErr { return false }
    }
    let id = EventHotKeyID(signature: OSType(0x43504C58), id: 1)  // 'CPLX'
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id,
      GetApplicationEventTarget(), 0, &ref)
    guard status == noErr else { return false }
    hotKey = ref
    return true
  }
}
