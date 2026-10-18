import Flutter
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
  }

  /// Spell check for the note editor (`corplex/spell`): `UITextChecker`,
  /// in the first preferred language it supports. Offsets are UTF-16, like
  /// Dart strings. Created per call, never at registration.
  private func registerSpellChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "corplex/spell", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let available = UITextChecker.availableLanguages
      let language =
        Locale.preferredLanguages
        .map { $0.replacingOccurrences(of: "-", with: "_") }
        .first { code in available.contains { code.hasPrefix($0) || $0.hasPrefix(code) } }
        .flatMap { code in available.first { code.hasPrefix($0) || $0.hasPrefix(code) } }
        ?? "en_US"
      switch call.method {
      case "check":
        let checker = UITextChecker()
        let texts = args["texts"] as? [String] ?? []
        result(
          texts.map { text -> [[Int]] in
            let length = (text as NSString).length
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
        let length = (word as NSString).length
        result(
          UITextChecker().guesses(
            forWordRange: NSRange(location: 0, length: length), in: word, language: language)
            ?? [])
      case "learn":
        if let word = args["word"] as? String { UITextChecker.learnWord(word) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
