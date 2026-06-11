import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'profile_screen.dart';
import '../widgets/bottom_nav.dart';

class PublicProfileScreen extends StatefulWidget {
  final ABKMUser user;

  const PublicProfileScreen({super.key, required this.user});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  UserRole _loggedInUserRole = UserRole.member;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final roleIndex = prefs.getInt('abkm_user_role') ?? 0;
    if (mounted) {
      setState(() {
        _loggedInUserRole = UserRole.values[roleIndex];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: ProfileScreen(
        isEditMode: true,
        user: widget.user,
        isTabMode: true,
        onTabSwitchRequested: (index) {
          Navigator.pop(context, index);
        },
      ),
      bottomNavigationBar: ABKMBottomNav(
        currentIndex: 0,
        userRole: _loggedInUserRole,
        onTap: (index) {
          Navigator.pop(context, index);
        },
      ),
    );
  }
}
