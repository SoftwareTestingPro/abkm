import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

Future<void> checkAndReloadWeb() async {
  if (!kIsWeb) return;
  try {
    // 1. Read bundled build ID
    String localBuildId = '';
    try {
      localBuildId = (await rootBundle.loadString('assets/images/build_id.txt')).trim();
    } catch (e) {
      debugPrint('Failed to load local build_id.txt: $e');
      return; // If we can't load the local build ID, do nothing.
    }
    
    if (localBuildId.isEmpty) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = 'build_id.txt?t=$timestamp';
    
    final request = await html.HttpRequest.request(url, method: 'GET');
    if (request.status == 200) {
      final serverBuildId = (request.responseText ?? '').trim();
      
      // Safeguard: If the server returned HTML content (e.g., fallback index.html for 404),
      // we must ignore it to prevent infinite reload loops in development or on missing files.
      if (serverBuildId.startsWith('<!DOCTYPE') || serverBuildId.startsWith('<html') || serverBuildId.startsWith('<body')) {
        debugPrint('Web update check: Server returned HTML page instead of plain-text build ID. Ignoring.');
        return;
      }

      if (serverBuildId.isNotEmpty && serverBuildId != localBuildId) {
        debugPrint('New web build detected! Local: $localBuildId, Server: $serverBuildId. Reloading page...');
        
        // Unregister service workers to avoid stale loading
        try {
          if (html.window.navigator.serviceWorker != null) {
            final registrations = await html.window.navigator.serviceWorker!.getRegistrations();
            for (var registration in registrations) {
              await registration.unregister();
            }
          }
        } catch (e) {
          debugPrint('Error unregistering service workers: $e');
        }
        
        // Hard reload
        html.window.location.reload();
      } else {
        debugPrint('Web app is up-to-date. Build ID: $localBuildId');
      }
    }
  } catch (e) {
    debugPrint('Error checking for web update: $e');
  }
}
