import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../models/models.dart';
import '../services/logic_service.dart';
import 'home_screen.dart';
import 'public_profile_screen.dart';
import '../widgets/location_selectors.dart';
import '../widgets/reputation_badge.dart';

class ProfileScreen extends StatefulWidget {
  final bool isEditMode;
  final ABKMUser? user;
  final bool isTabMode;
  final Function(int)? onTabSwitchRequested;
  final bool isActive;
  const ProfileScreen({
    super.key, 
    this.isEditMode = false, 
    this.user, 
    this.isTabMode = false, 
    this.onTabSwitchRequested,
    this.isActive = true,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _stateController = TextEditingController();
  final _professionController = TextEditingController();
  final _educationController = TextEditingController();
  String _mobileNumber = '';
  int _points = 0;
  int _referralCount = 0;
  int _completedEventsCount = 0;
  int _upcomingEventsCount = 0;
  bool _hasCompletedEventsCount = false;
  String _loggedInMobile = '';
  String _loggedInState = '';
  
  String? _maritalStatus;
  DateTime? _selectedDOB;
  
  final _districtController = TextEditingController();
  final _tehsilController = TextEditingController();
  final _villageController = TextEditingController();
  
  Timer? _debounceTimer;
  
  String _selectedSector = 'Select Sector';
  final Map<String, List<String>> _professionsBySector = {
    'Select Sector': [],
    'Agriculture': ['Farmer', 'Organic Farming', 'Dairy Business', 'Agri-Business', 'Fisheries', 'Poultry Farmer', 'Horticulturist', 'Floriculturist', 'Other'],
    'Education': ['Teacher', 'Primary Teacher', 'Professor', 'Lecturer', 'Principal/Headmaster', 'Coaching/Tutor', 'Yoga Instructor', 'Trainer', 'Other'],
    'Government': ['Civil Services (IAS/IPS)', 'PCS/State Service', 'Public Sector (PSU)', 'Defence/Military', 'Police/Paramilitary', 'Banking (Govt)', 'Railway', 'Education (Govt)', 'Healthcare (Govt)', 'Local Body (Panchayat/Municipal)', 'Postal/Other Dept', 'Other'],
    'Private': ['Software Engineer/IT', 'Marketing/Sales', 'Finance/Accounting', 'HR/Operations', 'Consulting', 'Design/Creative', 'Media/Journalism', 'Healthcare (Private)', 'Manufacturing/Factory', 'Retail/Hospitality', 'Real Estate/Construction', 'Other'],
    'Digital / Social Media': ['Content Creator', 'Influencer', 'YouTuber/Blogger', 'Digital Marketing', 'Social Media Manager', 'SEO Expert', 'Video Editor', 'Graphic Designer', 'Other'],
    'Self-Employed / Business': ['Business Owner', 'Trader', 'Manufacturer', 'Real Estate Developer', 'Transport/Logistics', 'Shopkeeper', 'Contractor', 'Freelancer', 'Other'],
    'Healthcare': ['Doctor', 'Nurse', 'Pharmacist', 'Lab Technician', 'Physiotherapist', 'Dentist', 'Veterinary', 'Psychologist', 'Other'],
    'Judiciary & Legal': ['Advocate/Lawyer', 'Judge', 'Notary', 'Legal Consultant', 'Legal Clerk', 'Other'],
    'Professional': ['Chartered Accountant (CA)', 'Architect', 'Company Secretary (CS)', 'Engineer (Consultant)', 'Scientist', 'Artist/Writer', 'Interior Designer', 'Fashion Designer', 'Other'],
    'Banking & Insurance': ['Bank Manager', 'Relationship Manager', 'Insurance Agent', 'Loan Officer', 'Stock Broker', 'Wealth Manager', 'Other'],
    'Skilled Trade': ['Electrician', 'Plumber', 'Carpenter', 'Mechanic', 'Welder', 'Technician', 'AC/Appliance Repair', 'Other'],
    'Services & Security': ['Delivery Partner', 'Driver (Professional)', 'Security In-charge', 'Security Guard', 'Housekeeping Manager', 'Facility Management', 'Other'],
    'Media & Entertainment': ['Journalist', 'Photographer/Videographer', 'Event Planner', 'Musician/Singer', 'Actor/Performer', 'Anchor/Emcee', 'Other'],
    'Student': ['High School', 'Undergraduate', 'Postgraduate', 'PhD/Research', 'UPSC/Civil Services Aspirant', 'Medical/Engineering Aspirant', 'Other'],
    'Home Maker': ['Home Maker'],
    'Retired': ['Retired'],
    'Other': ['Other']
  };
  bool _isCustomProfession = false;
  
  String _selectedEducationLevel = 'Select Education';
  String _selectedDegree = 'Select Degree';
  final _customEducationLevelController = TextEditingController();
  final _customDegreeController = TextEditingController();
  final _referralMobileController = TextEditingController();
  final List<String> _educationLevels = ['Select Education', 'High School', 'Intermediate', 'Graduation', 'Post Graduation', 'Doctorate (PhD)', 'Diploma', 'Other'];
  final Map<String, List<String>> _degreesByLevel = {
    'Select Education': [],
    'Graduation': ['Select Degree', 'BA', 'B.Com', 'B.Sc', 'B.Tech', 'BCA', 'BBA', 'MBBS', 'LLB', 'Other'],
    'Post Graduation': ['Select Degree', 'MA', 'M.Com', 'M.Sc', 'M.Tech', 'MCA', 'MBA', 'MD', 'LLM', 'Other'],
  };


  String _selectedGender = 'Select Gender';
  final _ageController = TextEditingController();
  String? _base64Image;
  UserRole _currentUserRole = UserRole.member;
  UserRole _loggedInUserRole = UserRole.member;
  String _userPosition = 'Member';
  bool _isLoading = true;
  bool _hasExistingProfile = false;
  String? _errorField;

  bool _isEditUnlocked = false;

  List<ABKMEvent> _myEvents = [];
  bool _isUpdatingRole = false;
  bool _isUpdatingPosition = false;
  bool _isBlockingUser = false;
  ABKMUser? _loggedInUserProfile;

  final Map<String, List<String>> _hierarchyData = {
    'Core Leadership (Executive)': [
      'Patron', 
      'President', 
      'Working President', 
      'Vice President'
    ],
    'Administrative & Secretarial': [
      'General Secretary', 
      'Secretary', 
      'Joint Secretary', 
      'Office Secretary'
    ],
    'Treasury & Auditing': [
      'Treasurer', 
      'Joint Treasurer', 
      'Auditor'
    ],
    'Legal & Advisory': [
      'Legal Advisor'
    ],
    'Media, IT & PR': [
      'Spokesperson', 
      'Media In-charge', 
      'IT & Social Media Coordinator', 
      'Public Relations Officer (PRO)'
    ],
    'Organizational & Coordination': [
      'In-charge', 
      'Organization Secretary', 
      'Coordinator'
    ],
    'Specialized Wings (Heads)': [
      'Youth Wing President', 
      'Women’s Wing President', 
      'Students’ Wing President', 
      'Professional/Business Cell Head'
    ],
    'General Membership': [
      'Executive Member', 
      'Active Member', 
      'Primary Member', 
      'Member'
    ],
  };

  final List<String> _hierarchyLevels = [
    'National', 
    'State', 
    'District', 
    'City/Tehsil/Block', 
    'Village/Unit'
  ];

  String? _selectedCategory;
  String? _selectedPosition;
  String? _selectedLevel;

  // Initial state variables to track modifications
  String? _initialName;
  String? _initialBio;
  String? _initialState;
  String? _initialDistrict;
  String? _initialTehsil;
  String? _initialVillage;
  String? _initialSector;
  String? _initialProfession;
  String? _initialEducation;
  String? _initialGender;
  String? _initialMaritalStatus;
  DateTime? _initialDOB;
  String? _initialAge;
  String? _initialReferralMobile;
  String? _initialBase64Image;

  void _captureInitialValues() {
    _initialName = _nameController.text;
    _initialBio = _bioController.text;
    _initialState = _stateController.text;
    _initialDistrict = _districtController.text;
    _initialTehsil = _tehsilController.text;
    _initialVillage = _villageController.text;
    _initialSector = _selectedSector;
    _initialProfession = _professionController.text;
    _initialEducation = _educationController.text;
    _initialGender = _selectedGender;
    _initialMaritalStatus = _maritalStatus;
    _initialDOB = _selectedDOB;
    _initialAge = _ageController.text;
    _initialReferralMobile = _referralMobileController.text;
    _initialBase64Image = _base64Image;
  }

  void _restoreInitialValues() {
    _nameController.text = _initialName ?? '';
    _bioController.text = _initialBio ?? '';
    _stateController.text = _initialState ?? '';
    _districtController.text = _initialDistrict ?? '';
    _tehsilController.text = _initialTehsil ?? '';
    _villageController.text = _initialVillage ?? '';
    _selectedSector = _initialSector ?? 'Select Sector';
    _professionController.text = _initialProfession ?? '';
    _educationController.text = _initialEducation ?? '';
    _selectedGender = _initialGender ?? 'Select Gender';
    _maritalStatus = _initialMaritalStatus;
    _selectedDOB = _initialDOB;
    _ageController.text = _initialAge ?? '';
    _referralMobileController.text = _initialReferralMobile ?? '';
    _base64Image = _initialBase64Image;
    _parseAndSetEducation(_educationController.text);
    _parseAndSetProfession(_selectedSector, _professionController.text);
    if (mounted) setState(() {});
  }

  bool _hasProfileChanged() {
    if (!_hasExistingProfile) return true;

    final nameChanged = _nameController.text.trim() != (_initialName ?? '').trim();
    final bioChanged = _bioController.text.trim() != (_initialBio ?? '').trim();
    final stateChanged = _stateController.text.trim() != (_initialState ?? '').trim();
    final districtChanged = _districtController.text.trim() != (_initialDistrict ?? '').trim();
    final tehsilChanged = _tehsilController.text.trim() != (_initialTehsil ?? '').trim();
    final villageChanged = _villageController.text.trim() != (_initialVillage ?? '').trim();
    final sectorChanged = _selectedSector != (_initialSector ?? 'Select Sector');
    final professionChanged = _professionController.text.trim() != (_initialProfession ?? '').trim();
    final educationChanged = _educationController.text.trim() != (_initialEducation ?? '').trim();
    final genderChanged = _selectedGender != (_initialGender ?? 'Select Gender');
    final maritalStatusChanged = _maritalStatus != _initialMaritalStatus;
    final dobChanged = _selectedDOB != _initialDOB;
    final ageChanged = _ageController.text.trim() != (_initialAge ?? '').trim();
    final referralMobileChanged = _referralMobileController.text.trim() != (_initialReferralMobile ?? '').trim();
    final imageChanged = _base64Image != _initialBase64Image;

    return nameChanged ||
        bioChanged ||
        stateChanged ||
        districtChanged ||
        tehsilChanged ||
        villageChanged ||
        sectorChanged ||
        professionChanged ||
        educationChanged ||
        genderChanged ||
        maritalStatusChanged ||
        dobChanged ||
        ageChanged ||
        referralMobileChanged ||
        imageChanged;
  }

  bool get _isReferralEditable => !_hasExistingProfile;

  DateTime? _lastLogin;

  final _scrollController = ScrollController();
  
  final _nameFocus = FocusNode();
  final _stateFocus = FocusNode();
  final _districtFocus = FocusNode();
  final _tehsilFocus = FocusNode();
  final _villageFocus = FocusNode();
  final _professionFocus = FocusNode();
  final _educationFocus = FocusNode();
  final _ageFocus = FocusNode();
  final _bioFocus = FocusNode();

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkAuth();
    _stateController.text = '';
    _loadProfileData();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (!widget.isActive) {
        // Unfocus active textfields to safely dismiss keyboards and autocomplete overlays
        FocusScope.of(context).unfocus();
        
        // Auto-lock and restore initial values when user navigates away or switches tabs
        setState(() {
          _isEditUnlocked = false;
        });
        _restoreInitialValues();
      }
    }
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('abkm_mobileNumber') == null) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _stateController.dispose();
    _professionController.dispose();
    _educationController.dispose();
    _ageController.dispose();
    _tehsilController.dispose();
    _villageController.dispose();
    _customEducationLevelController.dispose();
    _customDegreeController.dispose();
    _referralMobileController.dispose();
    
