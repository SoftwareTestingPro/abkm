import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'profile_screen.dart';
import 'add_event_screen.dart';
import 'event_details_screen.dart';
import 'public_profile_screen.dart';
import 'promotion_management_screen.dart';
import 'activity_screen.dart';
import 'member_directory_screen.dart';
import 'package:marquee/marquee.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/reputation_badge.dart';
import '../services/supabase_service.dart';
import '../services/logic_service.dart';
import '../services/event_logic.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _navIndex = 0;
  bool _isHostingView = false;
  List<ABKMEvent> _events = [];
  List<ABKMEvent> _filteredEvents = [];
  List<ABKMUser> _profiles = [];
  List<ABKMUser> _filteredProfiles = [];
  List<EventApplication> _userApplications = [];
  List<EventApplication> _allApplications = [];
  bool _isLoading = true;
  String _firstName = 'User';
  String? _profileImageUrl;
  String? _currentUserId;
  final _searchController = TextEditingController();
  int _unreadActivityCount = 0;
  UserRole _currentUserRole = UserRole.member;
  DateTime? _lastEssentialLoad;
  String? _userState;
  String _userPosition = 'Member';
  final ScrollController _homeScrollController = ScrollController();
  int _resetKey = 0;
  Timer? _permissionCheckTimer;
  bool _hasShownAnnouncementThisSession = false;
  DateTime? _backgroundAt;

  // Seniority weights for positions (Lower is more senior)
  final Map<String, int> _positionSeniority = {
    'Patron': 10,
    'President': 20,
    'Working President': 30,
    'Vice President': 40,
    'General Secretary': 50,
    'Secretary': 60,
    'Joint Secretary': 70,
    'Office Secretary': 80,
    'Treasurer': 90,
    'Joint Treasurer': 100,
    'Auditor': 110,
    'Legal Advisor': 120,
    'Spokesperson': 130,
    'Media In-charge': 140,
    'IT & Social Media Coordinator': 150,
    'Public Relations Officer (PRO)': 160,
    'In-charge': 170,
    'Organization Secretary': 180,
    'Coordinator': 190,
    'Youth Wing President': 200,
    'Women’s Wing President': 210,
    'Students’ Wing President': 220,
    'Professional/Business Cell Head': 230,
    'Executive Member': 240,
    'Active Member': 250,
    'Primary Member': 260,
    'Member': 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    
    // Immediate sync-like check to prevent unauthenticated access via direct URL
    SharedPreferences.getInstance().then((prefs) {
      final mobile = prefs.getString('abkm_mobileNumber');
      if (mobile == null) {
        if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
        return;
      }
      
      // If logged in, proceed with heavy loads
      _checkProfile();
      _loadData();
      _performAdminCleanup();
      _startPermissionMonitoring();
      CacheLogic.performCleanup(prefs);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundAt = DateTime.now();
      _permissionCheckTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  void _handleResume() {
    // Restart permission monitoring which was cancelled on pause
    _startPermissionMonitoring();
    
    if (_backgroundAt == null) return;
    final elapsed = DateTime.now().difference(_backgroundAt!);
    _backgroundAt = null;
    
    // If backgrounded for more than 30 seconds, silently refresh data
    // (main.dart handles >2 min by restarting via splash, so this covers the short gap)
    if (elapsed.inSeconds >= 30 && mounted) {
      debugPrint('HomeScreen resumed after ${elapsed.inSeconds}s — refreshing data silently');
      _loadEssentialData(silent: true).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Silent refresh timed out after resume');
        },
      );
    }
  }

  void _startPermissionMonitoring() {
    _permissionCheckTimer?.cancel();
    _permissionCheckTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _syncPermissions();
    });
  }

  Future<void> _syncPermissions() async {
    if (_currentUserId == null || !mounted) return;
    
    try {
      // Lightweight fetch targeting only permission/role columns to avoid massive DB spam and cache clearing
      final data = await SupabaseService().getProfilePermissions(_currentUserId!);
      
      if (data != null && mounted) {
        bool needsUpdate = false;
        
        final int roleIndex = data['user_role'] ?? 0;
        final UserRole fetchedRole = roleIndex < UserRole.values.length 
            ? UserRole.values[roleIndex] 
            : UserRole.member;
            
        final String fetchedPosition = data['position'] ?? 'Member';
        final bool isBlocked = data['is_blocked'] ?? false;
        
        // Check for role change
        if (fetchedRole != _currentUserRole) {
          debugPrint('Role change detected for ${_currentUserId}: ${_currentUserRole.name} -> ${fetchedRole.name}');
          needsUpdate = true;
          _currentUserRole = fetchedRole;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('abkm_user_role', fetchedRole.index);
          
          // Clear cached profile to force fetch on next manual view
          await prefs.remove('abkm_full_profile_$_currentUserId');
          
          // If demoted to member and on hosting view, force switch to discover
          if (_currentUserRole == UserRole.member && _selectedIndex == 0) {
            _navIndex = 0;
            _isHostingView = false;
          }
        }
        
        // Check for position change
        if (fetchedPosition != _userPosition) {
          debugPrint('Position change detected for ${_currentUserId}: ${_userPosition} -> $fetchedPosition');
          needsUpdate = true;
          _userPosition = fetchedPosition;
          
          // Clear cached profile to force fetch on next manual view
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('abkm_full_profile_$_currentUserId');
        }

        // Check for block status
        if (fetchedRole == UserRole.blocked || isBlocked) {
           _permissionCheckTimer?.cancel();
           
           final prefs = await SharedPreferences.getInstance();
           final String? cachedData = prefs.getString('abkm_full_profile_$_currentUserId');
           String? uState;
           if (cachedData != null) {
             try {
               final u = ABKMUser.fromJson(json.decode(cachedData));
               uState = u.state;
             } catch(_) {}
           }
           _showBlockedDialog(uState);
           return;
        }

        // Update UI state silently if role/position changed
        if (needsUpdate && mounted) {
          _loadEssentialData(silent: true);
        }
      }
    } catch (e) {
      debugPrint('Error syncing permissions: $e');
    }
  }

  Future<void> _showBlockedDialog([String? userState]) async {
    if (!mounted) return;
    
    final blocker = await SupabaseService().getBlockerProfile(_currentUserId ?? 'anonymous');
    final String blockerName = blocker!.name;
    final String blockerMobile = blocker.id;
    final String displayPosition = FormatUtils.formatDesignation(blocker);
    
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.red[700]),
            const SizedBox(width: 12),
            Text('Account Blocked', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your account has been blocked by the administrator.',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[800]),
            ),
            const SizedBox(height: 12),
            Text(
              'Please contact support for assistance:',
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[800]),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue[100]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Name: $blockerName ($displayPosition)',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mobile: $blockerMobile',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.blue[800]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final Uri telUri = Uri.parse('tel:$blockerMobile');
                  if (await canLaunchUrl(telUri)) {
                    await launchUrl(telUri, mode: LaunchMode.externalApplication);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open dialer.')),
                    );
                  }
                },
                icon: const Icon(Icons.phone, color: Colors.white),
                label: Text(
                  'Call $blockerMobile',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _logout(context),
            child: Text('OK', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _performAdminCleanup() async {
    if (_currentUserRole == UserRole.admin || _currentUserRole == UserRole.superUser) {
      await SupabaseService().cleanupNonUPData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionCheckTimer?.cancel();
    _searchController.dispose();
    _homeScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProfiles = _profiles.where((p) {
        final matchesName = p.name.toLowerCase().contains(query);
        final matchesProfession = p.profession.toLowerCase().contains(query);
        final matchesSector = p.sector.toLowerCase().contains(query);
        final matchesBio = p.bio.toLowerCase().contains(query);
        final matchesDistrict = p.district.toLowerCase().contains(query);
        final matchesTehsil = p.tehsil.toLowerCase().contains(query);
        final matchesVillage = p.village.toLowerCase().contains(query);
        final matchesMobile = p.id.toLowerCase().contains(query);
        
        return matchesName || 
               matchesProfession || 
               matchesSector || 
               matchesBio || 
               matchesDistrict || 
               matchesTehsil || 
               matchesVillage || 
               matchesMobile;
      }).toList();
      _sortProfiles(_filteredProfiles);
    });
  }

  void _sortProfiles(List<ABKMUser> list) {
    final Map<String, int> levelWeights = {
      'National': 0,
      'State': 1000,
      'District': 2000,
      'City/Tehsil/Block': 3000,
      'Village/Unit': 4000,
    };

    list.sort((a, b) {
      // Extract Level and Base Position
      String levelA = 'Village/Unit';
      String basePosA = a.position;
      for (var lvl in levelWeights.keys) {
        if (a.position.startsWith(lvl)) {
          levelA = lvl;
          basePosA = a.position.replaceFirst(lvl, '').trim();
          break;
        }
      }

      String levelB = 'Village/Unit';
      String basePosB = b.position;
      for (var lvl in levelWeights.keys) {
        if (b.position.startsWith(lvl)) {
          levelB = lvl;
          basePosB = b.position.replaceFirst(lvl, '').trim();
          break;
        }
      }

      final weightA = (levelWeights[levelA] ?? 5000) + (_positionSeniority[basePosA] ?? 999);
      final weightB = (levelWeights[levelB] ?? 5000) + (_positionSeniority[basePosB] ?? 999);
      
      if (weightA != weightB) {
        return weightA.compareTo(weightB);
      }
      
      final pointsCompare = b.points.compareTo(a.points);
      if (pointsCompare != 0) {
        return pointsCompare;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  bool _isDiscoveryLoaded = false;

  Future<void> _checkProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final mobileNumber = prefs.getString('abkm_mobileNumber');
    if (mobileNumber == null) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
      return;
    }
    
    try {
      final profile = await SupabaseService().getProfile(mobileNumber, forceRefresh: true);
      if (profile == null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ProfileScreen()),
        );
      } else if (profile.userRole == UserRole.blocked) {
        _showBlockedDialog(profile.state);
      } else {
        await prefs.setString('abkm_userName', profile.name);
        await prefs.setBool('abkm_hasProfile', true);
        await prefs.setInt('abkm_user_role', profile.userRole.index);
        
        // Update last login in the database on app launch for persistent sessions
        SupabaseService().updateLastLogin(mobileNumber);
        
        final cachedApps = prefs.getString('abkm_cached_essential_user_apps');
        final cachedEvents = prefs.getString('abkm_cached_home_events');
        final cachedProfiles = prefs.getString('abkm_cached_home_profiles');
        
        if (cachedApps != null || cachedEvents != null || cachedProfiles != null) {
          try {
            final appsList = cachedApps != null ? jsonDecode(cachedApps) as List : [];
            final eventsList = cachedEvents != null ? jsonDecode(cachedEvents) as List : [];
            final profilesList = cachedProfiles != null ? jsonDecode(cachedProfiles) as List : [];

            final cApps = appsList.map((e) => EventApplication.fromJson(e)).toList();
            final cEvents = eventsList.map((e) => ABKMEvent.fromJson(e)).toList();
            final cProfiles = profilesList
                .map((p) => ABKMUser.fromJson(p))
                .toList();

            if (mounted) {
              setState(() {
                _events = cEvents;
                _profiles = cProfiles;
                _userApplications = cApps;
                _isLoading = false;
              });
            }
          } catch (e) {
            debugPrint('Activity Cache Error: $e');
          }
        }
        
        if (mounted) {
          setState(() {
            _firstName = profile.name.split(' ')[0];
            _profileImageUrl = profile.profileImageUrl;
            _currentUserRole = profile.userRole;
            // If user is a member and was on Hosting (index 0), switch to Discover
            if (_currentUserRole == UserRole.member && _selectedIndex == 0) {
              _navIndex = 0; // Discover for member
              _selectedIndex = 0; 
              _isHostingView = false;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading profile in _checkProfile: $e');
      
      // Graceful offline fallback: if there is cached profile data, load it!
      final cachedProfileData = prefs.getString('abkm_full_profile_$mobileNumber');
      if (cachedProfileData != null) {
        try {
          final profile = ABKMUser.fromJson(json.decode(cachedProfileData));
          if (mounted) {
            setState(() {
              _firstName = profile.name.split(' ')[0];
              _profileImageUrl = profile.profileImageUrl;
              _currentUserRole = profile.userRole;
              if (_currentUserRole == UserRole.member && _selectedIndex == 0) {
                _navIndex = 0;
                _selectedIndex = 0;
                _isHostingView = false;
              }
            });
          }
        } catch (_) {}
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Working offline. Some data may be outdated.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _loadData() async {
    final bool hasData = _profiles.isNotEmpty || _events.isNotEmpty;
    _isDiscoveryLoaded = false;
    await _loadEssentialData(silent: hasData);
  }

  Future<void> _loadEssentialData({bool silent = false}) async {
    if (!mounted) return;
    _isDiscoveryLoaded = false;
    if (!silent) setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('abkm_user_id') ?? prefs.getString('abkm_mobileNumber') ?? 'anonymous';
      final currentUserId = _currentUserId!;
      
      final roleIndex = prefs.getInt('abkm_user_role') ?? 0;
      _currentUserRole = UserRole.values[roleIndex];
      
      // Synchronize hosting view and nav index based on user role and preferences
      if (_currentUserRole == UserRole.member) {
        _isHostingView = false;
        _navIndex = 0; // Discover
      } else {
        _navIndex = _isHostingView ? 0 : 1;
      }
      _selectedIndex = 0; // Both Hosting and Discover are in _buildMainContent at index 0

      // Fetch full profile to get user state for discovery - Force refresh to sync role changes
      try {
        final profile = await SupabaseService().getProfile(currentUserId, forceRefresh: true).timeout(const Duration(seconds: 10));
        if (profile != null) {
          _userState = profile.state;
          _userPosition = profile.position;
          if (mounted) {
            setState(() {
              _currentUserRole = profile.userRole; // Update local role if changed
            });
            // Also update shared prefs to ensure other screens see the new role
            await prefs.setInt('abkm_user_role', profile.userRole.index);
          }
        } else {
          _userState = prefs.getString('abkm_user_state') ?? 'Uttar Pradesh';
        }
      } catch (profileErr) {
        debugPrint('Error fetching profile in _loadEssentialData: $profileErr');
        _userState = prefs.getString('abkm_user_state') ?? 'Uttar Pradesh';
      }
      
      if (_userState != null) {
        prefs.setString('abkm_user_state', _userState!);
      }

      // Try to load cached essential data first for instant start
      final cachedHosted = prefs.getString('abkm_cached_essential_hosted_events');
      final cachedParticipated = prefs.getString('abkm_cached_essential_participated_events');
      final cachedApps = prefs.getString('abkm_cached_essential_user_apps');
      final cachedHostApps = prefs.getString('abkm_cached_essential_host_apps');

      if (cachedHosted != null || cachedParticipated != null || cachedApps != null || cachedHostApps != null) {
        setState(() {
          final List<ABKMEvent> cEvents = [];
          if (cachedHosted != null) cEvents.addAll((json.decode(cachedHosted) as List).map((e) => ABKMEvent.fromJson(e)).toList());
          if (cachedParticipated != null) cEvents.addAll((json.decode(cachedParticipated) as List).map((e) => ABKMEvent.fromJson(e)).toList());
          
          final Map<String, ABKMEvent> eventMap = {for (var e in cEvents) e.id: e};
          _events = eventMap.values.toList();
          
          if (cachedApps != null) _userApplications = (json.decode(cachedApps) as List).map((e) => EventApplication.fromJson(e)).toList();
          
          final List<EventApplication> hApps = [];
          if (cachedHostApps != null) hApps.addAll((json.decode(cachedHostApps) as List).map((e) => EventApplication.fromJson(e)).toList());
          _allApplications = [..._userApplications, ...hApps];
          
          _isLoading = false; // Show cached data immediately
        });
      }

      try {
        final results = await Future.wait([
          SupabaseService().getEventsByHost(currentUserId).timeout(const Duration(seconds: 15)),
          SupabaseService().getEventsParticipated(currentUserId).timeout(const Duration(seconds: 15)),
          SupabaseService().getApplicationsForUser(currentUserId).timeout(const Duration(seconds: 15)),
          SupabaseService().getApplicationsByHost(currentUserId).timeout(const Duration(seconds: 15)),
        ]);

        final hostedEvents = results[0] as List<ABKMEvent>;
        final participatedEvents = results[1] as List<ABKMEvent>;
        final userApps = results[2] as List<EventApplication>;
        final appsByMeAsHost = results[3] as List<EventApplication>;

        // Cache the results for next launch
        await prefs.setString('abkm_cached_essential_hosted_events', json.encode(hostedEvents.map((e) => e.toJson()).toList()));
        await prefs.setString('abkm_cached_essential_participated_events', json.encode(participatedEvents.map((e) => e.toJson()).toList()));
        await prefs.setString('abkm_cached_essential_user_apps', json.encode(userApps.map((a) => a.toJson()).toList()));
        await prefs.setString('abkm_cached_essential_host_apps', json.encode(appsByMeAsHost.map((a) => a.toJson()).toList()));

        if (mounted) {
          setState(() {
            final Map<String, ABKMEvent> eventMap = {for (var e in _events) e.id: e};
            for (var e in hostedEvents) eventMap[e.id] = e;
            for (var e in participatedEvents) eventMap[e.id] = e;
            
            _events = eventMap.values.toList();
            _userApplications = userApps;
            _allApplications = [...userApps, ...appsByMeAsHost];
            
            _applyInitialFiltering(currentUserId);
            
            final activityCount = _allApplications.length;
            final lastViewed = prefs.getInt('abkm_lastViewedActivityCount') ?? 0;
            _unreadActivityCount = activityCount > lastViewed ? activityCount - lastViewed : 0;
            
            _lastEssentialLoad = DateTime.now();
          });
        }

        SupabaseService().getActivityFeed(currentUserId);
        
        if (mounted) {
          try {
            prefs.setString('abkm_cached_home_events', CacheLogic.getStrippedJson(_events.take(20).toList()));
          } catch (e) {
            debugPrint('Failed to update essential cache: $e');
          }
        }

        _loadDiscoveryData();
      } catch (dataErr) {
        debugPrint('Error loading user-specific data lists in _loadEssentialData: $dataErr');
      }
    } catch (e) {
      debugPrint('General error in _loadEssentialData: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isDiscoveryLoading = false;
  Future<void> _loadDiscoveryData() async {
    if (_isDiscoveryLoaded || _isDiscoveryLoading || !mounted) return;
    
    setState(() => _isDiscoveryLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final results = await Future.wait([
        SupabaseService().getEventsLight(state: null).timeout(const Duration(seconds: 15)),
        SupabaseService().getProfilesLight(state: null).timeout(const Duration(seconds: 15)),
      ]);

      final cloudEvents = results[0] as List<ABKMEvent>;
      final cloudProfiles = results[1] as List<ABKMUser>;

      if (mounted) {
        setState(() {
          final Map<String, ABKMEvent> eventMap = {for (var e in _events) e.id: e};
          for (var e in cloudEvents) {
            eventMap[e.id] = e;
          }
          _events = eventMap.values.toList();
          
          _profiles = cloudProfiles.toList();
          _sortProfiles(_profiles);
          _filteredProfiles = _profiles;
          _isDiscoveryLoaded = true;
          _isDiscoveryLoading = false;
          _applyInitialFiltering(_currentUserId!);
        });
        _checkAndShowAnnouncement();
      }
      if (mounted) {
        try {
          prefs.setString('abkm_cached_home_profiles', CacheLogic.getStrippedJson(_profiles.take(20).toList()));
          prefs.setString('abkm_cached_home_events', CacheLogic.getStrippedJson(_events.take(50).toList()));
        } catch (e) {
          debugPrint('Failed to update discovery cache: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading discovery data: $e');
    } finally {
      if (mounted) {
        setState(() => _isDiscoveryLoading = false);
      }
    }
  }

  void _checkAndShowAnnouncement() {
    if (_hasShownAnnouncementThisSession) return;
    
    try {
      final now = DateTime.now();
      // Find the first approved announcement that hasn't expired yet
      final announcement = _events.firstWhere(
        (e) => e.eventType == EventType.announcement && 
               e.date.isAfter(now) && 
               e.isApproved &&
               (e.state.isEmpty || e.state == _userState),
      );
      
      _hasShownAnnouncementThisSession = true;
      
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _showAnnouncementDialog(announcement);
        }
      });
    } catch (_) {
      // No active announcements
    }
  }

  void _showAnnouncementDialog(ABKMEvent announcement) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.orange, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'IMPORTANT ANNOUNCEMENT',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                announcement.title,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    announcement.description,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyInitialFiltering(String currentUserId) {
    if (_isHostingView) {
      _filteredEvents = _events.where((e) => e.hostId == currentUserId).toList();
    } else {
      // Only show approved events in public discovery (excluding Announcement events)
      _filteredEvents = _events.where((e) => e.isApproved && e.eventType != EventType.announcement).toList();
    }
  }

  Future<void> _loadEvents() async {
    _isDiscoveryLoaded = false; // Force re-fetch of discovery data
    await _loadEssentialData();
    if (!_isHostingView) {
      await _loadDiscoveryData();
    }
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Find members by Name, City, or Profession...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty 
            ? IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () {
                  _searchController.clear();
                },
              )
            : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildMarqueeText({
    required String text,
    required TextStyle style,
    required double height,
    required double maxWidth,
    double blankSpace = 20.0,
    double velocity = 30.0,
    TextAlign textAlign = TextAlign.start,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: ui.TextDirection.ltr,
    )..layout();

    if (textPainter.width <= maxWidth) {
      return SizedBox(
        height: height,
        child: Text(
          text,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Marquee(
        text: text,
        style: style,
        scrollAxis: Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.start,
        blankSpace: blankSpace,
        velocity: velocity,
        pauseAfterRound: Duration.zero,
        accelerationDuration: Duration.zero,
        accelerationCurve: Curves.linear,
        decelerationDuration: Duration.zero,
        decelerationCurve: Curves.easeOut,
      ),
    );
  }

  Widget _buildAvailableABKMList() {
    final theme = Theme.of(context);
    if (_isDiscoveryLoading || (_profiles.isEmpty && !_isDiscoveryLoaded)) {
      return SizedBox(
        height: 260,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          itemBuilder: (context, index) => _buildSkeletonProfileCard(),
        ),
      );
    }
    
    if (_filteredProfiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Icon(Icons.search_off, color: Colors.grey[300], size: 40),
              const SizedBox(height: 8),
              Text('No community members found.', style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 260,
      child: ListView.builder(
        key: ValueKey('community_list_$_resetKey'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: _filteredProfiles.length,
        itemBuilder: (context, index) {
          final profile = _filteredProfiles[index];
          final location = [
            if (profile.village.isNotEmpty) profile.village,
            if (profile.tehsil.isNotEmpty) profile.tehsil,
            if (profile.district.isNotEmpty) profile.district,
            if (profile.state.isNotEmpty) profile.state,
          ].where((s) => s.isNotEmpty).join(', ');

          return GestureDetector(
            onTap: () {
              // Members cannot view other profiles
              if (_currentUserRole == UserRole.member) return;

              Navigator.of(context).push<dynamic>(
                MaterialPageRoute(
                  builder: (context) => PublicProfileScreen(user: profile),
                ),
              ).then((result) {
                _loadEvents();
                if (result is int) {
                  _onBottomNavTap(result);
                }
              });
            },
            child: Container(
              width: 180,
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.08), Colors.white),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15), width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   // Portrait Image
                   Expanded(
                     flex: 6,
                     child: Stack(
                       children: [
                         Container(
                           width: double.infinity,
                           height: double.infinity,
                           decoration: BoxDecoration(
                             borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                             color: theme.colorScheme.primary.withOpacity(0.05),
                           ),
                           child: ClipRRect(
                             borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                             child: profile.profileImageUrl != null
                               ? profile.profileImageUrl!.startsWith('http')
                                 ? Image.network(profile.profileImageUrl!, fit: BoxFit.cover, width: double.infinity)
                                 : Image.memory(base64Decode(profile.profileImageUrl!), fit: BoxFit.cover, width: double.infinity)
                               : Center(child: Icon(Icons.person, size: 50, color: theme.colorScheme.primary.withOpacity(0.2))),
                           ),
                         ),
                         Positioned(
                           bottom: 8,
                           right: 8,
                           child: _buildReputationBadge(theme, profile.points),
                         ),
                       ],
                     ),
                   ),
                  // Info Area
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Position - Below image, handle long text
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue[100]!, width: 0.5),
                              ),
                              child: _buildMarqueeText(
                                text: FormatUtils.formatDesignation(profile).toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 9, 
                                  fontWeight: FontWeight.bold, 
                                  color: Colors.blue[800],
                                  letterSpacing: 0.2
                                ),
                                height: 12,
                                maxWidth: 136, // 160 - 24 (padding)
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          _buildMarqueeText(
                            text: profile.name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, 
                              fontSize: 13, 
                              color: Colors.black87
                            ),
                            height: 18,
                            maxWidth: 160,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on, size: 10, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  style: GoogleFonts.inter(
                                    fontSize: 10, 
                                    color: Colors.grey[600], 
                                    fontWeight: FontWeight.w500,
                                    height: 1.1
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReputationBadge(ThemeData theme, int points) {
    return ReputationBadge(points: points, size: 26);
  }

  Widget _buildSkeletonProfileCard() {
    final theme = Theme.of(context);
    return Container(
      width: 180,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.08), Colors.white),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, color: theme.colorScheme.primary.withOpacity(0.05)),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 100,
                      height: 12,
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
                    ),
                  ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, delay: 200.ms),
                  const SizedBox(height: 8),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)),
                  ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, delay: 400.ms),
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 10,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)),
                  ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, delay: 600.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    Widget _buildMainContent() {
      return Stack(
        children: [
          _buildPageBackground(),
          RefreshIndicator(
            onRefresh: _loadEvents,
            color: Theme.of(context).colorScheme.primary,
            child: CustomScrollView(
              controller: _homeScrollController,
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildTopBar(context),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isHostingView) ...[
                          _buildHostDashboard(),
                        ] else ...[
                          _buildSectionHeader(context, 'Community Directory', action: '${_filteredProfiles.length} Members', onActionTap: (_currentUserRole == UserRole.superUser || _currentUserRole == UserRole.admin) ? () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const MemberDirectoryScreen()));
                          } : null),
                          _buildSearchBar(),
                          const SizedBox(height: 8),
                          _buildAvailableABKMList(),
                          const SizedBox(height: 24),
                          Builder(
                            builder: (context) {
                              final now = DateTime.now();
                              final futureEventsCount = _filteredEvents.where((e) => e.date.isAfter(now)).length;
                              return _buildSectionHeader(
                                context,
                                'Upcoming Events',
                                action: '$futureEventsCount ${futureEventsCount == 1 ? "Event" : "Events"}',
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          _buildWeddingEventsList(),
                          const SizedBox(height: 20),
                          Builder(
                            builder: (context) {
                              final now = DateTime.now();
                              final attendingFutureCount = _events.where((e) => e.approvedMemberIds.contains(_currentUserId) && e.date.isAfter(now)).length;
                              if (attendingFutureCount == 0) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader(
                                    context,
                                    "Events I'm Attending",
                                    action: '$attendingFutureCount ${attendingFutureCount == 1 ? "Event" : "Events"}',
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMyAttendingEventsList(isPast: false),
                                  const SizedBox(height: 12),
                                ],
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final now = DateTime.now();
                              final attendingPastCount = _events.where((e) => e.approvedMemberIds.contains(_currentUserId) && e.date.isBefore(now)).length;
                              if (attendingPastCount == 0) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader(
                                    context,
                                    "Events I've Attended",
                                    action: '$attendingPastCount ${attendingPastCount == 1 ? "Event" : "Events"}',
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMyAttendingEventsList(isPast: true),
                                  const SizedBox(height: 12),
                                ],
                              );
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final now = DateTime.now();
                              final pastEventsCount = _filteredEvents.where((e) => e.date.isBefore(now)).length;
                              if (pastEventsCount == 0) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader(
                                    context,
                                    'Completed Events',
                                    action: '$pastEventsCount ${pastEventsCount == 1 ? "Event" : "Events"}',
                                  ),
                                  const SizedBox(height: 8),
                                  _buildPastEventsList(),
                                  const SizedBox(height: 20),
                                ],
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              KeyedSubtree(
                key: ValueKey('discover_$_resetKey'),
                child: _buildMainContent(),
              ),
              AddEventScreen(
                key: ValueKey('add_$_resetKey'),
                isTabMode: true,
                onSaveComplete: () {
                  _loadData();
                  setState(() => _selectedIndex = 0);
                },
              ),
              ActivityScreen(key: ValueKey('activity_$_resetKey')),
              ProfileScreen(
                key: ValueKey('profile_$_resetKey'),
                isEditMode: true, 
                isTabMode: true,
                onTabSwitchRequested: _onBottomNavTap,
                isActive: _selectedIndex == 3,
              ),
              PromotionManagementScreen(key: ValueKey('promo_$_resetKey')),
            ],
          ),
          if (_isLoading)
            Positioned.fill(
              child: Stack(
                children: [
                  _buildPageBackground(),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 500),
                        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 65, maxWidth: 180),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo_large.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Image.asset(
                                      'assets/images/logo_medium.png',
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Image.asset(
                                          'assets/images/logo_small.png',
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: theme.colorScheme.primary.withOpacity(0.1),
                                              child: Icon(
                                                Icons.group,
                                                color: theme.colorScheme.primary,
                                                size: 28,
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'अखिल भारतीय कुशवाहा महासभा',
                              style: theme.textTheme.displayLarge?.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'शिक्षित बनो, संगठित रहो, संघर्ष करो',
                              style: GoogleFonts.inter(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'NATIONAL PATRONS',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 16,
                              runSpacing: 12,
                              children: [
                                _buildPatronAvatar('assets/images/patron1.jpg', 'श्री जे डी कौशल सैनी', 'संरक्षक अध्यक्ष'),
                                _buildPatronAvatar('assets/images/patron2.jpg', 'श्री शंकर मेहता', 'राष्ट्रीय अध्यक्ष'),
                                _buildPatronAvatar('assets/images/patron3.jpg', 'श्री उमेश पंचेश्वर', 'राष्ट्रीय प्रधान महासचिव'),
                                _buildPatronAvatar('assets/images/patron4.jpg', 'श्री डी एन भगत', 'राष्ट्रीय कोषाध्यक्ष'),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Syncing Data...',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(theme),
    );
  }

  Widget _buildPastEventsList() {
    final now = DateTime.now();
    final pastEvents = _filteredEvents.where((e) => e.date.isBefore(now)).toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // Most recent past events first

    if (pastEvents.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 240,
      child: ListView.builder(
        key: ValueKey('past_events_$_resetKey'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: pastEvents.length,
        itemBuilder: (context, index) {
          final event = pastEvents[index];
          return GestureDetector(
            onTap: () => Navigator.of(context).push<dynamic>(
              MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)),
            ).then((result) {
              _loadEvents();
              if (result is int) {
                _onBottomNavTap(result);
              }
            }),
            child: _buildModernEventCard(event, isPast: true),
          );
        },
      ),
    );
  }


  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.12),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Beautifully styled App Logo
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo_small.png',
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, error, stackTrace) {
                      return Image.asset(
                        'assets/images/logo_medium.png',
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (context, error, stackTrace) {
                          return Image.asset(
                            'assets/images/logo_large.png',
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                child: Icon(
                                  Icons.group,
                                  color: theme.colorScheme.primary,
                                  size: 28,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // App Full Name & Motto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppConfig.appFullName,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'शिक्षित बनो, संगठित रहो, संघर्ष करो',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {String? action, VoidCallback? onActionTap}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title, 
                    style: GoogleFonts.poppins(
                      fontSize: 15, 
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onActionTap ?? () {}, 
              child: Text(
                action, 
                style: GoogleFonts.inter(
                  color: theme.colorScheme.secondary, 
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyAttendingEventsList({bool isPast = false}) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final now = DateTime.now();
    final attendingEvents = _events.where((e) => 
      e.approvedMemberIds.contains(_currentUserId) && 
      (isPast ? e.date.isBefore(now) : e.date.isAfter(now))
    ).toList()
      ..sort((a, b) => isPast ? b.date.compareTo(a.date) : a.date.compareTo(b.date));

    if (attendingEvents.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 240,
      child: ListView.builder(
        key: ValueKey('attending_events_$_resetKey'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: attendingEvents.length,
        itemBuilder: (context, index) {
          final event = attendingEvents[index];
          return GestureDetector(
            onTap: () => Navigator.of(context).push<dynamic>(
              MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)),
            ).then((result) {
              _loadData();
              if (result is int) {
                _onBottomNavTap(result);
              }
            }),
            child: _buildModernEventCard(
              event,
              isApproved: true,
              isPast: isPast,
            ),
          );
        },
      ),
    );
  }

  Widget _buildWeddingEventsList() {
    if (_isDiscoveryLoading || (_events.where((e) => e.hostId != _currentUserId && e.date.isAfter(DateTime.now())).isEmpty && !_isDiscoveryLoaded)) {
      return SizedBox(
        height: 235,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          scrollDirection: Axis.horizontal,
          itemCount: 2,
          itemBuilder: (context, index) => _buildSkeletonEventCard(),
        ),
      );
    }

    final now = DateTime.now();
    final futureEvents = _filteredEvents.where((e) => e.date.isAfter(now)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (futureEvents.isEmpty) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_busy, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No events found.',
                style: GoogleFonts.inter(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 235,
      child: ListView.builder(
        key: ValueKey('wedding_events_$_resetKey'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: futureEvents.length,
        itemBuilder: (context, index) {
          final event = futureEvents[index];
          final eventApps = _userApplications.where((a) => a.eventId == event.id).toList();
          return GestureDetector(
            onTap: () => Navigator.of(context).push<dynamic>(
              MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)),
            ).then((result) {
              _loadEvents();
              if (result is int) {
                _onBottomNavTap(result);
              }
            }),
            child: _buildModernEventCard(event, applications: eventApps),
          );
        },
      ),
    );
  }

  Widget _buildCardIconButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Color _getEventTypeColor(EventType type) {
    switch (type) {
      case EventType.meeting: return Colors.indigo;
      case EventType.rally: return Colors.orange;
      case EventType.andolan: return Colors.red;
      case EventType.dharna: return Colors.amber;
      case EventType.conference: return Colors.blue;
      case EventType.protest: return Colors.deepOrange;
      default: return Colors.blueGrey;
    }
  }

  Widget _buildModernEventCard(ABKMEvent event, {
    bool isHost = false, 
    bool isPast = false, 
    bool isApproved = false, 
    VoidCallback? onWithdraw,
    List<EventApplication> applications = const [],
  }) {
    final sortedApps = applications.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    final theme = Theme.of(context);
    final guestsConfirmed = event.approvedMemberIds.length;
    
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 250,
        margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.08), Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.08), Colors.white),
          borderRadius: BorderRadius.circular(31),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  child: Container(
                    height: 90,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: event.imageUrl.startsWith('http') 
                            ? NetworkImage(event.imageUrl) as ImageProvider
                            : (event.imageUrl.startsWith('assets/') 
                                ? AssetImage(event.imageUrl) as ImageProvider
                                : MemoryImage(base64Decode(event.imageUrl))),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 15,
                  left: 15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _getEventTypeColor(event.eventType),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          event.eventType.name.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onWithdraw != null)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _buildCardIconButton(Icons.cancel_outlined, Colors.red, onWithdraw),
                  ),
                if (isHost && !isPast && (event.isApproved == false || _currentUserRole == UserRole.admin || _currentUserRole == UserRole.superUser))
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Row(
                      children: [
                        _buildCardIconButton(Icons.edit_outlined, Colors.blue, () async {
                           final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => AddEventScreen(eventToEdit: event)),
                           );
                           if (result == true) _loadData();
                        }),
                        const SizedBox(width: 8),
                        _buildCardIconButton(Icons.delete_outline, Colors.red, () async {
                           final confirm = await showDialog<bool>(
                             context: context,
                             builder: (context) => AlertDialog(
                               title: const Text('Delete Event'),
                               content: const Text('Are you sure you want to delete this event?'),
                               actions: [
                                 TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                 TextButton(
                                   onPressed: () => Navigator.pop(context, true),
                                   style: TextButton.styleFrom(foregroundColor: Colors.red),
                                   child: const Text('Delete'),
                                 ),
                               ],
                             ),
                           );
                           if (confirm == true) {
                             await SupabaseService().deleteEvent(event.id);
                             _loadData();
                           }
                        }),
                      ],
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('dd MMM | h:mm a').format(event.date),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 12, color: theme.colorScheme.primary.withOpacity(0.5)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${event.meetingPoint != null && event.meetingPoint!.isNotEmpty ? "${event.meetingPoint}, " : ""}${event.village.isNotEmpty ? "${event.village}, " : ""}${event.tehsil.isNotEmpty ? "${event.tehsil}, " : ""}${event.district.isNotEmpty ? "${event.district}, " : ""}${event.state}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isHost && !isPast && !event.isApproved)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                          const SizedBox(width: 6),
                          Text(
                            'Approval Pending',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.people_outline, size: 18, color: Colors.black87),
                      const SizedBox(width: 6),
                      Text(
                        guestsConfirmed == 1 
                          ? (isPast ? '1 Person attended' : '1 Person attending') 
                          : '$guestsConfirmed People ${isPast ? "attended" : "attending"}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  // Attendance count is already shown in the card info section above.
                  // We no longer need a separate "Join Requests" section as joining is direct.
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Future<void> _handleActivityClick() async {
    final prefs = await SharedPreferences.getInstance();
    int currentTotal = 0;
    for (var app in _allApplications) {
      final event = _events.firstWhere((e) => e.id == app.eventId, orElse: () => ABKMEvent(id: 'dummy', hostId: '', title: '', description: '', date: DateTime.now(), village: '', eventType: EventType.other, imageUrl: '', district: '', state: ''));
      if (event.id != 'dummy' && (app.applicantId == _currentUserId || event.hostId == _currentUserId)) {
        currentTotal++;
      }
    }
    await prefs.setInt('abkm_lastViewedActivityCount', currentTotal);
    
    final now = DateTime.now();
    if (_lastEssentialLoad == null || now.difference(_lastEssentialLoad!).inMinutes >= 2 || _unreadActivityCount > 0) {
      _loadEssentialData(); 
    }
  }

  Future<void> _onBottomNavTap(int index) async {
    FocusScope.of(context).unfocus();
    int mappedIndex = 0;

    if (_currentUserRole == UserRole.member) {
      // Member: 0:Discover, 1:Activity, 2:Profile
      if (index == 0) mappedIndex = 0; // Discover
      if (index == 1) {
        mappedIndex = 2; // Activity
        await _handleActivityClick();
      }
      if (index == 2) mappedIndex = 3; // Profile
    } else if (_currentUserRole == UserRole.moderator) {
      // Moderator: 0:Hosting, 1:Discover, 2:Create, 3:Activity, 4:Profile
      if (index == 0) mappedIndex = 0; // Hosting
      if (index == 1) mappedIndex = 0; // Discover
      if (index == 2) mappedIndex = 1; // Create
      if (index == 3) {
        mappedIndex = 2; // Activity
        await _handleActivityClick();
      }
      if (index == 4) mappedIndex = 3; // Profile
    } else {
      // Admin / SuperUser: 0:Hosting, 1:Discover, 2:Create, 3:Manage, 4:Activity, 5:Profile
      if (index == 0) mappedIndex = 0; // Hosting
      if (index == 1) mappedIndex = 0; // Discover
      if (index == 2) mappedIndex = 1; // Create
      if (index == 3) mappedIndex = 4; // Manage
      if (index == 4) {
        mappedIndex = 2; // Activity
        await _handleActivityClick();
      }
      if (index == 5) mappedIndex = 3; // Profile
    }

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedIndex = mappedIndex;
      _navIndex = index;
      
      if (_currentUserRole == UserRole.member) {
        _isHostingView = false;
        prefs.setBool('abkm_isHostingView', false);
      } else {
        if (index == 0) {
          _isHostingView = true;
          prefs.setBool('abkm_isHostingView', true);
          _applyInitialFiltering(_currentUserId!);
        } else if (index == 1) {
          _isHostingView = false;
          prefs.setBool('abkm_isHostingView', false);
          if (!_isDiscoveryLoaded) {
            _loadDiscoveryData();
          } else {
            _applyInitialFiltering(_currentUserId!);
          }
        }
      }
    });

    if (mappedIndex == 0) {
      _searchController.clear();
      
      // Always trigger a background refresh when navigating back to the main discovery feed
      _loadData();
      
      if (_homeScrollController.hasClients) {
        _homeScrollController.jumpTo(0);
      }
    }
  }

  Widget _buildBottomNav(ThemeData theme) {
    return ABKMBottomNav(
      currentIndex: _navIndex,
      userRole: _currentUserRole,
      unreadActivityCount: _unreadActivityCount,
      onTap: _onBottomNavTap,
    );
  }

  Widget _buildActivityIcon() {
    return Stack(
      children: [
        const Icon(Icons.notifications_outlined),
        if (_unreadActivityCount > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(
                minWidth: 12,
                minHeight: 12,
              ),
              child: Text(
                '$_unreadActivityCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
      ],
    );
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (String key in keys) {
      if (key.startsWith('abkm_')) {
        await prefs.remove(key);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
  }

  String _getStatusText(EventApplication app) {
    if (app.isInvitation) {
      if (app.status == ApplicationStatus.invitationPending) return 'Invitation';
      if (app.status == ApplicationStatus.invitationAccepted) return 'Accepted';
      if (app.status == ApplicationStatus.invitationDeclined) return 'Declined';
    }
    
    if (app.isApproved) return 'Approved';
    if (app.status == ApplicationStatus.declined) return 'Declined';
    if (app.status == ApplicationStatus.withdrawn) return 'Withdrawn';
    
    return 'Pending';
  }

  Widget _buildApplicationStatusInfo(List<EventApplication> apps, {bool isPast = false}) {
    return const SizedBox.shrink();
  }

  IconData _getStatusIcon(EventApplication app) {
    if (app.isApproved) return Icons.check_circle;
    if (app.status == ApplicationStatus.declined || app.status == ApplicationStatus.invitationDeclined) return Icons.cancel;
    if (app.status == ApplicationStatus.withdrawn) return Icons.backspace;
    return Icons.pending;
  }

  Widget _buildApplicationActionButtons(List<EventApplication> apps) {
     if (apps.any((a) => a.isInvitation && a.status == ApplicationStatus.invitationPending)) {
        final invite = apps.firstWhere((a) => a.isInvitation && a.status == ApplicationStatus.invitationPending);
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () async {
                await SupabaseService().respondToInvitation(invite.id, false, invite.eventId, invite.applicantId);
                _loadData();
              },
              child: const Text('Deny', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () async {
                await SupabaseService().respondToInvitation(invite.id, true, invite.eventId, invite.applicantId);
                _loadData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, 
                foregroundColor: Colors.white, 
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                minimumSize: const Size(0, 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Accept', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        );
     }
     return const SizedBox.shrink();
  }

  Color _getStatusColor(EventApplication app) {
    if (app.isInvitation && app.status == ApplicationStatus.invitationPending) return Colors.blue;
    if (app.isApproved || app.status == ApplicationStatus.invitationAccepted) return Colors.green;
    if (app.status == ApplicationStatus.declined || app.status == ApplicationStatus.invitationDeclined) return Colors.red;
    if (app.status == ApplicationStatus.withdrawn) return Colors.grey;
    return Colors.orange;
  }

  Widget _buildAnnouncementCard(ABKMEvent event, {bool isHost = false}) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 250,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.orange[50]!.withOpacity(0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.orange[100]!, width: 1.5),
        ),
        child: Container(
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Announcement Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange[100]!.withOpacity(0.6),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.campaign_outlined, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'ANNOUNCEMENT',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800]!,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    if (isHost && (event.isApproved == false || _currentUserRole == UserRole.admin || _currentUserRole == UserRole.superUser))
                      Row(
                        children: [
                          if (event.date.isAfter(DateTime.now())) ...[
                            InkWell(
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => AddEventScreen(eventToEdit: event)),
                                );
                                if (result == true) _loadData();
                              },
                              child: Icon(Icons.edit_outlined, color: Colors.blue[700], size: 16),
                            ),
                            const SizedBox(width: 10),
                          ],
                          InkWell(
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Announcement'),
                                  content: const Text('Are you sure you want to delete this announcement?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await SupabaseService().deleteEvent(event.id);
                                _loadData();
                              }
                            },
                            child: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.date.isBefore(DateTime.now())
                          ? 'Expired ${DateFormat('dd MMM yyyy | h:mm a').format(event.date.toLocal())}'
                          : 'Expiring ${DateFormat('dd MMM yyyy | h:mm a').format(event.date.toLocal())}',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: event.date.isBefore(DateTime.now()) ? Colors.red[900]! : Colors.orange[900]!,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey[600],
                        height: 1.3,
                      ),
                    ),
                    if (isHost && !event.isApproved)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                            const SizedBox(width: 6),
                            Text(
                              'Approval Pending',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHostDashboard() {
    if (_currentUserId == null) return const SizedBox.shrink();
    
    final futureEvents = EventLogic.filterHostEvents(_events, _currentUserId!, isPast: false)
        .where((e) => e.eventType != EventType.announcement)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
      
    final pastEvents = EventLogic.filterHostEvents(_events, _currentUserId!, isPast: true)
        .where((e) => e.eventType != EventType.announcement)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final now = DateTime.now();
    final activeAnnouncements = _events
        .where((e) => e.hostId == _currentUserId && e.eventType == EventType.announcement && e.date.isAfter(now))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final expiredAnnouncements = _events
        .where((e) => e.hostId == _currentUserId && e.eventType == EventType.announcement && e.date.isBefore(now))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          context,
          "I'm Hosting",
          action: '${futureEvents.length} ${futureEvents.length == 1 ? "Event" : "Events"}',
        ),
        const SizedBox(height: 8),
        if (futureEvents.isEmpty)
          Container(
            height: 120,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_note_outlined, color: Colors.grey[300], size: 40),
                  const SizedBox(height: 8),
                  Text('You are not hosting any upcoming events.', style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 240,
            child: ListView.builder(
              key: ValueKey('hosting_events_$_resetKey'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: futureEvents.length,
              itemBuilder: (context, index) {
                final event = futureEvents[index];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push<dynamic>(
                    MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)),
                  ).then((result) {
                    _loadEvents();
                    if (result is int) {
                      _onBottomNavTap(result);
                    }
                  }),
                  child: _buildModernEventCard(event, isHost: true),
                );
              },
            ),
          ),
        if (activeAnnouncements.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSectionHeader(
            context,
            "My Announcements",
            action: '${activeAnnouncements.length} ${activeAnnouncements.length == 1 ? "Announcement" : "Announcements"}',
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: ListView.builder(
              key: ValueKey('hosting_notices_$_resetKey'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: activeAnnouncements.length,
              itemBuilder: (context, index) {
                final announcement = activeAnnouncements[index];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push<dynamic>(
                    MaterialPageRoute(builder: (context) => EventDetailsScreen(event: announcement)),
                  ).then((result) {
                    _loadEvents();
                    if (result is int) {
                      _onBottomNavTap(result);
                    }
                  }),
                  child: _buildAnnouncementCard(announcement, isHost: true),
                );
              },
            ),
          ),
        ],
        if (expiredAnnouncements.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSectionHeader(
            context,
            "Expired Announcements",
            action: '${expiredAnnouncements.length} ${expiredAnnouncements.length == 1 ? "Announcement" : "Announcements"}',
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: ListView.builder(
              key: ValueKey('hosting_expired_notices_$_resetKey'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: expiredAnnouncements.length,
              itemBuilder: (context, index) {
                final announcement = expiredAnnouncements[index];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push<dynamic>(
                    MaterialPageRoute(builder: (context) => EventDetailsScreen(event: announcement)),
                  ).then((result) {
                    _loadEvents();
                    if (result is int) {
                      _onBottomNavTap(result);
                    }
                  }),
                  child: _buildAnnouncementCard(announcement, isHost: true),
                );
              },
            ),
          ),
        ],
        if (pastEvents.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSectionHeader(
            context,
            "I've Hosted",
            action: '${pastEvents.length} ${pastEvents.length == 1 ? "Event" : "Events"}',
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: pastEvents.length,
              itemBuilder: (context, index) {
                final event = pastEvents[index];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push<dynamic>(
                    MaterialPageRoute(builder: (context) => EventDetailsScreen(event: event)),
                  ).then((result) {
                    _loadData();
                    if (result is int) {
                      _onBottomNavTap(result);
                    }
                  }),
                  child: _buildModernEventCard(event, isHost: true, isPast: true),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSkeletonEventCard() {
    final theme = Theme.of(context);
    return Container(
      width: 250,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            ),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, color: theme.colorScheme.primary.withOpacity(0.1)),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 100,
                  height: 10,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)),
                ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, delay: 200.ms, color: theme.colorScheme.primary.withOpacity(0.1)),
                const SizedBox(height: 8),
                Container(
                  width: 180,
                  height: 16,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, delay: 400.ms, color: theme.colorScheme.primary.withOpacity(0.1)),
                const SizedBox(height: 8),
                Container(
                  width: 120,
                  height: 10,
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(5)),
                ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1500.ms, delay: 600.ms, color: theme.colorScheme.primary.withOpacity(0.1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.superUser: return Colors.purple;
      case UserRole.admin: return Colors.red;
      case UserRole.moderator: return Colors.blue;
      case UserRole.member: return Colors.green;
      case UserRole.blocked: return Colors.grey;
    }
  }

  Widget _buildPatronAvatar(String assetPath, String name, String designation) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 85,
          height: 85,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13.5),
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[100],
                  child: const Icon(
                    Icons.person,
                    color: Colors.grey,
                    size: 42,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 100,
          child: Text(
            name,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Colors.grey[850],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 100,
          child: Text(
            designation,
            style: GoogleFonts.inter(
              fontSize: 8.5,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
