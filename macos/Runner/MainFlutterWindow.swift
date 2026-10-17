import Cocoa
import FlutterMacOS

/// The one Corplex window. Content runs under a transparent title bar (the
/// Flutter side leaves a `macTitleBarHeight` strip at the top of each
/// column, so the traffic lights sit on the sidebar and the strip still
/// drags the window), the window remembers where it was, and the menu bar
/// carries the app's commands. Menu items and window events reach Dart on
/// the `corplex/window` channel (`lib/features/platform/mac_window.dart`).
class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var channel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    styleMask.insert(.fullSizeContentView)
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
      case "isFullScreen":
        result(self.styleMask.contains(.fullScreen))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    buildMenus()

    super.awakeFromNib()
  }

  // MARK: Full screen (the title bar strip collapses there)

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
    let item = NSMenuItem(title: title, action: #selector(menuCommand(_:)), keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.representedObject = id
    item.target = self
    return item
  }

  private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
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
      prefs.title = "Settings…"
      prefs.action = #selector(menuCommand(_:))
      prefs.target = self
      prefs.representedObject = "settings"
    }

    let file = menu(
      "File",
      [
        item("New Note", "newNote", key: "n"),
        item("Import PDF…", "importPdf", key: "o"),
        item("Import References…", "importReferences"),
        .separator(),
        item("Back Up to a File…", "backup"),
        item("Export as Markdown…", "exportMarkdown"),
        .separator(),
        item("Lock Note", "lockNote"),
        item("Close All Locked Notes", "lockAllNotes"),
        .separator(),
        item("Move to Trash", "moveToTrash", key: backspace),
        item("Show Trash", "trash"),
        .separator(),
        NSMenuItem(
          title: "Close Window", action: #selector(NSWindow.performClose(_:)),
          keyEquivalent: "w"),
      ])
    main.insertItem(file, at: 1)

    if let edit = main.items.first(where: { $0.title == "Edit" })?.submenu {
      // Spelling, substitutions, transformations and speech act on AppKit
      // text views, which Flutter's editors aren't; AppKit's Find is
      // replaced by ours, which reaches the focused document.
      for title in ["Find", "Spelling and Grammar", "Substitutions", "Transformations", "Speech"] {
        if let found = edit.items.first(where: { $0.title == title }) {
          edit.removeItem(found)
        }
      }
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
        .separator(),
        item("Bulleted List", "bulletList", key: "7", modifiers: shift),
        item("Numbered List", "numberedList", key: "9", modifiers: shift),
        item("Block Quote", "blockQuote", key: "'"),
        .separator(),
        item("Bold", "bold", key: "b"),
        item("Italic", "italic", key: "i"),
        item("Underline", "underline", key: "u"),
        item("Strikethrough", "strikethrough", key: "x", modifiers: shift),
        .separator(),
        item("Link to Note…", "linkNote", key: "k"),
        item("Cite Paper…", "citePaper", key: "k", modifiers: shift),
      ])
    if let viewIndex = main.items.firstIndex(where: { $0.title == "View" }) {
      main.insertItem(format, at: viewIndex)
    }

    if let view = main.items.first(where: { $0.title == "View" })?.submenu {
      let entries = [
        item("Notes", "showNotes", key: "1"),
        item("Library", "showLibrary", key: "2"),
        item("Search", "search", key: "f", modifiers: shift),
        .separator(),
        item("Toggle Sidebar", "toggleSidebar", key: "s", modifiers: [.command, .control]),
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

    let go = menu("Go", [item("Back", "back", key: "[")])
    if let windowIndex = main.items.firstIndex(where: { $0.title == "Window" }) {
      main.insertItem(go, at: windowIndex)
    }

    if let help = main.items.first(where: { $0.title == "Help" }) {
      let menu = NSMenu(title: "Help")
      menu.addItem(item("Keyboard Shortcuts", "keyboardShortcuts", key: "/"))
      help.submenu = menu
    }
  }
}
