import Flutter
import UIKit

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
    // Version obsolète : ouverture de la page de téléchargement.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VigiroadLinks") {
      let channel = FlutterMethodChannel(name: "fr.vigiroad/updater", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "openUrl",
              let args = call.arguments as? [String: Any],
              let text = args["url"] as? String,
              let url = URL(string: text) else {
          result(FlutterMethodNotImplemented)
          return
        }
        UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
      }
    }
  }
}
