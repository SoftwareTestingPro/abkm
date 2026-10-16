import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/config.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-cache the background image for smoother transition
    precacheImage(const AssetImage('assets/images/app_background.png'), context);
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? AppConfig.googleWebClientId : null,
        scopes: ['email'],
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      ABKMUser? cloudProfile = await SupabaseService().getProfileByGoogleId(googleUser.id);
      
      // Fallback: If not found by google_id, check if user exists with the same email
      if (cloudProfile == null && googleUser.email.isNotEmpty) {
        final emailProfile = await SupabaseService().getProfileByEmail(googleUser.email);
        if (emailProfile != null) {
          final linkedUser = emailProfile.copyWith(
            googleId: googleUser.id,
            email: googleUser.email,
          );
          await SupabaseService().upsertProfile(linkedUser);
          cloudProfile = linkedUser;
        }
      }

      final prefs = await SharedPreferences.getInstance();

      if (cloudProfile != null) {
        await prefs.setString('abkm_mobileNumber', cloudProfile.id);
        await prefs.setBool('abkm_hasProfile', true);
        await prefs.setBool('abkm_isLoggedIn', true);
        await prefs.setInt('abkm_user_role', cloudProfile.userRole.index);
        await SupabaseService().updateLastLogin(cloudProfile.id);

        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      } else {
        final tempUser = ABKMUser(
          id: '',
          name: googleUser.displayName ?? '',
          profileImageUrl: googleUser.photoUrl,
          email: googleUser.email,
          googleId: googleUser.id,
          userRole: UserRole.member,
          bio: '',
          gender: 'Select Gender',
        );

        if (!mounted) return;
        setState(() => _isLoading = false);
        
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/profile',
          (route) => false,
          arguments: tempUser,
        );
      }
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In failed: ${e.toString()}')),
        );
      }
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
                      'शिक्षित बनो, संगठित रहो, संघर्ष करो',
                      style: GoogleFonts.inter(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          backgroundColor: Colors.white,
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://developers.google.com/static/identity/images/g-logo.png',
                              height: 24,
                              width: 24,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata, color: Colors.blue, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Continue with Google',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                        '• Contact: Mobile Number for identification and records.\n'
                        '• Community: Profession, Education, and Location.\n'
                        '• Interaction: Event applications and activities.'),
                      _policySection('2. How We Use Data', 
                        'Your information is used for:\n'
                        '• Community directory connections.\n'
                        '• Event management.\n'
                        '• Member identification.\n'
                        '• Feature improvements.'),
                      _policySection('3. Data Deletion', 
                        'You can delete your entire profile and associated data via Profile > Delete Profile button. This is permanent.'),
                      _policySection('4. Data Security', 
                        'We use industry-standard security (Supabase RLS) to protect your data.'),
                      _policySection('5. Third-Party', 
                        'We use Supabase for database and storage.'),
                      _policySection('6. Contact', 
                        'Questions? Contact: support@futurelab.co.in'),
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
}
