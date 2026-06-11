import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'logic_service.dart';
import '../data/india_location_data.dart';

class SupabaseService {
  static final client = Supabase.instance.client;

  String _getIstIsoString([DateTime? dt]) {
    final DateTime target = dt ?? DateTime.now();
    final DateTime ist = target.toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${ist.year.toString().padLeft(4, '0')}-'
        '${ist.month.toString().padLeft(2, '0')}-'
        '${ist.day.toString().padLeft(2, '0')}T'
        '${ist.hour.toString().padLeft(2, '0')}:'
        '${ist.minute.toString().padLeft(2, '0')}:'
        '${ist.second.toString().padLeft(2, '0')}.${ist.millisecond.toString().padLeft(3, '0')}+05:30';
  }

  // --- Profile Operations ---
  
  Future<void> upsertProfile(ABKMUser user) async {
    await client.from('profiles').upsert({
      'id': user.id,
      'name': user.name,
      'gender': user.gender,
      'marital_status': user.maritalStatus,
      'dob': user.dob?.toIso8601String(),
      'user_role': user.userRole.index,
      'bio': user.bio,
      'profile_image_url': user.profileImageUrl,
      'state': user.state,
      'district': user.district,
      'tehsil': user.tehsil,
      'village': user.village,
      'sector': user.sector,
      'profession': user.profession,
      'education': user.education,
      'referral_mobile': user.referralMobile,
      'position': user.position,
      'is_blocked': user.isBlocked,
      'is_deleted': user.isDeleted,
      'last_login': _getIstIsoString(user.lastLogin),
      'blocked_by': user.blockedBy,
    });
    
    final prefs = await SharedPreferences.getInstance();

    // Recalculate and promote referrers up the chain recursively
    if (user.referralMobile != null && user.referralMobile!.isNotEmpty) {
      void _promoteChain(String rid) async {
        try {
          final parentProfile = await getProfile(rid, forceRefresh: true);
          if (parentProfile != null && parentProfile.referralMobile != null && parentProfile.referralMobile!.isNotEmpty) {
            _promoteChain(parentProfile.referralMobile!);
          }
        } catch (chainErr) {
          debugPrint('Error in recursive chain promotion: $chainErr');
        }
      }
      _promoteChain(user.referralMobile!);
    }

    try {
      final refData = await getReferralAnalytics();
      final Map<String, int> allPoints = refData['points'] ?? {};
      final pts = allPoints[user.id] ?? 0;
      final List<String> generalPositions = ['Member', 'Primary Member', 'Active Member', 'Executive Member', ''];
      if (generalPositions.contains(user.position)) {
        String newPos = 'Member';
        if (pts >= 10000) {
          newPos = 'Executive Member';
        } else if (pts >= 1000) {
          newPos = 'Active Member';
        } else if (pts >= 100) {
          newPos = 'Primary Member';
        }
        
        if (newPos != user.position) {
          await client.from('profiles').update({'position': newPos}).eq('id', user.id);
          debugPrint('User ${user.id} automatically promoted to $newPos!');
        }
      }
    } catch (e) {
      debugPrint('Error promoting user themselves on profile upsert: $e');
    }
    
    // Clear local caches to ensure fresh data on next fetch
    await prefs.remove('abkm_full_profile_${user.id}');
    await prefs.remove('abkm_cached_home_profiles'); // Force Home Screen to refresh discovery
    
    debugPrint('Successfully upserted profile for ${user.id}: ${user.profession}');
  }

  /// Fetches a profile that has been soft-deleted. Used during login to detect
  /// if an account was previously deleted and needs re-activation.
  Future<ABKMUser?> getDeletedProfile(String userId) async {
    try {
      final response = await client
          .from('profiles')
          .select('id, referral_mobile, is_deleted')
          .eq('id', userId)
          .eq('is_deleted', true)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (response == null) return null;
      return ABKMUser(
        id: response['id'],
        name: 'Deleted User',
        gender: 'Other',
        userRole: UserRole.member,
        bio: '',
        isDeleted: true,
        referralMobile: response['referral_mobile'],
      );
    } catch (e) {
      debugPrint('Error fetching deleted profile for $userId: $e');
      return null;
    }
  }

  /// Re-activates a soft-deleted profile: clears the is_deleted flag and
  /// resets the placeholder name/data so the user can re-fill their details.
  /// Crucially, referral_mobile is NOT touched — the chain remains intact.
  Future<void> reactivateProfile(String userId) async {
    await client.from('profiles').update({
      'is_deleted': false,
      'name': '',          // User will re-fill this in ProfileScreen
      'bio': '',
      'gender': 'Other',
      'position': 'Member',
      // referral_mobile intentionally left untouched
    }).eq('id', userId).timeout(const Duration(seconds: 10));
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('abkm_full_profile_$userId');
    debugPrint('Profile $userId re-activated. Referral chain preserved.');
  }

  static String normalizePhone(String phone) {
    String clean = phone.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[^\d]'), '');
    if (clean.length == 12 && clean.startsWith('91')) {
      clean = clean.substring(2);
    } else if (clean.length == 11 && clean.startsWith('0')) {
      clean = clean.substring(1);
    }
    return clean;
  }

  static int calculateTotalPoints(String userId, Map<String, List<String>> childrenOf, Map<String, bool> isDeletedMap) {
    Map<String, int> computedPoints = {};
    int calculate(String uid, Set<String> visited) {
      final normUid = normalizePhone(uid);
      if (computedPoints.containsKey(normUid)) return computedPoints[normUid]!;
      if (visited.contains(normUid)) return 0;
      visited.add(normUid);
      
      final children = childrenOf[normUid] ?? [];
      int total = 0;
      for (var childId in children) {
        final normChildId = normalizePhone(childId);
        final bool isChildDeleted = isDeletedMap[normChildId] ?? false;
        if (!isChildDeleted) {
          total += 5;
        }
        total += calculate(childId, visited);
      }
      
      visited.remove(normUid);
      computedPoints[normUid] = total;
      return total;
    }
    return calculate(userId, {});
  }

  Future<Map<String, dynamic>> getReferralAnalytics() async {
    Map<String, List<String>> childrenOf = {};
    Map<String, int> directCounts = {};
    Map<String, bool> isDeletedMap = {};
    try {
      // Fetch all profiles including soft-deleted ones to maintain chain integrity
      final allReferrals = await client
          .from('profiles')
          .select('id, referral_mobile, is_deleted')
          .limit(100000);
      
      for (var rec in allReferrals as List) {
        final String childId = normalizePhone(rec['id'] ?? '');
        final String parentId = normalizePhone(rec['referral_mobile'] ?? '');
        final bool isDeleted = rec['is_deleted'] ?? false;
        isDeletedMap[childId] = isDeleted;
        if (childId.isNotEmpty && parentId.isNotEmpty) {
          childrenOf[parentId] = (childrenOf[parentId] ?? [])..add(childId);
          if (!isDeleted) {
            directCounts[parentId] = (directCounts[parentId] ?? 0) + 1;
          }
        }
      }
    } catch (e) {
      debugPrint('Error batch fetching referral tree: $e');
    }

    Map<String, int> points = {};
    final allUserIds = childrenOf.keys.toSet();
    for (var rec in childrenOf.values) {
      allUserIds.addAll(rec);
    }
    
    for (var uid in allUserIds) {
      final normUid = normalizePhone(uid);
      points[normUid] = calculateTotalPoints(normUid, childrenOf, isDeletedMap);
    }

    return {
      'points': points,
      'directCounts': directCounts,
    };
  }

