import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/reputation_badge.dart';
import 'package:marquee/marquee.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import 'public_profile_screen.dart';
import '../services/logic_service.dart';

class MemberDirectoryScreen extends StatefulWidget {
  const MemberDirectoryScreen({super.key});

  @override
  State<MemberDirectoryScreen> createState() => _MemberDirectoryScreenState();
}

class _MemberDirectoryScreenState extends State<MemberDirectoryScreen> {
  UserRole _loggedInUserRole = UserRole.member;
  List<ABKMUser> _allUsers = [];
  List<ABKMUser> _filteredUsers = [];
  bool _isLoading = true;
  bool _isStateRestricted = false;
  String _restrictedState = '';

  // Filter states
  final Map<String, Set<String>> _selectedFilters = {
    'State': {},
    'District': {},
    'Tehsil': {},
    'Village': {},
    'Sector': {},
    'Profession': {},
    'Education': {},
    'Position': {},
    'Role': {},
    'Gender': {},
    'Marital Status': {},
  };

  int? _minAge;
  int? _maxAge;
  final TextEditingController _minAgeController = TextEditingController();
  final TextEditingController _maxAgeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  final Map<String, List<String>> _filterOptions = {
    'State': [],
    'District': [],
    'Tehsil': [],
    'Village': [],
    'Sector': [],
    'Profession': [],
    'Education': [],
    'Position': [],
    'Role': [],
    'Gender': [],
    'Marital Status': [],
  };

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minAgeController.dispose();
    _maxAgeController.dispose();
    super.dispose();
  }

  int _getPositionPriority(String? position) {
    if (position == null || position.isEmpty) return 0;
    
    final pos = position.trim();
    
    int levelWeight = 0;
    String remaining = pos;
    if (pos.startsWith('National ')) {
      levelWeight = 500;
      remaining = pos.substring('National '.length);
    } else if (pos.startsWith('State ')) {
      levelWeight = 400;
      remaining = pos.substring('State '.length);
    } else if (pos.startsWith('District ')) {
      levelWeight = 300;
      remaining = pos.substring('District '.length);
    } else if (pos.startsWith('City/Tehsil/Block ')) {
      levelWeight = 200;
      remaining = pos.substring('City/Tehsil/Block '.length);
    } else if (pos.startsWith('Village/Unit ')) {
      levelWeight = 100;
      remaining = pos.substring('Village/Unit '.length);
    }
    
    int titleWeight = 0;
    final title = remaining.trim().toLowerCase();
    
    if (title.contains('patron')) {
      titleWeight = 90;
    } else if (title == 'president') {
      titleWeight = 80;
    } else if (title.contains('working president')) {
      titleWeight = 75;
    } else if (title.contains('vice president')) {
      titleWeight = 70;
    } else if (title.contains('general secretary')) {
      titleWeight = 60;
    } else if (title == 'secretary') {
      titleWeight = 55;
    } else if (title.contains('joint secretary')) {
      titleWeight = 50;
    } else if (title.contains('office secretary')) {
      titleWeight = 45;
    } else if (title.contains('treasurer')) {
      titleWeight = 40;
    } else if (title.contains('joint treasurer')) {
      titleWeight = 35;
    } else if (title.contains('auditor')) {
      titleWeight = 30;
    } else if (title.contains('legal advisor')) {
      titleWeight = 25;
    } else if (title.contains('spokesperson')) {
      titleWeight = 20;
    } else if (title.contains('media in-charge')) {
      titleWeight = 18;
    } else if (title.contains('it & social media coordinator')) {
      titleWeight = 16;
    } else if (title.contains('public relations officer') || title.contains('pro')) {
      titleWeight = 14;
    } else if (title.contains('in-charge')) {
      titleWeight = 12;
    } else if (title.contains('organization secretary')) {
      titleWeight = 10;
    } else if (title.contains('coordinator')) {
      titleWeight = 8;
    } else if (title.contains('wing president') || title.contains('cell head')) {
      titleWeight = 6;
    } else if (title.contains('executive member')) {
      titleWeight = 4;
    } else if (title.contains('active member')) {
      titleWeight = 3;
    } else if (title.contains('primary member')) {
      titleWeight = 2;
    } else if (title.contains('member')) {
      titleWeight = 1;
    }
    
    return levelWeight + titleWeight;
  }

  int _compareUsers(ABKMUser a, ABKMUser b) {
    final priorityA = _getPositionPriority(a.position);
    final priorityB = _getPositionPriority(b.position);
    
    if (priorityA != priorityB) {
      return priorityB.compareTo(priorityA); // Descending priority
    }
    
    return b.points.compareTo(a.points); // Descending points
  }

  Future<void> _loadUsers() async {
    // existing code remains
    try {
      final prefs = await SharedPreferences.getInstance();
    final roleIndex = prefs.getInt('abkm_user_role') ?? 0;
    if (mounted) {
      setState(() {
        _loggedInUserRole = UserRole.values[roleIndex];
      });
    }
      final String? loggedInUserId = prefs.getString('abkm_user_id') ?? prefs.getString('abkm_mobileNumber');
      
      List<ABKMUser> users = [];
      bool restricted = false;
      String stateFilter = '';
      
      if (loggedInUserId != null) {
        final profile = await SupabaseService().getProfile(loggedInUserId);
        if (profile != null && 
            profile.userRole != UserRole.superUser && 
            profile.position != 'National President' && 
            profile.state.isNotEmpty) {
          restricted = true;
          stateFilter = profile.state;
        }
      }
      
      if (restricted) {
        users = await SupabaseService().getProfiles(state: stateFilter);
      } else {
        users = await SupabaseService().getProfiles();
      }
      
      if (mounted) {
        setState(() {
          _isStateRestricted = restricted;
          _restrictedState = stateFilter;
          _allUsers = users.toList();
          _allUsers.sort(_compareUsers);
          _filteredUsers = _allUsers;
          _extractFilterOptions();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading directory: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _extractFilterOptions() {
    _filterOptions['State'] = _allUsers.map((u) => u.state).where((s) => s.isNotEmpty).toSet().toList()..sort();
    _filterOptions['District'] = _allUsers.map((u) => u.district).where((s) => s.isNotEmpty).toSet().toList()..sort();
    _filterOptions['Tehsil'] = _allUsers.map((u) => u.tehsil).where((s) => s.isNotEmpty).toSet().toList()..sort();
    _filterOptions['Village'] = _allUsers.map((u) => u.village).where((s) => s.isNotEmpty).toSet().toList()..sort();
    _filterOptions['Sector'] = _allUsers.map((u) => u.sector).where((s) => s.isNotEmpty).toSet().toList()..sort();
    _filterOptions['Profession'] = _allUsers.map((u) => u.profession).where((s) => s.isNotEmpty).toSet().toList()..sort();
    _filterOptions['Education'] = _allUsers.map((u) => u.education).where((s) => s.isNotEmpty).toSet().toList()..sort();
    _filterOptions['Position'] = _allUsers.map((u) => u.position).where((s) => s.isNotEmpty).toSet().toList()..sort();
    _filterOptions['Role'] = UserRole.values.where((r) => r != UserRole.superUser).map((r) => r.name).toList();
    _filterOptions['Gender'] = ['Male', 'Female', 'Other'];
    _filterOptions['Marital Status'] = ['Married', 'Unmarried'];
  }

  void _applyFilters() {
    setState(() {
      _filteredUsers = _allUsers.where((u) {
        final matchesState = _selectedFilters['State']!.isEmpty || _selectedFilters['State']!.contains(u.state);
        final matchesDistrict = _selectedFilters['District']!.isEmpty || _selectedFilters['District']!.contains(u.district);
        final matchesTehsil = _selectedFilters['Tehsil']!.isEmpty || _selectedFilters['Tehsil']!.contains(u.tehsil);
        final matchesVillage = _selectedFilters['Village']!.isEmpty || _selectedFilters['Village']!.contains(u.village);
        final matchesSector = _selectedFilters['Sector']!.isEmpty || _selectedFilters['Sector']!.contains(u.sector);
        final matchesProfession = _selectedFilters['Profession']!.isEmpty || _selectedFilters['Profession']!.contains(u.profession);
        final matchesEducation = _selectedFilters['Education']!.isEmpty || _selectedFilters['Education']!.contains(u.education);
        final matchesPosition = _selectedFilters['Position']!.isEmpty || _selectedFilters['Position']!.contains(u.position);
        final matchesRole = _selectedFilters['Role']!.isEmpty || _selectedFilters['Role']!.contains(u.userRole.name);
        final matchesGender = _selectedFilters['Gender']!.isEmpty || _selectedFilters['Gender']!.contains(u.gender);
        final matchesMaritalStatus = _selectedFilters['Marital Status']!.isEmpty || _selectedFilters['Marital Status']!.contains(u.maritalStatus);
        
        bool matchesSearch = true;
        if (_searchController.text.isNotEmpty) {
          final query = _searchController.text.toLowerCase();
          matchesSearch = u.name.toLowerCase().contains(query) || 
                         u.id.toLowerCase().contains(query) || 
                         u.district.toLowerCase().contains(query) ||
                         u.tehsil.toLowerCase().contains(query) ||
                         u.village.toLowerCase().contains(query) ||
                         u.profession.toLowerCase().contains(query);
        }

        bool matchesAge = true;
        if (_minAge != null && u.age < _minAge!) matchesAge = false;
        if (_maxAge != null && u.age > _maxAge!) matchesAge = false;

        return matchesState && matchesDistrict && matchesTehsil && matchesVillage && matchesSector && matchesProfession && matchesEducation && matchesPosition && matchesRole && matchesGender && matchesAge && matchesMaritalStatus && matchesSearch;
      }).toList();
      _filteredUsers.sort(_compareUsers);
    });
  }

  Future<void> _exportToExcel() async {
    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];

    // Headers
    sheet.getRangeByIndex(1, 1).setText('Name');
    sheet.getRangeByIndex(1, 2).setText('Mobile/ID');
    sheet.getRangeByIndex(1, 3).setText('Role');
    sheet.getRangeByIndex(1, 4).setText('Position');
    sheet.getRangeByIndex(1, 5).setText('State');
    sheet.getRangeByIndex(1, 6).setText('District');
    sheet.getRangeByIndex(1, 7).setText('Tehsil');
    sheet.getRangeByIndex(1, 8).setText('Village');
    sheet.getRangeByIndex(1, 9).setText('Sector');
    sheet.getRangeByIndex(1, 10).setText('Profession');
    sheet.getRangeByIndex(1, 11).setText('Gender');
    sheet.getRangeByIndex(1, 12).setText('Age');
    sheet.getRangeByIndex(1, 13).setText('Marital Status');
    sheet.getRangeByIndex(1, 14).setText('Date of Birth');


    // Data
    for (int i = 0; i < _filteredUsers.length; i++) {
      final user = _filteredUsers[i];
      final row = i + 2;
      sheet.getRangeByIndex(row, 1).setText(user.name);
      sheet.getRangeByIndex(row, 2).setText(user.id);
      sheet.getRangeByIndex(row, 3).setText(user.userRole.name);
      sheet.getRangeByIndex(row, 4).setText(user.position);
      sheet.getRangeByIndex(row, 5).setText(user.state);
      sheet.getRangeByIndex(row, 6).setText(user.district);
      sheet.getRangeByIndex(row, 7).setText(user.tehsil);
      sheet.getRangeByIndex(row, 8).setText(user.village);
      sheet.getRangeByIndex(row, 9).setText(user.sector);
      sheet.getRangeByIndex(row, 10).setText(user.profession);
      sheet.getRangeByIndex(row, 11).setText(user.gender);
      sheet.getRangeByIndex(row, 12).setNumber(user.age.toDouble());
      sheet.getRangeByIndex(row, 13).setText(user.maritalStatus ?? '');
      sheet.getRangeByIndex(row, 14).setText(user.dob != null ? DateFormat('dd/MM/yyyy').format(user.dob!) : '');
    }

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    final String timestamp = DateFormat('ddMMyyyy_HHmmss').format(DateTime.now());
    final String fileName = 'ABKM_$timestamp.xlsx';

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: Uint8List.fromList(bytes),
      mimeType: MimeType.microsoftExcel,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${_filteredUsers.length} members to Excel')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // existing appBar configuration
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _isStateRestricted && _restrictedState.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Member Directory',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    _restrictedState,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              )
            : Text(
                'Member Directory',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.green),
            onPressed: _filteredUsers.isEmpty ? null : _exportToExcel,
            tooltip: 'Export to Excel',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDrawer(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/app_background.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [

                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total: ${_filteredUsers.length} members',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.grey[700]),
                            ),
                            if (_selectedFilters.values.any((s) => s.isNotEmpty))
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    for (var key in _selectedFilters.keys) {
                                      _selectedFilters[key]!.clear();
                                    }
                                    _minAge = null;
                                    _maxAge = null;
                                    _minAgeController.clear();
                                    _maxAgeController.clear();
                                    _applyFilters();
                                  });
                                },
                                child: const Text('Clear Filters', style: TextStyle(color: Colors.red)),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = _filteredUsers[index];
                            return _buildUserCard(user);
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
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

  Widget _buildUserCard(ABKMUser user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.04), // Subtle theme tint
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => PublicProfileScreen(user: user)));
            _loadUsers();
            if (result is int && mounted) {
              Navigator.pop(context, result);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    user.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _buildReputationIndicator(user.points),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            user.id,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      if (user.position.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  FormatUtils.formatDesignation(user),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '${user.district}${user.state.isNotEmpty ? ", ${user.state}" : ""}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReputationIndicator(int points) {
    return ReputationBadge(points: points, size: 20);
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.superUser: return Colors.purple;
      case UserRole.admin: return Colors.red;
      case UserRole.moderator: return Colors.orange;
      case UserRole.blocked: return Colors.grey;
      default: return Colors.blue;
    }
  }

  void _showFilterDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.94,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Advanced Filters',
                          style: GoogleFonts.poppins(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  
                  // Scrollable Content
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      children: [
                        _buildAgeRangeInputs(setModalState),
                        const SizedBox(height: 16),
                        ..._selectedFilters.keys.where((c) => !_isStateRestricted || c != 'State').map((category) {
                          return _buildFilterCategory(category, setModalState);
                        }).toList(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                  
                  // Footer Actions
                  Container(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: OutlinedButton(
                            onPressed: () {
                              setModalState(() {
                                for (var key in _selectedFilters.keys) {
                                  _selectedFilters[key]!.clear();
                                }
                                _minAge = null;
                                _maxAge = null;
                                _minAgeController.clear();
                                _maxAgeController.clear();
                                _applyFilters();
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              side: BorderSide(color: Colors.grey[300]!),
                            ),
                            child: Text('Reset', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.grey[600])),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: Text(
                              'Show ${_filteredUsers.length} Results',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildAgeRangeInputs(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text('Age Range', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.blue[800])),
        ),
        Row(
          children: [
            SizedBox(
              width: 100,
              child: TextField(
                controller: _minAgeController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Min',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) {
                  setState(() {
                    _minAge = int.tryParse(val);
                    _applyFilters();
                  });
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('to', style: TextStyle(color: Colors.grey)),
            ),
            SizedBox(
              width: 100,
              child: TextField(
                controller: _maxAgeController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Max',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (val) {
                  setState(() {
                    _maxAge = int.tryParse(val);
                    _applyFilters();
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  List<String> _getDynamicFilterOptions(String category) {
    if (category == 'State') {
      if (_isStateRestricted) return [];
      return _allUsers.map((u) => u.state).where((s) => s.isNotEmpty).toSet().toList()..sort();
    }
    
    if (category == 'District') {
      final selectedStates = _selectedFilters['State']!;
      final queryUsers = (selectedStates.isEmpty || _isStateRestricted)
          ? _allUsers 
          : _allUsers.where((u) => selectedStates.contains(u.state));
      return queryUsers.map((u) => u.district).where((d) => d.isNotEmpty).toSet().toList()..sort();
    }
    
    if (category == 'Tehsil') {
      final selectedStates = _selectedFilters['State']!;
      final selectedDistricts = _selectedFilters['District']!;
      
      var queryUsers = _allUsers;
      if (selectedDistricts.isNotEmpty) {
        queryUsers = queryUsers.where((u) => selectedDistricts.contains(u.district)).toList();
      } else if (selectedStates.isNotEmpty && !_isStateRestricted) {
        queryUsers = queryUsers.where((u) => selectedStates.contains(u.state)).toList();
      }
      
      return queryUsers.map((u) => u.tehsil).where((t) => t.isNotEmpty).toSet().toList()..sort();
    }
    
    if (category == 'Village') {
      final selectedStates = _selectedFilters['State']!;
      final selectedDistricts = _selectedFilters['District']!;
      final selectedTehsils = _selectedFilters['Tehsil']!;
      
      var queryUsers = _allUsers;
      if (selectedTehsils.isNotEmpty) {
        queryUsers = queryUsers.where((u) => selectedTehsils.contains(u.tehsil)).toList();
      } else if (selectedDistricts.isNotEmpty) {
        queryUsers = queryUsers.where((u) => selectedDistricts.contains(u.district)).toList();
      } else if (selectedStates.isNotEmpty && !_isStateRestricted) {
        queryUsers = queryUsers.where((u) => selectedStates.contains(u.state)).toList();
      }
      
      return queryUsers.map((u) => u.village).where((v) => v.isNotEmpty).toSet().toList()..sort();
    }
    
    if (category == 'Sector') {
      final selectedStates = _selectedFilters['State']!;
      final selectedDistricts = _selectedFilters['District']!;
      final selectedTehsils = _selectedFilters['Tehsil']!;
      final selectedVillages = _selectedFilters['Village']!;
      
      var queryUsers = _allUsers;
      if (selectedVillages.isNotEmpty) {
        queryUsers = queryUsers.where((u) => selectedVillages.contains(u.village)).toList();
      } else if (selectedTehsils.isNotEmpty) {
        queryUsers = queryUsers.where((u) => selectedTehsils.contains(u.tehsil)).toList();
      } else if (selectedDistricts.isNotEmpty) {
        queryUsers = queryUsers.where((u) => selectedDistricts.contains(u.district)).toList();
      } else if (selectedStates.isNotEmpty && !_isStateRestricted) {
        queryUsers = queryUsers.where((u) => selectedStates.contains(u.state)).toList();
      }
      return queryUsers.map((u) => u.sector).where((s) => s.isNotEmpty).toSet().toList()..sort();
    }
    
    // For other static categories, fallback to pre-extracted options
    return _filterOptions[category] ?? [];
  }

  void _pruneInvalidChildSelections() {
    // 1. Prune Districts if they don't belong to any selected States
    final selectedStates = _selectedFilters['State']!;
    if (selectedStates.isNotEmpty && !_isStateRestricted) {
      _selectedFilters['District']!.removeWhere((district) {
        final hasValidState = _allUsers.any((u) => u.district == district && selectedStates.contains(u.state));
        return !hasValidState;
      });
    }

    // 2. Prune Tehsils if they don't belong to any selected Districts (or States if no District is selected)
    final selectedDistricts = _selectedFilters['District']!;
    if (selectedDistricts.isNotEmpty) {
      _selectedFilters['Tehsil']!.removeWhere((tehsil) {
        final hasValidDistrict = _allUsers.any((u) => u.tehsil == tehsil && selectedDistricts.contains(u.district));
        return !hasValidDistrict;
      });
    } else if (selectedStates.isNotEmpty && !_isStateRestricted) {
      _selectedFilters['Tehsil']!.removeWhere((tehsil) {
        final hasValidState = _allUsers.any((u) => u.tehsil == tehsil && selectedStates.contains(u.state));
        return !hasValidState;
      });
    }

    // 3. Prune Villages if they don't belong to any selected Tehsils/Districts/States
    final selectedTehsils = _selectedFilters['Tehsil']!;
    if (selectedTehsils.isNotEmpty) {
      _selectedFilters['Village']!.removeWhere((village) {
        final hasValidTehsil = _allUsers.any((u) => u.village == village && selectedTehsils.contains(u.tehsil));
        return !hasValidTehsil;
      });
    } else if (selectedDistricts.isNotEmpty) {
      _selectedFilters['Village']!.removeWhere((village) {
        final hasValidDistrict = _allUsers.any((u) => u.village == village && selectedDistricts.contains(u.district));
        return !hasValidDistrict;
      });
    } else if (selectedStates.isNotEmpty && !_isStateRestricted) {
      _selectedFilters['Village']!.removeWhere((village) {
        final hasValidState = _allUsers.any((u) => u.village == village && selectedStates.contains(u.state));
        return !hasValidState;
      });
    }
  }

  Widget _buildFilterCategory(String category, StateSetter setModalState) {
    final options = _getDynamicFilterOptions(category);
    if (options.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(category, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.blue[800])),
        ),
        Wrap(
          spacing: 8,
          children: options.map((opt) {
            final isSelected = _selectedFilters[category]!.contains(opt);
            return FilterChip(
              label: Text(opt, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
              selected: isSelected,
              onSelected: (selected) {
                setModalState(() {
                  if (selected) {
                    _selectedFilters[category]!.add(opt);
                  } else {
                    _selectedFilters[category]!.remove(opt);
                    _pruneInvalidChildSelections();
                  }
                });
                _applyFilters();
              },
              selectedColor: Colors.blue[600],
              checkmarkColor: Colors.white,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
