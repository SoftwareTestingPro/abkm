import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/models.dart';
import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';
import '../services/event_logic.dart';
import '../services/logic_service.dart';
import 'event_details_screen.dart';
import 'public_profile_screen.dart';

class ActivityItem {
  final String id;
  final String type; // 'application', 'promotion', 'event', 'log'
  final DateTime createdAt;
  final Map<String, dynamic> rawData;
  
  ActivityItem({required this.id, required this.type, required this.createdAt, required this.rawData});

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'created_at': createdAt.toIso8601String(),
    'rawData': rawData,
  };

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    id: json['id'],
    type: json['type'],
    createdAt: DateTime.parse(json['created_at']),
    rawData: json['rawData'],
  );
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  static List<ActivityItem> cachedActivities = [];
  static Map<String, ABKMEvent> cachedEvents = {};
  static Map<String, ABKMUser> cachedProfiles = {};
  static DateTime? lastGlobalLoad;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  String? _currentUserId;
  List<ActivityItem> _activities = ActivityScreen.cachedActivities;
  Map<String, ABKMUser> _profilesMap = ActivityScreen.cachedProfiles;
  Map<String, ABKMEvent> _eventsMap = ActivityScreen.cachedEvents;
  DateTime? _lastLoadTime = ActivityScreen.lastGlobalLoad;
  DateTime? _lastClearedAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _loadClearedTimestamp();
    await _loadActivities();
  }

  Future<void> _loadClearedTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final clearedAtStr = prefs.getString('abkm_activities_cleared_at');
    if (clearedAtStr != null) {
      setState(() {
        _lastClearedAt = DateTime.parse(clearedAtStr);
      });
    }
  }

  Future<void> _clearAllActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString('abkm_activities_cleared_at', now.toIso8601String());
    setState(() {
      _lastClearedAt = now;
      _activities = []; // Immediately clear the list in UI
    });
  }

  Future<void> _loadActivities() async {
    if (ActivityScreen.lastGlobalLoad != null && 
        DateTime.now().difference(ActivityScreen.lastGlobalLoad!).inSeconds < 15 && 
        ActivityScreen.cachedActivities.isNotEmpty) {
      setState(() {
        _activities = ActivityScreen.cachedActivities;
        _eventsMap = ActivityScreen.cachedEvents;
        _profilesMap = ActivityScreen.cachedProfiles;
        _lastLoadTime = ActivityScreen.lastGlobalLoad;
        _isLoading = false;
      });
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('abkm_user_id') ?? prefs.getString('abkm_mobileNumber');
      if (_currentUserId == null) return;

      final cachedApps = prefs.getString('abkm_cached_activity_apps');
      final cachedEvents = prefs.getString('abkm_cached_activity_events');
      final cachedProfiles = prefs.getString('abkm_cached_activity_profiles');

      if (cachedApps != null && cachedEvents != null && cachedProfiles != null) {
        try {
          final appsList = jsonDecode(cachedApps) as List;
          final eventsList = jsonDecode(cachedEvents) as List;
          final profilesList = jsonDecode(cachedProfiles) as List;

          final cApps = appsList.map((e) => ActivityItem.fromJson(e)).toList();
          final cEvents = eventsList.map((e) => ABKMEvent.fromJson(e)).toList();
          final cProfiles = profilesList.map((p) => ABKMUser.fromJson(p)).toList();

          if (mounted) {
            setState(() {
              _eventsMap = {for (var e in cEvents) e.id: e};
              _profilesMap = {for (var p in cProfiles) p.id: p};
              _activities = cApps;
              _lastLoadTime = DateTime.now();
              _isLoading = false;
            });
          }
        } catch (e) {
          // ignore cache errors
        }
      }

      final feed = await SupabaseService().getActivityFeed(_currentUserId!);

      final List<ActivityItem> freshItems = [];
      final Map<String, ABKMEvent> freshEventsMap = {};
      final Map<String, ABKMUser> freshProfilesMap = {};

      for (var item in feed) {
        try {
          final type = item['activity_type'] ?? 'application';
          final createdAt = item['created_at'] != null ? DateTime.parse(item['created_at']).toLocal() : DateTime.now();
          
          freshItems.add(ActivityItem(
            id: item['id'].toString(),
            type: type,
            createdAt: createdAt,
            rawData: item,
          ));

          if (type == 'application' || type == 'event') {
            final e = item['events'];
            if (e != null) {
              final event = ABKMEvent(
                id: e['id'] ?? '',
                hostId: e['host_id'] ?? '',
                title: e['title'] ?? 'Untitled Event',
                description: e['description'] ?? '',
                date: e['date'] != null ? DateTime.parse(e['date']).toLocal() : DateTime.now(),
                village: e['village'] ?? e['location'] ?? '',
                district: e['district'] ?? e['city'] ?? '',
                state: e['state'] ?? '',
                tehsil: e['tehsil'] ?? '',
                meetingPoint: e['meeting_point'],
                eventType: (e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other,
                approvedMemberIds: List<String>.from(e['approved_member_ids'] ?? []),
                imageUrl: e['image_url'] ?? '',
              );
              freshEventsMap[event.id] = event;

              final h = e['Moderator'];
              if (h != null) {
                final host = ABKMUser(
                  id: h['id'] ?? '',
                  name: h['name'] ?? 'Anonymous',
                  gender: h['gender'] ?? 'Other',
                  userRole: (h['user_role'] ?? 1) < UserRole.values.length ? UserRole.values[h['user_role'] ?? 1] : UserRole.member,
                  bio: h['bio'] ?? '',
                  profileImageUrl: h['profile_image_url'],
                  village: h['village'] ?? h['city'] ?? '',
                  district: h['district'] ?? '',
                  state: h['state'] ?? '',
                  profession: h['profession'] ?? '',
                  education: h['education'] ?? '',
                );
                freshProfilesMap[host.id] = host;
              }
            }

            final a = item['applicant'];
            if (a != null) {
              final applicant = ABKMUser(
                id: a['id'] ?? '',
                name: a['name'] ?? 'Anonymous',
                gender: a['gender'] ?? 'Other',
                userRole: (a['user_role'] ?? 1) < UserRole.values.length ? UserRole.values[a['user_role'] ?? 1] : UserRole.member,
                bio: a['bio'] ?? '',
                profileImageUrl: a['profile_image_url'],
                village: a['village'] ?? a['city'] ?? '',
                district: a['district'] ?? '',
                state: a['state'] ?? '',
                profession: a['profession'] ?? '',
                education: a['education'] ?? '',
              );
              freshProfilesMap[applicant.id] = applicant;
            }
          } else if (type == 'promotion') {
            final t = item['target'];
            if (t != null) {
              final target = ABKMUser(
                id: t['id'] ?? '',
                name: t['name'] ?? 'Anonymous',
                gender: t['gender'] ?? 'Other',
                userRole: (t['user_role'] ?? 1) < UserRole.values.length ? UserRole.values[t['user_role'] ?? 1] : UserRole.member,
                bio: t['bio'] ?? '',
                profileImageUrl: t['profile_image_url'],
                village: t['village'] ?? t['city'] ?? '',
                district: t['district'] ?? '',
                state: t['state'] ?? '',
                profession: t['profession'] ?? '',
                education: t['education'] ?? '',
              );
              freshProfilesMap[target.id] = target;
            }
            
            final r = item['requester'];
            if (r != null) {
              final requester = ABKMUser(
                id: r['id'] ?? '',
                name: r['name'] ?? 'Anonymous',
                gender: r['gender'] ?? 'Other',
                userRole: (r['user_role'] ?? 1) < UserRole.values.length ? UserRole.values[r['user_role'] ?? 1] : UserRole.member,
                bio: r['bio'] ?? '',
                profileImageUrl: r['profile_image_url'],
                village: r['village'] ?? r['city'] ?? '',
                district: r['district'] ?? '',
                state: r['state'] ?? '',
                profession: r['profession'] ?? '',
                education: r['education'] ?? '',
              );
              freshProfilesMap[requester.id] = requester;
            }
          } else if (type == 'log') {
            final e = item['events'];
            if (e != null) {
              final event = ABKMEvent(
                id: e['id'] ?? '',
                hostId: e['host_id'] ?? '',
                title: e['title'] ?? 'Untitled Event',
                description: e['description'] ?? '',
                date: e['date'] != null ? DateTime.parse(e['date']).toLocal() : DateTime.now(),
                village: e['village'] ?? e['location'] ?? '',
                district: e['district'] ?? e['city'] ?? '',
                state: e['state'] ?? '',
                tehsil: e['tehsil'] ?? '',
                meetingPoint: e['meeting_point'],
                eventType: (e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other,
                approvedMemberIds: List<String>.from(e['approved_member_ids'] ?? []),
                imageUrl: e['image_url'] ?? '',
              );
              freshEventsMap[event.id] = event;
            }
            
            final actor = item['actor'];
            if (actor != null) {
              final actorUser = ABKMUser(
                id: actor['id'] ?? '',
                name: actor['name'] ?? 'Anonymous',
                gender: actor['gender'] ?? 'Other',
                userRole: (actor['user_role'] ?? 1) < UserRole.values.length ? UserRole.values[actor['user_role'] ?? 1] : UserRole.member,
                bio: actor['bio'] ?? '',
                profileImageUrl: actor['profile_image_url'],
                village: actor['village'] ?? actor['city'] ?? '',
                district: actor['district'] ?? '',
                state: actor['state'] ?? '',
                profession: actor['profession'] ?? '',
                education: actor['education'] ?? '',
              );
              freshProfilesMap[actorUser.id] = actorUser;
            }

            final target = item['target'];
            if (target != null) {
              final targetUser = ABKMUser(
                id: target['id'] ?? '',
                name: target['name'] ?? 'Anonymous',
                gender: target['gender'] ?? 'Other',
                userRole: (target['user_role'] ?? 1) < UserRole.values.length ? UserRole.values[target['user_role'] ?? 1] : UserRole.member,
                bio: target['bio'] ?? '',
                profileImageUrl: target['profile_image_url'],
                village: target['village'] ?? target['city'] ?? '',
                district: target['district'] ?? '',
                state: target['state'] ?? '',
                profession: target['profession'] ?? '',
                education: target['education'] ?? '',
              );
              freshProfilesMap[targetUser.id] = targetUser;
            }
          }
        } catch (e) {
          debugPrint('Error parsing activity item: $e');
        }
      }

      // Filter items based on last cleared timestamp
      final List<ActivityItem> filteredItems = _lastClearedAt == null 
          ? freshItems 
          : freshItems.where((item) => item.createdAt.isAfter(_lastClearedAt!)).toList();

      if (mounted) {
        setState(() {
          ActivityScreen.cachedActivities = filteredItems;
          ActivityScreen.cachedEvents = freshEventsMap;
          ActivityScreen.cachedProfiles = freshProfilesMap;
          ActivityScreen.lastGlobalLoad = DateTime.now();

          _eventsMap = freshEventsMap;
          _profilesMap = freshProfilesMap;
          _activities = filteredItems;
          _lastLoadTime = ActivityScreen.lastGlobalLoad;
          _isLoading = false;
        });
      }

      try {
        prefs.setString('abkm_cached_activity_apps', CacheLogic.getStrippedJson(freshItems.take(50).toList()));
        prefs.setString('abkm_cached_activity_events', CacheLogic.getStrippedJson(freshEventsMap.values.take(50).toList()));
        prefs.setString('abkm_cached_activity_profiles', CacheLogic.getStrippedJson(freshProfilesMap.values.take(50).toList()));
      } catch (e) {
        debugPrint('Failed to update activity cache: $e');
      }

    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int _getRoleRank(String roleName) {
    switch (roleName.toLowerCase()) {
      case 'blocked':
        return -1;
      case 'member':
        return 0;
      case 'moderator':
        return 1;
      case 'admin':
        return 2;
      case 'superuser':
        return 3;
      default:
        return 0;
    }
  }

  String _getActivityMessage(ActivityItem item) {
    if (item.type == 'promotion') {
      final target = _profilesMap[item.rawData['userId']];
      final requester = _profilesMap[item.rawData['requesterId']];
      final status = PromotionStatus.values[item.rawData['status'] ?? 0];
      final targetRole = (item.rawData['targetRole'] ?? 'admin').toUpperCase();
      
      final targetName = target?.name.split(' ')[0] ?? 'Someone';
      final requesterName = requester?.name.split(' ')[0] ?? 'Someone';
      final targetId = item.rawData['userId']?.toString();
      
      if (targetId == _currentUserId) {
        if (status == PromotionStatus.pending) {
          return 'Promotion to $targetRole pending';
        } else if (status == PromotionStatus.approved) {
          return 'Promoted to $targetRole!';
        } else {
          return 'Promotion to $targetRole declined';
        }
      } else {
        if (status == PromotionStatus.pending) {
          return '$requesterName requested promoting $targetName to $targetRole';
        } else if (status == PromotionStatus.approved) {
          return 'Approved $targetName as $targetRole';
        } else {
          return 'Declined $targetName as $targetRole';
        }
      }
    } else if (item.type == 'event') {
      final title = item.rawData['title'] ?? 'your event';
      final isApproved = item.rawData['is_approved'] ?? false;
      final isDeclined = item.rawData['is_declined'] ?? false;
      
      if (isApproved) return 'Event "$title" is approved & live!';
      if (isDeclined) return 'Event "$title" declined';
      return 'Event "$title" pending approval';
    } else if (item.type == 'log') {
      final logType = item.rawData['type'];
      final title = item.rawData['metadata']?['title'] ?? 'an event';
      final actor = _profilesMap[item.rawData['actor_id']];
      final hostId = item.rawData['metadata']?['host_id'];
      
      final actorName = actor?.name.split(' ')[0] ?? 'Someone';
      
      if (logType == 'event_created') {
        if (item.rawData['actor_id'] == _currentUserId) {
          return 'Event "$title" pending approval';
        } else {
          return 'New event "$title" needs approval';
        }
      } else if (logType == 'event_approved') {
        if (item.rawData['actor_id'] == _currentUserId) {
          return 'Approved event "$title"';
        } else if (hostId == _currentUserId) {
          return 'Event "$title" is approved & live!';
        } else {
          return 'Event "$title" approved by $actorName';
        }
      } else if (logType == 'event_declined') {
        if (item.rawData['actor_id'] == _currentUserId) {
          return 'Declined event "$title"';
        } else if (hostId == _currentUserId) {
          return 'Event "$title" declined';
        } else {
          return 'Event "$title" declined by $actorName';
        }
      } else if (logType == 'broadcast_new_event') {
        return 'New event live: "$title"';
      } else if (logType == 'role_updated') {
        final String oldRoleStr = item.rawData['metadata']?['old_role'] ?? 'unknown';
        final String newRoleStr = item.rawData['metadata']?['new_role'] ?? 'member';
        
        final String newRoleFormatted = newRoleStr.toUpperCase();
        final bool isSelf = item.rawData['metadata']?['target_id'] == _currentUserId;
        
        final target = _profilesMap[item.rawData['metadata']?['target_id']];
        final targetName = target?.name.split(' ')[0] ?? 'Someone';
        
        if (oldRoleStr == 'unknown') {
          if (isSelf) {
            return newRoleStr.toLowerCase() == 'blocked'
                ? 'Your account has been blocked.'
                : 'You\'ve been promoted to $newRoleFormatted!';
          } else {
            return newRoleStr.toLowerCase() == 'blocked'
                ? '$targetName was blocked.'
                : 'Role of $targetName updated to $newRoleFormatted';
          }
        }
        
        final int oldRank = _getRoleRank(oldRoleStr);
        final int newRank = _getRoleRank(newRoleStr);
        
        if (newRoleStr.toLowerCase() == 'blocked') {
          return isSelf 
              ? 'Your account has been blocked.' 
              : '$targetName was blocked.';
        } else if (newRank > oldRank) {
          return isSelf 
              ? 'You\'ve been promoted to $newRoleFormatted!' 
              : '$targetName promoted to $newRoleFormatted';
        } else if (newRank < oldRank) {
          return isSelf 
              ? 'You\'ve been demoted to $newRoleFormatted.' 
              : '$targetName demoted to $newRoleFormatted';
        } else {
          return isSelf 
              ? 'Your role was set to $newRoleFormatted.' 
              : 'Role of $targetName set to $newRoleFormatted';
        }
      } else if (logType == 'position_updated') {
        final newPos = item.rawData['metadata']?['new_position'] ?? 'Member';
        if (item.rawData['metadata']?['target_id'] == _currentUserId) {
          return 'Your position updated to "$newPos"';
        } else {
          final target = _profilesMap[item.rawData['metadata']?['target_id']];
          final targetName = target?.name.split(' ')[0] ?? 'Someone';
          return 'Position of $targetName updated to "$newPos"';
        }
      }
    }

    // Default application message
    final rawApp = item.rawData;
    final event = _eventsMap[rawApp['event_id']];
    if (event == null) return 'Activity updated';
    
    final applicant = _profilesMap[rawApp['applicant_id']];
    final host = _profilesMap[event.hostId];
    
    final applicantName = applicant?.name.split(' ')[0] ?? 'Someone';
    final hostName = host?.name.split(' ')[0] ?? 'Someone';
    final eventTitle = event.title;
    final status = (rawApp['status'] ?? 0) < ApplicationStatus.values.length ? ApplicationStatus.values[rawApp['status'] ?? 0] : ApplicationStatus.pending;
    final isInvitation = rawApp['is_invitation'] ?? false;
    
    String msg = '';

    if (rawApp['applicant_id'] == _currentUserId) {
      if (isInvitation) {
        if (status == ApplicationStatus.invitationPending) {
          msg = 'Invited by $hostName to join "$eventTitle"';
        } else if (status == ApplicationStatus.invitationAccepted) {
          msg = 'Accepted invitation to "$eventTitle"';
        } else if (status == ApplicationStatus.invitationDeclined) {
          msg = 'Declined invitation to "$eventTitle"';
        }
      } else {
        if (status == ApplicationStatus.pending) {
          msg = 'Request to join "$eventTitle" pending';
        } else if (status == ApplicationStatus.approved) {
          msg = 'Approved to join "$eventTitle"!';
        } else if (status == ApplicationStatus.declined) {
          msg = 'Request to join "$eventTitle" declined';
        } else if (status == ApplicationStatus.withdrawn) {
          msg = 'Withdrew request for "$eventTitle"';
        }
      }
    } else if (event.hostId == _currentUserId) {
      if (isInvitation) {
        if (status == ApplicationStatus.invitationPending) {
          msg = 'Invited $applicantName to join "$eventTitle"';
        } else if (status == ApplicationStatus.invitationAccepted) {
          msg = '$applicantName accepted invitation to "$eventTitle"';
        } else if (status == ApplicationStatus.invitationDeclined) {
          msg = '$applicantName declined invitation to "$eventTitle"';
        }
      } else {
        if (status == ApplicationStatus.pending) {
          msg = '$applicantName wants to join "$eventTitle"';
        } else if (status == ApplicationStatus.approved) {
          msg = 'Approved $applicantName for "$eventTitle"';
        } else if (status == ApplicationStatus.declined) {
          msg = 'Declined $applicantName for "$eventTitle"';
        } else if (status == ApplicationStatus.withdrawn) {
          msg = '$applicantName withdrew request for "$eventTitle"';
        }
      }
    } else {
      // General view for system-wide applications (Admins/Super Admins)
      if (isInvitation) {
        if (status == ApplicationStatus.invitationPending) {
          msg = '$hostName invited $applicantName to "$eventTitle"';
        } else if (status == ApplicationStatus.invitationAccepted) {
          msg = '$applicantName accepted $hostName\'s invite to "$eventTitle"';
        } else if (status == ApplicationStatus.invitationDeclined) {
          msg = '$applicantName declined $hostName\'s invite to "$eventTitle"';
        }
      } else {
        if (status == ApplicationStatus.pending) {
          msg = '$applicantName wants to join "$eventTitle"';
        } else if (status == ApplicationStatus.approved) {
          msg = '$applicantName approved for "$eventTitle"';
        } else if (status == ApplicationStatus.declined) {
          msg = '$applicantName declined for "$eventTitle"';
        } else if (status == ApplicationStatus.withdrawn) {
          msg = '$applicantName withdrew request for "$eventTitle"';
        }
      }
    }
    if (msg.isEmpty) msg = 'Activity on $eventTitle';
    return msg;
  }

  String _getActivityCategory(ActivityItem item) {
    if (item.type == 'promotion') return 'Promotion';
    if (item.type == 'event') return 'Event';
    if (item.type == 'log') {
      final logType = item.rawData['type'];
      if (logType == 'broadcast_new_event') return 'System';
      if (logType == 'role_updated' || logType == 'position_updated') {
        final newRoleStr = item.rawData['metadata']?['new_role'] ?? 'member';
        if (newRoleStr.toLowerCase() == 'blocked') return 'System';
        return 'Role';
      }
      return 'Event';
    }
    return 'Join Request';
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Event':
        return const Color(0xFFD97706); // Amber
      case 'Promotion':
        return const Color(0xFF7C3AED); // Purple
      case 'Role':
        return const Color(0xFF2563EB); // Royal Blue
      case 'System':
        return const Color(0xFFE11D48); // Rose
      case 'Join Request':
      default:
        return const Color(0xFF059669); // Emerald
    }
  }

  Color _getCategoryBgColor(String category) {
    switch (category) {
      case 'Event':
        return const Color(0xFFFFF7ED); // Light Amber
      case 'Promotion':
        return const Color(0xFFF5F3FF); // Light Purple
      case 'Role':
        return const Color(0xFFEFF6FF); // Light Blue
      case 'System':
        return const Color(0xFFFFF1F2); // Light Rose
      case 'Join Request':
      default:
        return const Color(0xFFECFDF5); // Light Emerald
    }
  }

  IconData _getActivityIcon(ActivityItem item) {
    if (item.type == 'promotion') {
      final status = PromotionStatus.values[item.rawData['status'] ?? 0];
      return status == PromotionStatus.approved ? Icons.workspace_premium_rounded : Icons.shield_rounded;
    } else if (item.type == 'event') {
      final isApproved = item.rawData['is_approved'] ?? false;
      final isDeclined = item.rawData['is_declined'] ?? false;
      if (isApproved) return Icons.check_circle_rounded;
      if (isDeclined) return Icons.cancel_rounded;
      return Icons.hourglass_empty_rounded;
    } else if (item.type == 'log') {
      final logType = item.rawData['type'];
      if (logType == 'event_created') return Icons.add_circle_outline_rounded;
      if (logType == 'event_approved') return Icons.check_circle_rounded;
      if (logType == 'event_declined') return Icons.cancel_rounded;
      if (logType == 'broadcast_new_event') return Icons.campaign_rounded;
      if (logType == 'role_updated') {
        final newRoleStr = item.rawData['metadata']?['new_role'] ?? 'member';
        if (newRoleStr.toLowerCase() == 'blocked') {
          return Icons.block_rounded;
        }
        final oldRoleStr = item.rawData['metadata']?['old_role'] ?? 'unknown';
        if (oldRoleStr != 'unknown') {
          final int oldRank = _getRoleRank(oldRoleStr);
          final int newRank = _getRoleRank(newRoleStr);
          if (newRank < oldRank) {
            return Icons.arrow_downward_rounded;
          }
        }
        return Icons.stars_rounded;
      }
      if (logType == 'position_updated') return Icons.badge_rounded;
    }
    // Join requests / applications
    final rawApp = item.rawData;
    final status = (rawApp['status'] ?? 0) < ApplicationStatus.values.length ? ApplicationStatus.values[rawApp['status'] ?? 0] : ApplicationStatus.pending;
    if (status == ApplicationStatus.approved) return Icons.check_circle_rounded;
    if (status == ApplicationStatus.declined) return Icons.cancel_rounded;
    return Icons.person_add_rounded;
  }

  Map<String, List<ActivityItem>> _groupActivities(List<ActivityItem> items) {
    final Map<String, List<ActivityItem>> grouped = {
      'Today': [],
      'Yesterday': [],
      'Earlier this week': [],
      'Older': [],
    };
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));

    for (var item in items) {
      final date = DateTime(item.createdAt.year, item.createdAt.month, item.createdAt.day);
      if (date == today) {
        grouped['Today']!.add(item);
      } else if (date == yesterday) {
        grouped['Yesterday']!.add(item);
      } else if (date.isAfter(startOfWeek)) {
        grouped['Earlier this week']!.add(item);
      } else {
        grouped['Older']!.add(item);
      }
    }
    
    // Remove empty categories
    grouped.removeWhere((key, list) => list.isEmpty);
    return grouped;
  }

  Widget _buildActivityCard(ActivityItem item, ABKMUser? otherPerson, String? imageUrl, VoidCallback? onTap, int index) {
    final category = _getActivityCategory(item);
    final accentColor = _getCategoryColor(category);
    final bgColor = _getCategoryBgColor(category);
    final text = _getActivityMessage(item);
    final timeStr = EventLogic.formatDateTime(item.createdAt);
    final iconData = _getActivityIcon(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 6,
                color: accentColor,
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: accentColor.withOpacity(0.08),
                                backgroundImage: imageUrl != null && imageUrl.startsWith('http')
                                    ? NetworkImage(imageUrl) as ImageProvider
                                    : imageUrl != null
                                        ? MemoryImage(base64Decode(imageUrl))
                                        : null,
                                child: imageUrl == null
                                    ? Icon(
                                        iconData,
                                        color: accentColor,
                                        size: 24,
                                      )
                                    : null,
                              ),
                              if (imageUrl != null)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      iconData,
                                      size: 12,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: bgColor,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: accentColor.withOpacity(0.2), width: 0.8),
                                      ),
                                      child: Text(
                                        category.toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: accentColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      timeStr,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.grey[400],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  text,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded, color: Colors.grey[400], size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate(delay: (index * 50).ms).fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutQuad);
  }

  Widget _buildPageBackground() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/app_background.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    ActivityScreen.lastGlobalLoad = null;
    await _loadActivities();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topPadding = MediaQuery.of(context).padding.top;
    
    // Group activities by date
    final grouped = _groupActivities(_activities);
    final List<Widget> listItems = [];
    int globalIndex = 0;

    grouped.forEach((categoryName, items) {
      listItems.add(
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10, left: 4),
          child: Text(
            categoryName,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
              letterSpacing: 0.3,
            ),
          ),
        ).animate().fadeIn(duration: 300.ms),
      );

      for (var item in items) {
        ABKMUser? otherPerson;
        String? imageUrl;
        VoidCallback? onTap;

        if (item.type == 'promotion') {
          final target = _profilesMap[item.rawData['userId']];
          final requester = _profilesMap[item.rawData['requesterId']];
          otherPerson = (item.rawData['userId'] == _currentUserId) ? requester : target;
          imageUrl = otherPerson?.profileImageUrl;

          final targetId = item.rawData['userId']?.toString();
          if (targetId != null) {
            onTap = () {
              final targetUser = _profilesMap[targetId];
              if (targetUser != null) {
                Navigator.push(context, MaterialPageRoute(builder: (context) => PublicProfileScreen(user: targetUser)));
              }
            };
          }
        } else if (item.type == 'log') {
          final logType = item.rawData['type'];
          final eventId = item.rawData['target_id'] ?? item.rawData['metadata']?['event_id'];
          final actor = _profilesMap[item.rawData['actor_id']];
          if (item.rawData['actor_id'] != _currentUserId) {
            otherPerson = actor;
            imageUrl = otherPerson?.profileImageUrl;
          } else {
            final targetId = item.rawData['target_id'] ?? item.rawData['metadata']?['target_id'];
            if (targetId != null) {
              otherPerson = _profilesMap[targetId];
              imageUrl = otherPerson?.profileImageUrl;
            }
          }

          if (logType == 'broadcast_new_event' || logType == 'event_created' || logType == 'event_approved' || logType == 'event_declined') {
            onTap = () {
              final id = eventId?.toString();
              if (id != null) {
                final event = _eventsMap[id];
                if (event != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)));
                }
              }
            };
          } else if (logType == 'role_updated' || logType == 'position_updated') {
            final targetId = item.rawData['target_id'] ?? item.rawData['metadata']?['target_id'];
            if (targetId != null) {
              onTap = () {
                final targetUser = _profilesMap[targetId.toString()];
                if (targetUser != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => PublicProfileScreen(user: targetUser)));
                }
              };
            }
          }
        } else if (item.type == 'event') {
          final event = _eventsMap[item.rawData['id'].toString()];
          if (event != null) {
            otherPerson = _profilesMap[event.hostId];
            imageUrl = otherPerson?.profileImageUrl;
            onTap = () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)),
              );
            };
          }
        } else {
          final event = _eventsMap[item.rawData['event_id']];
          if (event != null) {
            otherPerson = (item.rawData['applicant_id'] == _currentUserId) ? _profilesMap[event.hostId] : _profilesMap[item.rawData['applicant_id']];
            imageUrl = otherPerson?.profileImageUrl;
            onTap = () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)),
              );
            };
          }
        }

        // Filter out cleared activities
        if (_lastClearedAt == null || item.createdAt.isAfter(_lastClearedAt!)) {
          listItems.add(
            _buildActivityCard(item, otherPerson, imageUrl, onTap, globalIndex),
          );
          globalIndex++;
        }
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          _buildPageBackground(),
          _isLoading
              ? ListView.builder(
                  padding: EdgeInsets.only(top: topPadding + 10, left: 16, right: 16),
                  itemCount: 5,
                  itemBuilder: (context, index) => _buildSkeletonActivityCard(),
                )
              : RefreshIndicator(
                  onRefresh: _handleRefresh,
                  child: _activities.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.35),
                            Center(
                              child: Text(
                                'No activities yet.',
                                style: GoogleFonts.inter(color: Colors.grey),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.only(top: topPadding + 10, left: 20, right: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Activity Feed',
                                    style: GoogleFonts.poppins(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _clearAllActivities,
                                    child: Text(
                                      'Clear All',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 10, left: 16, right: 16, bottom: 24),
                                children: listItems,
                              ),
                            ),
                          ],
                        ),
                ),
        ],
      ),
    );
  }

  Widget _buildSkeletonActivityCard() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.08), Colors.white),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, color: theme.colorScheme.primary.withOpacity(0.1)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 150,
                  height: 14,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(7)),
                ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, delay: 200.ms, color: theme.colorScheme.primary.withOpacity(0.1)),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 10,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)),
                ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, delay: 400.ms, color: theme.colorScheme.primary.withOpacity(0.1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
