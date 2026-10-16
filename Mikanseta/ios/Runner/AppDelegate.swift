import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingURLs: [URL] = []
  private var archiveBridge: NativeArchiveBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func acceptURL(_ url:URL) { if let archiveBridge {archiveBridge.acceptURL(url)}else{pendingURLs.append(url)} }
  override func application(_ application:UIApplication,open url:URL,options:[UIApplication.OpenURLOptionsKey:Any]=[:])->Bool { if url.scheme=="mikanseta" {acceptURL(url);return true};return super.application(application,open:url,options:options) }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    archiveBridge = NativeArchiveBridge(messenger: engineBridge.applicationRegistrar.messenger())
    for url in pendingURLs { archiveBridge?.acceptURL(url) };pendingURLs=[]
  }
}
