import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate, UIPencilInteractionDelegate {
  private var pencilChannel: FlutterMethodChannel?

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
}
