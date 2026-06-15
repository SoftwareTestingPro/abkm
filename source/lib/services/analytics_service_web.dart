// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

void initAnalytics() {
  debugPrint('Analytics: Web Analytics Initialized.');
}

void logEvent(String name, Map<String, dynamic>? parameters) {
  try {
    if (js.context.hasProperty('gtag')) {
      if (parameters != null) {
        js.context.callMethod('gtag', ['event', name, js.JsObject.jsify(parameters)]);
      } else {
        js.context.callMethod('gtag', ['event', name]);
      }
      debugPrint('Analytics (Web): Logged event $name with params $parameters');
    } else {
      debugPrint('Analytics (Web): gtag is not available in window context');
    }
  } catch (e) {
    debugPrint('Analytics (Web): Error logging event $name: $e');
  }
}

void logScreen(String screenName) {
  logEvent('screen_view', {
    'screen_name': screenName,
  });
}
