import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/supabase_service.dart';

class LocationSelectors extends StatefulWidget {
  final TextEditingController stateController;
  final TextEditingController districtController;
  final TextEditingController tehsilController;
  final TextEditingController villageController;
  final TextEditingController? meetingPointController;

  final FocusNode? stateFocusNode;
  final FocusNode? districtFocusNode;
  final FocusNode? tehsilFocusNode;
  final FocusNode? villageFocusNode;
  final FocusNode? meetingPointFocusNode;

  final String? errorField;
  final Function(String?)? onErrorFieldChanged;
  final VoidCallback? onChanged;
  final bool isStateLocked;
  final bool isEnabled;
  final VoidCallback? onUnlockRequest;

  const LocationSelectors({
    super.key,
    required this.stateController,
    required this.districtController,
    required this.tehsilController,
    required this.villageController,
    this.meetingPointController,
    this.stateFocusNode,
    this.districtFocusNode,
    this.tehsilFocusNode,
    this.villageFocusNode,
    this.meetingPointFocusNode,
    this.errorField,
    this.onErrorFieldChanged,
    this.onChanged,
    this.isStateLocked = false,
    this.isEnabled = true,
    this.onUnlockRequest,
  });

  @override
  State<LocationSelectors> createState() => _LocationSelectorsState();
}

class _LocationSelectorsState extends State<LocationSelectors> {
  late String _selectedState;
  late String _selectedDistrict;
  late String _selectedTehsil;
  late String _selectedVillage;

  @override
  void initState() {
    super.initState();
    _selectedState = widget.stateController.text;
    _selectedDistrict = widget.districtController.text;
    _selectedTehsil = widget.tehsilController.text;
    _selectedVillage = widget.villageController.text;

    // Listen to parent text controllers to keep local states in sync (e.g. on profile loaded)
    widget.stateController.addListener(_onStateTextChanged);
    widget.districtController.addListener(_onDistrictTextChanged);
    widget.tehsilController.addListener(_onTehsilTextChanged);
    widget.villageController.addListener(_onVillageTextChanged);
  }

  @override
  void dispose() {
    widget.stateController.removeListener(_onStateTextChanged);
    widget.districtController.removeListener(_onDistrictTextChanged);
    widget.tehsilController.removeListener(_onTehsilTextChanged);
    widget.villageController.removeListener(_onVillageTextChanged);
    super.dispose();
  }

  void _onStateTextChanged() {
    if (widget.stateController.text != _selectedState) {
      if (mounted) {
        setState(() => _selectedState = widget.stateController.text);
      }
    }
  }

  void _onDistrictTextChanged() {
    if (widget.districtController.text != _selectedDistrict) {
      if (mounted) {
        setState(() => _selectedDistrict = widget.districtController.text);
      }
    }
  }

  void _onTehsilTextChanged() {
    if (widget.tehsilController.text != _selectedTehsil) {
      if (mounted) {
        setState(() => _selectedTehsil = widget.tehsilController.text);
      }
    }
  }

  void _onVillageTextChanged() {
    if (widget.villageController.text != _selectedVillage) {
      if (mounted) {
        setState(() => _selectedVillage = widget.villageController.text);
      }
    }
  }

