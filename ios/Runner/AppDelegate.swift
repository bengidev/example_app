import Flutter
import UIKit
import TradeInFramework

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  private var methodChannel: FlutterMethodChannel?
  private var pendingResult: FlutterResult?
  private var cachedResults: [String: Any]?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    setupMethodChannel()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func setupMethodChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    
    methodChannel = FlutterMethodChannel(
      name: "com.example.tradein/channel",
      binaryMessenger: controller.binaryMessenger
    )
    
    methodChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      
      switch call.method {
      case "startTradeIn":
        self.handleStartTradeIn(result: result)
        
      case "getDeviceInfo":
        self.handleGetDeviceInfo(result: result)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
  
  private func handleStartTradeIn(result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(
        code: "ALREADY_RUNNING",
        message: "Trade-in process is already running",
        details: nil
      ))
      return
    }
    
    guard let rootViewController = window?.rootViewController else {
      result(FlutterError(
        code: "NO_VIEW_CONTROLLER",
        message: "Root view controller not available",
        details: nil
      ))
      return
    }
    
    pendingResult = result
    
    let betaTest = TradeIn.createBetaTestAnalyzer(isFlutterCaller: true)
    betaTest.delegate = self
    
    // Set to fullscreen to prevent drag-to-dismiss gesture (iOS 13+)
    betaTest.modalPresentationStyle = .fullScreen
    
    rootViewController.present(betaTest, animated: true)
  }
  
  private func handleGetDeviceInfo(result: @escaping FlutterResult) {
    if let cached = cachedResults {
      result(cached)
    } else {
      result(FlutterError(
        code: "NO_DATA",
        message: "No cached device info available. Run startTradeIn first.",
        details: nil
      ))
    }
  }
}

// MARK: - UIAdaptivePresentationControllerDelegate
extension AppDelegate: UIAdaptivePresentationControllerDelegate {
  
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    // Handle when user dismisses via drag gesture (sheet presentation)
    if pendingResult != nil {
      let response: [String: Any] = [
        "results": [],
        "completed": false,
        "cancelled": true
      ]
      pendingResult?(response)
      pendingResult = nil
    }
  }
}

// MARK: - BetaTestDelegate
extension AppDelegate: BetaTestDelegate {
  
  func didCompleteAllTests(with results: [BetaTestViewController.ProcessResult]) {
    let resultsArray = results.map { result -> [String: Any] in
      return [
        "index": result.index,
        "title": result.title,
        "state": result.state == .success ? "success" : "failed"
      ]
    }
    
    let response: [String: Any] = [
      "results": resultsArray,
      "completed": true
    ]
    
    cachedResults = response
    pendingResult?(response)
    pendingResult = nil
  }
  
  func willFinishBetaTestFromFlutter() {
    window?.rootViewController?.dismiss(animated: true)
  }
}
