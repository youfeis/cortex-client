import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    CortexFocus.shared.restoreOnOpen()
  }
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for item in connectionOptions.urlContexts { _ = CortexFocus.shared.open(item.url) }
  }
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let other = URLContexts.filter { !CortexFocus.shared.open($0.url) }
    if !other.isEmpty { super.scene(scene, openURLContexts: other) }
  }
}
