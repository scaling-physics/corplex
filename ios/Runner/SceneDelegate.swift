import Flutter
import UIKit
import Speech

class SceneDelegate: FlutterSceneDelegate, UIPencilInteractionDelegate {
  private var pencilChannel: FlutterMethodChannel?
  private var speechChannel: FlutterMethodChannel?
  private var speechRecognizer: SFSpeechRecognizer?
  private var speechTask: SFSpeechRecognitionTask?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    // Apple Pencil double-tap: tell Flutter what the user chose in
    // Settings > Apple Pencil, so the sketch editor can follow it.
    pencilChannel = FlutterMethodChannel(
      name: "corplex/pencil",
      binaryMessenger: controller.binaryMessenger
    )
    // Voice notes: transcribe a finished recording, on this device only.
    speechChannel = FlutterMethodChannel(
      name: "corplex/speech",
      binaryMessenger: controller.binaryMessenger
    )
    speechChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "transcribe",
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      {
        self?.transcribe(path: path, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    if #available(iOS 17.5, *) {
      controller.view.addInteraction(UIPencilInteraction(delegate: self))
    } else {
      let interaction = UIPencilInteraction()
      interaction.delegate = self
      controller.view.addInteraction(interaction)
    }
  }

  private func actionName() -> String {
    switch UIPencilInteraction.preferredTapAction {
    case .switchEraser: return "switchEraser"
    case .switchPrevious: return "switchPrevious"
    case .showColorPalette, .showInkAttributes, .showContextualPalette: return "showColorPalette"
    case .ignore: return "ignore"
    @unknown default: return "switchEraser"
    }
  }

  // iOS 17.5 and later.
  @available(iOS 17.5, *)
  func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
    pencilChannel?.invokeMethod("doubleTap", arguments: actionName())
  }

  // Earlier versions.
  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    pencilChannel?.invokeMethod("doubleTap", arguments: actionName())
  }

  /// Replies with {status: ok|denied|unavailable, text}. Never uses the
  /// network: `requiresOnDeviceRecognition` makes a missing language model
  /// an "unavailable" instead of a cloud request.
  private func transcribe(path: String, result: @escaping FlutterResult) {
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        switch status {
        case .authorized:
          self.runRecognition(path: path, result: result)
        case .denied, .restricted:
          result(["status": "denied"])
        default:
          result(["status": "unavailable"])
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
    speechTask = recognizer.recognitionTask(with: request) { [weak self] recognition, error in
      if replied { return }
      if let recognition = recognition {
        best = recognition.bestTranscription.formattedString
        if recognition.isFinal {
          replied = true
          self?.speechTask = nil
          result(["status": "ok", "text": best])
          return
        }
      }
      if let error = error as NSError? {
        replied = true
        self?.speechTask = nil
        // 1110: no speech detected. Not a failure, just nothing to write.
        if error.code == 1110 || !best.isEmpty {
          result(["status": "ok", "text": best])
        } else {
          result(["status": "unavailable"])
        }
      }
    }
  }
}
