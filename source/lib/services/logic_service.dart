import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'dart:convert';

class FormatUtils {
  /// Converts text to Title Case (e.g., "john doe" -> "John Doe")
  static String toTitleCase(String text) {
    if (text.trim().isEmpty) return text;
    return text.trim().split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Formats designation/position by appending location suffixes based on level.
  static String formatDesignation(ABKMUser user) {
    final position = user.position;
    if (position.isEmpty) return 'Member';

    if (position.startsWith('State')) {
      final state = user.state.isNotEmpty ? user.state : 'Unknown State';
      return '$position - $state';
    } else if (position.startsWith('District')) {
      final locationParts = [
        if (user.district.isNotEmpty) user.district,
        if (user.state.isNotEmpty) user.state,
      ].where((s) => s.isNotEmpty).toList();
      final suffix = locationParts.isNotEmpty ? locationParts.join(', ') : 'Unknown District';
      return '$position - $suffix';
    } else if (position.startsWith('City/Tehsil/Block') || position.contains('Tehsil') || position.contains('Block')) {
      final locationParts = [
        if (user.tehsil.isNotEmpty) user.tehsil,
        if (user.district.isNotEmpty) user.district,
        if (user.state.isNotEmpty) user.state,
      ].where((s) => s.isNotEmpty).toList();
      final suffix = locationParts.isNotEmpty ? locationParts.join(', ') : 'Unknown Area';
      return '$position - $suffix';
    } else if (position.startsWith('Village/Unit') || position.contains('Village') || position.contains('Unit')) {
      final locationParts = [
        if (user.village.isNotEmpty) user.village,
        if (user.tehsil.isNotEmpty) user.tehsil,
        if (user.district.isNotEmpty) user.district,
        if (user.state.isNotEmpty) user.state,
      ].where((s) => s.isNotEmpty).toList();
      final suffix = locationParts.isNotEmpty ? locationParts.join(', ') : 'Unknown Village';
      return '$position - $suffix';
    }

    return position;
  }
}

class CacheLogic {
  static const String _CACHE_TIME_PREFIX = 'abkm_ts_';
  static const int MAX_CACHE_AGE_HOURS = 48;
  static const int MAX_CACHE_ITEMS = 50;

  /// Strips large base64 strings from JSON data to avoid exceeding localStorage quota.
  static String getStrippedJson(dynamic data) {
    if (data is List) {
      return json.encode(data.map((item) => _stripItem(item)).toList());
    } else {
      return json.encode(_stripItem(data));
    }
  }

  static Map<String, dynamic> _stripItem(dynamic item) {
    final Map<String, dynamic> map = Map<String, dynamic>.from(
      item is Map ? item : (item as dynamic).toJson()
    );
    
    if (map.containsKey('profileImageUrl') && map['profileImageUrl'] != null) {
      if (map['profileImageUrl'].toString().length > 1000) {
        map['profileImageUrl'] = null; 
      }
    }
    if (map.containsKey('imageUrl') && map['imageUrl'] != null) {
      if (map['imageUrl'].toString().length > 1000) {
        map['imageUrl'] = null;
      }
    }
    return map;
  }

  /// Saves a timestamp for a cache key to track its age.
  static Future<void> markTimestamp(SharedPreferences prefs, String key) async {
    await prefs.setInt(_CACHE_TIME_PREFIX + key, DateTime.now().millisecondsSinceEpoch);
  }

  /// Performs a thorough cleanup of old or excessive cached data.
  static Future<void> performCleanup(SharedPreferences prefs) async {
    final keys = prefs.getKeys();
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxAgeMs = MAX_CACHE_AGE_HOURS * 60 * 60 * 1000;

    // 1. Cleanup by Age
    final List<String> profileKeys = [];
    final List<String> eventKeys = [];

    for (final key in keys) {
      // Check if it's a timestamp key
      if (key.startsWith(_CACHE_TIME_PREFIX)) {
        final timestamp = prefs.getInt(key) ?? 0;
        if (now - timestamp > maxAgeMs) {
          final originalKey = key.replaceFirst(_CACHE_TIME_PREFIX, '');
          await prefs.remove(key);
          await prefs.remove(originalKey);
        }
      } 
      
      // Categorize for capacity cleanup
      if (key.startsWith('abkm_full_profile_')) profileKeys.add(key);
      if (key.startsWith('abkm_full_event_')) eventKeys.add(key);
    }

    // 2. Cleanup by Capacity (Keep only the most recent)
    if (profileKeys.length > MAX_CACHE_ITEMS) {
      profileKeys.sort((a, b) => (prefs.getInt(_CACHE_TIME_PREFIX + b) ?? 0).compareTo(prefs.getInt(_CACHE_TIME_PREFIX + a) ?? 0));
      for (int i = MAX_CACHE_ITEMS; i < profileKeys.length; i++) {
        await prefs.remove(profileKeys[i]);
        await prefs.remove(_CACHE_TIME_PREFIX + profileKeys[i]);
      }
    }

    if (eventKeys.length > MAX_CACHE_ITEMS) {
      eventKeys.sort((a, b) => (prefs.getInt(_CACHE_TIME_PREFIX + b) ?? 0).compareTo(prefs.getInt(_CACHE_TIME_PREFIX + a) ?? 0));
      for (int i = MAX_CACHE_ITEMS; i < eventKeys.length; i++) {
        await prefs.remove(eventKeys[i]);
        await prefs.remove(_CACHE_TIME_PREFIX + eventKeys[i]);
      }
    }
  }
}