  Future<ABKMUser?> getProfile(String userId, {bool forceRefresh = false}) async {

    final prefs = await SharedPreferences.getInstance();
    
    if (!forceRefresh) {
      final cachedData = prefs.getString('abkm_full_profile_$userId');
      if (cachedData != null) {
        try {
          return ABKMUser.fromJson(json.decode(cachedData));
        } catch (e) {
          debugPrint('Cache parsing error for profile $userId: $e');
        }
      }
    } else {
      await prefs.remove('abkm_full_profile_$userId');
      await prefs.remove('abkm_cached_home_profiles');
    }

    final response = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .or('is_deleted.eq.false,is_deleted.is.null')
        .maybeSingle()
        .timeout(const Duration(seconds: 10));
    
    if (response == null) {
      debugPrint('SupabaseService: getProfile($userId) returned NULL response');
      return null;
    }
    
    debugPrint('SupabaseService: getProfile($userId) raw position: ${response['position']}');
    int referralCount = 0;
    int points = 0;
    try {
      final refData = await getReferralAnalytics();
      final Map<String, int> allPoints = refData['points'] ?? {};
      final Map<String, int> allDirectCounts = refData['directCounts'] ?? {};
      
      final String normId = normalizePhone(userId);
      points = allPoints[normId] ?? 0;
      referralCount = allDirectCounts[normId] ?? 0;
    } catch (e) {
      debugPrint('Error getting referral count/points for $userId: $e');
    }
    
    String position = response['position'] ?? 'Member';
    final List<String> generalPositions = ['Member', 'Primary Member', 'Active Member', 'Executive Member', ''];
    if (generalPositions.contains(position)) {
      String newPosition = 'Member';
      if (points >= 10000) {
        newPosition = 'Executive Member';
      } else if (points >= 1000) {
        newPosition = 'Active Member';
      } else if (points >= 100) {
        newPosition = 'Primary Member';
      }
      
      if (newPosition != position) {
        try {
          await client.from('profiles').update({'position': newPosition}).eq('id', userId).timeout(const Duration(seconds: 10));
          position = newPosition;
          debugPrint('Automatically promoted user $userId to $newPosition based on $points points.');
        } catch (e) {
          debugPrint('Error auto-promoting user $userId: $e');
        }
      }
    }
    
    final user = ABKMUser(
      id: response['id'],
      name: response['name'],
      gender: response['gender'],
      maritalStatus: response['marital_status'] ?? 'Unmarried',
      dob: response['dob'] != null ? DateTime.parse(response['dob']) : null,
      userRole: (response['user_role'] ?? 0) < UserRole.values.length 
          ? UserRole.values[response['user_role'] ?? 0] 
          : UserRole.member,
      bio: response['bio'] ?? '',
      profileImageUrl: response['profile_image_url'],
      state: response['state'] ?? '',
      district: response['district'] ?? '',
      tehsil: response['tehsil'] ?? '',
      village: response['village'] ?? '',
      sector: response['sector'] ?? '',
      profession: response['profession'] ?? '',
      education: response['education'] ?? '',
      referralMobile: response['referral_mobile'],
      position: position,
      isBlocked: response['is_blocked'] ?? false,
      isDeleted: response['is_deleted'] ?? false,
      points: points,
      referralCount: referralCount,
      lastLogin: response['last_login'] != null ? DateTime.parse(response['last_login']).toLocal() : null,
      blockedBy: response['blocked_by'],
    );

    debugPrint('SupabaseService: getProfile($userId) final mapped position: ${user.position}');

    final String cacheKey = 'abkm_full_profile_$userId';
    await prefs.setString(cacheKey, json.encode(user.toJson()));
    await CacheLogic.markTimestamp(prefs, cacheKey);
    return user;
  }

