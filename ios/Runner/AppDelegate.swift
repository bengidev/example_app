import Flutter
import UIKit
import TradeInFramework

@main
@objc class AppDelegate: FlutterAppDelegate {

  private enum Channel {
    static let name = "com.example.tradein/channel"
    static let startTradeIn = "startTradeIn"
    static let getDeviceInfo = "getDeviceInfo"
  }

  private var methodChannel: FlutterMethodChannel?
  private var pendingResult: FlutterResult?
  private var latestProcessResults: [[String: Any]]?
  private var betaTestViewController: UIViewController?
  private var isFinishingFromFinishTest = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    setupNavigationController()
    setupMethodChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupNavigationController() {
    guard let flutterViewController = window?.rootViewController as? FlutterViewController else {
      return
    }

    let navigationController = UINavigationController(rootViewController: flutterViewController)
    navigationController.setNavigationBarHidden(true, animated: false)
    window?.rootViewController = navigationController
  }

  private func setupMethodChannel() {
    let controller: FlutterViewController?
    if let navigationController = window?.rootViewController as? UINavigationController {
      controller = navigationController.viewControllers.first as? FlutterViewController
    } else {
      controller = window?.rootViewController as? FlutterViewController
    }

    guard let flutterController = controller else {
      print("ERROR: Could not find FlutterViewController")
      return
    }

    methodChannel = FlutterMethodChannel(
      name: Channel.name,
      binaryMessenger: flutterController.binaryMessenger
    )

    methodChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }

      switch call.method {
      case Channel.startTradeIn:
        self.handleStartTradeIn(result: result)
      case Channel.getDeviceInfo:
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
    betaTest.title = "Device Diagnostics"
    betaTest.navigationItem.hidesBackButton = false

    betaTestViewController = betaTest
    navigationController.delegate = self
    navigationController.pushViewController(betaTest, animated: true)
  }

  private func handleGetDeviceInfo(result: @escaping FlutterResult) {
    if let response = buildResponseFromLatestResults() {
      result(response)
      return
    }

    result(FlutterError(
      code: "NO_DATA",
      message: "No cached device info available. Run startTradeIn first.",
      details: nil
    ))
  }

  private func mapState(_ state: BetaTestCardState) -> String {
    state == .success ? "success" : "failed"
  }

  private func buildResultEntry(index: Int, title: String, state: BetaTestCardState) -> [String: Any] {
    [
      "index": index,
      "title": title,
      "state": mapState(state)
    ]
  }

  private func sortedResults(_ results: [[String: Any]]) -> [[String: Any]] {
    results.sorted { lhs, rhs in
      let left = lhs["index"] as? Int ?? Int.max
      let right = rhs["index"] as? Int ?? Int.max
      return left < right
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

  private func clearFlowState(clearPendingResult: Bool) {
    if clearPendingResult {
      pendingResult = nil
    }
    latestProcessResults = nil
    betaTestViewController = nil
  }

  private func sendCancelledResponse(backButton: Bool) {
    var response: [String: Any] = [
      "results": [],
      "completed": false,
      "cancelled": true
    ]

    if backButton {
      response["backButton"] = true
    }

    pendingResult?(response)
    clearFlowState(clearPendingResult: true)
  }

  private func sendNoResultsError() {
    pendingResult?(FlutterError(
      code: "NO_RESULTS",
      message: "No diagnostic results available",
      details: nil
    ))
    pendingResult = nil
  }

  private func sendLatestResultsToFlutter() {
    guard pendingResult != nil else {
      return
    }

    guard let response = buildResponseFromLatestResults() else {
      sendNoResultsError()
      return
    }

    pendingResult?(response)
    clearFlowState(clearPendingResult: true)
  }

  private func updateLatestProcessResult(at index: Int, title: String, state: BetaTestCardState) {
    var currentResults = latestProcessResults ?? []
    let updated = buildResultEntry(index: index, title: title, state: state)

    if let existingIndex = currentResults.firstIndex(where: { ($0["index"] as? Int) == index }) {
      currentResults[existingIndex] = updated
    } else {
      currentResults.append(updated)
      currentResults = sortedResults(currentResults)
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

    latestProcessResults = sortedResults(currentResults)
  }
}

extension AppDelegate: UINavigationControllerDelegate {

  func navigationController(
    _ navigationController: UINavigationController,
    didShow viewController: UIViewController,
    animated: Bool
  ) {
    guard viewController is FlutterViewController, pendingResult != nil else {
      return
    }

    if isFinishingFromFinishTest {
      return
    }

    navigationController.setNavigationBarHidden(true, animated: true)
    sendCancelledResponse(backButton: true)
  }
}

extension AppDelegate: UIAdaptivePresentationControllerDelegate {

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if pendingResult != nil {
      sendCancelledResponse(backButton: false)
    }
  }
}

extension AppDelegate: BetaTestDelegate {

  func didCompleteTest(at index: Int, title: String, with state: BetaTestCardState) {
    updateLatestProcessResult(at: index, title: title, state: state)
  }

  func didCompleteAllTests(with results: [BetaTestViewController.ProcessResult]) {
    let completedResults = results.map { result in
      buildResultEntry(index: result.index, title: result.title, state: result.state)
    }
    mergeCompletedResultsIfNeeded(completedResults)
  }

  func didRetryTest(at index: Int, title: String, with state: BetaTestCardState) {
    updateLatestProcessResult(at: index, title: title, state: state)
  }

  func willStartAllTests() {
    betaTestViewController?.navigationItem.hidesBackButton = true
  }

  func willFinishBetaTestFromFlutter() {
    guard let navigationController = window?.rootViewController as? UINavigationController else {
      return
    }

    isFinishingFromFinishTest = true
    navigationController.popViewController(animated: true)
    navigationController.setNavigationBarHidden(true, animated: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      self.sendLatestResultsToFlutter()
      self.isFinishingFromFinishTest = false
    }
  }
}
