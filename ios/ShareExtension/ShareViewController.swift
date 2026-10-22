import UIKit
import UniformTypeIdentifiers

/// Receives PDFs, audio, links and text from the system share sheet, parks
/// them in the App Group and opens Corplex. The record format and URL
/// scheme match what `receive_sharing_intent` reads in the app, so the
/// Dart side (`ShareCoordinator`) needs nothing extra.
///
/// This is deliberately self-contained rather than subclassing the plugin's
/// `RSIShareViewController`: with Swift Package Manager the plugin is only
/// linked into Runner, and pulling Flutter into an extension isn't allowed.
final class ShareViewController: UIViewController {
  private struct Item: Encodable {
    var path: String
    var mimeType: String?
    var type: String  // "file" | "url" | "text"
  }

  private var items: [Item] = []
  private let lock = NSLock()

  private var hostBundleId: String {
    let id = Bundle.main.bundleIdentifier ?? "dev.corplex.app.ShareExtension"
    return id.split(separator: ".").dropLast().joined(separator: ".")
  }

  private var appGroupId: String {
    (Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String)
      ?? "group.\(hostBundleId)"
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    collect()
  }

  private func collect() {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    guard !providers.isEmpty else { return finish(open: false) }

    let group = DispatchGroup()
    for provider in providers {
      group.enter()
      load(provider) { group.leave() }
    }
    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      self.finish(open: self.save())
    }
  }

  private func add(_ item: Item) {
    lock.lock()
    items.append(item)
    lock.unlock()
  }

  /// Files first (a PDF from Files arrives as a file URL), then web links,
  /// then plain text.
  private func load(_ provider: NSItemProvider, done: @escaping () -> Void) {
    let fileId = UTType.fileURL.identifier
    let urlId = UTType.url.identifier
    let textId = UTType.plainText.identifier

    if provider.hasItemConformingToTypeIdentifier(fileId) {
      provider.loadItem(forTypeIdentifier: fileId) { [weak self] data, _ in
        if let url = data as? URL, url.isFileURL {
          self?.addFile(url)
        } else if let url = data as? URL {
          self?.add(Item(path: url.absoluteString, mimeType: nil, type: "url"))
        }
        done()
      }
    } else if provider.hasItemConformingToTypeIdentifier(urlId) {
      provider.loadItem(forTypeIdentifier: urlId) { [weak self] data, _ in
        if let url = data as? URL {
          if url.isFileURL {
            self?.addFile(url)
          } else {
            self?.add(Item(path: url.absoluteString, mimeType: nil, type: "url"))
          }
        }
        done()
      }
    } else if provider.hasItemConformingToTypeIdentifier(textId) {
      provider.loadItem(forTypeIdentifier: textId) { [weak self] data, _ in
        if let text = data as? String {
          self?.add(Item(path: text, mimeType: "text/plain", type: "text"))
        }
        done()
      }
    } else if let typeId = provider.registeredTypeIdentifiers.first(where: {
      UTType($0)?.conforms(to: .pdf) == true || UTType($0)?.conforms(to: .audio) == true
    }) {
      // A file offered as raw data (no URL): copy it out.
      provider.loadFileRepresentation(forTypeIdentifier: typeId) { [weak self] url, _ in
        if let url { self?.addFile(url) }
        done()
      }
    } else {
      done()
    }
  }

  /// Copies a file into the App Group (the source is only readable while
  /// this extension runs).
  private func addFile(_ source: URL) {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupId)
    else { return }
    let started = source.startAccessingSecurityScopedResource()
    defer { if started { source.stopAccessingSecurityScopedResource() } }

    let name = source.lastPathComponent.isEmpty ? UUID().uuidString : source.lastPathComponent
    let dest = container.appendingPathComponent(name)
    do {
      if FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.copyItem(at: source, to: dest)
    } catch {
      return
    }
    let mime = UTType(filenameExtension: source.pathExtension)?.preferredMIMEType
    add(Item(path: dest.absoluteString, mimeType: mime, type: "file"))
  }

  private func save() -> Bool {
    guard !items.isEmpty,
      let defaults = UserDefaults(suiteName: appGroupId),
      let data = try? JSONEncoder().encode(items)
    else { return false }
    defaults.set(data, forKey: "ShareKey")
    defaults.removeObject(forKey: "ShareMessageKey")
    defaults.synchronize()
    return true
  }

  private func finish(open: Bool) {
    if open, let url = URL(string: "ShareMedia-\(hostBundleId):share") {
      // Extensions can't call UIApplication.shared; walk the responder chain.
      var responder: UIResponder? = self
      while let r = responder {
        if let app = r as? UIApplication {
          app.open(url, options: [:], completionHandler: nil)
          break
        }
        responder = r.next
      }
    }
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
