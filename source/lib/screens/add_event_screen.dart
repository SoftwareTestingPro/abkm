import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/event_logic.dart';
import '../services/logic_service.dart';
import '../widgets/location_selectors.dart';

class AddEventScreen extends StatefulWidget {
  final ABKMEvent? eventToEdit;
  final VoidCallback? onSaveComplete;
  final bool isTabMode;
  const AddEventScreen({super.key, this.eventToEdit, this.onSaveComplete, this.isTabMode = false});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  final _descriptionController = TextEditingController();
  
  final _stateController = TextEditingController();
  final _districtController = TextEditingController();
  final _tehsilController = TextEditingController();
  final _villageController = TextEditingController();
  final _meetingPointController = TextEditingController();
  
  final _stateFocusNode = FocusNode();
  final _districtFocusNode = FocusNode();
  final _tehsilFocusNode = FocusNode();
  final _villageFocusNode = FocusNode();
  final _meetingPointFocusNode = FocusNode();

  Timer? _debounceTimer;

  late EventType _selectedType;
  late DateTime _selectedDate;
  String? _imageUrl;
  UserRole _userRole = UserRole.member;
  bool _isSaving = false;

  final ImagePicker _picker = ImagePicker();

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
            Text('Event Image Source', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Upload from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                _executePickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Capture with Camera'),
              onTap: () async {
                Navigator.pop(context);
                _executePickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executePickImage(ImageSource source, [CameraDevice? device]) async {
    try {
      final XFile? imageFile = await _picker.pickImage(
        source: source,
        preferredCameraDevice: device ?? CameraDevice.rear,
        imageQuality: 30,
        maxWidth: 600,
      );
      
      if (imageFile != null) {
        final bytes = await imageFile.readAsBytes();
        final decodedImage = img.decodeImage(bytes);
        if (decodedImage != null) {
          img.Image resizedImage = decodedImage;
          if (decodedImage.width > 800) {
            resizedImage = img.copyResize(decodedImage, width: 800);
          }
          final jpgBytes = img.encodeJpg(resizedImage, quality: 80);
          final base64String = base64Encode(jpgBytes);
          if (mounted) {
            setState(() {
              _imageUrl = base64String;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting image: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.eventToEdit?.title);
    _descriptionController.text = widget.eventToEdit?.description ?? '';
    
    if (widget.eventToEdit != null) {
      _stateController.text = widget.eventToEdit!.state;
      _districtController.text = widget.eventToEdit!.district; 
      _villageController.text = widget.eventToEdit!.village;
      _tehsilController.text = widget.eventToEdit!.tehsil;
      _meetingPointController.text = widget.eventToEdit!.meetingPoint ?? '';
    } else {
      _stateController.text = '';
    }
    
    _selectedType = widget.eventToEdit?.eventType ?? EventType.meeting;
    _selectedDate = widget.eventToEdit?.date ?? DateTime.now().add(const Duration(days: 7));
    _imageUrl = widget.eventToEdit?.imageUrl;
    _loadUserRoleAndState();
  }

  Future<void> _loadUserRoleAndState() async {
    final prefs = await SharedPreferences.getInstance();
    final roleIndex = prefs.getInt('abkm_user_role') ?? 0;
    
    String userState = '';
    if (widget.eventToEdit != null) {
      userState = widget.eventToEdit!.state;
    } else {
      userState = prefs.getString('abkm_userState') ?? prefs.getString('abkm_user_state') ?? '';
      if (userState.isEmpty) {
        final userId = prefs.getString('abkm_user_id') ?? prefs.getString('abkm_mobileNumber');
        if (userId != null) {
          try {
            final profile = await SupabaseService().getProfile(userId);
            if (profile != null && profile.state.isNotEmpty) {
              userState = profile.state;
            }
          } catch (_) {}
        }
      }
    }

    if (mounted) {
      setState(() {
        _userRole = UserRole.values[roleIndex];
        if (userState.isNotEmpty) {
          _stateController.text = userState;
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stateController.dispose();
    _districtController.dispose();
    _tehsilController.dispose();
    _villageController.dispose();
    _meetingPointController.dispose();
    _stateFocusNode.dispose();
    _districtFocusNode.dispose();
    _tehsilFocusNode.dispose();
    _villageFocusNode.dispose();
    _meetingPointFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().isBefore(_selectedDate) ? DateTime.now() : _selectedDate,
      lastDate: DateTime(2101),
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
    if (picked != null && picked != _selectedDate) {
      if (mounted) {
        setState(() {
          _selectedDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _selectedDate.hour,
            _selectedDate.minute,
          );
        });
      }
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (picked != null) {
      final now = DateTime.now();
      final newDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        picked.hour,
        picked.minute,
      );

      if (newDateTime.isBefore(now)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Selected time is in the past. Please select a future time.')),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _selectedDate = newDateTime;
        });
      }
    }
  }

  Future<void> _saveEvent() async {
    if (_isSaving) return; // Guard against double-tap
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        // Format text to Title Case (Camel Case) for consistent storage and display
        _titleController.text = FormatUtils.toTitleCase(_titleController.text);
        _tehsilController.text = FormatUtils.toTitleCase(_tehsilController.text);
        _villageController.text = FormatUtils.toTitleCase(_villageController.text);
        _meetingPointController.text = FormatUtils.toTitleCase(_meetingPointController.text);

        if (_selectedType != EventType.announcement && _districtController.text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a valid district')),
          );
          return;
        }

        if (_selectedDate.isBefore(DateTime.now())) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event cannot be scheduled in the past. Please select a future time.')),
          );
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final userId = prefs.getString('abkm_user_id') ?? prefs.getString('abkm_mobileNumber') ?? 'anonymous';
        
        // Guard against editing approved events by non-admins
        if (widget.eventToEdit != null && widget.eventToEdit!.isApproved && _userRole.index < UserRole.admin.index) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Approved events cannot be edited by Moderators.')),
            );
          }
          return;
        }

        String announcementState = '';
        if (_selectedType == EventType.announcement) {
          try {
            final creatorProfile = await SupabaseService().getProfile(widget.eventToEdit?.hostId ?? userId);
            if (!mounted) return;
            if (creatorProfile != null) {
              final pos = creatorProfile.position.trim();
              if (pos.toLowerCase().startsWith('state')) {
                announcementState = creatorProfile.state;
              }
            }
          } catch (e) {
            debugPrint('Error fetching announcement creator profile: $e');
          }
        }

        final event = ABKMEvent(
          id: widget.eventToEdit?.id ?? const Uuid().v4(),
          hostId: widget.eventToEdit?.hostId ?? userId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          date: _selectedDate,
          village: _selectedType == EventType.announcement ? '' : _villageController.text.trim(),
          eventType: _selectedType,
          approvedMemberIds: widget.eventToEdit?.approvedMemberIds ?? [],
          imageUrl: _selectedType == EventType.announcement ? '' : (_imageUrl ?? EventLogic.getDefaultImageUrl(_selectedType)),
          district: _selectedType == EventType.announcement ? '' : _districtController.text,
          state: _selectedType == EventType.announcement ? announcementState : _stateController.text,
          tehsil: _selectedType == EventType.announcement ? '' : _tehsilController.text,
          meetingPoint: _selectedType == EventType.announcement ? '' : _meetingPointController.text.trim(),
          isApproved: _userRole.index >= UserRole.admin.index,
        );

        if (widget.eventToEdit == null) {
          await SupabaseService().createEvent(event);
          if (!mounted) return;
          if (!event.isApproved) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Event created! It will be visible after Admin approval.')),
            );
          }
        } else {
          await SupabaseService().updateEvent(event);
          if (!mounted) return;
        }

        final eventsJson = prefs.getString('abkm_events') ?? '[]';
        List<dynamic> eventsList = json.decode(eventsJson);
        if (widget.eventToEdit == null) {
          eventsList.add(event.toJson());
        } else {
          final index = eventsList.indexWhere((e) => e['id'] == event.id);
          if (index != -1) {
            eventsList[index] = event.toJson();
          } else {
            eventsList.add(event.toJson());
          }
        }
        await prefs.setString('abkm_events', json.encode(eventsList));
        if (!mounted) return;

        if (widget.onSaveComplete != null) {
          widget.onSaveComplete!();
        } else {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving event: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.white,
      appBar: widget.isTabMode 
        ? null 
        : AppBar(
            title: null,
            elevation: 0,
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
      body: Stack(
        children: [
          _buildPageBackground(),
          SafeArea(
            child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isTabMode) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Create New Event',
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF8B0000), // Match the red theme
                        ),
                      ),
                    ),
                    Text(
                      'Organize a community gathering, meeting or announcement.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                  _buildSectionTitle('Event Category'),
                  const SizedBox(height: 12),
                  _buildEventTypeSelector(),
                  const SizedBox(height: 24),
                  _buildTextField('Event Title', _titleController, _selectedType == EventType.announcement ? 'e.g., Important Platform Maintenance' : 'e.g., Community Gathering for Justice'),
                  const SizedBox(height: 20),
                  _buildTextField('Description', _descriptionController, _selectedType == EventType.announcement ? 'Enter details of the announcement to be displayed to users.' : 'Provide details about the agenda and purpose of the meeting.', maxLines: 4),
                  if (_selectedType != EventType.announcement) ...[
                    const SizedBox(height: 24),
                    _buildSectionTitle('Event Cover Image (Optional)'),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickImage,
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                          image: _imageUrl != null && _imageUrl!.isNotEmpty
                              ? DecorationImage(
                                  image: _imageUrl!.startsWith('assets/')
                                      ? AssetImage(_imageUrl!) as ImageProvider
                                      : MemoryImage(base64Decode(_imageUrl!)),
                                  fit: BoxFit.cover,
                                )
                              : DecorationImage(
                                  image: AssetImage(EventLogic.getDefaultImageUrl(_selectedType)),
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: Text('Upload Custom Image', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Location Details'),
                    const SizedBox(height: 12),
                    LocationSelectors(
                      stateController: _stateController,
                      districtController: _districtController,
                      tehsilController: _tehsilController,
                      villageController: _villageController,
                      meetingPointController: _meetingPointController,
                      stateFocusNode: _stateFocusNode,
                      districtFocusNode: _districtFocusNode,
                      tehsilFocusNode: _tehsilFocusNode,
                      villageFocusNode: _villageFocusNode,
                      meetingPointFocusNode: _meetingPointFocusNode,
                      isStateLocked: true,
                      onChanged: () => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildSectionTitle(_selectedType == EventType.announcement ? 'Announcement Auto-Deletion Date & Time' : 'Date & Time'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDate(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 20, color: Colors.grey),
                                const SizedBox(width: 12),
                                Text(
                                  EventLogic.formatDate(_selectedDate),
                                  style: GoogleFonts.inter(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectTime(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 20, color: Colors.grey),
                                const SizedBox(width: 12),
                                Text(
                                  EventLogic.formatTime(_selectedDate),
                                  style: GoogleFonts.inter(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveEvent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isSaving
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            widget.eventToEdit == null 
                                ? 'Create ${FormatUtils.toTitleCase(_selectedType.name)}' 
                                : 'Update ${FormatUtils.toTitleCase(_selectedType.name)}',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);
}

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(label),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.grey, fontSize: 14),
            contentPadding: const EdgeInsets.all(16),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
          ),
          validator: (value) => value == null || value.isEmpty ? 'Please enter $label' : null,
        ),
      ],
    );
  }

  Widget _buildEventTypeSelector() {
    final allowedTypes = EventType.values.where((type) {
      if (type == EventType.protest) {
        return false; // Protest is streamlined/merged into Dharna
      }
      if (type == EventType.announcement) {
        return _userRole == UserRole.admin || _userRole == UserRole.superUser;
      }
      return true;
    }).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allowedTypes.map((type) {
        final isSelected = _selectedType == type;
        IconData icon;
        switch (type) {
          case EventType.meeting: icon = Icons.groups; break;
          case EventType.rally: icon = Icons.campaign; break;
          case EventType.andolan: icon = Icons.flag; break;
          case EventType.dharna: icon = Icons.accessibility_new; break;
          case EventType.conference: icon = Icons.business_center; break;
          case EventType.protest: icon = Icons.gavel; break;
          case EventType.other: icon = Icons.more_horiz; break;
          case EventType.announcement: icon = Icons.notifications_active; break;
        }

        return ChoiceChip(
          avatar: Icon(icon, size: 16, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
          label: Text(type.name.replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}').toUpperCase()),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _selectedType = type;
                if (_imageUrl != null && _imageUrl!.startsWith('assets/')) {
                  _imageUrl = null;
                }
              });
            }
          },
          selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          labelStyle: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[600],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: BorderSide(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[300]!),
        );
      }).toList(),
    );
  }
}
