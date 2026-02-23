import Flutter
import UIKit
import TradeInFramework

protocol TradeInBridgeDelegate: AnyObject {
  func tradeInDidComplete(with results: [String: Any])
  func tradeInDidCancel()
}

class TradeInBridge: NSObject {
  
  private weak var viewController: UIViewController?
  private var pendingResult: FlutterResult?
  weak var delegate: TradeInBridgeDelegate?
  
  var hasPendingResult: Bool {
    return pendingResult != nil
  }
  
  init(viewController: UIViewController) {
    self.viewController = viewController
    super.init()
  }
  
  func startTradeIn(result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(
        code: "ALREADY_RUNNING",
        message: "Trade-in process is already running",
        details: nil
      ))
      return
    }
    
    guard let viewController = viewController else {
      result(FlutterError(
        code: "NO_VIEW_CONTROLLER",
        message: "View controller not available",
        details: nil
      ))
      return
    }
    
    pendingResult = result
    
    let betaTest = TradeIn.createBetaTestAnalyzer(isFlutterCaller: true)
    betaTest.delegate = self
    
    viewController.present(betaTest, animated: true)
  }
  
  func clearPendingResult() {
    pendingResult = nil
  }
  
  private func sendResult(_ result: Any?) {
    pendingResult?(result)
    pendingResult = nil
  }
}

extension TradeInBridge: BetaTestDelegate {
  
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
    
    delegate?.tradeInDidComplete(with: response)
    sendResult(response)
  }
  
  func willFinishBetaTestFromFlutter() {
    viewController?.dismiss(animated: true)
  }
}
