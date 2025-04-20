import 'package:firebase_core/firebase_core.dart';
import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:flutter/material.dart';

// *** ADD Import for Firebase Messaging ***
import 'package:firebase_messaging/firebase_messaging.dart';

// Import your initial screen and potentially Firebase options
import 'views/pages/auth/welcome_screen.dart';
// import 'firebase_options.dart'; // Uncomment if using firebase_options.dart

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (ensure options are correctly configured if needed)
  await Firebase.initializeApp(
     // options: DefaultFirebaseOptions.currentPlatform, // Uncomment if using firebase_options.dart
  );

  // --- Add this block for Foreground Message Handling ---
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Foreground FCM message received!'); // Log that a message came in

    // Check if the message contains notification data
    if (message.notification != null) {
      print('Message also contained a notification:');
      print('  Title: ${message.notification!.title}');
      print('  Body: ${message.notification!.body}');

      // --- How to display this to the user? ---
      // For now, we just print. To show a visible notification banner
      // while the app is open, you'd typically use a package like
      // flutter_local_notifications here. We can implement that later if needed.
    }

    // Check if the message contains a data payload (optional)
    if (message.data.isNotEmpty) {
        print('Message data payload: ${message.data}');
        // You can use this data to update UI, navigate, etc.
    }
  });
  // --- End of Foreground Message Handling Block ---

  runApp(const MyApp()); // Start your app
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() =>  _MyAppState();
}

class  _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    // Your existing MyApp build method remains the same
    return ValueListenableBuilder(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDarkMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: isDarkMode ? Brightness.dark : Brightness.light,
            ),
             useMaterial3: true, // Recommended for modern Flutter UI
          ),
          // Ensure WelcomeScreen or your AuthGate is the home
          home: const WelcomeScreen(),
        );
      },
    );
  }
}