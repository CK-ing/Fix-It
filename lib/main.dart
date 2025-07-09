import 'package:firebase_core/firebase_core.dart';
import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'views/pages/splash_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// This function MUST be a top-level function (not inside a class).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, like Firestore,
  // make sure you call `initializeApp` before using them.
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

// --- NEW: Local Notifications Setup ---
// Create a global instance of the plugin.
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  await dotenv.load(fileName: ".env");

  // --- NEW: Set the background messaging handler. ---
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // --- NEW: Initialize Local Notifications for foreground display ---
  // Setup for Android
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher'); // Use the custom icon you added
      
  // Setup for iOS (requests permissions)
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  // --- End of Local Notifications Initialization ---


  // --- MODIFIED: Foreground Message Handling now shows a visible notification ---
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Foreground FCM message received!');
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    // If there's a notification, show it using flutter_local_notifications
    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel', // A channel ID
            'High Importance Notifications', // A channel name
            channelDescription: 'This channel is used for important notifications.',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher', 
          ),
        ),
      );
    }
  });
  // --- End of Foreground Message Handling Block ---

  runApp(const MyApp());
}

// Your existing MyApp widget remains UNCHANGED.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    // Your ValueListenableBuilder for dark mode is preserved perfectly.
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
            useMaterial3: true,
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
