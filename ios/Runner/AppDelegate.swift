import Flutter
import UIKit
import TradeInFramework

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  private var methodChannel: FlutterMethodChannel?
  private var pendingResult: FlutterResult?
  private var cachedResults: [String: Any]?
  private var navigationController: UINavigationController?
  private var betaTestViewController: UIViewController?
  
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
    
    // Show back button initially - user can go back before starting tests
    betaTest.navigationItem.hidesBackButton = false
    
    // Store reference to navigation controller for later use
    self.navigationController = navigationController
    self.betaTestViewController = betaTest
    
    // Set navigation controller delegate to detect back button taps
    navigationController.delegate = self
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

// MARK: - UINavigationControllerDelegate
extension AppDelegate: UINavigationControllerDelegate {
  
  func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
    // Check if we're back to Flutter (root view controller)
    if viewController is FlutterViewController && pendingResult != nil {
      print("=== User navigated back to Flutter via back button ===")
      
      // Hide navigation bar when returning to Flutter
      navigationController.setNavigationBarHidden(true, animated: true)
      
      // Notify Flutter that user cancelled by going back
      let response: [String: Any] = [
        "results": [],
        "completed": false,
        "cancelled": true,
        "backButton": true
      ]
      pendingResult?(response)
      pendingResult = nil
      
      // Clear stored references
      self.navigationController = nil
      self.betaTestViewController = nil
      
      print("====================================")
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
    
    // Get navigation controller and pop BetaTest from the stack
    guard let navigationController = window?.rootViewController as? UINavigationController else {
      print("ERROR: Navigation controller not found")
      return
    }
    
    // Pop BetaTest view controller to return to Flutter
    navigationController.popViewController(animated: true)
    
    // Hide navigation bar when returning to Flutter (fixes green header bug)
    navigationController.setNavigationBarHidden(true, animated: true)
    
    // Send results after a short delay to allow animation to complete
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      
      print("=== BetaTest popped from navigation stack, sending results to Flutter ===")
      
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
