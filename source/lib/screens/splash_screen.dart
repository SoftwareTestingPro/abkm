import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _startTimerAndCheckLogin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-cache background and logo for seamless transition
    precacheImage(const AssetImage('assets/images/app_background.png'), context);
    precacheImage(const AssetImage('assets/images/logo_large.png'), context);
  }

  Future<void> _startTimerAndCheckLogin() async {
    // Run the splash display timer and login status check in parallel
    final stopwatch = Stopwatch()..start();
    
    bool isLoggedIn = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      isLoggedIn = (prefs.getBool('abkm_isLoggedIn') ?? false) && 
                   prefs.getString('abkm_mobileNumber') != null;
    } catch (e) {
      debugPrint('Error loading preferences in Splash: $e');
    }

    final elapsedMs = stopwatch.elapsedMilliseconds;
    // Cold start splash duration is now incredibly fast (1200ms) for high-end look
    const splashDurationMs = 1200;
    
    // Wait for the remaining time if database/shared preferences loaded faster
    if (elapsedMs < splashDurationMs) {
      await Future.delayed(Duration(milliseconds: splashDurationMs - elapsedMs));
    }

    if (!mounted) return;
    
    // Navigate cleanly using pushReplacement so user cannot back into splash screen
    if (isLoggedIn) {
      Navigator.of(context).pushReplacementNamed('/home');
    } else {
      Navigator.of(context).pushReplacementNamed('/auth');
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
              padding: const EdgeInsets.all(24.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
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
                      constraints: const BoxConstraints(maxHeight: 75, maxWidth: 200),
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
                                        size: 32,
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
                    const SizedBox(height: 20),
                    Text(
                      'अखिल भारतीय कुशवाहा महासभा',
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
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
}
