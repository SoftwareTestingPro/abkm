import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'add_event_screen.dart';
import 'manage_applications_screen.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/event_logic.dart';
import '../services/logic_service.dart';
import 'public_profile_screen.dart';
import '../widgets/bottom_nav.dart';

class EventDetailsScreen extends StatefulWidget {
  final ABKMEvent event;
  const EventDetailsScreen({super.key, required this.event});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  late ABKMEvent _currentEvent;
  List<EventApplication> _myApplications = [];
  ABKMUser? _currentUser;
  ABKMUser? _hostUser;
  bool _isLoading = true;
  List<EventApplication> _allApplications = [];
  Map<String, ABKMUser> _applicantProfiles = {};
  UserRole _currentUserRole = UserRole.member;
  
  bool get isHost => _currentUser?.id == _currentEvent.hostId;
  bool get isPast => EventLogic.isEventPast(_currentEvent);

  @override
  void initState() {
    super.initState();
    _currentEvent = widget.event;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('abkm_user_id') ?? prefs.getString('abkm_mobileNumber') ?? 'anonymous';
      
      final results = await Future.wait([
        SupabaseService().getProfile(userId),
        SupabaseService().getProfile(_currentEvent.hostId),
        SupabaseService().getApplicationsForUserForEvent(_currentEvent.id, userId),
        SupabaseService().getEventById(_currentEvent.id),
      ]);
      
      final profile = results[0] as ABKMUser?;
      final hostProfile = results[1] as ABKMUser?;
      final applications = results[2] as List<EventApplication>;
      final updatedEvent = results[3] as ABKMEvent?;
      
      if (mounted) {
        setState(() {
          _currentUser = profile;
          _hostUser = hostProfile;
          _myApplications = applications;
          if (updatedEvent != null) {
            _currentEvent = updatedEvent;
          }
          if (profile != null) {
            _currentUserRole = profile.userRole;
          }
        });
        
        final attendees = _currentEvent.approvedMemberIds;
        List<ABKMUser> profilesResults = [];
        if (attendees.isNotEmpty) {
           profilesResults = await SupabaseService().getProfilesByIds(attendees);
        }
        final Map<String, ABKMUser> profileMap = {for (var p in profilesResults) p.id: p};
        
        List<EventApplication> allApps = [];
        if (userId == _currentEvent.hostId) {
          allApps = await SupabaseService().getApplicationsForEvent(_currentEvent.id);
          // Also fetch profiles for applicants
          final applicantIds = allApps.map((a) => a.applicantId).toList();
          if (applicantIds.isNotEmpty) {
            final applicantProfiles = await SupabaseService().getProfilesByIds(applicantIds);
            for (var p in applicantProfiles) {
              profileMap[p.id] = p;
            }
          }
        }
        
        if (mounted) {
          setState(() {
            _allApplications = allApps;
            _applicantProfiles = profileMap;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading event details: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // _joinEvent is no longer needed as we use _toggleAttendance for direct joining.

  Future<void> _respondToInvitation(EventApplication app, bool accept) async {
    setState(() => _isLoading = true);
    await SupabaseService().respondToInvitation(app.id, accept, _currentEvent.id, app.applicantId);
    await _loadData();
  }

  Future<void> _withdrawApplication(EventApplication app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw Request'),
        content: const Text('Are you sure you want to withdraw your request to join this event?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      await SupabaseService().cancelApplication(app.id, _currentEvent.id, app.applicantId);
      await _loadData();
    }
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
    final activeApp = _myApplications.where((app) => 
      app.status == ApplicationStatus.pending || 
      app.status == ApplicationStatus.approved || 
      app.status == ApplicationStatus.invitationPending || 
      app.status == ApplicationStatus.invitationAccepted
    ).firstOrNull;

    if (_currentEvent.eventType == EventType.announcement) {
      final now = DateTime.now();
      final isExpired = _currentEvent.date.isBefore(now);
      
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.orange[800]),
        ),
        body: Stack(
          children: [
            _buildPageBackground(),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Premium Announcement Container
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.orange[200]!, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.1),
                            blurRadius: 30,
                            spreadRadius: 2,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Banner with campaign/announcement icon
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                            decoration: BoxDecoration(
                              color: Colors.orange[50]!,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.orange.withOpacity(0.4),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.campaign, color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'OFFICIAL ANNOUNCEMENT',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange[900]!,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Expiring ${DateFormat('dd MMM yyyy | hh:mm a').format(_currentEvent.date.toLocal())}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange[800]!,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Announcement Body
                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentEvent.title,
                                  style: GoogleFonts.poppins(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  height: 2,
                                  color: Colors.grey[200]!,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  _currentEvent.description,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: Colors.grey[850]!,
                                    height: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                // Expired Badge/Banner if past
                                if (isExpired)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50]!,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.red[100]!),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.lock_clock_outlined, color: Colors.red[700]!, size: 20),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'This announcement has expired and is no longer active.',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.red[800]!,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50]!,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.blue[100]!),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline, color: Colors.blue[700]!, size: 20),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'This announcement is active and visible to all community members.',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blue[800]!,
                                            ),
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
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    color: Colors.white.withOpacity(0.4),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: ABKMBottomNav(
          currentIndex: _currentUser?.userRole == UserRole.member ? 0 : 1,
          userRole: _currentUser?.userRole ?? UserRole.member,
          onTap: (index) {
            Navigator.of(context).pop(index);
          },
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
      ),
      body: Stack(
        children: [
          _buildPageBackground(),
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 100, left: 24.0, right: 24.0, bottom: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEventHeader(),
                const SizedBox(height: 24),
                
                if (_currentEvent.eventType != EventType.announcement && !isHost) ...[
                  _buildAttendanceSection(),
                ],

                if (_currentEvent.eventType != EventType.announcement && (isHost || _currentUserRole == UserRole.admin || _currentUserRole == UserRole.superUser)) ...[
                  const SizedBox(height: 32),
                  _buildSectionTitle('People Attending'),
                  const SizedBox(height: 12),
                  _buildAttendeesList(),
                ],
                const SizedBox(height: 100),
              ],
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(
                  color: Colors.white.withOpacity(0.4),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ABKMBottomNav(
        currentIndex: _currentUser?.userRole == UserRole.member ? 0 : 1,
        userRole: _currentUser?.userRole ?? UserRole.member,
        onTap: (index) {
          Navigator.of(context).pop(index);
        },
      ),
    );
  }

  Widget _buildAttendanceSection() {
    if (_currentUser == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    
    final isPast = EventLogic.isEventPast(_currentEvent);
    final isAttending = _currentEvent.approvedMemberIds.contains(_currentUser!.id);
    
    if (isPast) {
      return Center(
        child: Text(
          isAttending ? 'You attended this event' : 'Event has ended',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _toggleAttendance,
              style: ElevatedButton.styleFrom(
                backgroundColor: isAttending ? Colors.green[50] : theme.colorScheme.primary,
                foregroundColor: isAttending ? Colors.green[700] : Colors.white,
                elevation: isAttending ? 0 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isAttending ? BorderSide(color: Colors.green[200]!) : BorderSide.none,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isAttending) ...[
                    const Icon(Icons.check_circle, size: 20),
                    const SizedBox(width: 8),
                    Text('Cancel Attendance', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                  ] else ...[
                    const Icon(Icons.touch_app, size: 20),
                    const SizedBox(width: 8),
                    Text('I will Attend', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
          ),
          if (isAttending) 
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'You are on the guest list!',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleAttendance() async {
    setState(() => _isLoading = true);
    try {
      final isAttending = _currentEvent.approvedMemberIds.contains(_currentUser!.id);
      if (isAttending) {
        await SupabaseService().removeAttendee(_currentEvent.id, _currentUser!.id);
      } else {
        await SupabaseService().addAttendee(_currentEvent.id, _currentUser!.id);
      }
      
      // Update local state to reflect change immediately
      final updatedEvent = await SupabaseService().getEventById(_currentEvent.id, forceRefresh: true);
      if (updatedEvent != null) {
        setState(() {
          _currentEvent = updatedEvent;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildEventHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentEvent.imageUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: _currentEvent.imageUrl.startsWith('http')
                ? Image.network(_currentEvent.imageUrl, height: 200, width: double.infinity, fit: BoxFit.cover)
                : (_currentEvent.imageUrl.startsWith('/9j/')
                    ? Image.memory(base64Decode(_currentEvent.imageUrl), height: 200, width: double.infinity, fit: BoxFit.cover)
                    : Image.asset(_currentEvent.imageUrl, height: 200, width: double.infinity, fit: BoxFit.cover)),
          ),
          const SizedBox(height: 20),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _eventTypeBadge(_currentEvent.eventType),
            Text(
              EventLogic.formatDateTime(_currentEvent.date),
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _currentEvent.title,
          style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        if (_currentEvent.eventType != EventType.announcement) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.location_on, size: 18, color: Colors.redAccent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  [
                    if (_currentEvent.meetingPoint != null && _currentEvent.meetingPoint!.isNotEmpty) _currentEvent.meetingPoint,
                    if (_currentEvent.village.isNotEmpty) _currentEvent.village,
                    if (_currentEvent.tehsil.isNotEmpty) _currentEvent.tehsil,
                    if (_currentEvent.district.isNotEmpty) _currentEvent.district,
                    _currentEvent.state,
                  ].join(', '),
                  style: GoogleFonts.inter(fontSize: 16, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          if (_currentEvent.meetingPoint != null && _currentEvent.meetingPoint!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.pin_drop, size: 18, color: Colors.blueAccent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Meeting Point: ${_currentEvent.meetingPoint}',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.blue[800]),
                  ),
                ),
              ],
            ),
          ],
        ],
        if (_currentEvent.description.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildSectionTitle('Description'),
          const SizedBox(height: 12),
          Text(
            _currentEvent.description,
            style: GoogleFonts.inter(fontSize: 15, color: Colors.black87, height: 1.5),
          ),
        ],
        if (_currentEvent.eventType != EventType.announcement && _hostUser != null) ...[
          const SizedBox(height: 24),
          _buildSectionTitle('Hosted by'),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                backgroundImage: _hostUser!.profileImageUrl != null && _hostUser!.profileImageUrl!.startsWith('http')
                    ? NetworkImage(_hostUser!.profileImageUrl!) as ImageProvider
                    : (_hostUser!.profileImageUrl != null
                        ? MemoryImage(base64Decode(_hostUser!.profileImageUrl!))
                        : null),
                child: _hostUser!.profileImageUrl == null
                    ? Icon(Icons.person, color: Theme.of(context).colorScheme.primary)
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hostUser!.name,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    _hostUser!.village.isNotEmpty && _hostUser!.village != 'Village' ? _hostUser!.village : 'Location not set',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildAttendeesList() {
    final attendees = _currentEvent.approvedMemberIds;
    final theme = Theme.of(context);
    
    if (attendees.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text('No one attending yet.', style: GoogleFonts.inter(color: Colors.grey))),
      );
    }

    return Column(
      children: attendees.map((uid) {
        final profile = _applicantProfiles[uid];
        return InkWell(
          onTap: () {
            if (profile != null) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PublicProfileScreen(user: profile)),
              );
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  backgroundImage: profile?.profileImageUrl != null && profile!.profileImageUrl!.startsWith('http')
                      ? NetworkImage(profile.profileImageUrl!) as ImageProvider
                      : (profile?.profileImageUrl != null ? MemoryImage(base64Decode(profile!.profileImageUrl!)) : null),
                  child: profile?.profileImageUrl == null ? Icon(Icons.person, size: 20, color: theme.colorScheme.primary) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile?.name ?? 'Anonymous Member', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(profile?.village ?? 'Location hidden', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                if (isHost && uid != _currentUser?.id && !isPast)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Remove Attendee'),
                          content: Text('Are you sure you want to remove ${profile?.name ?? 'this member'} from the event?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        setState(() => _isLoading = true);
                        await SupabaseService().removeAttendee(_currentEvent.id, uid);
                        await _loadData();
                      }
                    },
                  )
                else
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _eventTypeBadge(EventType type) {
    Color color;
    switch (type) {
      case EventType.meeting: color = Colors.indigo; break;
      case EventType.rally: color = Colors.orange; break;
      case EventType.andolan: color = Colors.red; break;
      case EventType.dharna: color = Colors.amber; break;
      case EventType.conference: color = Colors.blue; break;
      case EventType.protest: color = Colors.deepOrange; break;
      case EventType.announcement: color = Colors.deepPurple; break;
      default: color = Colors.blueGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(
        type.name.replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}').toUpperCase(),
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