    _nameFocus.dispose();
    _stateFocus.dispose();
    _districtFocus.dispose();
    _tehsilFocus.dispose();
    _villageFocus.dispose();
    _professionFocus.dispose();
    _educationFocus.dispose();
    _ageFocus.dispose();
    _bioFocus.dispose();
    _scrollController.dispose();

    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _loggedInState = prefs.getString('abkm_userState') ?? '';
      _loggedInMobile = prefs.getString('abkm_mobileNumber') ?? '';
      _mobileNumber = _loggedInMobile;
      final roleIndex = prefs.getInt('abkm_user_role') ?? 0;
      _loggedInUserRole = UserRole.values[roleIndex];

      SupabaseService().getProfile(_loggedInMobile).then((p) {
        if (mounted) {
          setState(() {
            _loggedInUserProfile = p;
            if (p != null) {
              _loggedInState = p.state;
            }
          });
        }
      });

      SupabaseService().getEventsByHost(_loggedInMobile).then((events) {
        if (mounted) {
          setState(() {
            _myEvents = events.where((e) => e.isApproved).toList();
          });
        }
      });
      
      if (widget.user != null) {
        final u = widget.user!;
        _hasExistingProfile = true;
        _isEditUnlocked = false; // Locked by default for existing profile
        _mobileNumber = u.id;
        _currentUserRole = u.userRole;
        _nameController.text = u.name;
        _bioController.text = u.bio;
        _stateController.text = u.state;
        _districtController.text = u.district;
        _tehsilController.text = u.tehsil;
        _villageController.text = u.village;
        _ageController.text = u.age.toString();
        _selectedGender = u.gender.isNotEmpty ? u.gender : 'Select Gender';
        _base64Image = u.profileImageUrl;
        _selectedSector = u.sector.isNotEmpty ? u.sector : 'Select Sector';
        _professionController.text = u.profession;
        _educationController.text = u.education;
        
        _parseAndSetEducation(u.education);
        _parseAndSetProfession(u.sector, u.profession);
        _referralMobileController.text = u.referralMobile ?? '';
        _userPosition = u.position;
        _maritalStatus = u.maritalStatus;
        _selectedDOB = u.dob;
        if (_selectedDOB != null) {
           _ageController.text = u.age.toString();
        }
        _referralCount = u.referralCount;
        _points = u.points;
        _lastLogin = u.lastLogin;
 
        // Fetch accurate recursive points and count in background
        SupabaseService().getProfile(u.id, forceRefresh: true).then((cloudProfile) {
          if (mounted && cloudProfile != null) {
            setState(() {
              _referralCount = cloudProfile.referralCount;
              _points = cloudProfile.points;
              _lastLogin = cloudProfile.lastLogin;
              
              // Load all missing fields from the full remote sync profile
              _maritalStatus = cloudProfile.maritalStatus;
              _selectedGender = cloudProfile.gender.isNotEmpty ? cloudProfile.gender : 'Select Gender';
              _selectedDOB = cloudProfile.dob;
              if (_selectedDOB != null) {
                _ageController.text = cloudProfile.age.toString();
              }
              _bioController.text = cloudProfile.bio;
              _stateController.text = cloudProfile.state;
              _districtController.text = cloudProfile.district;
              _tehsilController.text = cloudProfile.tehsil;
              _villageController.text = cloudProfile.village;
              _parseAndSetEducation(cloudProfile.education);
              _parseAndSetProfession(cloudProfile.sector, cloudProfile.profession);
              _userPosition = cloudProfile.position;
              _currentUserRole = cloudProfile.userRole;

              if (_referralMobileController.text.isEmpty && cloudProfile.referralMobile != null) {
                _referralMobileController.text = cloudProfile.referralMobile!;
              }
              _captureInitialValues(); // Recapture on background remote sync
            });
          }
        });

        // Fetch events hosted by this target user to count completed and upcoming approved ones
        SupabaseService().getEventsByHost(u.id).then((events) {
          if (mounted) {
            final now = DateTime.now();
            final completedCount = events.where((e) => e.date.isBefore(now) && e.isApproved).length;
            final upcomingCount = events.where((e) => e.date.isAfter(now) && e.isApproved).length;
            setState(() {
              _completedEventsCount = completedCount;
              _upcomingEventsCount = upcomingCount;
              _hasCompletedEventsCount = true;
            });
          }
        });
 
        if (mounted) {
          setState(() {
            _isLoading = false;
            _captureInitialValues();
          });
        }
        return;
      }
      
      // FOR OWN PROFILE (widget.user == null)
      // 1. Instantly load local fallback/cached data to avoid blank fields on screen load
      final String cacheKey = 'abkm_full_profile_$_mobileNumber';
      final String? cachedProfileStr = prefs.getString(cacheKey);
      
