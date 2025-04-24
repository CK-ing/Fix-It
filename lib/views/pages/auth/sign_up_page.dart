import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher

import '../../widget_tree.dart';
import 'sign_in_page.dart';

class SignUpPage extends StatefulWidget {
 final String role;

 const SignUpPage({super.key, required this.role});

 @override
 State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
 // Controllers and Keys
 final _nameController = TextEditingController();
 final _emailController = TextEditingController();
 final _passwordController = TextEditingController();
 final _confirmPasswordController = TextEditingController();
 final _formKey = GlobalKey<FormState>();

 // State Variables
 bool _passwordVisible = false;
 bool _confirmPasswordVisible = false;
 bool _isLoading = false;
 bool _termsAccepted = false;

 // Firebase instances
 final FirebaseAuth _auth = FirebaseAuth.instance; // Added _auth instance
 final DatabaseReference _dbRef = FirebaseDatabase.instance.ref(); // Added _dbRef instance


 @override
 void dispose() {
   // Dispose controllers
   _nameController.dispose();
   _emailController.dispose();
   _passwordController.dispose();
   _confirmPasswordController.dispose();
   super.dispose();
 }

 // --- Helper Functions (Show SnackBar, Launch URL) ---
 void _showSnackBar(String message, {bool isError = true}) {
   if (!mounted) return;
   ScaffoldMessenger.of(context).showSnackBar(
     SnackBar(
       content: Text(message),
       backgroundColor: isError ? Colors.red[600] : Colors.green[600],
     )
   );
 }

