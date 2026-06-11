import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';

class ABKMBottomNav extends StatelessWidget {
  final int currentIndex;
  final UserRole userRole;
  final Function(int) onTap;
  final int unreadActivityCount;

  const ABKMBottomNav({
    super.key,
    required this.currentIndex,
    required this.userRole,
    required this.onTap,
    this.unreadActivityCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: _getActiveColor(context, currentIndex),
        unselectedItemColor: Colors.grey[400],
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 10),
        items: _buildNavItems(),
      ),
    );
  }

  Color _getActiveColor(BuildContext context, int index) {
    final theme = Theme.of(context);
    // Dynamic colors based on tab purpose
    if (userRole == UserRole.member) {
      switch (index) {
        case 0: return const Color(0xFF1E88E5); // Discover - Blue
        case 1: return const Color(0xFFF4511E); // Activity - Deep Orange
        case 2: return const Color(0xFF6A1B9A); // Profile - Purple
        default: return theme.colorScheme.primary; // Default Orange
      }
    } else if (userRole == UserRole.moderator) {
      switch (index) {
        case 0: return const Color(0xFF00897B); // Host - Teal
        case 1: return const Color(0xFF1E88E5); // Discover - Blue
        case 2: return const Color(0xFF8B0000); // Create - Red
        case 3: return const Color(0xFFF4511E); // Activity - Deep Orange
        case 4: return const Color(0xFF6A1B9A); // Profile - Purple
        default: return theme.colorScheme.primary; // Default Orange
      }
    } else {
      switch (index) {
        case 0: return const Color(0xFF00897B); // Host - Teal
        case 1: return const Color(0xFF1E88E5); // Discover - Blue
        case 2: return const Color(0xFF8B0000); // Create - Red
        case 3: return const Color(0xFF4527A0); // Manage - Deep Purple
        case 4: return const Color(0xFFF4511E); // Activity - Deep Orange
        case 5: return const Color(0xFF6A1B9A); // Profile - Purple
        default: return theme.colorScheme.primary; // Default Orange
      }
    }
  }

  List<BottomNavigationBarItem> _buildNavItems() {
    if (userRole == UserRole.member) {
      return [
        BottomNavigationBarItem(
          icon: const Icon(Icons.explore_outlined, color: Color(0xFF1E88E5)), 
          activeIcon: const Icon(Icons.explore), 
          label: 'Discover'
        ),
        BottomNavigationBarItem(
          icon: _buildActivityIcon(color: const Color(0xFFF4511E)),
          activeIcon: const Icon(Icons.notifications),
          label: 'Activity',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.person_outline, color: Color(0xFF6A1B9A)), 
          activeIcon: const Icon(Icons.person), 
          label: 'Profile'
        ),
      ];
    } else if (userRole == UserRole.moderator) {
      return [
        BottomNavigationBarItem(
          icon: const Icon(Icons.dashboard_outlined, color: Color(0xFF00897B)), 
          activeIcon: const Icon(Icons.dashboard), 
          label: 'Host'
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.explore_outlined, color: Color(0xFF1E88E5)), 
          activeIcon: const Icon(Icons.explore), 
          label: 'Discover'
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.add_circle_outline, color: Color(0xFFE91E63)),
          activeIcon: const Icon(Icons.add_circle),
          label: 'Create',
        ),
        BottomNavigationBarItem(
          icon: _buildActivityIcon(color: const Color(0xFFF4511E)),
          activeIcon: const Icon(Icons.notifications),
          label: 'Activity',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.person_outline, color: Color(0xFF6A1B9A)), 
          activeIcon: const Icon(Icons.person), 
          label: 'Profile'
        ),
      ];
    } else {
      // Admin and Super User
      return [
        BottomNavigationBarItem(
          icon: const Icon(Icons.dashboard_outlined, color: Color(0xFF00897B)), 
          activeIcon: const Icon(Icons.dashboard), 
          label: 'Host'
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.explore_outlined, color: Color(0xFF1E88E5)), 
          activeIcon: const Icon(Icons.explore), 
          label: 'Discover'
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.add_circle_outline, color: Color(0xFFE91E63)),
          activeIcon: const Icon(Icons.add_circle),
          label: 'Create',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF4527A0)), 
          activeIcon: const Icon(Icons.admin_panel_settings), 
          label: 'Manage'
        ),
        BottomNavigationBarItem(
          icon: _buildActivityIcon(color: const Color(0xFFF4511E)),
          activeIcon: const Icon(Icons.notifications),
          label: 'Activity',
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.person_outline, color: Color(0xFF6A1B9A)), 
          activeIcon: const Icon(Icons.person), 
          label: 'Profile'
        ),
      ];
    }
  }

  Widget _buildActivityIcon({Color? color}) {
    return Stack(
      children: [
        Icon(Icons.notifications_outlined, color: color),
        if (unreadActivityCount > 0)
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
                '$unreadActivityCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
