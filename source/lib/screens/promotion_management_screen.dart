import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/event_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'public_profile_screen.dart';

class PromotionManagementScreen extends StatefulWidget {
  const PromotionManagementScreen({super.key});

  @override
  State<PromotionManagementScreen> createState() => _PromotionManagementScreenState();
}

class _PromotionManagementScreenState extends State<PromotionManagementScreen> {
  bool _isLoading = true;
  List<ABKMEvent> _pendingEvents = [];
  Map<String, ABKMUser> _profiles = {};
  UserRole _currentUserRole = UserRole.member;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadPendingEvents();
  }

  Future<void> _loadPendingEvents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('abkm_user_id') ?? prefs.getString('abkm_mobileNumber');
      final roleIndex = prefs.getInt('abkm_user_role') ?? 0;
      _currentUserRole = UserRole.values[roleIndex];

      final adminProfile = await SupabaseService().getProfile(_currentUserId!, forceRefresh: false);
      
      final List<ABKMEvent> pendingEvents;
      if (adminProfile != null && adminProfile.userRole != UserRole.superUser && adminProfile.position != 'National President') {
        pendingEvents = await SupabaseService().getPendingEvents(state: adminProfile.state.isNotEmpty ? adminProfile.state : null);
      } else {
        pendingEvents = await SupabaseService().getPendingEvents();
      }
      
      final profileIds = pendingEvents.map((e) => e.hostId).toSet().toList();
      final profilesList = await SupabaseService().getProfilesByIds(profileIds);
      final profileMap = {for (var p in profilesList) p.id: p};

      if (mounted) {
        setState(() {
          _pendingEvents = pendingEvents;
          _profiles = profileMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading pending events: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleEventAction(String eventId, bool approved) async {
    if (_currentUserId == null) return;
    setState(() => _isLoading = true);
    try {
      if (approved) {
        await SupabaseService().approveEvent(eventId, _currentUserId!);
      } else {
        await SupabaseService().declineEvent(eventId, _currentUserId!);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved ? 'Event approved!' : 'Event declined.'),
            backgroundColor: approved ? Colors.green : Colors.red,
          ),
        );
      }
      _loadPendingEvents();
    } catch (e) {
      debugPrint('Error handling event action: $e');
      if (mounted) setState(() => _isLoading = false);
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _buildPageBackground(),
          Column(
            children: [
              const SizedBox(height: 20),
              const SizedBox(height: 20),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading && _pendingEvents.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _pendingEvents.isEmpty 
                        ? _buildEmptyState('No pending events') 
                        : _buildEventsList(theme),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.inter(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'All community events have been reviewed.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadPendingEvents,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _pendingEvents.length,
        itemBuilder: (context, index) {
          final event = _pendingEvents[index];
          final host = _profiles[event.hostId];

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.12), Colors.white),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      backgroundImage: host?.profileImageUrl != null
                          ? (host!.profileImageUrl!.startsWith('http') 
                              ? NetworkImage(host.profileImageUrl!) as ImageProvider
                              : MemoryImage(base64Decode(host.profileImageUrl!)))
                          : null,
                      child: host?.profileImageUrl == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(event.title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () {
                              if (host != null) {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => PublicProfileScreen(user: host)));
                              }
                            },
                            child: Text(
                              'Moderator: ${host?.name ?? 'Unknown'}', 
                              style: GoogleFonts.inter(
                                fontSize: 12, 
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              )
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Event Details:',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  '${EventLogic.formatDate(event.date)} at ${event.meetingPoint != null && event.meetingPoint!.isNotEmpty ? "${event.meetingPoint}, " : ""}${event.village.isNotEmpty ? "${event.village}, " : ""}${event.tehsil.isNotEmpty ? "${event.tehsil}, " : ""}${event.district.isNotEmpty ? "${event.district}, " : ""}${event.state}',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _handleEventAction(event.id, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _handleEventAction(event.id, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