  void _notifyChange() {
    if (widget.onChanged != null) {
      widget.onChanged!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isStateSelected = _selectedState.isNotEmpty;
    final bool isDistrictSelected = _selectedDistrict.isNotEmpty;
    final bool isTehsilSelected = _selectedTehsil.isNotEmpty;

    return Column(
      children: [
        // State autocomplete
        _buildLocationAutocomplete(
          controller: widget.stateController,
          focusNode: widget.stateFocusNode,
          hint: 'State',
          icon: Icons.location_on_outlined,
          type: 'state',
          enabled: widget.isEnabled && !widget.isStateLocked,
          fieldKey: 'state',
          onSelected: (val) {
            setState(() {
              _selectedState = val;
              _selectedDistrict = '';
              _selectedTehsil = '';
              _selectedVillage = '';
              widget.districtController.clear();
              widget.tehsilController.clear();
              widget.villageController.clear();
            });
            _notifyChange();
          },
        ),
        const SizedBox(height: 12),
        // District autocomplete
        Opacity(
          opacity: (widget.isEnabled && !isStateSelected) ? 0.5 : 1.0,
          child: _buildLocationAutocomplete(
            controller: widget.districtController,
            focusNode: widget.districtFocusNode,
            hint: 'District',
            icon: Icons.location_city_outlined,
            type: 'district',
            enabled: widget.isEnabled && isStateSelected,
            fieldKey: 'district',
            onSelected: (val) {
              setState(() {
                _selectedDistrict = val;
                _selectedTehsil = '';
                _selectedVillage = '';
                widget.tehsilController.clear();
                widget.villageController.clear();
              });
              _notifyChange();
            },
          ),
        ),
        const SizedBox(height: 12),
        // Tehsil autocomplete
        Opacity(
          opacity: (widget.isEnabled && !isDistrictSelected) ? 0.5 : 1.0,
          child: _buildLocationAutocomplete(
            controller: widget.tehsilController,
            focusNode: widget.tehsilFocusNode,
            hint: 'Tehsil',
            icon: Icons.map_outlined,
            type: 'tehsil',
            enabled: widget.isEnabled && isDistrictSelected,
            fieldKey: 'tehsil',
            onSelected: (val) {
              setState(() {
                _selectedTehsil = val;
                _selectedVillage = '';
                widget.villageController.clear();
              });
              _notifyChange();
            },
          ),
        ),
        const SizedBox(height: 12),
        // Village autocomplete
        Opacity(
          opacity: (widget.isEnabled && !isTehsilSelected) ? 0.5 : 1.0,
          child: _buildLocationAutocomplete(
            controller: widget.villageController,
            focusNode: widget.villageFocusNode,
            hint: 'Village / Locality',
            icon: Icons.home_work_outlined,
            type: 'village',
            enabled: widget.isEnabled && isTehsilSelected,
            fieldKey: 'village',
            onSelected: (val) {
              setState(() {
                _selectedVillage = val;
              });
              _notifyChange();
            },
          ),
        ),
        // Optional Custom Meeting Point (only displayed if controller is provided)
        if (widget.meetingPointController != null) ...[
          const SizedBox(height: 12),
          Opacity(
            opacity: (widget.isEnabled && !isDistrictSelected) ? 0.5 : 1.0,
            child: _buildLocationAutocomplete(
              controller: widget.meetingPointController!,
              focusNode: widget.meetingPointFocusNode,
              hint: 'Specific Meeting Point (e.g. Near Shiv Mandir)',
              icon: Icons.pin_drop_outlined,
              type: 'custom',
              enabled: widget.isEnabled && isDistrictSelected,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocationAutocomplete({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hint,
    required IconData icon,
    required String type,
    bool enabled = true,
    Function(String)? onSelected,
    String? fieldKey,
  }) {
    return Autocomplete<String>(
      focusNode: focusNode,
      textEditingController: controller,
      displayStringForOption: (String option) => option,
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (!mounted) return const Iterable<String>.empty();
        if (!enabled || type == 'custom') return const Iterable<String>.empty();

        final query = textEditingValue.text.trim();

        // Threshold of 1 character for rapid lookups
        if (query.isEmpty) {
          return const Iterable<String>.empty();
        }

        try {
          final Iterable<String> results;
          if (type == 'state') {
            results = await SupabaseService().getUniqueStates(query: query);
          } else {
            results = await SupabaseService().getLocationSuggestions(
              type: type,
              state: _selectedState,
              district: _selectedDistrict,
              tehsil: type == 'village' ? widget.tehsilController.text : null,
              query: query,
            );
          }
          if (!mounted) return const Iterable<String>.empty();
          return results;
        } catch (e) {
          debugPrint('Error in LocationSelectors optionsBuilder: $e');
          return const Iterable<String>.empty();
        }
      },
      onSelected: (String selection) {
        controller.text = selection;
        controller.selection = TextSelection.collapsed(offset: selection.length);
        if (onSelected != null) onSelected(selection);
        setState(() {});
      },
      fieldViewBuilder: (context, textController, focusNodeAutocomplete, onFieldSubmitted) {
        final hasError = widget.errorField == fieldKey;
        final theme = Theme.of(context);

        return TextFormField(
          controller: textController,
          focusNode: focusNodeAutocomplete,
          enabled: enabled,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: enabled ? Colors.black87 : Colors.grey[500],
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(
              icon, 
              size: 20, 
              color: hasError 
                  ? Colors.red 
                  : (enabled ? Colors.grey : Colors.grey[400]),
            ),
            hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14),
            suffixIcon: (type == 'state' && widget.isStateLocked)
                ? const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: Colors.grey,
                  )
                : (!widget.isEnabled
                    ? (widget.onUnlockRequest != null
                        ? IconButton(
                            icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                            onPressed: widget.onUnlockRequest,
                          )
                        : null)
                    : null),
            contentPadding: const EdgeInsets.all(16),
            filled: true,
            fillColor: hasError 
                ? Colors.red.withOpacity(0.05) 
                : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: hasError 
                    ? Colors.red 
                    : Colors.grey[300]!, 
                width: hasError ? 2 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: hasError 
                    ? Colors.red 
                    : Colors.grey[200]!, 
                width: hasError ? 2 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: hasError 
                    ? Colors.red 
                    : theme.colorScheme.primary, 
                width: 2,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
          ),
          onChanged: (val) {
            if (widget.errorField != null && widget.onErrorFieldChanged != null) {
              widget.onErrorFieldChanged!(null);
            }

            // Clean child selections if parent is manually modified or cleared
            if (type == 'state' && _selectedState.isNotEmpty) {
              setState(() {
                _selectedState = '';
                _selectedDistrict = '';
                _selectedTehsil = '';
                _selectedVillage = '';
                widget.districtController.clear();
                widget.tehsilController.clear();
                widget.villageController.clear();
              });
              _notifyChange();
            } else if (type == 'district' && _selectedDistrict.isNotEmpty) {
              setState(() {
                _selectedDistrict = '';
                _selectedTehsil = '';
                _selectedVillage = '';
                widget.tehsilController.clear();
                widget.villageController.clear();
              });
              _notifyChange();
            } else if (type == 'tehsil' && _selectedTehsil.isNotEmpty && val.isEmpty) {
              setState(() {
                _selectedTehsil = '';
                _selectedVillage = '';
                widget.villageController.clear();
              });
              _notifyChange();
            }
          },
        );
      },
    );
  }
}
