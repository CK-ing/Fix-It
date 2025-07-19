import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fixit_app_a186687/services/settings_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:fixit_app_a186687/views/pages/splash_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

late List<CameraDescription> cameras;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  await Firebase.initializeApp();
  await dotenv.load(fileName: ".env");
  await SettingsService.loadSettings();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
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

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Foreground FCM message received!');
    RemoteNotification? notification = message.notification;
    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            channelDescription: 'This channel is used for important notifications.',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, themeMode, __) {
        return ValueListenableBuilder<Locale>(
          valueListenable: localeNotifier,
          builder: (_, locale, __) {
            return ValueListenableBuilder<double>(
              valueListenable: fontSizeNotifier,
              builder: (_, textScale, __) {
                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: locale,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
                    useMaterial3: true,
                  ),
                  darkTheme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
                    useMaterial3: true,
                  ),
                  themeMode: themeMode,
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(textScale),
                      ),
                      child: child!,
                    );
                  },
                  home: const SplashScreen(),
                );
              },
            );
          },
        );
      },
    );
  }
}

class LiveDetectionScreen extends StatefulWidget {
  const LiveDetectionScreen({super.key});

  @override
  State<LiveDetectionScreen> createState() => _LiveDetectionScreenState();
}

class _LiveDetectionScreenState extends State<LiveDetectionScreen> {
  late FlutterVision vision;
  late CameraController controller;
  CameraImage? cameraImage;
  bool isLoaded = false;
  bool isDetecting = false;
  List<Map<String, dynamic>> yoloResults = [];

  @override
  void initState() {
    super.initState();
    init();
  }

  init() async {
    controller = CameraController(cameras[0], ResolutionPreset.high);
    await controller.initialize();
    vision = FlutterVision();
    await vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/yolov8n.tflite',
      modelVersion: "yolov8",
      quantization: false,
      numThreads: 1,
      useGpu: false,
    );
    setState(() {
      isLoaded = true;
    });
    startDetection();
  }

  @override
  void dispose() {
    // It's important to stop the stream before disposing the controller
    if (controller.value.isStreamingImages) {
      controller.stopImageStream();
    }
    controller.dispose();
    vision.closeYoloModel();
    super.dispose();
  }

  void startDetection() async {
    if (controller.value.isStreamingImages) {
      return;
    }
    await controller.startImageStream((image) async {
      if (isDetecting) return;
      isDetecting = true;
      cameraImage = image;
      final result = await vision.yoloOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.4,
        confThreshold: 0.01,
        classThreshold: 0.5,
      );
      if (result.isNotEmpty && mounted) {
        setState(() {
          yoloResults = result;
        });
      }
      isDetecting = false;
    });
  }

  // --- NEW: Function to capture the image and return it ---
  Future<void> _captureAndReturnImage() async {
    // Ensure the controller is initialized and not busy
    if (!controller.value.isInitialized || controller.value.isTakingPicture) {
      return;
    }
    try {
      // Stop the image stream to freeze the preview
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      // Take the picture
      final XFile imageFile = await controller.takePicture();
      
      // Pop the screen and return the captured image file
      if (mounted) {
        Navigator.pop(context, imageFile);
      }
    } catch (e) {
      print("Error capturing image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    if (!isLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text("Loading...")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: CameraPreview(controller),
          ),
          ...displayBoxes(size),
          // --- NEW: Back Button ---
          Positioned(
            top: 40,
            left: 20,
            child: FloatingActionButton.small(
              heroTag: 'backButton',
              onPressed: () => Navigator.of(context).pop(),
              backgroundColor: Colors.black.withOpacity(0.5),
              child: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            ),
          ),
        ],
      ),
      // --- NEW: Floating Action Button to Capture Image ---
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.large(
        heroTag: 'captureButton',
        onPressed: _captureAndReturnImage,
        backgroundColor: Colors.white,
        child: const Icon(Icons.camera_alt, size: 40),
      ),
    );
  }

  List<Widget> displayBoxes(Size screen) {
    if (cameraImage == null) return [];
    final double factorX = screen.width / cameraImage!.height;
    final double factorY = screen.height / cameraImage!.width;
    return yoloResults.map((result) {
      return Positioned(
        left: result["box"][0] * factorX,
        top: result["box"][1] * factorY,
        width: (result["box"][2] - result["box"][0]) * factorX,
        height: (result["box"][3] - result["box"][1]) * factorY,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: Colors.pink, width: 2.0),
          ),
          child: Text(
            "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              background: Paint()..color = Colors.pink,
              color: Colors.white,
              fontSize: 18.0,
            ),
          ),
        ),
      );
    }).toList();
  }
}
