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
    
    // Wrap FlutterViewController in UINavigationController for navigation stack
    setupNavigationController()
    
    setupMethodChannel()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func setupNavigationController() {
    guard let flutterViewController = window?.rootViewController as? FlutterViewController else {
      return
    }
    
    // Create UINavigationController with Flutter as root
    let navigationController = UINavigationController(rootViewController: flutterViewController)
    navigationController.setNavigationBarHidden(true, animated: false)
    
    // Replace window's rootViewController with navigation controller
    window?.rootViewController = navigationController
  }
  
  private func setupMethodChannel() {
    // Get FlutterViewController from navigation controller or directly
    let controller: FlutterViewController?
    if let navController = window?.rootViewController as? UINavigationController {
      controller = navController.viewControllers.first as? FlutterViewController
    } else {
      controller = window?.rootViewController as? FlutterViewController
    }
    
    guard let flutterController = controller else {
      print("ERROR: Could not find FlutterViewController")
      return
    }
    
    methodChannel = FlutterMethodChannel(
      name: "com.example.tradein/channel",
      binaryMessenger: flutterController.binaryMessenger
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
    
    guard let navigationController = window?.rootViewController as? UINavigationController else {
      result(FlutterError(
        code: "NO_NAVIGATION_CONTROLLER",
        message: "Navigation controller not available",
        details: nil
      ))
      return
    }
    
    pendingResult = result
    
    let betaTest = TradeIn.createBetaTestAnalyzer(isFlutterCaller: true)
    betaTest.delegate = self
    
    // Push BetaTest onto the navigation stack (Flutter is the root)
    betaTest.title = "Device Diagnostics"
    navigationController.pushViewController(betaTest, animated: true)
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
    // // GUARD: Prevent processing results multiple times (infinite loop protection)
    // if cachedResults != nil {
    //   print("=== didCompleteAllTests called (ALREADY PROCESSED - SKIPPING) ===")
    //   return
    // }
    
    print("=== didCompleteAllTests called ===")
    print("Processing \(results.count) test results...")
    
    let resultsArray = results.map { result -> [String: Any] in
      let stateString = result.state == .success ? "success" : "failed"
      print("  Test #\(result.index): \(result.title) -> \(stateString)")
      return [
        "index": result.index,
        "title": result.title,
        "state": stateString
      ]
    }
    
    let response: [String: Any] = [
      "results": resultsArray,
      "completed": true
    ]
    
    // Cache results - they will be sent to Flutter after user taps "Lanjut" and UI dismisses
    cachedResults = response
    print("Results cached. Waiting for user to tap 'Lanjut'...")
    print("====================================")
    
    // NOTE: Results are NOT sent here. They are sent in willFinishBetaTestFromFlutter
    // after the native UI is dismissed, to ensure proper flow.
  }
  
  func willFinishBetaTestFromFlutter() {
    // DEBUG: Called when user taps "Lanjut" (Continue) button in native UI
    print("=== willFinishBetaTestFromFlutter called ===")
    
    // Dismiss the view controller and send results after animation completes
    window?.rootViewController?.dismiss(animated: true) { [weak self] in
      guard let self = self else { return }
      
      print("=== Native UI dismissed, sending results to Flutter ===")
      
      // Send cached results to Flutter after dismissal completes
      if let cached = self.cachedResults {
        print("Sending cached results to Flutter:")
        print("  - Completed: \(cached["completed"] ?? false)")
        print("  - Results count: \((cached["results"] as? [[String: Any]])?.count ?? 0)")
        
        // Only send if we haven't already sent results
        if self.pendingResult != nil {
          self.pendingResult?(cached)
          self.pendingResult = nil
          print("Results successfully sent to Flutter")
        } else {
          print("Pending result already cleared, results were sent earlier")
        }
      } else {
        print("WARNING: No cached results available to send!")
        if self.pendingResult != nil {
          self.pendingResult?(FlutterError(
            code: "NO_RESULTS",
            message: "No diagnostic results available",
            details: nil
          ))
          self.pendingResult = nil
        }
      }
      
      print("====================================")
    }
  }
}