 Future<void> _launchURL(String urlString) async {
   final Uri url = Uri.parse(urlString);
   if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
     _showSnackBar('Could not launch $urlString', isError: true);
   }
 }

 // --- Sign Up Logic (Email & Google - unchanged) ---
 Future<void> _signUpWithEmail() async {
   if (!_formKey.currentState!.validate()) { /* ... */ return; }
   if (!_termsAccepted) { /* ... */ return; }
   if (_isLoading) return;
   setState(() { _isLoading = true; });
   String name = _nameController.text.trim();
   String email = _emailController.text.trim();
   String password = _passwordController.text;
   String role = widget.role;
   try {
     final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password); // Use instance _auth
     if (cred.user == null) throw FirebaseAuthException(code: 'user-creation-failed');
     await _dbRef.child("users/${cred.user!.uid}").set({ // Use instance _dbRef
       'name': name, 'email': email, 'role': role, 'createdAt': ServerValue.timestamp,
     });
     if (!mounted) return;
     Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => WidgetTree(userRole: role)), (route) => false);
   } on FirebaseAuthException catch (e) {
     if (!mounted) return;
     String errorMessage = "Sign up failed. Please try again.";
     if (e.code == 'weak-password') errorMessage = 'The password provided is too weak.';
     else if (e.code == 'email-already-in-use') errorMessage = 'An account already exists for that email.';
     else if (e.code == 'invalid-email') errorMessage = 'The email address is not valid.';
     else print("FirebaseAuthException: ${e.code} - ${e.message}");
     _showSnackBar(errorMessage, isError: true);
   } catch (e) {
     if (!mounted) return; print("Sign Up Error: $e");
     _showSnackBar("An unexpected error occurred during sign up.", isError: true);
   } finally {
     if (mounted) setState(() { _isLoading = false; });
   }
 }

 Future<void> _signUpWithGoogle() async {
   if (!_termsAccepted) { /* ... */ return; }
   if (_isLoading) return;
   setState(() { _isLoading = true; });
   try {
     await GoogleSignIn().signOut();
     final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
     if (googleUser == null) { /* ... */ if (mounted) setState(() => _isLoading = false); return; }
     final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
     final credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
     final userCredential = await _auth.signInWithCredential(credential); // Use instance _auth
     final user = userCredential.user;
     if (user == null) throw FirebaseAuthException(code: 'google-user-null');
     final userSnapshot = await _dbRef.child("users/${user.uid}").get(); // Use instance _dbRef
     if (!mounted) return;
     if (userSnapshot.exists) {
       _showSnackBar("This Google account is already registered. Please sign in instead.", isError: true);
       await _auth.signOut(); await GoogleSignIn().signOut();
     } else {
       await _dbRef.child("users/${user.uid}").set({ // Use instance _dbRef
         'name': user.displayName ?? '', 'email': user.email ?? '', 'role': widget.role,
         'createdAt': ServerValue.timestamp, 'profileImageUrl': user.photoURL
       });
       if (!mounted) return;
       Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => WidgetTree(userRole: widget.role)), (route) => false);
     }
   } on FirebaseAuthException catch(e){ /* ... */ _showSnackBar("Google sign-up failed. Please try again.", isError: true);
   } catch (e) { /* ... */ _showSnackBar("An unexpected error occurred with Google sign-up.", isError: true);
   } finally {
     if (mounted) setState(() { _isLoading = false; });
   }
 }


 @override
 Widget build(BuildContext context) {
   // *** Define input border style consistent with SignInPage ***
   final inputBorder = OutlineInputBorder(
     borderRadius: BorderRadius.circular(12),
     borderSide: BorderSide(color: Colors.grey.shade300),
   );

   return Scaffold(
     // *** Match SignInPage background color ***
     backgroundColor: const Color(0xF1F9FFFF),
     appBar: AppBar(
       // Style matches SignInPage already
       backgroundColor: Colors.blue[800],
       title: const Text("Sign Up", style: TextStyle(color: Colors.white)),
       leading: IconButton(
         icon: const Icon(Icons.arrow_back, color: Colors.white),
         onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
       ),
       elevation: 0, // Match SignInPage elevation
     ),
     body: SafeArea( // Added SafeArea like SignInPage
       child: SingleChildScrollView(
         // *** Match SignInPage padding ***
         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
         child: Form(
           key: _formKey,
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               // --- Name Field ---
               // *** Added Text Label above field ***
               const Text("Full Name", style: TextStyle(fontSize: 16)),
               const SizedBox(height: 8),
               TextFormField(
                 controller: _nameController,
                 enabled: !_isLoading,
                 textCapitalization: TextCapitalization.words,
                 decoration: InputDecoration( // *** Apply consistent decoration ***
                   hintText: "Enter your full name",
                   border: inputBorder,
                   enabledBorder: inputBorder,
                   focusedBorder: inputBorder,
                   filled: true,
                   fillColor: _isLoading ? Colors.grey[200] : Colors.white,
                 ),
                 validator: (value) { /* ... validation ... */
                   if (value == null || value.trim().isEmpty) { return 'Name is required';} return null;
                 },
                 autovalidateMode: AutovalidateMode.onUserInteraction,
               ),
               const SizedBox(height: 20), // Match spacing

               // --- Email Field ---
               // *** Added Text Label above field ***
               const Text("Email address", style: TextStyle(fontSize: 16)),
               const SizedBox(height: 8),
               TextFormField(
                 controller: _emailController,
                 enabled: !_isLoading,
                 keyboardType: TextInputType.emailAddress,
                 decoration: InputDecoration( // *** Apply consistent decoration ***
                   hintText: "Your email",
                   border: inputBorder,
                   enabledBorder: inputBorder,
                   focusedBorder: inputBorder,
                   filled: true,
                   fillColor: _isLoading ? Colors.grey[200] : Colors.white,
                 ),
                  validator: (value) { /* ... validation ... */
                    if (value == null || value.trim().isEmpty) { return 'Email is required'; }
                    final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegExp.hasMatch(value.trim())) { return 'Enter a valid email format';}
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
               ),
               const SizedBox(height: 20), // Match spacing

               // --- Password Field ---
               // *** Added Text Label above field ***
               const Text("Create Password", style: TextStyle(fontSize: 16)),
               const SizedBox(height: 8),
               TextFormField(
                 controller: _passwordController,
                 enabled: !_isLoading,
                 obscureText: !_passwordVisible,
                 decoration: InputDecoration( // *** Apply consistent decoration ***
                   hintText: "Password (6+ characters)",
                   border: inputBorder,
                   enabledBorder: inputBorder,
                   focusedBorder: inputBorder,
                   filled: true,
                   fillColor: _isLoading ? Colors.grey[200] : Colors.white,
                   suffixIcon: IconButton(
                     icon: Icon(_passwordVisible ? LucideIcons.eye : LucideIcons.eyeOff,),
                     onPressed: _isLoading ? null : () { setState(() { _passwordVisible = !_passwordVisible; }); },
                   ),
                 ),
                  validator: (value) { /* ... validation ... */
                    if (value == null || value.isEmpty) { return 'Password is required';}
                    if (value.length < 6) { return 'Password must be at least 6 characters';}
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
               ),
               const SizedBox(height: 20), // Match spacing

               // --- Confirm Password Field ---
               // *** Added Text Label above field ***
               const Text("Confirm Password", style: TextStyle(fontSize: 16)),
               const SizedBox(height: 8),
               TextFormField(
                 controller: _confirmPasswordController,
                  enabled: !_isLoading,
                 obscureText: !_confirmPasswordVisible,
                 decoration: InputDecoration( // *** Apply consistent decoration ***
                   hintText: "Repeat password",
                   border: inputBorder,
                   enabledBorder: inputBorder,
                   focusedBorder: inputBorder,
                   filled: true,
                   fillColor: _isLoading ? Colors.grey[200] : Colors.white,
                   suffixIcon: IconButton(
                     icon: Icon(_confirmPasswordVisible ? LucideIcons.eye : LucideIcons.eyeOff,),
                      onPressed: _isLoading ? null : () { setState(() { _confirmPasswordVisible = !_confirmPasswordVisible; });},
                   ),
                 ),
                  validator: (value) { /* ... validation ... */
                    if (value == null || value.isEmpty) { return 'Please confirm your password'; }
                    if (value != _passwordController.text) { return 'Passwords do not match';}
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
               ),
               const SizedBox(height: 16), // Spacing before T&C

               // --- Terms & Conditions Checkbox --- (Keep previous enhanced version)
               CheckboxListTile(
                 title: RichText( /* ... T&C Text with links ... */
                   text: TextSpan(
                     style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14, color: Colors.black),
                     children: <TextSpan>[
                       TextSpan(text: 'I agree', style: TextStyle(fontWeight: FontWeight.bold)),
                       const TextSpan(text: ' to the '),
                       TextSpan(text: 'Terms & Conditions', style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () { _launchURL('https://example.com/terms'); }),
                       const TextSpan(text: ' and '),
                       TextSpan(text: 'Privacy Policy', style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () { _launchURL('https://example.com/privacy'); }),
                       const TextSpan(text: '.'),
                     ],
                   ),
                 ),
                 value: _termsAccepted,
                 onChanged: _isLoading ? null : (bool? value) { setState(() { _termsAccepted = value ?? false; }); },
                 controlAffinity: ListTileControlAffinity.leading,
                 contentPadding: EdgeInsets.zero,
                 dense: true,
                  activeColor: Colors.blue[800],
               ),
               const SizedBox(height: 24), // Match spacing

               // --- Sign Up Button ---
               SizedBox(
                 width: double.infinity,
                 child: ElevatedButton(
                   style: ElevatedButton.styleFrom( // *** Match SignIn Button Style ***
                     backgroundColor: Colors.blue[800],
                     foregroundColor: Colors.white,
                     padding: const EdgeInsets.symmetric(vertical: 16),
                     shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12),),
                     disabledBackgroundColor: Colors.blue[300], // Match disabled color
                   ),
                   onPressed: _isLoading || !_termsAccepted ? null : _signUpWithEmail,
                   child: _isLoading
                       ? const SizedBox( height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),)
                       : const Text("Sign Up", style: TextStyle(fontSize: 16)), // Text style matches
                 ),
               ),
               const SizedBox(height: 32), // Match spacing

               // --- Divider --- (Matches SignInPage)
               Row(
                  children: const [
                    Expanded(child: Divider()),
                    Padding( padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Or Sign Up with"),),
                    Expanded(child: Divider()),
                  ],
               ),
               const SizedBox(height: 16), // Match spacing

               // --- Google Sign Up Button ---
               SizedBox(
                 width: double.infinity,
                 child: OutlinedButton.icon(
                   style: OutlinedButton.styleFrom( // *** Match SignIn Google Button Style ***
                     padding: const EdgeInsets.symmetric(vertical: 14),
                     side: BorderSide(color: _isLoading || !_termsAccepted ? Colors.grey[400]! : Colors.grey),
                     shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12),),
                      disabledForegroundColor: Colors.grey[600],
                   ),
                   icon: Image.asset('assets/images/google_logo.png', height: 24,),
                   label: Text("Google", style: TextStyle(fontSize: 16, color: _isLoading || !_termsAccepted ? Colors.grey[600] : Colors.black)),
                   onPressed: _isLoading || !_termsAccepted ? null : _signUpWithGoogle,
                 ),
               ),
               const SizedBox(height: 24), // Match spacing

               // --- Sign In Link --- (Matches SignInPage Style)
               Center( // Added Center to match SignInPage
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     const Text("Already have an account? "),
                     GestureDetector(
                       onTap: _isLoading ? null : () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SignInPage()),); },
                       child: Text(
                         "Sign in",
                         style: TextStyle(
                           color: _isLoading ? Colors.grey : Colors.blue,
                           fontWeight: FontWeight.w600, // Use w600 to match SignInPage
                           decoration: TextDecoration.underline,
                         ),
                       ),
                     ),
                   ],
                 ),
               ),
               const SizedBox(height: 16), // Match spacing
             ],
           ),
         ),
       ),
     ),
   );
 }
}