import AVFoundation
import Cocoa
import FlutterMacOS
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

/// Spell check for the note editor (`corplex/spell`): `NSSpellChecker`,
/// which uses the system language settings and the user's learned words.
/// Offsets are UTF-16, like Dart strings. The checker is touched only on a
/// call, never at registration.
private func registerSpellChannel(_ messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(name: "corplex/spell", binaryMessenger: messenger)
  spellChannel = channel
  channel.setMethodCallHandler { call, result in
    let args = call.arguments as? [String: Any] ?? [:]
    let checker = NSSpellChecker.shared
    switch call.method {
    case "check":
      let texts = args["texts"] as? [String] ?? []
      result(
        texts.map { text -> [[Int]] in
          let ns = text as NSString
          var found: [[Int]] = []
          var at = 0
          while at < ns.length {
            let r = checker.checkSpelling(
              of: text, startingAt: at, language: nil, wrap: false,
              inSpellDocumentWithTag: 0, wordCount: nil)
            if r.location == NSNotFound || r.length == 0 { break }
            found.append([r.location, r.length])
            at = r.location + r.length
          }
          return found
        })
    case "guesses":
      let word = args["word"] as? String ?? ""
      let ns = word as NSString
      result(
        checker.guesses(
          forWordRange: NSRange(location: 0, length: ns.length), in: word, language: nil,
          inSpellDocumentWithTag: 0) ?? [])
    case "learn":
      if let word = args["word"] as? String { checker.learnWord(word) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
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
