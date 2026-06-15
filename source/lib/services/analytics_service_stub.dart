import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _measurementId = 'G-SW62G7VM28';
String? _clientId;

Future<String> _getClientId() async {
  if (_clientId != null) return _clientId!;
  try {
    final prefs = await SharedPreferences.getInstance();
    String? cid = prefs.getString('ga_client_id');
    if (cid == null) {
      cid = const Uuid().v4();
      await prefs.setString('ga_client_id', cid);
    }
    _clientId = cid;
    return cid;
  } catch (e) {
    return 'anonymous_android_user';
  }
}

void initAnalytics() {
  debugPrint('Analytics: Android/Native Analytics Initialized.');
  logEvent('app_start', null);
}

void logEvent(String name, Map<String, dynamic>? parameters) async {
  debugPrint('Analytics (Native): Queueing event "$name" with params $parameters');
  try {
    final cid = await _getClientId();
    final client = HttpClient();
    
    // Format parameters or metadata to include in the GA4 collect request
    final uri = Uri.parse('https://www.google-analytics.com/g/collect?v=2&tid=$_measurementId&cid=$cid&en=$name');
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    
    if (parameters != null) {
      request.write(jsonEncode(parameters));
    }
    
    final response = await request.close();
    debugPrint('Analytics (Native): Sent event "$name". Status code: ${response.statusCode}');
  } catch (e) {
    debugPrint('Analytics (Native): Failed to send event "$name": $e');
  }
}

void logScreen(String screenName) {
  logEvent('screen_view', {
    'screen_name': screenName,
  });
}
