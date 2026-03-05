import 'package:flutter/services.dart';

/// Service class for communicating with native TradeInFramework via MethodChannel.
///
/// Provides type-safe wrappers for native TradeInFramework operations including
/// launching the trade-in diagnostics UI.
class TradeInChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.example.tradein/channel',
  );

  /// Launches the native TradeInFramework UI for device trade-in.
  ///
  /// Returns a [Future] that completes with a map containing the trade-in results
  /// when the user finishes the flow. The native side presents a BetaTest view
  /// controller and returns results as an array of [ProcessResult] objects.
  ///
  /// The returned map structure:
  /// ```
  /// {
  ///   'results': [
  ///     {
  ///       'index': int,
  ///       'title': String,
  ///       'state': String, // 'success' or 'failed'
  ///       'descriptions': Map<String, String>, // optional detail fields per test
  ///     },
  ///     ...
  ///   ],
  ///   'completed': bool
  /// }
  /// ```
  ///
  /// Throws a [PlatformException] if the native operation fails.
  Future<Map<String, dynamic>> startTradeIn() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startTradeIn',
      );

      if (result == null) {
        throw PlatformException(
          code: 'NULL_RESULT',
          message: 'Native method returned null result',
        );
      }

      return _convertToStringDynamicMap(result);
    } on PlatformException catch (e) {
      throw PlatformException(
        code: e.code,
        message: 'Failed to start trade-in: ${e.message}',
        details: e.details,
      );
    } catch (e) {
      throw PlatformException(
        code: 'UNEXPECTED_ERROR',
        message: 'Unexpected error during trade-in: $e',
      );
    }
  }

  /// Converts a `Map<dynamic, dynamic>` to `Map<String, dynamic>`.
  ///
  /// This is necessary because MethodChannel returns `Map<dynamic, dynamic>`
  /// but we want type-safe `Map<String, dynamic>` for the public API.
  Map<String, dynamic> _convertToStringDynamicMap(
    Map<dynamic, dynamic> original,
  ) {
    return original.map((key, value) {
      final stringKey = key.toString();

      // Recursively convert nested maps
      if (value is Map<dynamic, dynamic>) {
        return MapEntry(stringKey, _convertToStringDynamicMap(value));
      }

      // Convert lists that may contain maps
      if (value is List) {
        return MapEntry(
          stringKey,
          value.map((item) {
            if (item is Map<dynamic, dynamic>) {
              return _convertToStringDynamicMap(item);
            }
            return item;
          }).toList(),
        );
      }

      return MapEntry(stringKey, value);
    });
  }
}
