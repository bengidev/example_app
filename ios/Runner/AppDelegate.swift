import Flutter
import UIKit
import TradeInFramework

@main
@objc class AppDelegate: FlutterAppDelegate {

  private enum Channel {
    static let name = "com.example.tradein/channel"
    static let startTradeIn = "startTradeIn"
  }

  private var methodChannel: FlutterMethodChannel?
  private var pendingResult: FlutterResult?
  private var activeSessionID: UUID?
  private var activeResultsByIndex: [Int: [String: Any]] = [:]
  private var activeAnalyzer: DeviceTestViewController?
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

    resetFlowState(clearPendingResult: true)

    let sessionID = UUID()
    activeSessionID = sessionID
    pendingResult = result
    activeResultsByIndex = [:]

    let analyzer = TradeIn.createDeviceTestAnalyzer(isFlutterCaller: true, testEngineType: .beta)
    configureCallbacks(for: analyzer, sessionID: sessionID)
    analyzer.title = "Device Diagnostics"
    analyzer.navigationItem.hidesBackButton = false

    activeAnalyzer = analyzer
    navigationController.delegate = self
    navigationController.pushViewController(analyzer, animated: true)
  }

  private func configureCallbacks(for analyzer: DeviceTestViewController, sessionID: UUID) {
    analyzer.onDidCompleteTest = { [weak self] result in
      self?.upsertResult(result, sessionID: sessionID)
    }
    analyzer.onDidRetryTest = { [weak self] result in
      self?.upsertResult(result, sessionID: sessionID)
    }
    analyzer.onDidCompleteAllTests = { [weak self] results in
      self?.upsertResults(results, sessionID: sessionID)
      self?.setBackButtonHidden(false, sessionID: sessionID)
    }
    analyzer.onWillStartAllTests = { [weak self] in
      self?.setBackButtonHidden(true, sessionID: sessionID)
    }
    analyzer.onWillFinishFromFlutter = { [weak self] in
      self?.finishFlowFromFramework(sessionID: sessionID)
    }
    analyzer.delegate = nil
  }

  private func isCurrentSession(_ sessionID: UUID) -> Bool {
    activeSessionID == sessionID
  }

  private func mapState(_ state: DeviceTestCardState) -> String {
    state == .success ? "success" : "failed"
  }

  private func buildResultEntry(from result: DeviceTestProcessResult) -> [String: Any] {
    var entry: [String: Any] = [
      "index": result.index,
      "title": result.title,
      "state": mapState(result.state)
    ]

    if !result.descriptions.isEmpty {
      entry["descriptions"] = result.descriptions
    }

    return entry
  }

  private func upsertResult(_ result: DeviceTestProcessResult, sessionID: UUID) {
    guard isCurrentSession(sessionID) else {
      return
    }

    activeResultsByIndex[result.index] = buildResultEntry(from: result)
  }

  private func upsertResults(_ results: [DeviceTestProcessResult], sessionID: UUID) {
    guard isCurrentSession(sessionID) else {
      return
    }

    for result in results {
      activeResultsByIndex[result.index] = buildResultEntry(from: result)
    }
  }

  private func sortedResults() -> [[String: Any]] {
    activeResultsByIndex.keys.sorted().compactMap { activeResultsByIndex[$0] }
  }

  private func buildCompletedResponse() -> [String: Any] {
    return [
      "results": sortedResults(),
      "completed": true
    ]
  }

  private func resetFlowState(clearPendingResult: Bool) {
    activeAnalyzer?.onDidCompleteTest = nil
    activeAnalyzer?.onDidRetryTest = nil
    activeAnalyzer?.onDidCompleteAllTests = nil
    activeAnalyzer?.onWillStartAllTests = nil
    activeAnalyzer?.onWillFinishFromFlutter = nil
    activeAnalyzer?.delegate = nil

    if clearPendingResult {
      pendingResult = nil
    }
    activeSessionID = nil
    activeResultsByIndex = [:]
    activeAnalyzer = nil
  }

  private func sendCancelledResponse(sessionID: UUID, backButton: Bool) {
    guard isCurrentSession(sessionID), let callback = pendingResult else {
      return
    }

    var response: [String: Any] = [
      "results": [],
      "completed": false,
      "cancelled": true
    ]

    if backButton {
      response["backButton"] = true
    }

    callback(response)
    resetFlowState(clearPendingResult: true)
  }

  private func sendNoResultsError(sessionID: UUID) {
    guard isCurrentSession(sessionID), let callback = pendingResult else {
      return
    }

    callback(FlutterError(
      code: "NO_RESULTS",
      message: "No diagnostic results available",
      details: nil
    ))
    resetFlowState(clearPendingResult: true)
  }

  private func sendLatestResultsToFlutter(sessionID: UUID) {
    guard isCurrentSession(sessionID), let callback = pendingResult else {
      return
    }

    if activeResultsByIndex.isEmpty {
      sendNoResultsError(sessionID: sessionID)
      return
    }

    callback(buildCompletedResponse())
    resetFlowState(clearPendingResult: true)
  }

  private func finishFlowFromFramework(sessionID: UUID) {
    guard isCurrentSession(sessionID) else {
      return
    }

    guard let navigationController = window?.rootViewController as? UINavigationController else {
      sendLatestResultsToFlutter(sessionID: sessionID)
      return
    }

    isFinishingFromFinishTest = true
    navigationController.popViewController(animated: true)
    navigationController.setNavigationBarHidden(true, animated: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self = self else { return }
      self.sendLatestResultsToFlutter(sessionID: sessionID)
      self.isFinishingFromFinishTest = false
    }
  }

  private func setBackButtonHidden(_ hidden: Bool, sessionID: UUID, animated: Bool = true) {
    guard isCurrentSession(sessionID), let activeAnalyzer else { return }

    guard animated, let navigationBar = activeAnalyzer.navigationController?.navigationBar else {
      activeAnalyzer.navigationItem.setHidesBackButton(hidden, animated: animated)
      return
    }

    activeAnalyzer.navigationItem.setHidesBackButton(hidden, animated: animated)
    navigationBar.layoutIfNeeded()
  }
}

extension AppDelegate: UINavigationControllerDelegate {

  func navigationController(
    _ navigationController: UINavigationController,
    willShow viewController: UIViewController,
    animated: Bool
  ) {
    guard viewController is FlutterViewController,
      let sessionID = activeSessionID,
      pendingResult != nil else {
      return
    }

    if isFinishingFromFinishTest {
      return
    }

    navigationController.setNavigationBarHidden(true, animated: false)
    sendCancelledResponse(sessionID: sessionID, backButton: true)
  }

  func navigationController(
    _ navigationController: UINavigationController,
    didShow viewController: UIViewController,
    animated: Bool
  ) {
    guard viewController is FlutterViewController else {
      return
    }

    navigationController.setNavigationBarHidden(true, animated: false)
  }
}

extension AppDelegate: UIAdaptivePresentationControllerDelegate {

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if let sessionID = activeSessionID, pendingResult != nil {
      sendCancelledResponse(sessionID: sessionID, backButton: false)
    }
  }
}
