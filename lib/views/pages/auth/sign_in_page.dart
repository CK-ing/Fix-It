import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widget_tree.dart'; // Ensure this import path is correct
import 'select_role_page.dart'; // Ensure this import path is correct
import 'package:firebase_database/firebase_database.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  // *** Declare Dialog controller and key at the State level ***
  late TextEditingController _resetEmailController;
  final GlobalKey<FormState> _dialogFormKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref().child("users");

  @override
  void initState() {
    super.initState();
    // *** Initialize dialog controller here ***
    _resetEmailController = TextEditingController();
    _loadSavedCredentials();
  }

  // *** Dispose ALL controllers here ***
  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _resetEmailController.dispose(); // Dispose dialog controller
    super.dispose();
  }


  void _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rememberMe = prefs.getBool('rememberMe') ?? false;
      if (_rememberMe) {
        emailController.text = prefs.getString('email') ?? '';
        passwordController.text = prefs.getString('password') ?? '';
      }
    });
  }

  void _saveCredentials() async {
    // ... (save credentials logic remains the same)
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool('rememberMe', true);
      await prefs.setString('email', emailController.text);
      await prefs.setString('password', passwordController.text);
    } else {
      await prefs.remove('rememberMe');
      await prefs.remove('email');
      await prefs.remove('password');
    }
  }

  void _showError(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: Colors.red[600],
       )
     );
   }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[600],
      )
    );
  }


  Future<void> _signInWithEmail() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; });
    try {
      // ... (sign in logic remains the same)
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      final uid = userCredential.user?.uid;
      if (uid == null) throw FirebaseAuthException(code: 'user-uid-null');
      final snapshot = await _dbRef.child(uid).get();
      if (!mounted) return;
      if (snapshot.exists && snapshot.value != null) {
        final userData = Map<String, dynamic>.from(snapshot.value as Map);
        final userRole = userData['role'] ?? 'Handyman';
        _saveCredentials();
        selectedPageNotifier.value = 0;
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => WidgetTree(userRole: userRole),
        ));
      } else {
        _showError("User data not found in the database.");
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'user-not-found') {
        _showError('No account found for this email. Please sign up.');
      } else if (e.code == 'wrong-password') {
        _showError('Incorrect password. Please try again.');
      } else if (e.code == 'invalid-email') {
        _showError('Invalid email format.');
      } else {
        print("Firebase Auth Error: ${e.code} - ${e.message}");
        _showError('Sign in failed. Please try again.');
      }
    } catch (e) {
      print("SignIn Error: $e");
      if (!mounted) return;
      _showError('Sign in failed. Please check your internet connection.');
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    setState(() { _isLoading = true; });
    try {
      // ... (google sign in logic remains the same)
      await GoogleSignIn().signOut();
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) throw FirebaseAuthException(code: 'user-credential-null');
      final uid = user.uid;
      final snapshot = await _dbRef.child(uid).get();
      if (!mounted) return;
      if (snapshot.exists && snapshot.value != null) {
        final userData = Map<String, dynamic>.from(snapshot.value as Map);
        final userRole = userData['role'] ?? 'Handyman';
        selectedPageNotifier.value = 0;
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => WidgetTree(userRole: userRole),
        ));
      } else {
        _showError("This Google account is not registered. Please sign up first.");
        await _auth.signOut();
      }
    } catch (e) {
      print("Google Sign-In Error: $e");
      if (!mounted) return;
      _showError("Google Sign-In failed. Please try again.");
    } finally {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // *** Forgot Password uses the State's controller and key ***
  Future<void> _forgotPassword() async {
    if (_isLoading) return;

    // Clear previous value if dialog is reopened
    _resetEmailController.clear();

    await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Reset Password"),
            content: Form(
              // *** Use the state's form key ***
              key: _dialogFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Enter your account email to receive a password reset link."),
                  const SizedBox(height: 16),
                  TextFormField(
                    // *** Use the state's controller ***
                    controller: _resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'e.g., name@example.com',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      // ... (validation remains the same)
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email.';
                      }
                      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(value.trim())) {
                        return 'Please enter a valid email format.';
                      }
                      return null;
                    },
                     autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  // *** Validate using the state's key ***
                  if (_dialogFormKey.currentState!.validate()) {
                    // *** Get email from the state's controller ***
                    final email = _resetEmailController.text.trim();
                    Navigator.pop(context); // Close dialog first
                    // *** Don't dispose controller here ***
                    await _sendPasswordResetEmail(email); // Send the email
                  }
                },
                child: const Text("Send Link"),
              ),
            ],
          );
        });
     // *** Do NOT dispose controller here ***
  }

  Future<void> _sendPasswordResetEmail(String email) async {
      if (_isLoading) return;
      setState(() => _isLoading = true);
      try {
        await _auth.sendPasswordResetEmail(email: email);
        if (!mounted) return;
        _showSuccess("Password reset link sent to $email. Please check your inbox.");
      } on FirebaseAuthException catch (e) {
         if (!mounted) return;
         if (e.code == 'user-not-found') {
           _showError('No user found for this email.');
         } else {
           print("Password Reset Error: ${e.code} - ${e.message}");
           _showError("Failed to send reset email. Please try again.");
         }
      } catch (e) {
         print("Password Reset Error: $e");
         if (!mounted) return;
         _showError("Failed to send reset email. Please try again.");
      } finally {
         if (mounted) setState(() => _isLoading = false);
      }
  }


  @override
  Widget build(BuildContext context) {
    // ... (inputBorder definition remains the same) ...
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );

    return Scaffold(
      // ... (Scaffold structure remains the same) ...
      backgroundColor: const Color(0xF1F9FFFF),
      appBar: AppBar(
        backgroundColor: Colors.blue[800],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: const Text('Sign In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Email Field ---
              const Text('Email address', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                enabled: !_isLoading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration( /* ... styling ... */
                  hintText: 'Your email',
                  border: inputBorder,
                  enabledBorder: inputBorder,
                  focusedBorder: inputBorder,
                  filled: true,
                  fillColor: _isLoading ? Colors.grey[200] : Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // --- Password Field ---
              const Text('Password', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                enabled: !_isLoading,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: _isLoading ? null : (_) => _signInWithEmail(),
                decoration: InputDecoration( /* ... styling ... */
                  hintText: 'Password',
                  border: inputBorder,
                  enabledBorder: inputBorder,
                  focusedBorder: inputBorder,
                  filled: true,
                  fillColor: _isLoading ? Colors.grey[200] : Colors.white,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: _isLoading ? null : () {
                      setState(() { _obscurePassword = !_obscurePassword; });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // --- Remember Me & Forgot Password Row ---
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: _isLoading ? null : (value) {
                      setState(() { _rememberMe = value!; });
                    },
                  ),
                  const Text('Remember me'),
                  const Spacer(),
                  TextButton(
                    onPressed: _isLoading ? null : _forgotPassword, // Use the function
                    child: const Text('Forgot password?'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // --- Sign In Button ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom( /* ... styling ... */
                     backgroundColor: Colors.blue[800],
                     padding: const EdgeInsets.symmetric(vertical: 16),
                     shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(12),
                     ),
                     disabledBackgroundColor: Colors.blue[300],
                  ),
                  onPressed: _isLoading ? null : _signInWithEmail,
                  child: _isLoading
                      ? const SizedBox( /* ... CircularProgressIndicator ... */
                          height: 20, width: 20,
                          child: CircularProgressIndicator( strokeWidth: 2.0, color: Colors.white,),
                        )
                      : const Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 32),

              // --- Divider ---
              Row( /* ... Divider ... */
                 children: const [
                   Expanded(child: Divider()),
                   Padding( padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Or Sign In with"),),
                   Expanded(child: Divider()),
                 ],
              ),
              const SizedBox(height: 16),

              // --- Google Sign In Button ---
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom( /* ... styling ... */
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: _isLoading ? Colors.grey[400]! : Colors.grey),
                    shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12),),
                    disabledForegroundColor: Colors.grey[600],
                  ),
                  icon: Image.asset('assets/images/google_logo.png', height: 24),
                  label: Text("Google", style: TextStyle(fontSize: 16, color: _isLoading ? Colors.grey[600] : Colors.black)),
                  onPressed: _isLoading ? null : _signInWithGoogle,
                ),
              ),
              const SizedBox(height: 24),

              // --- Sign Up Link ---
              Center(
                child: Row( /* ... Sign Up Link ... */
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     const Text("Don’t have an account? "),
                     GestureDetector(
                       onTap: _isLoading ? null : () {
                         Navigator.push( context, MaterialPageRoute(builder: (_) => const SelectRolePage()),);
                       },
                       child: Text( "Sign up", style: TextStyle( color: _isLoading ? Colors.grey : Colors.blue, fontWeight: FontWeight.w600, decoration: TextDecoration.underline,),),
                     ),
                   ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}