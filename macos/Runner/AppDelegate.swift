import AVFoundation
import Cocoa
import CoreSpotlight
import FlutterMacOS
import NaturalLanguage
import Speech
import Vision

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// A Spotlight result opened: hands its unique id (a Dart `NavTarget.key`)
  /// to Dart on `corplex/spotlight`, held until Dart says it is ready.
  override func application(
    _ application: NSApplication, continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
  ) -> Bool {
    if userActivity.activityType == CSSearchableItemActionType,
      let id = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
    {
      SpotlightBridge.shared.open(id)
      return true
    }
    return super.application(
      application, continue: userActivity, restorationHandler: restorationHandler)
  }

  /// Right-click the Dock icon → New Note (quick capture, like the ⌃⌥N
  /// hotkey).
  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    guard let window = NSApp.windows.compactMap({ $0 as? MainFlutterWindow }).first else {
      return nil
    }
    let menu = NSMenu()
    let item = NSMenuItem(
      title: menuTitle("New Note"),
      action: #selector(MainFlutterWindow.dockNewNote(_:)), keyEquivalent: "")
    item.target = window
    menu.addItem(item)
    return menu
  }
}

/// App-specific platform channels (OCR, speech), registered by
/// `MainFlutterWindow` once the engine exists. Each must create its SDK
/// objects lazily, on the first call — never here.
func registerNativeChannels(_ messenger: FlutterBinaryMessenger) {
  registerOcrChannel(messenger)
  registerSpeechChannel(messenger)
  registerSpellChannel(messenger)
  registerSpeakChannel(messenger)
  SpotlightBridge.shared.register(messenger)
}

private var speakChannel: FlutterMethodChannel?
private var speaker: Speaker?

private func registerSpeakChannel(_ messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(name: "corplex/speak", binaryMessenger: messenger)
  speakChannel = channel
  let handler = Speaker(channel)
  speaker = handler
  channel.setMethodCallHandler { call, result in handler.handle(call, result) }
}

private var ocrChannel: FlutterMethodChannel?
private var spellChannel: FlutterMethodChannel?
private var speechChannel: FlutterMethodChannel?
private var speechRecognizer: SFSpeechRecognizer?
private var speechTask: SFSpeechRecognitionTask?

/// On-device OCR (`corplex/ocr`): Apple Vision, accurate level with language
/// correction. Same contract as iOS: PNG bytes in, lines with word boxes as
/// fractions of the image (origin top-left) out. Vision objects are created
/// per call, never at registration.
private func registerOcrChannel(_ messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(name: "corplex/ocr", binaryMessenger: messenger)
  ocrChannel = channel
  channel.setMethodCallHandler { call, result in
    guard call.method == "recognize",
      let args = call.arguments as? [String: Any],
      let data = (args["image"] as? FlutterStandardTypedData)?.data,
      let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
      result(FlutterError(code: "bad_args", message: "Expected PNG bytes", details: nil))
      return
    }
    DispatchQueue.global(qos: .utility).async {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
      let handler = VNImageRequestHandler(cgImage: image, options: [:])
      do {
        try handler.perform([request])
        var lines: [[String: Any]] = []
        for observation in request.results ?? [] {
          guard let candidate = observation.topCandidates(1).first else { continue }
          let string = candidate.string
          var words: [[String: Any]] = []
          string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byWords) {
            _, range, _, _ in
            guard let box = try? candidate.boundingBox(for: range) else { return }
            let b = box.boundingBox
            words.append([
              "text": String(string[range]),
              "left": Double(b.minX), "right": Double(b.maxX),
              "top": Double(1 - b.maxY), "bottom": Double(1 - b.minY),
            ])
          }
          lines.append(["text": string, "words": words])
        }
        DispatchQueue.main.async { result(lines) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

/// Voice notes (`corplex/speech`): transcribe a finished recording on this
/// device only. Replies {status: ok|denied|unavailable, text}. The recogniser
/// and authorisation request are created on the first call.
private func registerSpeechChannel(_ messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(name: "corplex/speech", binaryMessenger: messenger)
  speechChannel = channel
  channel.setMethodCallHandler { call, result in
    guard call.method == "transcribe" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
      result(FlutterError(code: "bad_args", message: "Expected a path", details: nil))
      return
    }
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        switch status {
        case .authorized: runRecognition(path: path, result: result)
        case .denied, .restricted: result(["status": "denied"])
        default: result(["status": "unavailable"])
        }
      }
    }
  }
}

