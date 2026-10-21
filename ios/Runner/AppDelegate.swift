import AVFoundation
import Flutter
import NaturalLanguage
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerOcrChannel(engineBridge.applicationRegistrar.messenger())
    registerSpellChannel(engineBridge.applicationRegistrar.messenger())
    registerSpeakChannel(engineBridge.applicationRegistrar.messenger())
  }

  private func registerSpeakChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "corplex/speak", binaryMessenger: messenger)
    let handler = Speaker(channel)
    speakHandler = handler
    channel.setMethodCallHandler { call, result in handler.handle(call, result) }
  }

  /// Spell check for the note editor (`corplex/spell`): `UITextChecker`.
  /// Each paragraph is checked in its own language among the user's
  /// (NaturalLanguage's guess), falling back to the first preferred language
  /// the checker supports. Offsets are UTF-16, like Dart strings. `guesses`
  /// takes the word's paragraph and offset (`text`, `start`) for context.
  /// One checker for the app, created on the first call, so Ignore Spelling
  /// holds in every note until the app quits.
  private func registerSpellChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "corplex/spell", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      let checker = self.textChecker ?? UITextChecker()
      self.textChecker = checker
      switch call.method {
      case "check":
        let texts = args["texts"] as? [String] ?? []
        result(
          texts.map { text -> [[Int]] in
            let length = (text as NSString).length
            let language = Self.spellLanguage(for: text)
            var found: [[Int]] = []
            var at = 0
            while at < length {
              let r = checker.rangeOfMisspelledWord(
                in: text, range: NSRange(location: 0, length: length), startingAt: at,
                wrap: false, language: language)
              if r.location == NSNotFound || r.length == 0 { break }
              found.append([r.location, r.length])
              at = r.location + r.length
            }
            return found
          })
      case "guesses":
        let word = args["word"] as? String ?? ""
        var text = args["text"] as? String ?? word
        var range = NSRange(
          location: args["start"] as? Int ?? 0, length: (word as NSString).length)
        let ns = text as NSString
        if NSMaxRange(range) > ns.length || ns.substring(with: range) != word {
          text = word
          range = NSRange(location: 0, length: (word as NSString).length)
        }
        result(
          checker.guesses(forWordRange: range, in: text, language: Self.spellLanguage(for: text))
            ?? [])
      case "learn":
        if let word = args["word"] as? String { UITextChecker.learnWord(word) }
        result(nil)
      case "ignore":
        if let word = args["word"] as? String { checker.ignoreWord(word) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var textChecker: UITextChecker?

  /// The checker language for [text]: NaturalLanguage's guess among the
  /// user's languages when it is confident, else the first preferred
  /// language the checker supports (en_US if none).
  private static func spellLanguage(for text: String) -> String {
    let available = UITextChecker.availableLanguages
    let preferred = Locale.preferredLanguages.map {
      $0.replacingOccurrences(of: "-", with: "_")
    }
    func supported(_ code: String) -> String? {
      if available.contains(code) { return code }
      return available.first { code.hasPrefix($0) || $0.hasPrefix(code) }
    }
    let recognizer = NLLanguageRecognizer()
    var hints: [NLLanguage: Double] = [:]
    for code in preferred {
      hints[NLLanguage(rawValue: String(code.prefix { $0 != "_" }))] = 0.6
    }
    recognizer.languageHints = hints
    recognizer.processString(text)
    if let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
      confidence >= 0.6
    {
      let code = language.rawValue
      if let regional = preferred.first(where: { $0 == code || $0.hasPrefix(code + "_") }),
        let match = supported(regional)
      {
        return match
      }
      if let match = supported(code) { return match }
    }
    return preferred.lazy.compactMap(supported).first ?? "en_US"
  }

  /// On-device OCR (`corplex/ocr`): Apple Vision, accurate level with
  /// language correction. Returns lines with word boxes as fractions of the
  /// image, origin top-left.
  private func registerOcrChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "corplex/ocr", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize",
        let args = call.arguments as? [String: Any],
        let data = (args["image"] as? FlutterStandardTypedData)?.data,
        let image = UIImage(data: data)?.cgImage
      else {
        result(FlutterError(code: "bad_args", message: "Expected PNG bytes", details: nil))
        return
      }
      DispatchQueue.global(qos: .utility).async {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(iOS 16.0, *) { request.automaticallyDetectsLanguage = true }
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
}

private var speakHandler: Speaker?

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
      do {
          // Spoken audio: plays with the silent switch on.
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playback, mode: .spokenAudio)
          try session.setActive(true)
        } catch {}
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
