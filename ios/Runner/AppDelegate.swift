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
