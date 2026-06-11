import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_screen.dart';
import 'home_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/logic_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isOtpSent = false;
  bool _isLoading = false;
  final String _staticOtp = "1234";
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-cache the background image for smoother transition
    precacheImage(const AssetImage('assets/images/app_background.png'), context);
  }

  Future<void> _sendOtp() async {
    if (_phoneController.text.length == 4) {
      _otpController.clear();
      setState(() => _isOtpSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP sent: 1234 (Static)')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a 4-digit Mobile Number')),
      );
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text == _staticOtp) {
      FocusScope.of(context).unfocus();
      setState(() => _isLoading = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        final String? oldMobileNumber = prefs.getString('abkm_mobileNumber');
        final String currentMobileNumber = _phoneController.text;

        // If a different user is logging in, clear previous local profile data
        if (oldMobileNumber != null && oldMobileNumber != currentMobileNumber) {
          final keysToRemove = [
            'abkm_hasProfile', 'abkm_userName', 'abkm_userBio', 'abkm_userCity', 'abkm_userState', 
            'abkm_userDistrict', 'abkm_userTehsil', 'abkm_userVillage', 'abkm_userSector',
            'abkm_userProfession', 'abkm_userEducation', 
            'abkm_userImageBase64', 'abkm_userGender', 'abkm_userAge', 'abkm_user_role'
          ];
          for (final key in keysToRemove) {
            await prefs.remove(key);
          }
        }

        await prefs.setString('abkm_mobileNumber', currentMobileNumber);
        
        // Check cloud profile (only returns active/non-deleted profiles)
        final cloudProfile = await SupabaseService().getProfile(currentMobileNumber, forceRefresh: true);
        
        if (cloudProfile != null && cloudProfile.userRole == UserRole.blocked) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          
          final blocker = await SupabaseService().getBlockerProfile(cloudProfile.id);
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
                  onPressed: () => Navigator.pop(context),
                  child: Text('OK', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          return;
        }

        // ── Soft-deleted account check ────────────────────────────────
        // getProfile returns null for both new users AND soft-deleted accounts.
        // Check if a deleted row exists before treating this as a brand new user.
        if (cloudProfile == null) {
          final deletedProfile = await SupabaseService().getDeletedProfile(currentMobileNumber);
          if (deletedProfile != null) {
            if (!mounted) return;
            setState(() => _isLoading = false);

            final reactivate = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Row(
                  children: [
                    Icon(Icons.restore, color: Colors.orange[700]),
                    const SizedBox(width: 12),
                    Text('Account Found', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Text(
                  'This mobile number had a previously deleted account.\n\n'
                  'Would you like to re-create your profile? '
                  'Your referral chain and membership points history will be preserved.',
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[800]),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel', style: GoogleFonts.inter()),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Re-create Profile', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );

            if (reactivate == true) {
              if (!mounted) return;
              setState(() => _isLoading = true);
              await SupabaseService().reactivateProfile(currentMobileNumber);
              await prefs.setBool('abkm_hasProfile', false);
              await prefs.setBool('abkm_isLoggedIn', false);
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil('/profile', (route) => false);
            }
            // else: user cancelled — stay on auth screen
            return;
          }
        }
        // ─────────────────────────────────────────────────────────────

        final bool hasProfile = (cloudProfile != null);
        await prefs.setBool('abkm_hasProfile', hasProfile);
        await prefs.setBool('abkm_isLoggedIn', hasProfile);
        if (cloudProfile != null) {
          await prefs.setInt('abkm_user_role', cloudProfile.userRole.index);
          await SupabaseService().updateLastLogin(currentMobileNumber);
        }

        if (!mounted) return;
        
        if (hasProfile) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        } else {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/profile', (route) => false);
        }
      } catch (e) {
        debugPrint('Error during OTP verification: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP. Use 1234')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Stack(
        children: [
          _buildBackground(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
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
                    const SizedBox(height: 24),
                    Text(
                      'अखिल भारतीय कुशवाहा महासभा',
                      style: theme.textTheme.displayLarge?.copyWith(fontSize: 22),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isOtpSent ? 'Enter the OTP sent to your phone' : 'शिक्षित बनो, संगठित रहो, संघर्ष करो',
                      style: GoogleFonts.inter(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (!_isOtpSent) ...[
                      _buildTextField(
                        controller: _phoneController,
                        hint: '4-Digit Mobile Number',
                        icon: Icons.phone_android,
                        keyboardType: TextInputType.phone,
                        maxLength: 4,
                      ),
                      const SizedBox(height: 24),
                      _buildButton(
                        text: 'Send OTP',
                        onPressed: _sendOtp,
                      ),
                    ] else ...[
                      _buildTextField(
                        controller: _otpController,
                        hint: 'Enter 4-digit OTP',
                        icon: Icons.lock_outline,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                      ),
                      const SizedBox(height: 24),
                      _buildButton(
                        text: 'Verify & Login',
                        onPressed: _verifyOtp,
                      ),
                      TextButton(
                        onPressed: () {
                          _otpController.clear();
                          setState(() => _isOtpSent = false);
                        },
                        child: const Text('Change Number'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => _showPrivacyPolicy(context),
                      child: Text(
                        'Privacy Policy',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[600],
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
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
                          'Verifying...',
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
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/app_background.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.grey),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        counterText: "",
      ),
    );
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

  Widget _buildButton({required String text, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