  Future<ABKMUser?> getNationalPresident() async {
    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('position', 'National President')
          .or('is_deleted.eq.false,is_deleted.is.null')
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      
      String pos = response['position'] ?? 'Member';
      return ABKMUser(
        id: response['id'],
        name: response['name'],
        gender: response['gender'],
        maritalStatus: response['marital_status'] ?? 'Unmarried',
        dob: response['dob'] != null ? DateTime.parse(response['dob']) : null,
        userRole: (response['user_role'] ?? 0) < UserRole.values.length 
            ? UserRole.values[response['user_role'] ?? 0] 
            : UserRole.member,
        bio: response['bio'] ?? '',
        profileImageUrl: response['profile_image_url'],
        state: response['state'] ?? '',
        district: response['district'] ?? '',
        tehsil: response['tehsil'] ?? '',
        village: response['village'] ?? '',
        sector: response['sector'] ?? '',
        profession: response['profession'] ?? '',
        education: response['education'] ?? '',
        referralMobile: response['referral_mobile'],
        position: pos,
        isBlocked: response['is_blocked'] ?? false,
        isDeleted: response['is_deleted'] ?? false,
        points: 0,
        referralCount: 0,
        lastLogin: response['last_login'] != null ? DateTime.parse(response['last_login']).toLocal() : null,
      );
    } catch (e) {
      debugPrint('Error getting National President: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getProfilePermissions(String userId) async {
    try {
      final response = await client
          .from('profiles')
          .select('user_role, position, is_blocked')
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error getting profile permissions: $e');
      return null;
    }
  }

  Future<void> updateLastLogin(String userId) async {
    try {
      await client.from('profiles').update({
        'last_login': _getIstIsoString(),
      }).eq('id', userId);
      debugPrint('Successfully updated last login for $userId');
    } catch (e) {
      debugPrint('Error updating last login: $e');
    }
  }

  // --- Role & Promotion Operations ---

  Future<void> updateUserRole(String userId, UserRole newRole, {String? actorId}) async {
    try {
      // Fetch old role before updating to log promotion/demotion
      String oldRoleName = 'unknown';
      try {
        final currentProfile = await client
            .from('profiles')
            .select('user_role')
            .eq('id', userId)
            .maybeSingle();
        if (currentProfile != null && currentProfile['user_role'] != null) {
          final int roleIndex = currentProfile['user_role'] as int;
          if (roleIndex >= 0 && roleIndex < UserRole.values.length) {
            oldRoleName = UserRole.values[roleIndex].name;
          }
        }
      } catch (e) {
        debugPrint('Error fetching old role before update: $e');
      }

      final response = await client.from('profiles').update({
        'user_role': newRole.index
      }).eq('id', userId).select();
      
      if ((response as List).isEmpty) {
        debugPrint('Update failed for user $userId: No rows affected. Check permissions/ID.');
      }
      
      final String? finalActorId = actorId ?? (await SharedPreferences.getInstance()).getString('abkm_user_id');
      if (finalActorId != null) {
        await _logActivity(
          actorId: finalActorId,
          targetId: userId,
          type: 'role_updated',
          metadata: {
            'old_role': oldRoleName,
            'new_role': newRole.name,
            'target_id': userId,
          },
        );
      }
      
      debugPrint('Successfully updated user $userId role to $newRole (old: $oldRoleName)');
      
      // Clear caches
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('abkm_full_profile_$userId');
      await prefs.remove('abkm_cached_home_profiles');
      debugPrint('Cleared caches for $userId after role update');
    } catch (e) {
      debugPrint('Error updating user role for $userId: $e');
      rethrow;
    }
  }

  Future<void> updateUserPosition(String userId, String newPosition, {String? actorId}) async {
    try {
      debugPrint('Updating user $userId position to: $newPosition');
      final response = await client.from('profiles').update({
        'position': newPosition
      }).eq('id', userId).select();

      if ((response as List).isEmpty) {
        debugPrint('Update failed for user $userId: No rows affected. Check permissions/ID.');
      }

      final String? finalActorId = actorId ?? (await SharedPreferences.getInstance()).getString('abkm_user_id');
      if (finalActorId != null) {
        await _logActivity(
          actorId: finalActorId,
          targetId: userId,
          type: 'position_updated',
          metadata: {
            'new_position': newPosition,
            'target_id': userId,
          },
        );
      }
      
      debugPrint('Successfully updated user $userId position to $newPosition');

      // Clear caches
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('abkm_full_profile_$userId');
      await prefs.remove('abkm_cached_home_profiles');
      debugPrint('Cleared caches for $userId after position update');
    } catch (e) {
      debugPrint('Error updating user position for $userId: $e');
      rethrow;
    }
  }

  Future<void> toggleUserBlockStatus(String userId, bool isBlocked, {String? actorId}) async {
    try {
      await client.from('profiles').update({
        'is_blocked': isBlocked,
        'blocked_by': isBlocked ? actorId : null,
      }).eq('id', userId);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('abkm_full_profile_$userId');
      await prefs.remove('abkm_cached_home_profiles');
    } catch (e) {
      debugPrint('Error toggling block status: $e');
      rethrow;
    }
  }

  Future<void> requestPromotion({
    required String userId,
    required String requesterId,
    required UserRole currentRequesterRole,
    UserRole targetRole = UserRole.admin,
  }) async {
    try {
      if (currentRequesterRole == UserRole.superUser) {
        // SuperUser can directly update the role
        await updateUserRole(userId, targetRole, actorId: requesterId);
        
        // Log as approved activity - wrap in try-catch to avoid breaking flow on RLS issues
        try {
          await client.from('promotion_requests').insert({
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'userId': userId,
            'requesterId': requesterId,
            'targetRole': targetRole.name,
            'status': PromotionStatus.approved.index,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        } catch (auditError) {
          debugPrint('Service Audit Warning: Could not log promotion request: $auditError');
        }
      } else if (currentRequesterRole == UserRole.admin || currentRequesterRole == UserRole.moderator) {
        await client.from('promotion_requests').insert({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'userId': userId,
          'requesterId': requesterId,
          'targetRole': targetRole.name,
          'status': PromotionStatus.pending.index,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Critical error in requestPromotion: $e');
      rethrow;
    }
  }

  Future<List<PromotionRequest>> getPendingPromotions() async {
    final response = await client
        .from('promotion_requests')
        .select()
        .eq('status', PromotionStatus.pending.index);
    
    return (response as List).map((r) => PromotionRequest.fromJson(r)).toList();
  }

  Future<PromotionRequest?> getPendingPromotionForUser(String userId) async {
    final response = await client
        .from('promotion_requests')
        .select()
        .eq('userId', userId)
        .eq('status', PromotionStatus.pending.index)
        .maybeSingle();
    
    if (response == null) return null;
    return PromotionRequest.fromJson(response);
  }

  Future<void> handlePromotionRequest(String requestId, PromotionStatus newStatus) async {
    final requestData = await client
        .from('promotion_requests')
        .select()
        .eq('id', requestId)
        .single();
    
    await client.from('promotion_requests').update({
      'status': newStatus.index
    }).eq('id', requestId);

    if (newStatus == PromotionStatus.approved) {
      final prefs = await SharedPreferences.getInstance();
      final String? actorId = prefs.getString('abkm_user_id');
      await updateUserRole(requestData['userId'], UserRole.admin, actorId: actorId);
    }
  }

  Future<List<ABKMUser>> getProfiles({String? state, int? limit}) async {
    var query = client.from('profiles').select().or('is_deleted.eq.false,is_deleted.is.null');
    if (state != null) {
      query = query.eq('state', state);
    }
    final response = await query;
    
    Map<String, int> allPoints = {};
    Map<String, int> allDirectCounts = {};
    try {
      final refData = await getReferralAnalytics();
      allPoints = refData['points'] ?? {};
      allDirectCounts = refData['directCounts'] ?? {};
    } catch (e) {
      debugPrint('Error fetching referral analytics in getProfiles: $e');
    }

    return (response as List).map((p) {
      final String userId = p['id'] ?? '';
      final String normId = normalizePhone(userId);
      final int pts = allPoints[normId] ?? 0;
      final int refCount = allDirectCounts[normId] ?? 0;
      
      final user = ABKMUser.fromJson(p);
      return user.copyWith(
        points: pts,
        referralCount: refCount,
      );
    }).toList().cast<ABKMUser>();
  }

  Future<List<ABKMUser>> getProfilesLight({String? state, int? limit}) async {
    // Only select essential fields for cards
    var query = client
        .from('profiles')
        .select('id, name, profile_image_url, district, position, user_role, profession, sector, village, tehsil, gender, education, bio, state')
        .or('is_deleted.eq.false,is_deleted.is.null');
    
    if (state != null) {
      query = query.eq('state', state);
    }
    
    final response = await query;
    
    Map<String, int> allPoints = {};
    Map<String, int> allDirectCounts = {};
    try {
      final refData = await getReferralAnalytics();
      allPoints = refData['points'] ?? {};
      allDirectCounts = refData['directCounts'] ?? {};
    } catch (e) {
      debugPrint('Error fetching referral analytics in getProfilesLight: $e');
    }
    
    return (response as List).map((p) {
      final String userId = p['id'] ?? '';
      final String normId = normalizePhone(userId);
      final int pts = allPoints[normId] ?? 0;
      final int refCount = allDirectCounts[normId] ?? 0;
      
      return ABKMUser(
        id: userId,
        name: p['name'] ?? 'Anonymous',
        gender: p['gender'] ?? 'Other',
        userRole: p['user_role'] != null && p['user_role'] < UserRole.values.length 
            ? UserRole.values[p['user_role']] 
            : UserRole.member,
        bio: p['bio'] ?? '',
        profileImageUrl: p['profile_image_url'],
        state: p['state'] ?? '',
        district: p['district'] ?? '',
        tehsil: p['tehsil'] ?? '',
        village: p['village'] ?? '',
        sector: p['sector'] ?? '',
        profession: p['profession'] ?? '',
        education: p['education'] ?? '',
        position: p['position'] ?? 'Member',
        points: pts,
        referralCount: refCount,
      );
    }).toList().cast<ABKMUser>();
  }

  Future<ABKMUser?> getFullProfile(String userId) async {
    return await getProfile(userId);
  }
  Future<List<ABKMUser>> getProfilesByIds(List<String> ids) async {
    final response = await client
        .from('profiles')
        .select()
        .filter('id', 'in', ids)
        .or('is_deleted.eq.false,is_deleted.is.null');
    
    Map<String, int> allPoints = {};
    Map<String, int> allDirectCounts = {};
    try {
      final refData = await getReferralAnalytics();
      allPoints = refData['points'] ?? {};
      allDirectCounts = refData['directCounts'] ?? {};
    } catch (e) {
      debugPrint('Error fetching referral analytics in getProfilesByIds: $e');
    }

    return (response as List).map((p) {
      final String userId = p['id'] ?? '';
      final String normId = normalizePhone(userId);
      final int pts = allPoints[normId] ?? 0;
      final int refCount = allDirectCounts[normId] ?? 0;
      
      return ABKMUser(
        id: userId,
        name: p['name'] ?? 'Anonymous',
        gender: p['gender'] ?? 'Other',
        maritalStatus: p['marital_status'] ?? 'Unmarried',
        dob: p['dob'] != null ? DateTime.parse(p['dob']) : null,
        userRole: p['user_role'] != null && p['user_role'] < UserRole.values.length 
            ? UserRole.values[p['user_role']] 
            : UserRole.member,
        bio: p['bio'] ?? '',
        profileImageUrl: p['profile_image_url'],
        state: p['state'] ?? '',
        district: p['district'] ?? '',
        tehsil: p['tehsil'] ?? '',
        village: p['village'] ?? '',
        sector: p['sector'] ?? '',
        profession: p['profession'] ?? '',
        education: p['education'] ?? '',
        referralMobile: p['referral_mobile'],
        position: p['position'] ?? 'Member',
        lastLogin: p['last_login'] != null ? DateTime.parse(p['last_login']).toLocal() : null,
        blockedBy: p['blocked_by'],
        points: pts,
        referralCount: refCount,
      );
    }).toList().cast<ABKMUser>();
  }


  // --- Event Operations ---

  Future<void> createEvent(ABKMEvent event) async {
    await client.from('events').insert({
      'id': event.id,
      'host_id': event.hostId,
      'title': event.title,
      'description': event.description,
      'date': event.date.toUtc().toIso8601String(),
      'village': event.village,
      'event_type': event.eventType.index,
      'approved_member_ids': event.approvedMemberIds,
      'image_url': event.imageUrl,
      'district': event.district,
      'state': event.state,
      'tehsil': event.tehsil,
      'meeting_point': event.meetingPoint,
      'is_approved': event.isApproved,
    });
    
    await _logActivity(
      actorId: event.hostId,
      targetId: event.id,
      type: 'event_created',
      metadata: {'title': event.title, 'is_admin_request': !event.isApproved},
    );
  }

  Future<void> updateEvent(ABKMEvent event) async {
    await client.from('events').update({
      'title': event.title,
      'description': event.description,
      'date': event.date.toUtc().toIso8601String(),
      'village': event.village,
      'event_type': event.eventType.index,
      'approved_member_ids': event.approvedMemberIds,
      'image_url': event.imageUrl,
      'district': event.district,
      'state': event.state,
      'tehsil': event.tehsil,
      'meeting_point': event.meetingPoint,
      'is_approved': event.isApproved,
    }).eq('id', event.id);
  }

  Future<List<ABKMEvent>> getEvents({String? state, int limit = 200}) async {
    final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180)).toUtc().toIso8601String();
    var query = client.from('events').select();
    
    if (state != null) {
      query = query.eq('state', state);
    }
    
    final response = await query
        .gte('date', sixMonthsAgo)
        .order('date', ascending: true)
        .limit(limit);
    
    return (response as List).map((e) => ABKMEvent.fromJson(e)).toList();
  }

  Future<List<ABKMEvent>> getEventsLight({String? state, int limit = 100}) async {
    final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180)).toUtc().toIso8601String();
    var query = client
        .from('events')
        .select('id, host_id, title, description, date, village, event_type, approved_member_ids, image_url, district, state, is_approved, meeting_point, tehsil');
    
    if (state != null) {
      query = query.eq('state', state);
    }
    
    final response = await query
        .gte('date', sixMonthsAgo)
        .order('date', ascending: true)
        .limit(limit);
    
    return (response as List).map((e) => ABKMEvent(
      id: e['id'],
      hostId: e['host_id'],
      title: e['title'],
      description: e['description'] ?? '',
      date: DateTime.parse(e['date'].toString().endsWith('Z') || e['date'].toString().contains('+') || e['date'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? e['date'] : '${e['date']}Z').toLocal(),
      village: e['village'] ?? e['location'] ?? '',
      district: e['district'] ?? e['city'] ?? '',
      state: e['state'] ?? '',
      tehsil: e['tehsil'] ?? '',
      meetingPoint: e['meeting_point'],
      eventType: (e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other,
      approvedMemberIds: List<String>.from(e['approved_member_ids'] ?? []),
      imageUrl: e['image_url'] ?? 'assets/images/${((e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other).name}.jpg',
      isApproved: e['is_approved'] ?? true,
    )).toList();
  }

  Future<ABKMEvent?> getEventById(String eventId, {bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final String cacheKey = 'abkm_full_event_$eventId';
    
    if (!forceRefresh) {
      final cachedData = prefs.getString(cacheKey);
      if (cachedData != null) {
        try {
          return ABKMEvent.fromJson(json.decode(cachedData));
        } catch (e) {
          debugPrint('Cache parsing error for event $eventId: $e');
        }
      }
    }

    final response = await client.from('events').select().eq('id', eventId).maybeSingle();
    if (response == null) return null;
    
    final event = ABKMEvent.fromJson(response);
    await prefs.setString(cacheKey, json.encode(event.toJson()));
    await CacheLogic.markTimestamp(prefs, cacheKey);
    return event;
  }

  Future<ABKMEvent?> getFullEvent(String eventId) async {
    return await getEventById(eventId);
  }

  Future<List<ABKMEvent>> getPendingEvents({String? state}) async {
    var query = client.from('events').select().eq('is_approved', false);
    
    if (state != null) {
      query = query.eq('state', state);
    }
    
    final response = await query.order('date', ascending: true);
    
    return (response as List).map<ABKMEvent>((e) => ABKMEvent(
      id: e['id'],
      hostId: e['host_id'],
      title: e['title'],
      description: e['description'] ?? '', 
      date: DateTime.parse(e['date'].toString().endsWith('Z') || e['date'].toString().contains('+') || e['date'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? e['date'] : '${e['date']}Z').toLocal(),
      village: e['village'] ?? e['location'] ?? '',
      district: e['district'] ?? e['city'] ?? '',
      state: e['state'] ?? '',
      tehsil: e['tehsil'] ?? '',
      meetingPoint: e['meeting_point'],
      eventType: (e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other,
      approvedMemberIds: List<String>.from(e['approved_member_ids'] ?? []),
      imageUrl: 'assets/images/${((e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other).name}.jpg',
      isApproved: false,
    )).toList();
  }

  Future<void> approveEvent(String eventId, String adminId) async {
    final eventData = await client.from('events').select('title, host_id, state').eq('id', eventId).single();
    
    // Enforce state boundary check
    final adminProfile = await getProfile(adminId);
    if (adminProfile != null && adminProfile.userRole != UserRole.superUser && adminProfile.position != 'National President') {
      if (adminProfile.state.isNotEmpty && eventData['state'] != null) {
        if (eventData['state'].toString().trim().toLowerCase() != adminProfile.state.trim().toLowerCase()) {
          throw Exception('You do not have permission to approve events from other states.');
        }
      }
    }

    await client.from('events').update({
      'is_approved': true,
    }).eq('id', eventId);

    await _logActivity(
      actorId: adminId,
      targetId: eventId,
      type: 'event_approved',
      metadata: {
        'title': eventData['title'], 
        'host_id': eventData['host_id']
      },
    );

    // Broadcast new event to everyone
    await _logActivity(
      actorId: adminId,
      targetId: eventId,
      type: 'broadcast_new_event',
      metadata: {
        'title': eventData['title'],
        'is_broadcast': true
      },
    );
  }

  Future<void> declineEvent(String eventId, String adminId) async {
    final eventData = await client.from('events').select('title, host_id, state').eq('id', eventId).single();
    
    // Enforce state boundary check
    final adminProfile = await getProfile(adminId);
    if (adminProfile != null && adminProfile.userRole != UserRole.superUser && adminProfile.position != 'National President') {
      if (adminProfile.state.isNotEmpty && eventData['state'] != null) {
        if (eventData['state'].toString().trim().toLowerCase() != adminProfile.state.trim().toLowerCase()) {
          throw Exception('You do not have permission to decline events from other states.');
        }
      }
    }

    // For now we delete, but we log the decline first
    await _logActivity(
      actorId: adminId,
      targetId: eventId,
      type: 'event_declined',
      metadata: {
        'title': eventData['title'], 
        'host_id': eventData['host_id']
      },
    );
    
    await client.from('events').delete().eq('id', eventId);
  }

  Future<List<ABKMEvent>> getEventsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final response = await client
        .from('events')
        .select()
        .filter('id', 'in', ids);
    
    return (response as List).map((e) => ABKMEvent(
      id: e['id'],
      hostId: e['host_id'],
      title: e['title'],
      description: e['description'],
      date: DateTime.parse(e['date'].toString().endsWith('Z') || e['date'].toString().contains('+') || e['date'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? e['date'] : '${e['date']}Z').toLocal(),
      village: e['village'] ?? e['location'] ?? '',
      district: e['district'] ?? e['city'] ?? '',
      state: e['state'] ?? '',
      tehsil: e['tehsil'] ?? '',
      meetingPoint: e['meeting_point'],
      eventType: (e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other,
      approvedMemberIds: List<String>.from(e['approved_member_ids']),
      imageUrl: (e['image_url'] != null && (e['image_url'].toString().startsWith('assets/') || e['image_url'].toString().startsWith('/9j/'))) 
          ? e['image_url'] 
          : 'assets/images/${((e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other).name}.jpg',
      isApproved: e['is_approved'] ?? true,
    )).toList();
  }

  Future<List<ABKMEvent>> getEventsByHost(String hostId) async {
    final response = await client
        .from('events')
        .select()
        .eq('host_id', hostId)
        .order('date', ascending: false);
    
    return (response as List).map((e) => ABKMEvent(
      id: e['id'],
      hostId: e['host_id'],
      title: e['title'],
      description: e['description'],
      date: DateTime.parse(e['date'].toString().endsWith('Z') || e['date'].toString().contains('+') || e['date'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? e['date'] : '${e['date']}Z').toLocal(),
      village: e['village'] ?? e['location'] ?? '',
      district: e['district'] ?? e['city'] ?? '',
      state: e['state'] ?? '',
      tehsil: e['tehsil'] ?? '',
      meetingPoint: e['meeting_point'],
      eventType: (e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other,
      approvedMemberIds: List<String>.from(e['approved_member_ids']),
      imageUrl: (e['image_url'] != null && (e['image_url'].toString().startsWith('assets/') || e['image_url'].toString().startsWith('/9j/'))) 
          ? e['image_url'] 
          : 'assets/images/${((e['event_type'] ?? 0) < EventType.values.length ? EventType.values[e['event_type'] ?? 0] : EventType.other).name}.jpg',
      isApproved: e['is_approved'] ?? true,
    )).toList();
  }

  Future<List<ABKMEvent>> getEventsParticipated(String userId) async {
    final apps = await client
        .from('applications')
        .select('event_id')
        .eq('applicant_id', userId)
        .eq('status', ApplicationStatus.approved.index);
    
    final ids = (apps as List).map((a) => a['event_id'] as String).toList();
    if (ids.isEmpty) return [];
    return await getEventsByIds(ids);
  }

  // --- Application Operations ---

  Future<void> deleteEvent(String eventId) async {
    final event = await getEventById(eventId);
    if (event != null && event.eventType == EventType.announcement) {
      if (event.date.isBefore(DateTime.now())) {
        await client.from('applications').delete().eq('event_id', eventId);
        await client.from('events').delete().eq('id', eventId);
      } else {
        await client.from('events').update({
          'date': DateTime.now().subtract(const Duration(seconds: 10)).toUtc().toIso8601String()
        }).eq('id', eventId);
      }
    } else {
      await client.from('applications').delete().eq('event_id', eventId);
      await client.from('events').delete().eq('id', eventId);
    }
  }


  Future<void> applyForRole(EventApplication app) async {
    await client.from('applications').insert({
      'id': app.id,
      'event_id': app.eventId,
      'applicant_id': app.applicantId,
      'message': app.message,
      'is_approved': app.isApproved,
      'status': app.status.index,
      'is_invitation': app.isInvitation,
    });
  }

  Future<List<EventApplication>> getApplicationsForEvent(String eventId) async {
    final response = await client
        .from('applications')
        .select()
        .eq('event_id', eventId);
    
    return (response as List).map((app) => EventApplication(
      id: app['id'],
      eventId: app['event_id'],
      applicantId: app['applicant_id'],
      message: app['message'],
      isApproved: app['is_approved'],
      status: (app['status'] ?? 0) < ApplicationStatus.values.length ? ApplicationStatus.values[app['status'] ?? 0] : ApplicationStatus.pending,
      isInvitation: app['is_invitation'] ?? false,
      createdAt: app['created_at'] != null ? DateTime.parse(app['created_at'].toString().endsWith('Z') || app['created_at'].toString().contains('+') || app['created_at'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? app['created_at'] : '${app['created_at']}Z').toLocal() : null,
    )).toList();
  }

  Future<void> approveApplication(String applicationId, String eventId, String applicantId) async {
    await client.from('applications').update({
      'is_approved': true,
      'status': ApplicationStatus.approved.index,
    }).eq('id', applicationId);
    
    final eventResponse = await client.from('events').select('approved_member_ids').eq('id', eventId).single();
    List<String> approved = List<String>.from(eventResponse['approved_member_ids']);
    
    if (!approved.contains(applicantId)) {
      approved.add(applicantId);
      await client.from('events').update({'approved_member_ids': approved}).eq('id', eventId);
    }
  }

  Future<void> declineApplication(String applicationId) async {
    await client.from('applications').update({
      'is_approved': false,
      'status': ApplicationStatus.declined.index,
    }).eq('id', applicationId);
  }

  Future<void> respondToInvitation(String applicationId, bool accept, String eventId, String userId) async {
    if (accept) {
      await approveApplication(applicationId, eventId, userId);
      await client.from('applications').update({
        'status': ApplicationStatus.invitationAccepted.index,
      }).eq('id', applicationId);
    } else {
      await client.from('applications').update({
        'status': ApplicationStatus.invitationDeclined.index,
      }).eq('id', applicationId);
    }
  }

  Future<void> cancelApplication(String applicationId, String eventId, String userId) async {
    await client.from('applications').update({
      'status': ApplicationStatus.withdrawn.index,
    }).eq('id', applicationId);
  }

  Future<void> updateApplicationStatus(String applicationId, ApplicationStatus status) async {
    await client.from('applications').update({
      'status': status.index,
    }).eq('id', applicationId);
  }

  Future<void> sendInvitation({
    required String eventId,
    required String hostId,
    required String applicantId,
  }) async {
    final invitation = EventApplication(
      id: Uuid().v4(),
      eventId: eventId,
      applicantId: applicantId,
      message: 'You have been invited to join an event!',
      isInvitation: true,
      status: ApplicationStatus.invitationPending,
    );
    
    await client.from('applications').insert(invitation.toJson());
  }

  Future<void> removeMemberFromEvent(String eventId, String userId) async {
    final eventResponse = await client.from('events').select('approved_member_ids').eq('id', eventId).single();
    List<String> approved = List<String>.from(eventResponse['approved_member_ids']);
    
    if (approved.contains(userId)) {
      approved.remove(userId);
      await client.from('events').update({'approved_member_ids': approved}).eq('id', eventId);
    }
  }

  Future<bool> hasApplied(String eventId, String applicantId) async {
    final response = await client
        .from('applications')
        .select()
        .eq('event_id', eventId)
        .eq('applicant_id', applicantId)
        .maybeSingle();
    return response != null;
  }

  Future<List<EventApplication>> getApplicationsForUserForEvent(String eventId, String applicantId) async {
    final response = await client
        .from('applications')
        .select()
        .eq('event_id', eventId)
        .eq('applicant_id', applicantId);
    
    return (response as List).map((app) => EventApplication(
      id: app['id'],
      eventId: app['event_id'],
      applicantId: app['applicant_id'],
      message: app['message'],
      isApproved: app['is_approved'],
      status: (app['status'] ?? 0) < ApplicationStatus.values.length ? ApplicationStatus.values[app['status'] ?? 0] : ApplicationStatus.pending,
      isInvitation: app['is_invitation'] ?? false,
      createdAt: app['created_at'] != null ? DateTime.parse(app['created_at'].toString().endsWith('Z') || app['created_at'].toString().contains('+') || app['created_at'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? app['created_at'] : '${app['created_at']}Z').toLocal() : null,
    )).toList();
  }

  Future<List<EventApplication>> getApplicationsForUser(String userId, {int limit = 50}) async {
    final response = await client
        .from('applications')
        .select()
        .eq('applicant_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    
    return (response as List).map((app) => EventApplication(
      id: app['id'],
      eventId: app['event_id'],
      applicantId: app['applicant_id'],
      message: app['message'],
      isApproved: app['is_approved'],
      status: (app['status'] ?? 0) < ApplicationStatus.values.length ? ApplicationStatus.values[app['status'] ?? 0] : ApplicationStatus.pending,
      isInvitation: app['is_invitation'] ?? false,
      createdAt: app['created_at'] != null ? DateTime.parse(app['created_at'].toString().endsWith('Z') || app['created_at'].toString().contains('+') || app['created_at'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? app['created_at'] : '${app['created_at']}Z').toLocal() : null,
    )).toList();
  }

  Future<List<EventApplication>> getAllApplications() async {
    final response = await client
        .from('applications')
        .select();
    
    return (response as List).map((app) => EventApplication(
      id: app['id'],
      eventId: app['event_id'],
      applicantId: app['applicant_id'],
      message: app['message'],
      isApproved: app['is_approved'],
      status: (app['status'] ?? 0) < ApplicationStatus.values.length ? ApplicationStatus.values[app['status'] ?? 0] : ApplicationStatus.pending,
      isInvitation: app['is_invitation'] ?? false,
      createdAt: app['created_at'] != null ? DateTime.parse(app['created_at'].toString().endsWith('Z') || app['created_at'].toString().contains('+') || app['created_at'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? app['created_at'] : '${app['created_at']}Z').toLocal() : null,
    )).toList();
  }

  Future<List<Map<String, dynamic>>> getActivityFeed(String userId) async {
    try {
      // Get user role first (safely default to Member role = 0 if not found yet)
      int userRole = 0;
      try {
        final profileResponse = await client.from('profiles').select('user_role').eq('id', userId).single();
        userRole = (profileResponse['user_role'] ?? 0);
      } catch (e) {
        debugPrint('getActivityFeed: Profile for $userId not found or role query failed: $e. Defaulting userRole to 0.');
      }

      // 1. Fetch Event Applications (both as applicant and host)
      final List<dynamic> appsResponse;
      final myEventsResponse = await client.from('events').select('id,host_id,title,is_approved,created_at').eq('host_id', userId);
      
      if (userRole >= 2) {
        // Admins and Super Admins see all applications system-wide
        final systemAppsResponse = await client.from('applications')
            .select('id,event_id,applicant_id,message,is_approved,status,is_invitation,created_at')
            .order('created_at', ascending: false)
            .limit(100);
        appsResponse = systemAppsResponse;
      } else {
        final myAppsResponse = await client.from('applications')
            .select('id,event_id,applicant_id,message,is_approved,status,is_invitation,created_at')
            .eq('applicant_id', userId)
            .order('created_at', ascending: false)
            .limit(60);
        
        final myEventIds = (myEventsResponse as List).map((e) => e['id'].toString()).toList();
        
        List<dynamic> hostAppsResponse = [];
        if (myEventIds.isNotEmpty) {
          hostAppsResponse = await client.from('applications')
              .select('id,event_id,applicant_id,message,is_approved,status,is_invitation,created_at')
              .filter('event_id', 'in', myEventIds)
              .order('created_at', ascending: false)
              .limit(60);
        }
        appsResponse = [...(myAppsResponse as List), ...hostAppsResponse];
      }

      // 2. Fetch Promotion Requests
      final List<dynamic> promotionRequestsResponse;
      if (userRole >= 2) {
        // Admins and Super Admins see all promotion requests system-wide
        promotionRequestsResponse = await client.from('promotion_requests')
            .select()
            .order('created_at', ascending: false)
            .limit(50);
      } else {
        promotionRequestsResponse = await client.from('promotion_requests')
            .select()
            .or('userId.eq.$userId,requesterId.eq.$userId')
            .order('created_at', ascending: false)
            .limit(30);
      }

      // 3. Fetch Activity Logs
      final List<dynamic> logsResponse;
      if (userRole >= 2) {
        // Admins and Super Admins see all logs system-wide without actor/owner constraints
        logsResponse = await client.from('activity_logs')
            .select()
            .order('created_at', ascending: false)
            .limit(150);
      } else {
        final String orFilter = 'actor_id.eq.$userId,target_id.eq.$userId,metadata->>host_id.eq.$userId,metadata->>target_id.eq.$userId,metadata->>is_broadcast.eq.true';
        logsResponse = await client.from('activity_logs')
            .select()
            .or(orFilter)
            .order('created_at', ascending: false)
            .limit(80);
      }

      // 4. Combine and Merge
      final allRawApps = appsResponse;
      final Map<String, Map<String, dynamic>> uniqueApps = {};
      for (var a in allRawApps) {
        final id = a['id'].toString();
        uniqueApps[id] = Map<String, dynamic>.from(a);
        uniqueApps[id]!['activity_type'] = 'application';
      }

      final List<Map<String, dynamic>> finalFeed = uniqueApps.values.toList();
      
      for (var pr in promotionRequestsResponse) {
        final Map<String, dynamic> item = Map<String, dynamic>.from(pr);
        item['activity_type'] = 'promotion';
        finalFeed.add(item);
      }

      // Add Events themselves as activity (for host, or pending events for admins)
      final List<dynamic> eventsToAdd = [...(myEventsResponse as List)];
      if (userRole >= 2) {
        try {
          final adminProfile = await getProfile(userId);
          var query = client.from('events').select('id,host_id,title,is_approved,created_at,state').eq('is_approved', false);
          
          if (adminProfile != null && adminProfile.userRole != UserRole.superUser && adminProfile.position != 'National President') {
            if (adminProfile.state.isNotEmpty) {
              query = query.eq('state', adminProfile.state);
            }
          }
          
          final pendingEventsResponse = await query;
          
          final existingIds = eventsToAdd.map((e) => e['id'].toString()).toSet();
          for (var e in (pendingEventsResponse as List)) {
            if (!existingIds.contains(e['id'].toString())) {
              eventsToAdd.add(e);
            }
          }
        } catch (e) {
          debugPrint('Error querying system-wide pending events: $e');
        }
      }

      for (var e in eventsToAdd) {
        final Map<String, dynamic> item = Map<String, dynamic>.from(e);
        item['activity_type'] = 'event';
        finalFeed.add(item);
      }

      for (var log in logsResponse) {
        final Map<String, dynamic> item = Map<String, dynamic>.from(log);
        item['activity_type'] = 'log';
        finalFeed.add(item);
      }

      if (finalFeed.isEmpty) return [];

      // Fetch related data (Events and Profiles)
      // Fetch related data (Events and Profiles)
      final appEventIds = finalFeed
          .where((a) => a['activity_type'] == 'application' || 
                 a['activity_type'] == 'event' ||
                 (a['activity_type'] == 'log' && a['target_id'] != null && a['type'].toString().contains('event')))
          .map((a) => (a['event_id'] ?? a['target_id'] ?? a['id']).toString())
          .toSet()
          .toList();
          
      final userIdsToFetch = <String>{};
      
      for (var item in finalFeed) {
        if (item['activity_type'] == 'application') {
          userIdsToFetch.add(item['applicant_id'].toString());
        } else if (item['activity_type'] == 'promotion') {
          userIdsToFetch.add(item['userId'].toString());
          userIdsToFetch.add(item['requesterId'].toString());
        } else if (item['activity_type'] == 'log') {
          userIdsToFetch.add(item['actor_id'].toString());
          if (item['target_id'] != null) {
            userIdsToFetch.add(item['target_id'].toString());
          }
          if (item['metadata']?['host_id'] != null) {
            userIdsToFetch.add(item['metadata']['host_id'].toString());
          }
          if (item['metadata']?['target_id'] != null) {
            userIdsToFetch.add(item['metadata']['target_id'].toString());
          }
        } else if (item['activity_type'] == 'event') {
          userIdsToFetch.add(item['host_id'].toString());
        }
      }
      
      final events = appEventIds.isNotEmpty ? await getEventsByIds(appEventIds) : <ABKMEvent>[];
      final eventsMap = {for (var e in events) e.id: e};
      
      for (var e in events) {
        userIdsToFetch.add(e.hostId);
      }

      final profiles = await getProfilesByIds(userIdsToFetch.toList());
      final profilesMap = {for (var p in profiles) p.id: p};

      final List<Map<String, dynamic>> merged = finalFeed.map((item) {
        final Map<String, dynamic> result = Map<String, dynamic>.from(item);
        
        if (item['activity_type'] == 'application') {
          final event = eventsMap[item['event_id'].toString()];
          final applicant = profilesMap[item['applicant_id'].toString()];
          final host = event != null ? profilesMap[event.hostId] : null;
          
          result['events'] = event != null ? {
            'id': event.id,
            'title': event.title,
            'date': event.date.toIso8601String(),
            'village': event.village,
            'event_type': event.eventType.index,
            'host_id': event.hostId,
            'district': event.district,
            'state': event.state,
            'approved_member_ids': event.approvedMemberIds,
            'image_url': event.imageUrl,
            'meeting_point': event.meetingPoint,
            'tehsil': event.tehsil,
            'Moderator': host != null ? {
              'id': host.id,
              'name': host.name,
              'profile_image_url': host.profileImageUrl,
              'user_role': host.userRole.index,
            } : null,
          } : null;

          result['applicant'] = applicant != null ? {
            'id': applicant.id,
            'name': applicant.name,
            'profile_image_url': applicant.profileImageUrl,
            'user_role': applicant.userRole.index,
          } : null;
        } else if (item['activity_type'] == 'promotion') {
          final target = profilesMap[item['userId'].toString()];
          final requester = profilesMap[item['requesterId'].toString()];
          
          result['target'] = target != null ? {
            'id': target.id,
            'name': target.name,
            'profile_image_url': target.profileImageUrl,
            'user_role': target.userRole.index,
          } : null;
          
          result['requester'] = requester != null ? {
            'id': requester.id,
            'name': requester.name,
            'profile_image_url': requester.profileImageUrl,
            'user_role': requester.userRole.index,
          } : null;
        } else if (item['activity_type'] == 'log') {
          final actor = profilesMap[item['actor_id'].toString()];
          final host = item['metadata']?['host_id'] != null ? profilesMap[item['metadata']['host_id'].toString()] : null;
          final target = item['target_id'] != null 
              ? profilesMap[item['target_id'].toString()] 
              : (item['metadata']?['target_id'] != null 
                  ? profilesMap[item['metadata']['target_id'].toString()] 
                  : null);
          
          result['actor'] = actor != null ? {
            'id': actor.id,
            'name': actor.name,
            'profile_image_url': actor.profileImageUrl,
            'user_role': actor.userRole.index,
          } : null;

          result['host'] = host != null ? {
            'id': host.id,
            'name': host.name,
            'profile_image_url': host.profileImageUrl,
            'user_role': host.userRole.index,
          } : null;

          result['target'] = target != null ? {
            'id': target.id,
            'name': target.name,
            'profile_image_url': target.profileImageUrl,
            'user_role': target.userRole.index,
          } : null;

          final eventId = (item['target_id'] ?? item['metadata']?['event_id'])?.toString();
          if (eventId != null && eventsMap.containsKey(eventId)) {
            result['events'] = eventsMap[eventId]?.toJson();
          }
        } else if (item['activity_type'] == 'event') {
          final event = eventsMap[item['id'].toString()];
          final host = event != null ? profilesMap[event.hostId] : null;
          
          result['events'] = event != null ? {
            'id': event.id,
            'title': event.title,
            'date': event.date.toIso8601String(),
            'village': event.village,
            'event_type': event.eventType.index,
            'host_id': event.hostId,
            'district': event.district,
            'state': event.state,
            'approved_member_ids': event.approvedMemberIds,
            'image_url': event.imageUrl,
            'meeting_point': event.meetingPoint,
            'tehsil': event.tehsil,
            'Moderator': host != null ? {
              'id': host.id,
              'name': host.name,
              'profile_image_url': host.profileImageUrl,
              'user_role': host.userRole.index,
            } : null,
          } : null;
        }
        
        return result;
      }).toList();

      merged.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
      return merged;
    } catch (e) {
      debugPrint('Error loading activity feed: $e');
      return [];
    }
  }

  Future<List<EventApplication>> getApplicationsByHost(String hostId, {int limit = 50}) async {
    final response = await client
        .from('applications')
        .select('*, events!inner(host_id)')
        .eq('events.host_id', hostId)
        .order('created_at', ascending: false)
        .limit(limit);
    
    return (response as List).map((app) => EventApplication(
      id: app['id'],
      eventId: app['event_id'],
      applicantId: app['applicant_id'],
      message: app['message'],
      isApproved: app['is_approved'],
      status: (app['status'] ?? 0) < ApplicationStatus.values.length ? ApplicationStatus.values[app['status'] ?? 0] : ApplicationStatus.pending,
      isInvitation: app['is_invitation'] ?? false,
      createdAt: app['created_at'] != null ? DateTime.parse(app['created_at'].toString().endsWith('Z') || app['created_at'].toString().contains('+') || app['created_at'].toString().contains(RegExp(r'-\d{2}:\d{2}$')) ? app['created_at'] : '${app['created_at']}Z').toLocal() : null,
    )).toList();
  }

  Future<void> deleteProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? loggedInUserId = prefs.getString('abkm_mobileNumber');

    if (loggedInUserId == null) throw Exception('Not logged in');

    try {
      // Check authorization
      final int roleIndex = prefs.getInt('abkm_user_role') ?? 0;
      final UserRole loggedInRole = UserRole.values[roleIndex];
      final bool isSelfDelete = userId == loggedInUserId;
      final bool isAuthorized = isSelfDelete || loggedInRole == UserRole.admin || loggedInRole == UserRole.superUser;

      if (!isAuthorized) throw Exception('Unauthorized to delete this profile');

      // Step A: Delete applications BY this user
      await client.from('applications').delete().eq('applicant_id', userId);

      // Step B: Handle events hosted BY this user
      final hostedEvents = await client.from('events').select('id').eq('host_id', userId);
      for (var event in hostedEvents) {
        final eventId = event['id'];
        await client.from('applications').delete().eq('event_id', eventId);
        try {
          await client.from('activity_logs').delete().eq('target_id', eventId);
        } catch (e) {
          debugPrint('Error deleting event logs: $e');
        }
        await client.from('events').delete().eq('id', eventId);
      }

      // Step C: Delete promotion requests related to this user
      try {
        await client.from('promotion_requests').delete().eq('userId', userId);
        await client.from('promotion_requests').delete().eq('requesterId', userId);
      } catch (e) {
        debugPrint('Non-critical error deleting promotion requests: $e');
      }

      // Step D: Remove user from all event attendee lists
      try {
        final allEventsWithUser = await client.from('events').select('id, approved_member_ids').filter('approved_member_ids', 'cs', '{"$userId"}}');
        for (var event in allEventsWithUser) {
          final List<String> currentAttendees = List<String>.from(event['approved_member_ids'] ?? []);
          if (currentAttendees.contains(userId)) {
            currentAttendees.remove(userId);
            await client.from('events').update({'approved_member_ids': currentAttendees}).eq('id', event['id']);
          }
        }
      } catch (e) {
        debugPrint('Error removing user from attendee lists: $e');
      }

      // Step E: Delete activity logs involving this user
      try {
        await client.from('activity_logs').delete().or('actor_id.eq.$userId,target_id.eq.$userId');
      } catch (logErr) {
        debugPrint('Non-critical error deleting activity logs: $logErr');
      }

      // Step F: SOFT-DELETE the profile row.
      // Personal data is wiped but id + referral_mobile are kept to preserve the referral chain.
      await client.from('profiles').update({
        'is_deleted': true,
        'name': 'Deleted User',
        'bio': '',
        'dob': null,
        'gender': 'Other',
        'marital_status': null,
        'profile_image_url': null,
        'state': '',
        'district': '',
        'tehsil': '',
        'village': '',
        'sector': '',
        'profession': '',
        'education': '',
        'position': 'Member',
        'last_login': null,
        'is_blocked': false,
      }).eq('id', userId);

      debugPrint('Soft-delete completed for $userId — referral chain preserved.');

      // Step G: Clear all related caches
      await prefs.remove('abkm_full_profile_$userId');
      await prefs.remove('abkm_cached_home_profiles');
      await prefs.remove('abkm_cached_essential_hosted_events');
      await prefs.remove('abkm_cached_essential_participated_events');
      await prefs.remove('abkm_cached_essential_user_apps');
      await prefs.remove('abkm_cached_essential_host_apps');

      // If self-delete, clear session
      if (isSelfDelete) {
        final keys = prefs.getKeys();
        for (String key in keys) {
          if (key.startsWith('abkm_')) {
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      debugPrint('Critical failure in profile soft-delete for $userId: $e');
      rethrow;
    }
  }

  Future<void> updateUserBlockStatus(String userId, bool isBlocked, {String? actorId}) async {
    int targetRoleIndex = UserRole.member.index;

    // Get actor ID upfront to avoid blocking on SharedPreferences later
    final String? finalActorId = actorId ?? (await SharedPreferences.getInstance()).getString('abkm_user_id');

    if (isBlocked) {
      targetRoleIndex = UserRole.blocked.index;
    } else {
      // Fetch the user's position to determine the correct role on unblock
      try {
        final profileResponse = await client
            .from('profiles')
            .select('position')
            .eq('id', userId)
            .maybeSingle();

        if (profileResponse != null) {
          final String position = profileResponse['position'] ?? 'Member';
          final List<String> generalPositions = ['Member', 'Primary Member', 'Active Member', 'Executive Member', ''];

          if (position == 'State President' || 
              position == 'National President' || 
              ((position.startsWith('State ') || position.startsWith('National ')) && position.contains('President'))) {
            targetRoleIndex = UserRole.admin.index;
          } else if (generalPositions.contains(position)) {
            targetRoleIndex = UserRole.member.index;
          } else {
            // Other leadership positions default to moderator
            targetRoleIndex = UserRole.moderator.index;
          }
        }
      } catch (e) {
        debugPrint('Error determining user role on unblock for $userId: $e');
        // Fallback to member if query fails
        targetRoleIndex = UserRole.member.index;
      }
    }

    // Update both user_role, is_blocked, and blocked_by columns to ensure data consistency
    final response = await client.from('profiles').update({
      'user_role': targetRoleIndex,
      'is_blocked': isBlocked,
      'blocked_by': isBlocked ? finalActorId : null,
    }).eq('id', userId).select();

    if ((response as List).isEmpty) {
      throw Exception('Failed to update block status: No rows affected. You may not have permissions to modify this user.');
    }

    // Clear cached profile so next fetch gets fresh data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('abkm_full_profile_$userId');

    // Log block activity in the background (fire-and-forget) to avoid blocking the UI
    if (finalActorId != null) {
      _logActivity(
        actorId: finalActorId,
        targetId: userId,
        type: isBlocked ? 'account_blocked' : 'account_unblocked',
        metadata: {
          'target_id': userId,
        },
      ).catchError((e) => debugPrint('Error logging block activity: $e'));
    }
  }

  Future<ABKMUser?> getBlockerProfile(String blockedUserId) async {
    try {
      // 1. Direct query of profiles table to find blockerId from 'blocked_by' column
      final profileData = await client
          .from('profiles')
          .select('blocked_by')
          .eq('id', blockedUserId)
          .maybeSingle();

      if (profileData != null && profileData['blocked_by'] != null) {
        final String blockerId = profileData['blocked_by'].toString();
        final blockerProfile = await getProfile(blockerId);
        if (blockerProfile != null) {
          return blockerProfile;
        }
      }

      // 2. Fallback: Query activity logs (if authorized/accessible)
      final logResponse = await client
          .from('activity_logs')
          .select('actor_id')
          .eq('target_id', blockedUserId)
          .eq('type', 'account_blocked')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (logResponse != null && logResponse['actor_id'] != null) {
        final String blockerId = logResponse['actor_id'].toString();
        final blockerProfile = await getProfile(blockerId);
        if (blockerProfile != null) {
          return blockerProfile;
        }
      }
    } catch (e) {
      debugPrint('Error getting blocker profile: $e');
    }
    
    // Fallback: If no blocker is found, return the National President
    return await getNationalPresident();
  }

  Future<void> cleanupNonUPData() async {
    // Disabled as app is now all India level
    debugPrint('cleanupNonUPData: bypassed (All India level enabled)');
  }

  // --- Location Operations ---

  Future<List<String>> getUniqueStates({String? query}) async {
    try {
      final response = await client.rpc('get_unique_locations', params: {
        'target_col': 'state',
        'search_query': query
      });
      
      if (response == null || (response as List).isEmpty) {
        return _getLocalStates(query);
      }
      return (response as List).map((item) => item['name'].toString()).toList();
    } catch (e) {
      debugPrint('Error fetching states: $e');
      return _getLocalStates(query);
    }
  }

  List<String> _getLocalStates(String? query) {
    if (query == null || query.trim().isEmpty) {
      return indiaStatesAndDistricts.keys.toList();
    }
    final q = query.trim().toLowerCase();
    return indiaStatesAndDistricts.keys
        .where((state) => state.toLowerCase().contains(q))
        .toList();
  }

  Future<List<String>> getDistrictsForState(String state) async {
    try {
      final response = await client.rpc('get_unique_locations', params: {
        'target_col': 'district',
        'state_val': state
      });
      
      if (response == null || (response as List).isEmpty) {
        return _getLocalDistricts(state, null);
      }
      return (response as List).map((item) => item['name'].toString()).toList();
    } catch (e) {
      debugPrint('Error fetching districts: $e');
      return _getLocalDistricts(state, null);
    }
  }

  List<String> _getLocalDistricts(String state, String? query) {
    final districts = indiaStatesAndDistricts[state] ?? [];
    if (query == null || query.trim().isEmpty) {
      return districts;
    }
    final q = query.trim().toLowerCase();
    return districts
        .where((d) => d.toLowerCase().contains(q))
        .toList();
  }

  Future<bool> validateLocation({
    required String type,
    String? state,
    String? district,
    String? tehsil,
    required String value,
  }) async {
    try {
      final response = await client.rpc('get_unique_locations', params: {
        'target_col': type,
        'state_val': (state == null || state.isEmpty) ? null : state,
        'district_val': (district == null || district.isEmpty) ? null : district,
        'tehsil_val': (tehsil == null || tehsil.isEmpty) ? null : tehsil,
        'search_query': value 
      });
      
      if (response == null || (response as List).isEmpty) {
        if (type == 'state') {
          return indiaStatesAndDistricts.containsKey(value);
        } else if (type == 'district' && state != null) {
          return (indiaStatesAndDistricts[state] ?? []).any((d) => d.toLowerCase() == value.toLowerCase());
        }
        return true; // Safe default for un-cached fields when offline/empty table
      }
      final results = (response as List).map((item) => item['name'].toString()).toList();
      
      // Case-insensitive exact match to ensure the value exists in our database
      return results.any((name) => name.toLowerCase() == value.toLowerCase());
    } catch (e) {
      debugPrint('Error validating location: $e');
      if (type == 'state') {
        return indiaStatesAndDistricts.containsKey(value);
      } else if (type == 'district' && state != null) {
        return (indiaStatesAndDistricts[state] ?? []).any((d) => d.toLowerCase() == value.toLowerCase());
      }
      return true;
    }
  }

  Future<List<String>> getLocationSuggestions({
    required String type, 
    required String state,
    required String district, 
    String? tehsil,
    required String query
  }) async {
    try {
      final response = await client.rpc('get_unique_locations', params: {
        'target_col': type,
        'state_val': state.isEmpty ? null : state,
        'district_val': district.isEmpty ? null : district,
        'tehsil_val': (tehsil == null || tehsil.isEmpty) ? null : tehsil,
        'search_query': query.isEmpty ? null : query
      });
      
      if (response == null || (response as List).isEmpty) {
        return _getLocalSuggestions(type: type, state: state, query: query);
      }
      return (response as List).map((item) => item['name'].toString()).toList();
    } catch (e) {
      debugPrint('Error fetching location suggestions: $e');
      return _getLocalSuggestions(type: type, state: state, query: query);
    }
  }

  List<String> _getLocalSuggestions({
    required String type,
    required String state,
    required String query,
  }) {
    if (type == 'district') {
      return _getLocalDistricts(state, query);
    }
    return [];
  }

  Future<int> getReferralCount(String mobileNumber) async {
    final response = await client
        .from('profiles')
        .select('id')
        .eq('referral_mobile', mobileNumber);
    // Count all referrals including soft-deleted ones so chain points stay intact
    return (response as List).length;
  }

  Future<List<ABKMUser>> getReferredUsers(String userId) async {
    // Include deleted users — the UI will display them as a greyed placeholder
    final response = await client
        .from('profiles')
        .select('id, name, profile_image_url, position, user_role, district, referral_mobile, gender, bio, state, is_deleted')
        .eq('referral_mobile', userId);
    

    Map<String, List<String>> childrenOf = {};
    Map<String, bool> isDeletedMap = {};
    try {
      final allReferrals = await client
          .from('profiles')
          .select('id, referral_mobile, is_deleted')
          .limit(100000);
      
      for (var rec in allReferrals as List) {
        final String childId = normalizePhone(rec['id'] ?? '');
        final String parentId = normalizePhone(rec['referral_mobile'] ?? '');
        final bool isDeleted = rec['is_deleted'] ?? false;
        isDeletedMap[childId] = isDeleted;
        if (childId.isNotEmpty && parentId.isNotEmpty) {
          childrenOf[parentId] = (childrenOf[parentId] ?? [])..add(childId);
        }
      }
    } catch (e) {
      debugPrint('Error batch fetching child referrals: $e');
    }

    return (response as List).map((p) {
      final String uid = p['id'] ?? '';
      final bool isDeleted = p['is_deleted'] ?? false;
      final String normUid = normalizePhone(uid);
      final int pts = calculateTotalPoints(normUid, childrenOf, isDeletedMap);
      final int directCount = (childrenOf[normUid] ?? [])
          .where((cid) => !(isDeletedMap[normalizePhone(cid)] ?? false))
          .length;

      return ABKMUser(
        id: uid,
        name: isDeleted ? 'Deleted Account' : (p['name'] ?? 'Anonymous'),
        profileImageUrl: isDeleted ? null : p['profile_image_url'],
        position: isDeleted ? '' : (p['position'] ?? 'Member'),
        userRole: p['user_role'] != null && p['user_role'] < UserRole.values.length 
            ? UserRole.values[p['user_role']] 
            : UserRole.member,
        district: isDeleted ? '' : (p['district'] ?? ''),
        state: isDeleted ? '' : (p['state'] ?? ''),
        gender: p['gender'] ?? 'Other',
        bio: '',
        isDeleted: isDeleted,
        points: pts,
        referralCount: directCount,
        referralMobile: p['referral_mobile'],
      );
    }).toList();
  }

  Future<void> _logActivity({
    required String actorId,
    required String targetId,
    required String type,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await client.from('activity_logs').insert({
        'actor_id': actorId,
        'target_id': targetId,
        'type': type,
        'metadata': metadata,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error logging activity: $e');
    }
  }

  Future<void> addAttendee(String eventId, String userId) async {
    final event = await client.from('events').select('approved_member_ids').eq('id', eventId).single();
    final List<String> attendees = List<String>.from(event['approved_member_ids'] ?? []);
    if (!attendees.contains(userId)) {
      attendees.add(userId);
      await client.from('events').update({'approved_member_ids': attendees}).eq('id', eventId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('abkm_full_event_$eventId');
    await prefs.remove('abkm_cached_essential_hosted_events');
    await prefs.remove('abkm_cached_essential_participated_events');
  }

  Future<void> removeAttendee(String eventId, String userId) async {
    final event = await client.from('events').select('approved_member_ids').eq('id', eventId).single();
    final List<String> attendees = List<String>.from(event['approved_member_ids'] ?? []);
    if (attendees.contains(userId)) {
      attendees.remove(userId);
      await client.from('events').update({'approved_member_ids': attendees}).eq('id', eventId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('abkm_full_event_$eventId');
    await prefs.remove('abkm_cached_essential_hosted_events');
    await prefs.remove('abkm_cached_essential_participated_events');
  }
}
