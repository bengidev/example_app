import Flutter
import UIKit
import TradeInFramework

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  private var methodChannel: FlutterMethodChannel?
  private var pendingResult: FlutterResult?
  private var latestProcessResults: [[String: Any]]?
  private var navigationController: UINavigationController?
  private var betaTestViewController: UIViewController?
  private var isFinishingFromLanjut = false
  
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

    latestProcessResults = nil
    
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
    if let response = buildResponseFromLatestResults() {
      result(response)
    } else {
      result(FlutterError(
        code: "NO_DATA",
        message: "No cached device info available. Run startTradeIn first.",
        details: nil
      ))
    }
  }

  private func buildResponseFromLatestResults() -> [String: Any]? {
    guard let results = latestProcessResults else {
      return nil
    }

    return [
      "results": results,
      "completed": true
    ]
  }

  private func updateLatestProcessResult(
    at index: Int,
    title: String,
    state: BetaTestCardState
  ) {
    var currentResults = latestProcessResults ?? []

    let updated: [String: Any] = [
      "index": index,
      "title": title,
      "state": state == .success ? "success" : "failed"
    ]

    if let existingIndex = currentResults.firstIndex(where: { ($0["index"] as? Int) == index }) {
      currentResults[existingIndex] = updated
    } else {
      currentResults.append(updated)
      currentResults.sort { (lhs, rhs) in
        let left = lhs["index"] as? Int ?? Int.max
        let right = rhs["index"] as? Int ?? Int.max
        return left < right
      }
    }

    latestProcessResults = currentResults
  }

  private func mergeCompletedResultsIfNeeded(_ results: [[String: Any]]) {
    var currentResults = latestProcessResults ?? []

    for result in results {
      guard let index = result["index"] as? Int else {
        continue
      }

      if currentResults.firstIndex(where: { ($0["index"] as? Int) == index }) == nil {
        currentResults.append(result)
      }
    }

    currentResults.sort { (lhs, rhs) in
      let left = lhs["index"] as? Int ?? Int.max
      let right = rhs["index"] as? Int ?? Int.max
      return left < right
    }

    latestProcessResults = currentResults
  }
}

// MARK: - UINavigationControllerDelegate
extension AppDelegate: UINavigationControllerDelegate {
  
  func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
    // Check if we're back to Flutter (root view controller)
    if viewController is FlutterViewController && pendingResult != nil {
      if isFinishingFromLanjut {
        return
      }

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
      latestProcessResults = nil
      
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
      latestProcessResults = nil
    }
  }
}

// MARK: - BetaTestDelegate
extension AppDelegate: BetaTestDelegate {

  func didCompleteTest(at index: Int, title: String, with state: BetaTestCardState) {
    updateLatestProcessResult(at: index, title: title, state: state)
  }
  
  func didCompleteAllTests(with results: [BetaTestViewController.ProcessResult]) {
    print("=== didCompleteAllTests called ===")
    print("Processing \(results.count) test results...")
    
    for result in results {
      let stateString = result.state == .success ? "success" : "failed"
      print("  Test #\(result.index): \(result.title) -> \(stateString)")
    }

    let completedResults = results.map { result in
      [
        "index": result.index,
        "title": result.title,
        "state": result.state == .success ? "success" : "failed"
      ]
    }
    mergeCompletedResultsIfNeeded(completedResults)
    print("Latest process results captured. Waiting for user to tap 'Lanjut'...")
    print("====================================")
    
    // NOTE: Results are NOT sent here. They are sent in willFinishBetaTestFromFlutter
    // after the native UI is dismissed, to ensure proper flow.
  }

  func didRetryTest(at index: Int, title: String, with state: BetaTestCardState) {
    print("=== didRetryTest called ===")
    let stateString = state == .success ? "success" : "failed"
    print("  Retry result #\(index): \(title) -> \(stateString)")

    updateLatestProcessResult(at: index, title: title, state: state)

    if let latest = buildResponseFromLatestResults() {
      print("Updated latest results after retry:")
      print("  - Results count: \((latest["results"] as? [[String: Any]])?.count ?? 0)")
    }
    print("====================================")
  }
  
  
  func willStartAllTests() {
    // DEBUG: Called when user taps "Mulai Tes" (Start Test) button
    print("=== willStartAllTests called - Hiding back button ===")
    
    // Hide back button when tests start - user must complete the process
    if let betaTest = betaTestViewController {
      betaTest.navigationItem.hidesBackButton = true
      print("Back button hidden - user must complete diagnostics")
    }
  }
  
  func willFinishBetaTestFromFlutter() {
    // DEBUG: Called when user taps "Lanjut" (Continue) button in native UI
    print("=== willFinishBetaTestFromFlutter called ===")
    
    // Get navigation controller and pop BetaTest from the stack
    guard let navigationController = window?.rootViewController as? UINavigationController else {
      print("ERROR: Navigation controller not found")
      return
    }
    
    isFinishingFromLanjut = true

    navigationController.popViewController(animated: true)
    navigationController.setNavigationBarHidden(true, animated: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      
      print("=== BetaTest popped from navigation stack, sending results to Flutter ===")

      if let response = self.buildResponseFromLatestResults() {
        print("Sending latest results to Flutter:")
        print("  - Completed: \(response["completed"] ?? false)")
        print("  - Results count: \((response["results"] as? [[String: Any]])?.count ?? 0)")
        
        // Only send if we haven't already sent results
        if self.pendingResult != nil {
          self.pendingResult?(response)
          self.pendingResult = nil
          self.latestProcessResults = nil
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

      self.isFinishingFromLanjut = false
      
      print("====================================")
    }
  }
}
