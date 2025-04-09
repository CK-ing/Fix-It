import 'package:firebase_core/firebase_core.dart';
import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:flutter/material.dart';

import 'views/pages/auth/welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Required before using Firebase
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() =>  _MyAppState();
}

class  _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: isDarkModeNotifier, builder: (context, isDarkMode, child) {
      return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: isDarkMode ? Brightness.dark : Brightness.light,
        ),
      ),
      home: WelcomeScreen(),
    );
    },);
  }
}