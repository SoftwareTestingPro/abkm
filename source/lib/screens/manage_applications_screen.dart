import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/models.dart';
import 'public_profile_screen.dart';
import '../services/supabase_service.dart';
import '../services/event_logic.dart';
import '../widgets/bottom_nav.dart';

class ManageApplicationsScreen extends StatefulWidget {
  final ABKMEvent event;
  const ManageApplicationsScreen({super.key, required this.event});

  @override
  State<ManageApplicationsScreen> createState() => _ManageApplicationsScreenState();
}

class _ManageApplicationsScreenState extends State<ManageApplicationsScreen> {
  List<EventApplication> _applications = [];
  Map<String, ABKMUser> _applicantProfiles = {};
  bool _isLoading = true;
  UserRole _currentUserRole = UserRole.member;

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('abkm_user_id') ?? prefs.getString('abkm_mobileNumber') ?? 'anonymous';
      final currentUserProfile = await SupabaseService().getProfile(currentUserId);
      _currentUserRole = currentUserProfile?.userRole ?? UserRole.member;

      final results = await Future.wait([
        SupabaseService().getApplicationsForEvent(widget.event.id),
        SupabaseService().getProfiles(),
      ]);
      
      final cloudApps = results[0] as List<EventApplication>;
      final profiles = results[1] as List<ABKMUser>;
      final Map<String, ABKMUser> profileMap = {
        for (var p in profiles) p.id: p
      };

      if (mounted) {
        setState(() {
          _applications = cloudApps;
          _applicantProfiles = profileMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading applications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(EventApplication app, ApplicationStatus status) async {
    setState(() => _isLoading = true);
    try {
      await SupabaseService().updateApplicationStatus(app.id, status);
      await _loadApplications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Application ${status.name} successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error updating application: $e');
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: null,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _buildPageBackground(),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _applications.isEmpty
                  ? _buildEmptyState()
                  : _buildApplicationsList(theme),
        ],
      ),
      bottomNavigationBar: ABKMBottomNav(
        currentIndex: _currentUserRole == UserRole.member ? 0 : 1,
        userRole: _currentUserRole,
        onTap: (index) => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No member requests yet',
            style: GoogleFonts.inter(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationsList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _applications.length,
      itemBuilder: (context, index) {
        final app = _applications[index];
        final applicant = _applicantProfiles[app.applicantId];
        
        if (applicant == null) return const SizedBox.shrink();

        // Security check: Admins should not manage Super User profiles (though Super Users shouldn't be applying usually)
        if (_currentUserRole == UserRole.admin && applicant.userRole == UserRole.superUser) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(theme.colorScheme.primary.withOpacity(0.12), Colors.white),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () {
                  if (_currentUserRole == UserRole.member) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PublicProfileScreen(user: applicant),
                    ),
                  ).then((_) => _loadApplications());
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      backgroundImage: applicant.profileImageUrl != null
                          ? MemoryImage(base64Decode(applicant.profileImageUrl!))
                          : null,
                      child: applicant.profileImageUrl == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            applicant.name,
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            [
                              if (applicant.tehsil.isNotEmpty) applicant.tehsil,
                              if (applicant.district.isNotEmpty) applicant.district,
                              if (applicant.state.isNotEmpty) applicant.state,
                            ].join(', '),
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusBadge(app),
                  ],
                ),
              ),
              if (app.message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '"${app.message}"',
                    style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey[700]),
                  ),
                ),
              ],
              if (app.status == ApplicationStatus.pending) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _updateStatus(app, ApplicationStatus.declined),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _updateStatus(app, ApplicationStatus.approved),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(EventApplication app) {
    Color color;
    String label;
    
    switch (app.status) {
      case ApplicationStatus.approved:
        color = Colors.green;
        label = 'Approved';
        break;
      case ApplicationStatus.declined:
        color = Colors.red;
        label = 'Declined';
        break;
      case ApplicationStatus.withdrawn:
        color = Colors.grey;
        label = 'Withdrawn';
        break;
      default:
        color = Colors.orange;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