      if (cachedProfileStr != null) {
        try {
          final cachedProfile = ABKMUser.fromJson(json.decode(cachedProfileStr));
          _hasExistingProfile = true;
          _isEditUnlocked = false; // Locked by default for existing profile
          _currentUserRole = cachedProfile.userRole;
          _nameController.text = cachedProfile.name;
          _bioController.text = cachedProfile.bio;
          _stateController.text = cachedProfile.state;
          _districtController.text = cachedProfile.district;
          _tehsilController.text = cachedProfile.tehsil;
          _villageController.text = cachedProfile.village;
          
          _parseAndSetEducation(cachedProfile.education);
          _base64Image = cachedProfile.profileImageUrl;
          _selectedGender = cachedProfile.gender.isNotEmpty ? cachedProfile.gender : 'Select Gender';
          _ageController.text = cachedProfile.age.toString();
          _referralMobileController.text = cachedProfile.referralMobile ?? '';
          _parseAndSetProfession(cachedProfile.sector, cachedProfile.profession);
          _userPosition = cachedProfile.position;
          _maritalStatus = cachedProfile.maritalStatus;
          _selectedDOB = cachedProfile.dob;
          if (_selectedDOB != null) {
             _ageController.text = cachedProfile.age.toString();
          }
          _referralCount = cachedProfile.referralCount;
          _points = cachedProfile.points;
          _lastLogin = cachedProfile.lastLogin;
        } catch (cacheErr) {
          debugPrint('Error parsing cached profile: $cacheErr');
        }
      } else {
        // Individual SharedPreferences fallback
        final hasLocalProfile = prefs.getBool('abkm_hasProfile') ?? false;
        _hasExistingProfile = hasLocalProfile;
        _isEditUnlocked = !hasLocalProfile;
        _nameController.text = prefs.getString('abkm_userName') ?? '';
        _bioController.text = prefs.getString('abkm_userBio') ?? '';
        _stateController.text = prefs.getString('abkm_userState') ?? '';
        _districtController.text = prefs.getString('abkm_userDistrict') ?? '';
        _tehsilController.text = prefs.getString('abkm_userTehsil') ?? '';
        _villageController.text = prefs.getString('abkm_userVillage') ?? '';
        _parseAndSetEducation(prefs.getString('abkm_userEducation') ?? '');
        _parseAndSetProfession(prefs.getString('abkm_userSector') ?? 'Select Sector', prefs.getString('abkm_userProfession') ?? '');
        _base64Image = prefs.getString('abkm_userImageBase64');
        _selectedGender = prefs.getString('abkm_userGender') ?? 'Select Gender';
        final savedAge = prefs.getInt('abkm_userAge');
        _ageController.text = savedAge != null ? savedAge.toString() : '';
      }
      
      // Update UI with cached data instantly before doing any slow network call
      if (mounted) {
        setState(() {
          _captureInitialValues();
        });
      }
 
      // 2. Fetch fresh cloud profile in background
      try {
        final cloudProfile = await SupabaseService().getProfile(_mobileNumber, forceRefresh: true).timeout(const Duration(seconds: 10));
        if (!mounted) return;
        
        if (cloudProfile != null) {
          _hasExistingProfile = true;
          if (!_isEditUnlocked) {
            _isEditUnlocked = false; // Locked by default for existing profile
          }
          _currentUserRole = cloudProfile.userRole;
          _nameController.text = cloudProfile.name;
          _bioController.text = cloudProfile.bio;
          _stateController.text = cloudProfile.state;
          _districtController.text = cloudProfile.district;
          _tehsilController.text = cloudProfile.tehsil;
          _villageController.text = cloudProfile.village;
          
          _parseAndSetEducation(cloudProfile.education);
          _base64Image = cloudProfile.profileImageUrl;
          _selectedGender = cloudProfile.gender.isNotEmpty ? cloudProfile.gender : 'Select Gender';
          _ageController.text = cloudProfile.age.toString();
          _referralMobileController.text = cloudProfile.referralMobile ?? '';
          _parseAndSetProfession(cloudProfile.sector, cloudProfile.profession);
          _userPosition = cloudProfile.position;
          _maritalStatus = cloudProfile.maritalStatus;
          _selectedDOB = cloudProfile.dob;
          if (_selectedDOB != null) {
             _ageController.text = cloudProfile.age.toString();
          }
          _referralCount = cloudProfile.referralCount;
          _points = cloudProfile.points;
          _lastLogin = cloudProfile.lastLogin;
          
          if (mounted) {
            setState(() {
              _captureInitialValues();
            });
          }
        }
      } catch (cloudErr) {
        debugPrint('Error loading cloud profile in background: $cloudErr');
      }
      
      // Fetch events hosted by this user to count completed and upcoming approved ones
      SupabaseService().getEventsByHost(_mobileNumber).then((events) {
        if (mounted) {
          final now = DateTime.now();
          final completedCount = events.where((e) => e.date.isBefore(now) && e.isApproved).length;
          final upcomingCount = events.where((e) => e.date.isAfter(now) && e.isApproved).length;
          setState(() {
            _completedEventsCount = completedCount;
            _upcomingEventsCount = upcomingCount;
            _hasCompletedEventsCount = true;
          });
        }
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _parseAndSetEducation(String edu) {
    _educationController.text = edu;
    if (edu.isEmpty || edu == 'Select Education') return;

    // First check if the entire string matches an education level (e.g. "Doctorate (PhD)")
    final exactLevelMatch = _educationLevels.firstWhere(
      (l) => l.toLowerCase() == edu.toLowerCase(),
      orElse: () => ''
    );

    if (exactLevelMatch.isNotEmpty) {
      _selectedEducationLevel = exactLevelMatch;
      _selectedDegree = 'Select Degree';
      return;
    }

    // If not an exact level match, check if it's a "Level (Degree)" format
    if (edu.contains(' (')) {
      final parts = edu.split(' (');
      final levelInput = parts[0];
      
      _selectedEducationLevel = _educationLevels.firstWhere(
        (l) => l.toLowerCase() == levelInput.toLowerCase(),
        orElse: () => 'Other'
      );
      
      if (_selectedEducationLevel == 'Other') {
        _customEducationLevelController.text = levelInput;
      }
      
      final degreePartInput = parts[1].replaceAll(')', '');
      final levelDegrees = _degreesByLevel[_selectedEducationLevel] ?? [];
      
      _selectedDegree = levelDegrees.firstWhere(
        (d) => d.toLowerCase() == degreePartInput.toLowerCase(),
        orElse: () => 'Other'
      );
      
      if (_selectedDegree == 'Other') {
        _customDegreeController.text = degreePartInput;
      }
    } else {
      _selectedEducationLevel = _educationLevels.firstWhere(
        (l) => l.toLowerCase() == edu.toLowerCase(),
        orElse: () => 'Other'
      );
      
      if (_selectedEducationLevel == 'Other') {
        _customEducationLevelController.text = edu;
      }
    }
  }

  void _parseAndSetProfession(String sector, String prof) {
    _selectedSector = _professionsBySector.keys.firstWhere(
      (s) => s.toLowerCase() == sector.toLowerCase(),
      orElse: () => 'Select Sector'
    );
    _professionController.text = prof;
    
    if (_selectedSector != 'Select Sector') {
      final listForSector = _professionsBySector[_selectedSector] ?? [];
      // Use case-insensitive comparison to handle Title Case normalization differences
      final bool isPredefined = listForSector.any((p) => p.toLowerCase() == prof.toLowerCase());
      
      if (isPredefined) {
        _isCustomProfession = false;
        // Map back to the exact case from the list to ensure UI consistency
        _professionController.text = listForSector.firstWhere((p) => p.toLowerCase() == prof.toLowerCase());
      } else if (prof.isNotEmpty) {
        _isCustomProfession = true;
      } else {
        _isCustomProfession = false;
      }
    }
  }

  List<String> _getRolesForGender(String gender) {
    return []; // Roles removed
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'N/A';
    final DateTime ist = dt.toUtc().add(const Duration(hours: 5, minutes: 30));
    final DateFormat formatter = DateFormat('dd MMM yyyy, hh:mm a');
    return '${formatter.format(ist)} IST';
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Choose Profile Photo', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Upload from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image = await _picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 30,
                  maxWidth: 400,
                );
                if (image != null) _processImage(image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Capture with Camera'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image = await _picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 30,
                  maxWidth: 400,
                );
                if (image != null) _processImage(image);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processImage(XFile image) async {
    final bytes = await image.readAsBytes();
    setState(() {
      _base64Image = base64Encode(bytes);
    });
  }

  void _scrollToField(String field) {
    setState(() => _errorField = field);
    switch (field) {
      case 'name': _nameFocus.requestFocus(); break;
      case 'state': _stateFocus.requestFocus(); break;
      case 'district': _districtFocus.requestFocus(); break;
      case 'tehsil': _tehsilFocus.requestFocus(); break;
      case 'village': _villageFocus.requestFocus(); break;
      case 'profession': _professionFocus.requestFocus(); break;
      case 'education': _educationFocus.requestFocus(); break;
      case 'age': _ageFocus.requestFocus(); break;
      case 'bio': _bioFocus.requestFocus(); break;
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _errorField = null);

    if (_base64Image == null) {
      _scrollToField('image');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload a profile picture')));
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _scrollToField('name');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your full name')));
      return;
    }
    if (_stateController.text.trim().isEmpty) {
      _scrollToField('state');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your state')));
      return;
    }
    if (_districtController.text.trim().isEmpty) {
      _scrollToField('district');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your district')));
      return;
    }
    if (_tehsilController.text.trim().isEmpty) {
      _scrollToField('tehsil');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your Sub-District / Tehsil')));
      return;
    }
    if (_villageController.text.trim().isEmpty) {
      _scrollToField('village');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your Town / Village')));
      return;
    }
    if (_selectedSector == 'Select Sector') {
      _scrollToField('profession');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your employment sector')));
      return;
    }
    if (_professionController.text.trim().isEmpty) {
      _scrollToField('profession');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your profession')));
      return;
    }
    if (_selectedEducationLevel == 'Select Education') {
      _scrollToField('education');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your education level')));
      return;
    }
    if (_degreesByLevel.containsKey(_selectedEducationLevel) && _selectedDegree == 'Select Degree') {
      _scrollToField('education');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your degree')));
      return;
    }
    if (_selectedGender == 'Select Gender') {
      _scrollToField('gender');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your gender')));
      return;
    }
    if (_ageController.text.trim().isEmpty) {
      _scrollToField('age');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your age')));
      return;
    }

    setState(() => _isLoading = true);

    // Strict location validation: Only allow values from the database/dropdown
    final isDistrictValid = await SupabaseService().validateLocation(
      type: 'district',
      state: _stateController.text,
      value: _districtController.text,
    );
    if (!mounted) return;
    if (!isDistrictValid) {
      _scrollToField('district');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid District from the list')));
      return;
    }

    final isTehsilValid = await SupabaseService().validateLocation(
      type: 'tehsil',
      state: _stateController.text,
      district: _districtController.text,
      value: _tehsilController.text,
    );
    if (!mounted) return;
    if (!isTehsilValid) {
      _scrollToField('tehsil');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid Sub-District/Tehsil from the list')));
      return;
    }

    final isVillageValid = await SupabaseService().validateLocation(
      type: 'village',
      state: _stateController.text,
      district: _districtController.text,
      tehsil: _tehsilController.text,
      value: _villageController.text,
    );
    if (!mounted) return;
    if (!isVillageValid) {
      _scrollToField('village');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a valid Town/Village from the list')));
      return;
    }

    // Format text to Title Case (Camel Case) for consistent storage and display
    _nameController.text = FormatUtils.toTitleCase(_nameController.text);
    _professionController.text = FormatUtils.toTitleCase(_professionController.text);
    _tehsilController.text = FormatUtils.toTitleCase(_tehsilController.text);
    _villageController.text = FormatUtils.toTitleCase(_villageController.text);
    _customEducationLevelController.text = FormatUtils.toTitleCase(_customEducationLevelController.text);
    _customDegreeController.text = FormatUtils.toTitleCase(_customDegreeController.text);

    final referralMobile = _referralMobileController.text.trim();
    if (!_hasExistingProfile && referralMobile.isEmpty) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral mobile is mandatory while creating a profile')));
      }
      return;
    }

    if (referralMobile.isNotEmpty) {
      if (referralMobile.length != 4) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral mobile must be exactly 4 digits')));
        }
        return;
      }
      
