import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fixit_app_a186687/views/pages/auth/welcome_screen.dart';
import 'package:fixit_app_a186687/views/widget_tree.dart';
import 'package:flutter/material.dart';
// *** NEW: Import for Google Fonts ***
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

// *** MODIFIED: Added SingleTickerProviderStateMixin for animation ***
class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {

  // *** NEW: Animation controller for the scale effect ***
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // *** NEW: Initialize animation ***
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
    
    // Existing logic to check auth state remains unchanged
    Timer(const Duration(seconds: 3), _checkAuthState); // Increased duration slightly for animation
  }
  
  // *** NEW: Dispose animation controller ***
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthState() async {
    final user = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (user != null) {
      // User is logged in, get their role and go to the main app
      try {
        final ref = FirebaseDatabase.instance.ref().child('users').child(user.uid);
        final snapshot = await ref.get();
        if (mounted && snapshot.exists) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          final role = data['role'] as String?;
          if (role != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => WidgetTree(userRole: role)),
            );
          } else {
            // Role not found, go to welcome screen as a fallback
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            );
          }
        } else {
          // User data not found, go to welcome screen
           Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            );
        }
      } catch (e) {
        // Error fetching data, go to welcome screen
         Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          );
      }
    } else {
      // User is not logged in, go to the welcome screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // *** MODIFIED: Updated UI to match WelcomeScreen style ***
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App title with matching style and animation
            ScaleTransition(
              scale: _scaleAnimation,
              child: Text(
                'Fixit',
                style: GoogleFonts.poppins(
                  fontSize: 96,
                  fontWeight: FontWeight.w900,
                  color: Colors.blue[800],
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // App logo image
            SizedBox(
              height: 250, // Constrain image size
              width: 250,
              child: Image.asset('assets/images/splash_screen.png'),
            ),
            const SizedBox(height: 40),

            // Loading indicator
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading your experience...',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