private func runRecognition(path: String, result: @escaping FlutterResult) {
  guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable,
    recognizer.supportsOnDeviceRecognition
  else {
    result(["status": "unavailable"])
    return
  }
  speechRecognizer = recognizer
  let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
  request.requiresOnDeviceRecognition = true
  request.shouldReportPartialResults = false
  var replied = false
  var best = ""
  speechTask = recognizer.recognitionTask(with: request) { recognition, error in
    if replied { return }
    if let recognition = recognition {
      best = recognition.bestTranscription.formattedString
      if recognition.isFinal {
        replied = true
        speechTask = nil
        result(["status": "ok", "text": best])
        return
      }
    }
    if let error = error as NSError? {
      replied = true
      speechTask = nil
      // 1110: no speech detected. Not a failure, just nothing to write.
      if error.code == 1110 || !best.isEmpty {
        result(["status": "ok", "text": best])
      } else {
        result(["status": "unavailable"])
      }
    }
  }
}

/// Spell and grammar check for the note editor (`corplex/spell`):
/// `NSSpellChecker`. Each paragraph is checked in its own language (see
/// [spellLanguage]) rather than the Spelling panel's, which on a bilingual
/// Mac is often the other language. Offsets are UTF-16, like Dart strings.
/// The checker is touched only on a call, never at registration.
///
/// `check` answers, per text, `[start, length]` for a misspelling and
/// `[start, length, 1, message, [corrections]]` for a grammar issue.
/// `guesses` takes the word's paragraph and offset (`text`, `start`) so the
/// checker ranks by context; its autocorrection comes first.
private func registerSpellChannel(_ messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(name: "corplex/spell", binaryMessenger: messenger)
  spellChannel = channel
  channel.setMethodCallHandler { call, result in
    let args = call.arguments as? [String: Any] ?? [:]
    let checker = NSSpellChecker.shared
    let tag = spellDocumentTag()
    switch call.method {
    case "check":
      let texts = args["texts"] as? [String] ?? []
      let types =
        NSTextCheckingResult.CheckingType.spelling.rawValue
        | NSTextCheckingResult.CheckingType.grammar.rawValue
      result(
        texts.map { text -> [[Any]] in
          let ns = text as NSString
          var options: [NSSpellChecker.OptionKey: Any] = [:]
          if let language = spellLanguage(for: text, available: checker.availableLanguages) {
            options[.orthography] = NSOrthography.defaultOrthography(forLanguage: language)
          }
          var found: [[Any]] = []
          for r in checker.check(
            text, range: NSRange(location: 0, length: ns.length), types: types,
            options: options, inSpellDocumentWithTag: tag, orthography: nil, wordCount: nil)
          {
            switch r.resultType {
            case .spelling:
              found.append([r.range.location, r.range.length])
            case .grammar:
              for detail in r.grammarDetails ?? [] {
                guard let sub = (detail[NSGrammarRange] as? NSValue)?.rangeValue,
                  sub.length > 0
                else { continue }
                found.append([
                  r.range.location + sub.location, sub.length, 1,
                  detail[NSGrammarUserDescription] as? String ?? "",
                  detail[NSGrammarCorrections] as? [String] ?? [],
                ])
              }
            default:
              break
            }
          }
          return found
        })
    case "guesses":
      let word = args["word"] as? String ?? ""
      var text = args["text"] as? String ?? word
      var range = NSRange(location: args["start"] as? Int ?? 0, length: (word as NSString).length)
      let ns = text as NSString
      if NSMaxRange(range) > ns.length || ns.substring(with: range) != word {
        text = word
        range = NSRange(location: 0, length: (word as NSString).length)
      }
      let language =
        spellLanguage(for: text, available: checker.availableLanguages) ?? checker.language()
      var out: [String] = []
      if let best = checker.correction(
        forWordRange: range, in: text, language: language, inSpellDocumentWithTag: tag)
      {
        out.append(best)
      }
      for guess in checker.guesses(
        forWordRange: range, in: text, language: language, inSpellDocumentWithTag: tag) ?? []
      where !out.contains(guess) {
        out.append(guess)
      }
      result(out)
    case "learn":
      if let word = args["word"] as? String { checker.learnWord(word) }
      result(nil)
    case "ignore":
      if let word = args["word"] as? String {
        checker.ignoreWord(word, inSpellDocumentWithTag: tag)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// One spell document for the whole app, so Ignore Spelling holds in every
/// note until the app quits (as in other Mac apps).
private var spellTag: Int?
private func spellDocumentTag() -> Int {
  if let tag = spellTag { return tag }
  let tag = NSSpellChecker.uniqueSpellDocumentTag()
  spellTag = tag
  return tag
}

/// The checker language for [text]: NaturalLanguage's guess among the
/// user's languages, as the checker names it, preferring the user's region
/// ("en_IN" on a Mac set to English (India)). nil when the paragraph is too
/// short to tell, and the checker then identifies the language itself.
private func spellLanguage(for text: String, available: [String]) -> String? {
  let recognizer = NLLanguageRecognizer()
  let preferred = Locale.preferredLanguages.map {
    $0.replacingOccurrences(of: "-", with: "_")
  }
  var hints: [NLLanguage: Double] = [:]
  for code in preferred {
    hints[NLLanguage(rawValue: String(code.prefix { $0 != "_" }))] = 0.6
  }
  recognizer.languageHints = hints
  recognizer.processString(text)
  guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
    confidence >= 0.6
  else { return nil }
  let code = language.rawValue
  if let regional = preferred.first(where: {
    ($0 == code || $0.hasPrefix(code + "_")) && available.contains($0)
  }) {
    return regional
  }
  if available.contains(code) { return code }
  return available.first { $0.hasPrefix(code + "_") }
}

/// Read aloud (`corplex/speak`): `AVSpeechSynthesizer`. Utterances queue
/// natively; each reports `done` (finished true, or false when cut off by
/// `stop`). The synthesizer is created on the first `speak`, never at
/// registration.
private final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
  private let channel: FlutterMethodChannel
  private var synthesizer: AVSpeechSynthesizer?
  private var ids: [AVSpeechUtterance: Int] = [:]

  init(_ channel: FlutterMethodChannel) { self.channel = channel }

  func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "speak":
      guard let args = call.arguments as? [String: Any],
        let id = args["id"] as? Int, let text = args["text"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Expected id and text", details: nil))
        return
      }
      let multiplier = (args["rate"] as? Double) ?? 1.0
      let utterance = AVSpeechUtterance(string: text)
      let rate = Float(multiplier) * AVSpeechUtteranceDefaultSpeechRate
      utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
      if let language = args["language"] as? String,
        let voice = AVSpeechSynthesisVoice(language: language)
      {
        utterance.voice = voice
      }
      let synth = synthesizer ?? makeSynthesizer()
      ids[utterance] = id
      synth.speak(utterance)
      result(nil)
    case "pause":
      synthesizer?.pauseSpeaking(at: .immediate)
      result(nil)
    case "resume":
      synthesizer?.continueSpeaking()
      result(nil)
    case "stop":
      synthesizer?.stopSpeaking(at: .immediate)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func makeSynthesizer() -> AVSpeechSynthesizer {
    let synth = AVSpeechSynthesizer()
    synth.delegate = self
    synthesizer = synth
    return synth
  }

  private func report(_ utterance: AVSpeechUtterance, finished: Bool) {
    guard let id = ids.removeValue(forKey: utterance) else { return }
    DispatchQueue.main.async {
      self.channel.invokeMethod("done", arguments: ["id": id, "finished": finished])
    }
  }

  func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    report(utterance, finished: true)
  }

  func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    report(utterance, finished: false)
  }
}

/// Spotlight (`corplex/spotlight`): `index` (list of {id, title, subtitle,
/// text, keywords}), `remove` (ids), `clear`; `ready` from Dart releases the
/// ids of results opened before it listened (a cold launch from Spotlight),
/// which go back as `open`. `CSSearchableIndex` is touched only on a call,
/// never at registration. Needs no entitlement in the sandbox.
final class SpotlightBridge {
  static let shared = SpotlightBridge()
  private static let domain = "com.corplex.items"

  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var pending: [String] = []

  func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "corplex/spotlight", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  func open(_ id: String) {
    if let window = NSApp.windows.compactMap({ $0 as? MainFlutterWindow }).first {
      window.bringForward()
    }
    if dartReady {
      channel?.invokeMethod("open", arguments: id)
    } else {
      pending.append(id)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      dartReady = true
      let queued = pending
      pending = []
      for id in queued { channel?.invokeMethod("open", arguments: id) }
      result(nil)
    case "index":
      guard let list = call.arguments as? [[String: Any]] else {
        result(FlutterError(code: "bad_args", message: "Expected a list", details: nil))
        return
      }
      let items = list.compactMap { entry -> CSSearchableItem? in
        guard let id = entry["id"] as? String, let title = entry["title"] as? String else {
          return nil
        }
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        if let subtitle = entry["subtitle"] as? String, !subtitle.isEmpty {
          attributes.contentDescription = subtitle
        }
        if let text = entry["text"] as? String, !text.isEmpty { attributes.textContent = text }
        attributes.keywords = entry["keywords"] as? [String]
        let item = CSSearchableItem(
          uniqueIdentifier: id, domainIdentifier: SpotlightBridge.domain,
          attributeSet: attributes)
        item.expirationDate = Date.distantFuture
        return item
      }
      CSSearchableIndex.default().indexSearchableItems(items) { error in
        DispatchQueue.main.async { Self.reply(result, error) }
      }
    case "remove":
      let ids = call.arguments as? [String] ?? []
      CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { error in
        DispatchQueue.main.async { Self.reply(result, error) }
      }
    case "clear":
      CSSearchableIndex.default().deleteSearchableItems(
        withDomainIdentifiers: [SpotlightBridge.domain]
      ) { error in
        DispatchQueue.main.async { Self.reply(result, error) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func reply(_ result: FlutterResult, _ error: Error?) {
    if let error = error {
      result(FlutterError(code: "spotlight_failed", message: error.localizedDescription, details: nil))
    } else {
      result(nil)
    }
  }
}
