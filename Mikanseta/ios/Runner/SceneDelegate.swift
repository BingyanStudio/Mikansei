import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options connectionOptions:UIScene.ConnectionOptions) {
    super.scene(scene,willConnectTo:session,options:connectionOptions)
    for item in connectionOptions.urlContexts { (UIApplication.shared.delegate as? AppDelegate)?.acceptURL(item.url) }
  }
  override func scene(_ scene:UIScene,openURLContexts URLContexts:Set<UIOpenURLContext>) {
    for item in URLContexts { (UIApplication.shared.delegate as? AppDelegate)?.acceptURL(item.url) }
  }
}