      setState(() => _isLoading = true);
      try {
        final referrer = await SupabaseService().getProfile(referralMobile);
        if (!mounted) return;
        if (referrer == null) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Referral mobile does not exist. Please enter a valid number or leave it empty.'))
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error validating referral: ${e.toString()}'))
        );
        debugPrint('Error validating referral: $e');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final currentLoggedInNumber = prefs.getString('abkm_mobileNumber');
      final targetId = widget.user?.id ?? _mobileNumber;
      final bool isOwnProfile = targetId == currentLoggedInNumber;

      if (isOwnProfile || widget.user == null) {
        await prefs.setString('abkm_userName', _nameController.text);
        await prefs.setString('abkm_userBio', _bioController.text);
        await prefs.setString('abkm_userState', _stateController.text);
        await prefs.setString('abkm_userSector', _selectedSector);
        await prefs.setString('abkm_userProfession', _professionController.text);
        await prefs.setString('abkm_userEducation', _educationController.text);
        if (_base64Image != null) await prefs.setString('abkm_userImageBase64', _base64Image!);
        await prefs.setString('abkm_userGender', _selectedGender);
        await prefs.setInt('abkm_userAge', int.tryParse(_ageController.text) ?? 0);
        await prefs.setBool('abkm_hasProfile', true);
        await prefs.setBool('abkm_isLoggedIn', true);
        _hasExistingProfile = true;

        await prefs.setString('abkm_userDistrict', _districtController.text);
        await prefs.setString('abkm_userTehsil', _tehsilController.text);
        await prefs.setString('abkm_userVillage', _villageController.text);
        await prefs.setString('abkm_referralMobile', _referralMobileController.text);
        if (_maritalStatus != null) await prefs.setString('abkm_userMaritalStatus', _maritalStatus!);
        if (_selectedDOB != null) await prefs.setString('abkm_userDOB', _selectedDOB!.toIso8601String());
      }

      // Save to Supabase
      final user = ABKMUser(
        id: targetId,
        name: _nameController.text,
        gender: _selectedGender,
        userRole: _currentUserRole,
        bio: _bioController.text,
        profileImageUrl: _base64Image,
        state: _stateController.text,
        district: _districtController.text,
        tehsil: _tehsilController.text,
        village: _villageController.text,
        sector: _selectedSector,
        profession: _professionController.text,
        education: _educationController.text,
        referralMobile: _referralMobileController.text.trim().isNotEmpty ? _referralMobileController.text.trim() : null,
        position: _userPosition,
        maritalStatus: _maritalStatus,
        dob: _selectedDOB,
      );
      
      debugPrint('Saving profile to Supabase: ${user.id} | Profession: ${user.profession} | Sector: ${user.sector}');
      await SupabaseService().upsertProfile(user);

      if (mounted) {
        setState(() {
          _isEditUnlocked = false;
        });
      }

      if (!mounted) return;

