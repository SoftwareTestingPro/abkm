import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFFFF5722); // Deep Orange from ABKM logo
  static const Color accentColor = Color(0xFFB8860B); // Dark Goldenrod
  static const Color backgroundColor = Color(0xFFFAFAFA); // Clean modern off-white
  static const Color surfaceColor = Colors.white;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: accentColor,
        surface: surfaceColor,
        background: backgroundColor,
      ),
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        displayLarge: GoogleFonts.poppins(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: primaryColor,
        ),
        headlineMedium: GoogleFonts.poppins(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: primaryColor,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          color: Colors.black87,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 8,
        shadowColor: primaryColor.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