      if (widget.isEditMode) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
      }
      
      // Always redirect to HomeScreen (Discover page) after update
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } catch (e) {
      debugPrint('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Profile', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text(
          'Are you sure you want to delete your profile?\n\n'
          '• All your personal data, hosted events, and applications will be erased.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );


    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await SupabaseService().deleteProfile(_mobileNumber);
        if (!mounted) return;
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final String? currentLoggedInNumber = prefs.getString('abkm_mobileNumber');

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile deleted successfully')));
        
        if (currentLoggedInNumber == _mobileNumber) {
          final keys = prefs.getKeys();
          for (String key in keys) {
            await prefs.remove(key);
          }
          if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
        } else {
          if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        }
      } catch (e) {
        debugPrint('Error deleting profile: $e');
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete profile. Please try again.')));
        }
      }
    }
  }

  Future<void> _showDeveloperConnectDialog() async {
    String selectedOption = 'Provide Feedback';
    final descriptionController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Connect to Developer', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedOption,
                decoration: const InputDecoration(labelText: 'Purpose'),
                items: ['Provide Feedback', 'Raise a Bug', 'Request a Feature']
                    .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                    .toList(),
                onChanged: (val) => setDialogState(() => selectedOption = val!),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Describe your issue/feedback...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final description = descriptionController.text.trim();
                if (description.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a description')));
                  return;
                }
                
                final String subject = '$selectedOption - ABKM App';
                final String body = 'From: ${_nameController.text}\n'
                                   'Mobile: $_mobileNumber\n\n'
                                   'Type: $selectedOption\n'
                                   'Description: $description';
                
                final Uri emailUri = Uri(
                  scheme: 'mailto',
                  path: 'automation.sushil@gmail.com',
                  query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
                );

                if (await canLaunchUrl(emailUri)) {
                  await launchUrl(emailUri, mode: LaunchMode.externalApplication);
                  if (mounted) Navigator.pop(context);
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch email client')));
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDOB ?? DateTime(2000),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDOB) {
      setState(() {
        _selectedDOB = picked;
        // Always calculate age from DOB
        final now = DateTime.now();
        int age = now.year - picked.year;
        if (now.month < picked.month || (now.month == picked.month && now.day < picked.day)) {
          age--;
        }
        _ageController.text = age.toString();
      });
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

    return PopScope(
      canPop: widget.isEditMode && _hasExistingProfile,
      onPopInvoked: (didPop) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please complete your profile to continue')),
        );
      },
      child: Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: null,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Builder(
            builder: (context) {
              final bool isOwnProfile = widget.user == null || _loggedInMobile == widget.user!.id;
              final bool canEditThisProfile = isOwnProfile || _loggedInUserRole == UserRole.superUser;
              
              if (_hasExistingProfile && canEditThisProfile) {
                return TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isEditUnlocked = !_isEditUnlocked;
                      if (!_isEditUnlocked) {
                        _restoreInitialValues();
                      }
                    });
                  },
                  icon: Icon(
                    _isEditUnlocked ? Icons.lock : Icons.edit,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    _isEditUnlocked ? 'Lock' : 'Edit',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Builder(
            builder: (context) {
              final bool isOwnProfile = widget.user == null || _loggedInMobile == widget.user!.id;
              if (isOwnProfile) {
                return TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final keys = prefs.getKeys();
                    for (String key in keys) {
                      if (key.startsWith('abkm_')) {
                        await prefs.remove(key);
                      }
                    }
                    if (!context.mounted) return;
                    Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Logout',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.logout, color: Colors.white, size: 20),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildPageBackground(),
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    backgroundImage: _base64Image != null && _base64Image!.startsWith('http')
                      ? NetworkImage(_base64Image!) as ImageProvider
                      : _base64Image != null 
                        ? MemoryImage(base64Decode(_base64Image!)) 
                        : null,
                    child: _base64Image == null 
                      ? Icon(Icons.person, size: 60, color: theme.colorScheme.primary)
                      : null,
                  ),
                  if (!_hasExistingProfile || _isEditUnlocked)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: theme.colorScheme.primary,
                          child: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                        ),
                      ),
                    )
                  else if (_hasExistingProfile)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: ReputationBadge(points: _points, size: 36),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone_android, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      _mobileNumber,
                      style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.w600),
                    ),
                    if (widget.user == null || _loggedInMobile == widget.user!.id) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                ),
                child: Text(
                  FormatUtils.formatDesignation(
                    ABKMUser(
                      id: _mobileNumber,
                      name: _nameController.text,
                      gender: _selectedGender,
                      userRole: _currentUserRole,
                      bio: _bioController.text,
                      state: _stateController.text,
                      district: _districtController.text,
                      tehsil: _tehsilController.text,
                      village: _villageController.text,
                      position: _userPosition,
                    ),
                  ),
                  style: GoogleFonts.inter(
                    color: theme.colorScheme.primary, 
                    fontWeight: FontWeight.bold,
                    fontSize: 14
                  ),
                ),
              ),
            ),
            if (_lastLogin != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Last Login: ${_formatDateTime(_lastLogin)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            _buildLabel('Full Name'),
            _buildTextField(
              controller: _nameController, 
              hint: 'Full Name', 
              icon: Icons.person_outline,
              focusNode: _nameFocus,
              fieldKey: 'name',
            ),
            const SizedBox(height: 20),
            _buildLabel('Address'),
            _buildLocationSelectors(),
            const SizedBox(height: 20),
            _buildLabel('Employment Sector'),
            _buildSectorSelector(),
            if (_selectedSector != 'Select Sector') ...[
              const SizedBox(height: 20),
              _buildLabel('Profession'),
              _buildProfessionSelector(),
              if (_isCustomProfession) ...[
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _professionController, 
                  hint: 'Enter your specific profession', 
                  icon: Icons.edit_note,
                  onChanged: (val) => setState(() {}),
                  focusNode: _professionFocus,
                  fieldKey: 'profession',
                ),
              ],
            ],
            const SizedBox(height: 20),
            _buildLabel('Education'),
            _buildEducationSection(),
            const SizedBox(height: 20),
            _buildLabel('Gender'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Male', 'Female', 'Other'].map((g) => _buildGenderChip(g)).toList(),
            ),
            const SizedBox(height: 20),
            _buildLabel('Marital Status'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Married', 'Unmarried'].map((s) => _buildMaritalStatusChip(s)).toList(),
            ),
            const SizedBox(height: 20),
            _buildLabel('Age'),
            InkWell(
              onTap: (!_hasExistingProfile || _isEditUnlocked) ? () => _selectDate(context) : null,
              child: IgnorePointer(
                child: _buildTextField(
                  controller: _ageController, 
                  hint: 'Tap to select Date of Birth', 
                  icon: Icons.cake_outlined,
                  focusNode: _ageFocus,
                  fieldKey: 'age',
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildLabel('Short Bio (Optional)', isRequired: false),

            _buildTextField(
              controller: _bioController,
              hint: 'Tell us a bit about yourself...',
              maxLines: 3,
              icon: Icons.notes,
              focusNode: _bioFocus,
              fieldKey: 'bio',
            ),
            if (_hasExistingProfile) ...[
              const SizedBox(height: 20),
              _buildPointsAndPromotionSection(theme),
            ],

            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: RichText(
                text: TextSpan(
                  text: 'Referral Mobile',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
                  children: [
                    if (!_hasExistingProfile)
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
            ),
            _buildTextField(
              controller: _referralMobileController,
              hint: 'Enter 4 digit mobile number',
              icon: Icons.person_add_alt_1_outlined,
              keyboardType: TextInputType.phone,
              fillColor: Colors.white,
              enabled: _isReferralEditable,
            ),
            const SizedBox(height: 40),
            if (widget.user == null || _loggedInMobile == widget.user!.id) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: ((!_hasExistingProfile || _isEditUnlocked) && _hasProfileChanged()) 
                      ? _saveProfile 
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ((!_hasExistingProfile || _isEditUnlocked) && _hasProfileChanged())
                        ? theme.colorScheme.primary
                        : Colors.white.withOpacity(0.9),
                    foregroundColor: ((!_hasExistingProfile || _isEditUnlocked) && _hasProfileChanged())
                        ? Colors.white
                        : Colors.grey[500],
                    disabledBackgroundColor: Colors.grey[100],
                    disabledForegroundColor: Colors.grey[500],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: BorderSide(
                      color: ((!_hasExistingProfile || _isEditUnlocked) && _hasProfileChanged())
                          ? Colors.transparent
                          : Colors.grey[200]!,
                    ),
                    elevation: ((!_hasExistingProfile || _isEditUnlocked) && _hasProfileChanged()) ? 2 : 0,
                  ),
                  child: Text(widget.isEditMode ? 'Update Profile' : 'Save Profile', 
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            if (widget.isEditMode) ...[
              FutureBuilder<SharedPreferences>(
                future: SharedPreferences.getInstance(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final prefs = snapshot.data!;
                  final currentLoggedInNumber = prefs.getString('abkm_mobileNumber');
                  final bool isOwnProfile = currentLoggedInNumber == _mobileNumber;
                  final bool isSuperUser = _loggedInUserRole == UserRole.superUser;
                  
                  final bool isEnabled = _isEditUnlocked;
                  if (isOwnProfile || isSuperUser) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: isEnabled ? _deleteProfile : null,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isEnabled ? Colors.red[50] : Colors.grey[100],
                            side: BorderSide(color: isEnabled ? Colors.red : Colors.grey[200]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text('Delete Profile', 
                            style: GoogleFonts.inter(
                              fontSize: 18, 
                              fontWeight: FontWeight.bold, 
                              color: isEnabled ? Colors.red : Colors.grey[500],
                            )),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
            Builder(
              builder: (context) {
                final bool isOwnProfile = widget.user == null || _loggedInMobile == widget.user!.id;
                if (!isOwnProfile && _loggedInUserRole != UserRole.member) {
                  return Column(
                    children: [
                      const SizedBox(height: 24),
                      _buildRoleManagementSection(theme),
                      const SizedBox(height: 24),
                      if (_canUpdateHierarchy()) ...[
                        _buildHierarchyManagementSection(theme),
                        const SizedBox(height: 24),
                      ],
                      if (_canBlockTargetUser()) ...[
                        _buildAccountSecuritySection(theme),
                        const SizedBox(height: 24),
                      ],
                      if (_myEvents.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _showInviteDialog,
                            icon: const Icon(Icons.mail_outline),
                            label: Text('Invite to Join Event', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'COMPLIANCE & STANDARDS',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => _showPrivacyPolicy(context),
                icon: const Icon(Icons.privacy_tip_outlined, color: Colors.blue),
                label: Text('Privacy Policy', 
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _showDeveloperConnectDialog,
                icon: const Icon(Icons.support_agent, color: Colors.blue),
                label: Text('Connect to Developer', 
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
              ),
            ),
            const SizedBox(height: 24),
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
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Please wait...',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  ),
);
}

  Widget _buildLabel(String label, {bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          text: label,
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black),
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointsAndPromotionSection(ThemeData theme) {
    final int points = _points;
    final int directPoints = _referralCount * 5;
    final int indirectPoints = points - directPoints;
    final int indirectRefs = indirectPoints ~/ 5;
    
    final bool isOwnProfile = (widget.user == null || widget.user!.id == _loggedInMobile);
    final bool canSeeHostedEvents = isOwnProfile || (_loggedInUserRole == UserRole.admin || _loggedInUserRole == UserRole.superUser);
    
    final rep = getReputationLevel(points);
    final String currentRank = 'Level ${rep.level}';
    final List<int> milestones = [0, 100, 500, 1000, 5000, 10000, 25000, 50000, 75000, 100000];
    
    String nextRank = '';
    int currentMilestone = 0;
    int nextMilestone = 0;
    double progress = 0.0;
    
    if (rep.level < 10) {
      currentMilestone = milestones[rep.level - 1];
      nextMilestone = milestones[rep.level];
      nextRank = 'Level ${rep.level + 1}';
      progress = (points - currentMilestone) / (nextMilestone - currentMilestone);
    } else {
      nextRank = '';
      currentMilestone = 100000;
      nextMilestone = 100000;
      progress = 1.0;
    }
    
    progress = progress.clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReputationBadge(points: points, size: 26, showTooltip: false),
              const SizedBox(width: 12),
              Text(
                'Membership & Points',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Points',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$points pts',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.arrow_right_alt, size: 10, color: Colors.blue[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Direct: $directPoints pts ($_referralCount ref${_referralCount == 1 ? "" : "s"})',
                                style: GoogleFonts.inter(fontSize: 8.5, color: Colors.grey[600], fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.arrow_right_alt, size: 10, color: Colors.orange[600]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Indirect: $indirectPoints pts ($indirectRefs ref${indirectRefs == 1 ? "" : "s"})',
                                style: GoogleFonts.inter(fontSize: 8.5, color: Colors.grey[600], fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            _showReferralListBottomSheet(context, widget.user?.id ?? _mobileNumber);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total Referrals',
                                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$_referralCount ${_referralCount == 1 ? "user" : "users"}',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Icon(Icons.touch_app, size: 11, color: theme.colorScheme.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Click to view list',
                                      style: GoogleFonts.inter(
                                        fontSize: 9, 
                                        color: theme.colorScheme.primary, 
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (canSeeHostedEvents) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[50]!,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.event_available, color: Colors.green[700]!, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Events Hosted',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _hasCompletedEventsCount
                              ? 'Completed: $_completedEventsCount  •  Upcoming: $_upcomingEventsCount'
                              : 'Loading...',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800]!,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 32),
          if (nextRank.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Referral Progress',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${points - currentMilestone}/${nextMilestone - currentMilestone} to $nextRank',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFFE65100)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Get 5 points for each referral. Invite new members!',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: Colors.grey[500],
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Highest Membership Rank Achieved! 🏆',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[800],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }



  Widget _buildTextField({
    required TextEditingController controller, 
    required String hint, 
    int maxLines = 1,
    IconData? icon,
    FocusNode? focusNode,
    Function(String)? onChanged,
    TextInputType? keyboardType,
    bool? enabled,
    String? fieldKey,
    Color? fillColor,
  }) {
    final bool isOwnProfile = widget.user == null || _loggedInMobile == widget.user!.id;
    final bool isFieldEnabled = enabled ?? (!_hasExistingProfile || _isEditUnlocked);
    final hasError = _errorField == fieldKey;
    final theme = Theme.of(context);

    // Individual edit icons removed since we have a common edit link at the top
    final suffixIconToShow = null;
    
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      onChanged: (val) {
        if (hasError) setState(() => _errorField = null);
        if (onChanged != null) onChanged(val);
        setState(() {}); // Trigger rebuild to update Update Button state dynamically
      },
      keyboardType: keyboardType,
      enabled: isFieldEnabled,
      style: GoogleFonts.inter(
        fontSize: 14,
        color: isFieldEnabled ? Colors.black87 : Colors.grey[500],
      ),
      decoration: InputDecoration(
        prefixIcon: icon != null ? Icon(icon, color: hasError ? Colors.red : (isFieldEnabled ? Colors.grey : Colors.grey[300])) : null,
        suffixIcon: (enabled == false) 
            ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey) 
            : suffixIconToShow,
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.grey[400]),
        filled: true,
        fillColor: fillColor ?? (hasError ? Colors.red.withOpacity(0.05) : (isFieldEnabled ? Colors.grey[50] : Colors.grey[100])),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hasError ? Colors.red : Colors.grey[300]!, width: hasError ? 2 : 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hasError ? Colors.red : Colors.grey[200]!, width: hasError ? 2 : 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hasError ? Colors.red : theme.colorScheme.primary, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
      ),
    );
  }

  Widget _buildEducationSection() {
    final hasError = _errorField == 'education';
    final enabled = !_hasExistingProfile || _isEditUnlocked;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: hasError ? Colors.red.withOpacity(0.05) : (enabled ? Colors.grey[50] : Colors.grey[100]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hasError ? Colors.red : Colors.grey[200]!, width: hasError ? 2 : 1),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              focusNode: _educationFocus,
              value: _selectedEducationLevel,
              isExpanded: true,
              style: GoogleFonts.inter(fontSize: 14, color: enabled ? Colors.black87 : Colors.grey[500]),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              items: _educationLevels.map((String level) {
                return DropdownMenuItem<String>(
                  value: level,
                  child: Text(level, style: GoogleFonts.inter(fontSize: 14, color: enabled ? Colors.black87 : Colors.grey[500])),
                );
              }).toList(),
              onChanged: enabled
                  ? (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedEducationLevel = newValue;
                          if (newValue == 'Other') {
                            _educationController.text = _customEducationLevelController.text;
                          } else if (_degreesByLevel.containsKey(newValue)) {
                            _selectedDegree = 'Select Degree';
                            _educationController.text = '$_selectedEducationLevel ($_selectedDegree)';
                          } else {
                            _educationController.text = newValue;
                          }
                          _errorField = null;
                        });
                      }
                    }
                  : null,
            ),
          ),
        ),
        if (_selectedEducationLevel == 'Other') ...[
          const SizedBox(height: 12),
          _buildTextField(
            controller: _customEducationLevelController, 
            hint: 'Enter your education level', 
            icon: Icons.school_outlined,
            onChanged: (val) {
              setState(() {
                _educationController.text = val;
              });
            },
          ),
        ],
        if (_selectedEducationLevel != 'Select Level' && _degreesByLevel.containsKey(_selectedEducationLevel)) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: enabled ? Colors.grey[50] : Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDegree == 'Select Degree' ? null : _selectedDegree,
                hint: Text('Select Degree', style: GoogleFonts.inter(fontSize: 14, color: enabled ? Colors.black87 : Colors.grey[500])),
                isExpanded: true,
                style: GoogleFonts.inter(fontSize: 14, color: enabled ? Colors.black87 : Colors.grey[500]),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                items: _degreesByLevel[_selectedEducationLevel]!.map((String degree) {
                  return DropdownMenuItem<String>(
                    value: degree,
                    child: Text(degree, style: GoogleFonts.inter(fontSize: 14, color: enabled ? Colors.black87 : Colors.grey[500])),
                  );
                }).toList(),
                onChanged: enabled
                    ? (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedDegree = newValue;
                            if (newValue == 'Other') {
                              _educationController.text = '$_selectedEducationLevel (${_customDegreeController.text})';
                            } else {
                              _educationController.text = '$_selectedEducationLevel ($_selectedDegree)';
                            }
                          });
                        }
                      }
                    : null,
              ),
            ),
          ),
          if (_selectedDegree == 'Other') ...[
            const SizedBox(height: 12),
            _buildTextField(
              controller: _customDegreeController, 
              hint: 'Enter your specific degree', 
              icon: Icons.history_edu_outlined,
              onChanged: (val) {
                setState(() {
                  _educationController.text = '$_selectedEducationLevel ($val)';
                });
              },
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildLocationSelectors() {
    return LocationSelectors(
      stateController: _stateController,
      districtController: _districtController,
      tehsilController: _tehsilController,
      villageController: _villageController,
      stateFocusNode: _stateFocus,
      districtFocusNode: _districtFocus,
      tehsilFocusNode: _tehsilFocus,
      villageFocusNode: _villageFocus,
      errorField: _errorField,
      onErrorFieldChanged: (field) {
        setState(() {
          _errorField = field;
        });
      },
      onChanged: () => setState(() {}),
      isStateLocked: _hasExistingProfile,
      isEnabled: !_hasExistingProfile || _isEditUnlocked,
    );
  }

  Widget _buildSectorSelector() {
    final hasError = _errorField == 'profession';
    final enabled = !_hasExistingProfile || _isEditUnlocked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: hasError ? Colors.red.withOpacity(0.05) : (enabled ? Colors.grey[50] : Colors.grey[100]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hasError ? Colors.red : Colors.grey[200]!, width: hasError ? 2 : 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          focusNode: _professionFocus,
          value: _selectedSector,
          isExpanded: true,
          style: GoogleFonts.inter(fontSize: 14, color: enabled ? Colors.black87 : Colors.grey[500]),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
          items: _professionsBySector.keys.map((String sector) {
            return DropdownMenuItem<String>(
              value: sector,
              child: Text(sector, style: GoogleFonts.inter(fontSize: 14, color: enabled ? Colors.black87 : Colors.grey[500])),
            );
          }).toList(),
          onChanged: enabled
              ? (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedSector = newValue;
                      _professionController.clear();
                      _isCustomProfession = (newValue == 'Other' || newValue == 'Retired' || newValue == 'Home Maker');
                      if (newValue == 'Retired') _professionController.text = 'Retired';
                      if (newValue == 'Home Maker') _professionController.text = 'Home Maker';
                      _errorField = null;
                    });
                  }
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildProfessionSelector() {
    final professions = _professionsBySector[_selectedSector] ?? [];
    if (professions.isEmpty || _selectedSector == 'Retired' || _selectedSector == 'Home Maker') {
       return const SizedBox.shrink();
    }
    final enabled = !_hasExistingProfile || _isEditUnlocked;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: professions.map((p) {
        final isSelected = (_professionController.text.toLowerCase() == p.toLowerCase() && !_isCustomProfession) || (p == 'Other' && _isCustomProfession);
        
        final chip = ChoiceChip(
          showCheckmark: false,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Icon(
                  Icons.check_circle, 
                  size: 16, 
                  color: enabled ? Colors.green : Colors.grey[600],
                ),
                const SizedBox(width: 6),
              ],
              Text(p),
            ],
          ),
          selected: isSelected,
          onSelected: (val) {
            if (enabled) {
              setState(() {
                if (p == 'Other') {
                  _isCustomProfession = true;
                  _professionController.clear();
                } else {
                  _isCustomProfession = false;
                  _professionController.text = p;
                }
              });
            }
          },
          selectedColor: enabled 
              ? Theme.of(context).colorScheme.primary.withOpacity(0.15) 
              : Colors.grey[200],
          backgroundColor: Colors.grey[50],
          side: BorderSide(
            color: isSelected 
                ? (enabled ? Theme.of(context).colorScheme.primary : Colors.grey[400]!) 
                : Colors.grey[300]!,
            width: isSelected ? 1.5 : 1.0,
          ),
          labelStyle: GoogleFonts.inter(
            fontSize: 12,
            color: isSelected 
                ? (enabled ? Theme.of(context).colorScheme.primary : Colors.grey[800]) 
                : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        );

        if (!enabled) {
          return AbsorbPointer(
            absorbing: true,
            child: chip,
          );
        }
        return chip;
      }).toList(),
    );
  }

  Widget _buildGenderChip(String gender) {
    final isSelected = _selectedGender == gender;
    final enabled = !_hasExistingProfile || _isEditUnlocked;
    
    final chip = ChoiceChip(
      showCheckmark: false,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected) ...[
            Icon(
              Icons.check_circle, 
              size: 16, 
              color: enabled ? Colors.green : Colors.grey[600],
            ),
            const SizedBox(width: 6),
          ],
          Text(gender),
        ],
      ),
      selected: isSelected,
      onSelected: (val) {
        if (enabled && val) {
          setState(() {
            _selectedGender = gender;
          });
        }
      },
      selectedColor: enabled 
          ? Theme.of(context).colorScheme.primary.withOpacity(0.15) 
          : Colors.grey[200],
      backgroundColor: Colors.grey[50],
      side: BorderSide(
        color: isSelected 
            ? (enabled ? Theme.of(context).colorScheme.primary : Colors.grey[400]!) 
            : Colors.grey[300]!,
        width: isSelected ? 1.5 : 1.0,
      ),
      labelStyle: GoogleFonts.inter(
        color: isSelected 
            ? (enabled ? Theme.of(context).colorScheme.primary : Colors.grey[800]) 
            : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );

    if (!enabled) {
      return AbsorbPointer(
        absorbing: true,
        child: chip,
      );
    }
    return chip;
  }

  Widget _buildMaritalStatusChip(String status) {
    final isSelected = _maritalStatus == status;
    final enabled = !_hasExistingProfile || _isEditUnlocked;
    
    final chip = ChoiceChip(
      showCheckmark: false,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected) ...[
            Icon(
              Icons.check_circle, 
              size: 16, 
              color: enabled ? Colors.green : Colors.grey[600],
            ),
            const SizedBox(width: 6),
          ],
          Text(status),
        ],
      ),
      selected: isSelected,
      onSelected: (val) {
        if (enabled && val) {
          setState(() {
            _maritalStatus = status;
          });
        }
      },
      selectedColor: enabled 
          ? Theme.of(context).colorScheme.primary.withOpacity(0.15) 
          : Colors.grey[200],
      backgroundColor: Colors.grey[50],
      side: BorderSide(
        color: isSelected 
            ? (enabled ? Theme.of(context).colorScheme.primary : Colors.grey[400]!) 
            : Colors.grey[300]!,
        width: isSelected ? 1.5 : 1.0,
      ),
      labelStyle: GoogleFonts.inter(
        color: isSelected 
            ? (enabled ? Theme.of(context).colorScheme.primary : Colors.grey[800]) 
            : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );

    if (!enabled) {
      return AbsorbPointer(
        absorbing: true,
        child: chip,
      );
    }
    return chip;
  }

  void _showPrivacyPolicy(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Privacy Policy',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Updated: May 05, 2026',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _policySection('1. Information We Collect', 
                        'To provide a community-building experience, we collect:\n'
                        '• Personal Identity: Name, Age, Gender, Profile Image.\n'
                        '• Contact: Mobile Number for authentication.\n'
                        '• Community: Profession, Education, and Location.\n'
                        '• Interaction: Event applications and activities.'),
                      _policySection('2. How We Use Data', 
                        'Your information is used for:\n'
                        '• Community directory connections.\n'
                        '• Event management.\n'
                        '• Secure mobile login.\n'
                        '• Feature improvements.'),
                      _policySection('3. Data Deletion', 
                        'You can delete your entire profile and associated data via Profile > Delete Profile button. This is permanent.'),
                      _policySection('4. Data Security', 
                        'We use industry-standard security (Supabase RLS) to protect your data.'),
                      _policySection('5. Third-Party', 
                        'We use Supabase for database and storage.'),
                      _policySection('6. Contact', 
                        'Questions? Contact: automation.sushil@gmail.com'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _policySection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showReferralListBottomSheet(BuildContext context, String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 5,
              )
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Direct Referrals',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<ABKMUser>>(
                  future: SupabaseService().getReferredUsers(userId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading referrals',
                          style: GoogleFonts.inter(color: Colors.red),
                        ),
                      );
                    }
                    final users = (snapshot.data ?? []).where((u) => !u.isDeleted).toList();
                    if (users.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No direct referrals yet.',
                              style: GoogleFonts.inter(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (context, index) {
                        final u = users[index];
                        // ── Deleted account placeholder ─────────────────────
                        if (u.isDeleted) {
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.grey[200],
                              child: Icon(Icons.person_off_outlined, color: Colors.grey[400], size: 22),
                            ),
                            title: Text(
                              'Deleted Account',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            subtitle: Text(
                              'Mobile: ${u.id}',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[400]),
                            ),
                            trailing: Icon(Icons.block, color: Colors.grey[300], size: 18),
                          );
                        }
                        // ── Active user row ──────────────────────────────────
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.blue[50]!,
                            backgroundImage: _getAvatarImage(u.profileImageUrl),
                            child: _getAvatarImage(u.profileImageUrl) == null
                                ? Text(
                                    u.name.isNotEmpty ? u.name.substring(0, 1).toUpperCase() : '?',
                                    style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          title: Text(
                            u.name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            '${FormatUtils.formatDesignation(u)} • ${u.district}${u.state.isNotEmpty ? ", ${u.state}" : ""}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () {
                            Navigator.pop(context); // Close bottom sheet
                            Navigator.push<dynamic>(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PublicProfileScreen(user: u),
                              ),
                            ).then((result) {
                              if (result is int && widget.onTabSwitchRequested != null) {
                                widget.onTabSwitchRequested!(result);
                              }
                            });
                          },
                        );
                      },

                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ABKMUser get _targetUser => widget.user!;

  bool _canBlockTargetUser() {
    if (_targetUser.id == _loggedInMobile) return false;
    if (_targetUser.userRole == UserRole.superUser) return false;
    if (_targetUser.userRole == UserRole.admin) {
      return _loggedInUserRole == UserRole.superUser;
    }
    if (_loggedInUserRole == UserRole.superUser) return true;
    if (_loggedInUserRole == UserRole.admin) {
      final bool isSameState = _loggedInState.isNotEmpty && 
          _loggedInState.trim().toLowerCase() == _targetUser.state.trim().toLowerCase();
      if (!isSameState) return false;
      if (_targetUser.userRole == UserRole.moderator) return true;
      if (_targetUser.userRole == UserRole.member) return true;
    }
    return false;
  }

  bool _canUpdateHierarchy() {
    if (_targetUser.id == _loggedInMobile) return false;
    if (_targetUser.userRole == UserRole.superUser) return false;
    if (_targetUser.userRole == UserRole.admin) {
      return _loggedInUserRole == UserRole.superUser;
    }
    if (_loggedInUserRole == UserRole.superUser) return true;
    if (_loggedInUserRole == UserRole.admin) {
      final bool isSameState = _loggedInState.isNotEmpty && 
          _loggedInState.trim().toLowerCase() == _targetUser.state.trim().toLowerCase();
      if (!isSameState) return false;
      if (_targetUser.userRole == UserRole.moderator) return true;
      if (_targetUser.userRole == UserRole.member) return true;
    }
    return false;
  }

  UserRole _getFallbackRole(String position) {
    final List<String> generalPositions = ['Executive Member', 'Active Member', 'Primary Member', 'Member'];
    if (generalPositions.contains(position)) {
      return UserRole.member;
    }
    return UserRole.moderator;
  }

  Widget _buildRoleManagementSection(ThemeData theme) {
    if (_loggedInUserRole != UserRole.superUser) return const SizedBox.shrink();
    
    final bool isTargetAdmin = _targetUser.userRole.index == UserRole.admin.index || _targetUser.userRole.index == UserRole.superUser.index;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                'Privileged Role Management',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'As a Super User, you can specifically grant or revoke administrative rights.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isUpdatingRole ? null : () async {
                setState(() => _isUpdatingRole = true);
                try {
                  final bool currentlyAdmin = _targetUser.userRole.index == UserRole.admin.index || _targetUser.userRole.index == UserRole.superUser.index;
                  UserRole fallbackRole = _getFallbackRole(_targetUser.position);
                  UserRole newRole = currentlyAdmin ? fallbackRole : UserRole.admin;
                  
                  await SupabaseService().updateUserRole(_targetUser.id, newRole, actorId: _mobileNumber);
                  
                  if (mounted) {
                    setState(() {
                      _currentUserRole = newRole;
                      _isUpdatingRole = false;
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(currentlyAdmin ? 'Admin rights revoked. User is now ${newRole.name}' : 'Admin rights granted!'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                    
                    Future.delayed(const Duration(milliseconds: 2000), () {
                      if (mounted) _loadProfileData();
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() => _isUpdatingRole = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error updating role: $e')),
                    );
                  }
                }
              },
              icon: _isUpdatingRole 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(isTargetAdmin ? Icons.person_remove_outlined : Icons.admin_panel_settings),
              label: Text(
                _isUpdatingRole ? 'LOADING...' : (isTargetAdmin ? 'Revoke Admin Role' : 'Assign Admin Role'),
                style: GoogleFonts.inter(fontWeight: FontWeight.bold)
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isTargetAdmin ? Colors.red[50] : theme.colorScheme.primary,
                foregroundColor: isTargetAdmin ? Colors.red[700] : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHierarchyManagementSection(ThemeData theme) {
    bool isGeneralMembership = _selectedCategory == 'General Membership';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_outlined, color: Colors.orange[800]),
              const SizedBox(width: 12),
              Text(
                'Organizational Hierarchy',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Current Position: ${FormatUtils.formatDesignation(_targetUser)}',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            hint: Text('Select Category', style: GoogleFonts.inter(fontSize: 14)),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Select Category'),
              ),
              ..._hierarchyData.keys.map((cat) => DropdownMenuItem(
                value: cat,
                child: Text(cat, style: GoogleFonts.inter(fontSize: 14)),
              )),
            ],
            onChanged: (val) {
              setState(() {
                _selectedCategory = val;
                _selectedPosition = null; 
                _selectedLevel = null;
              });
            },
            decoration: InputDecoration(
              labelText: 'Step 1: Category',
              labelStyle: GoogleFonts.inter(color: Colors.orange[800], fontWeight: FontWeight.bold),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey[50],
            ),
          ),
          
          if (_selectedCategory != null) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedPosition,
              hint: Text('Select Position', style: GoogleFonts.inter(fontSize: 14)),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Select Position'),
                ),
                ..._hierarchyData[_selectedCategory!]!.map((pos) => DropdownMenuItem(
                  value: pos,
                  child: Text(pos, style: GoogleFonts.inter(fontSize: 14)),
                )),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedPosition = val;
                });
              },
              decoration: InputDecoration(
                labelText: 'Step 2: Position',
                labelStyle: GoogleFonts.inter(color: Colors.orange[800], fontWeight: FontWeight.bold),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ],

          if (_selectedPosition != null && !isGeneralMembership) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedLevel,
              hint: Text('Select Level', style: GoogleFonts.inter(fontSize: 14)),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Select Level'),
                ),
                ..._hierarchyLevels.map((lvl) => DropdownMenuItem(
                  value: lvl,
                  child: Text(lvl, style: GoogleFonts.inter(fontSize: 14)),
                )),
              ],
              onChanged: (val) => setState(() => _selectedLevel = val),
              decoration: InputDecoration(
                labelText: 'Step 3: Organization Level',
                labelStyle: GoogleFonts.inter(color: Colors.orange[800], fontWeight: FontWeight.bold),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ],
          
          if (_selectedPosition != null && (isGeneralMembership || _selectedLevel != null)) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isUpdatingPosition ? null : () async {
                  setState(() => _isUpdatingPosition = true);
                  try {
                    final fullPosition = isGeneralMembership 
                        ? _selectedPosition! 
                        : '$_selectedLevel $_selectedPosition';
                        
                    await SupabaseService().updateUserPosition(_targetUser.id, fullPosition, actorId: _mobileNumber);
                    
                    UserRole autoRole = UserRole.moderator;
                    if (isGeneralMembership) {
                      autoRole = UserRole.member;
                    } else if (fullPosition == 'State President' || fullPosition == 'National President') {
                      autoRole = UserRole.admin;
                    }
                    
                    if (_targetUser.userRole != UserRole.superUser) {
                      if (_targetUser.userRole != autoRole) {
                        await SupabaseService().updateUserRole(_targetUser.id, autoRole, actorId: _mobileNumber);
                      }
                    }

                    if (mounted) {
                      setState(() {
                        _userPosition = fullPosition;
                        _currentUserRole = (_targetUser.userRole == UserRole.superUser) ? UserRole.superUser : autoRole;
                        _selectedLevel = null;
                        _selectedCategory = null;
                        _selectedPosition = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Position updated to $fullPosition successfully')),
                      );
                      
                      Future.delayed(const Duration(seconds: 1), () {
                        if (mounted) _loadProfileData();
                      });
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating position: $e')),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isUpdatingPosition = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[800],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isUpdatingPosition 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Update Member Position', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountSecuritySection(ThemeData theme) {
    final bool isBlocked = _targetUser.isBlocked;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security_outlined, color: Colors.red[800]),
              const SizedBox(width: 12),
              Text(
                'Account Security',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isBlocked 
              ? 'This account is currently blocked. User cannot log in or participate in events.'
              : 'Blocking user will log them out and they will not be able to log in or participate in events unless unblocked.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isBlockingUser ? null : () async {
                setState(() => _isBlockingUser = true);
                try {
                  final bool nextBlockStatus = !isBlocked;
                  await SupabaseService().toggleUserBlockStatus(_targetUser.id, nextBlockStatus, actorId: _mobileNumber);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(nextBlockStatus ? 'User successfully blocked' : 'User successfully unblocked')),
                    );
                    
                    Future.delayed(const Duration(seconds: 1), () {
                      if (mounted) {
                        _loadProfileData().then((_) {
                          setState(() {
                            _isBlockingUser = false;
                          });
                        });
                      }
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() => _isBlockingUser = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              icon: _isBlockingUser 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(isBlocked ? Icons.lock_open : Icons.block),
              label: Text(isBlocked ? 'Unblock User Account' : 'Block User Account', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isBlocked ? Colors.green[800] : Colors.red[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showInviteDialog() async {
    if (_myEvents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This user is already part of your events.')),
      );
      return;
    }

    ABKMEvent? selectedEvent = _myEvents[0];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Invite to Join Event', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select an event to invite this user to:', style: GoogleFonts.inter(fontSize: 14)),
              const SizedBox(height: 16),
              DropdownButtonFormField<ABKMEvent>(
                value: selectedEvent,
                items: _myEvents.map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e.title, style: GoogleFonts.inter(fontSize: 14)),
                )).toList(),
                onChanged: (val) => setDialogState(() => selectedEvent = val),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedEvent == null ? null : () async {
                try {
                  await SupabaseService().sendInvitation(
                    eventId: selectedEvent!.id,
                    hostId: _mobileNumber,
                    applicantId: _targetUser.id,
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Invitation sent for ${selectedEvent!.title}')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('Send Invite'),
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider? _getAvatarImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (imageUrl.startsWith('http')) {
      return NetworkImage(imageUrl);
    }
    try {
      return MemoryImage(base64Decode(imageUrl));
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
      return null;
    }
  }
}
