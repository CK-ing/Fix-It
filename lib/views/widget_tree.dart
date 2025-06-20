import 'dart:async'; // Import for StreamSubscription

import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:fixit_app_a186687/views/pages/bookings_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Import Page Widgets
import 'pages/homeowner_home_page.dart';
import 'pages/handyman_home_page.dart';
import 'pages/profile_page.dart';
import 'widgets/navbar_widget.dart';
import 'pages/auth/welcome_screen.dart';
import 'pages/chat_list_page.dart';
import 'pages/notifications_page.dart'; // *** NEW: Import NotificationsPage ***

List<Widget> getPages(String userRole) {
  return [
    userRole == "Handyman" ? const HandymanHomePage() : const HomeownerHomePage(),
    BookingsPage(userRole: userRole),
    const ChatListPage(),
    const ProfilePage(),
  ];
}

class WidgetTree extends StatefulWidget {
  final String userRole;
  const WidgetTree({super.key, required this.userRole});
  @override
  State<WidgetTree> createState() => _WidgetTreeState();
}

class _WidgetTreeState extends State<WidgetTree> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  User? _currentUser;

  // Drawer State
  String _drawerUserName = "User";
  String _drawerUserEmail = "";
  String? _drawerUserPhotoUrl;
  bool _isLoadingDrawerData = true;

  // --- NEW: Notification State ---
  bool _hasUnreadNotifications = false;
  StreamSubscription? _notificationsSubscription;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser; // Get current user once
    _loadDrawerData();
    _requestAndSaveToken();
    // *** NEW: Start listening for notifications if user is a homeowner ***
    if (widget.userRole == 'Homeowner') {
      _listenForUnreadNotifications();
    }
  }

  @override
  void dispose() {
    // *** NEW: Cancel subscription to prevent memory leaks ***
    _notificationsSubscription?.cancel();
    super.dispose();
  }
  
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // --- NEW: Real-time listener for the notification indicator ---
  void _listenForUnreadNotifications() {
    if (_currentUser == null) return;
    _notificationsSubscription?.cancel(); // Cancel any old listener
    final notificationsRef = _db.child('notifications/${_currentUser!.uid}');
    
    _notificationsSubscription = notificationsRef.onValue.listen((event) {
      if (!mounted) return;
      bool hasUnread = false;
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        // Check if any notification has isRead: false or isRead is null
        hasUnread = data.values.any((notification) => 
          notification is Map && (notification['isRead'] == false || notification['isRead'] == null)
        );
      }
      setStateIfMounted(() {
        _hasUnreadNotifications = hasUnread;
      });
    }, onError: (error) {
      print("Error listening for notifications in WidgetTree: $error");
    });
  }

  Future<void> _loadDrawerData() async {
    final user = _auth.currentUser; if (user == null) { if (mounted) setState(() => _isLoadingDrawerData = false); return; } try { final snapshot = await _db.child('users').child(user.uid).get(); if (mounted && snapshot.exists && snapshot.value != null) { final data = Map<String, dynamic>.from(snapshot.value as Map); setState(() { _drawerUserName = data['name'] ?? user.displayName ?? "User"; _drawerUserEmail = data['email'] ?? user.email ?? ""; _drawerUserPhotoUrl = data['profileImageUrl']; _isLoadingDrawerData = false; }); } else { if (mounted) { setState(() { _drawerUserName = user.displayName ?? "User"; _drawerUserEmail = user.email ?? ""; _drawerUserPhotoUrl = user.photoURL; _isLoadingDrawerData = false; }); } } } catch (e) { print("Error loading drawer data: $e"); if (mounted && user != null) { setState(() { _drawerUserName = user.displayName ?? "User"; _drawerUserEmail = user.email ?? ""; _drawerUserPhotoUrl = user.photoURL; _isLoadingDrawerData = false; }); } else if (mounted) { setState(() => _isLoadingDrawerData = false); } }
  }
  Future<void> _requestAndSaveToken() async { await _requestNotificationPermission(); await _saveDeviceToken(); }
  Future<void> _requestNotificationPermission() async { FirebaseMessaging messaging = FirebaseMessaging.instance; try { NotificationSettings settings = await messaging.requestPermission( alert: true, announcement: false, badge: true, carPlay: false, criticalAlert: false, provisional: false, sound: true,); print('User granted permission: ${settings.authorizationStatus}'); } catch (e) { print('Error requesting notification permission: $e'); } }
  Future<void> _saveDeviceToken() async { final user = _auth.currentUser; if (user == null) return; try { String? fcmToken = await FirebaseMessaging.instance.getToken(); if (fcmToken != null) { print("FCM Token: $fcmToken"); DatabaseReference userRef = _db.child('users').child(user.uid); await userRef.update({'fcmToken': fcmToken}); print("FCM Token saved to database."); FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async { print("FCM Token Refreshed: $newToken"); try { await userRef.update({'fcmToken': newToken}); print("Refreshed FCM Token saved."); } catch (e) { print("Error saving refreshed token: $e"); } }); } else { print("Could not get FCM token."); } } catch (e) { print("Error getting/saving FCM token: $e"); } }


  @override
  Widget build(BuildContext context) {
    final String currentUserRole = widget.userRole;
    return ValueListenableBuilder<int>(
      valueListenable: selectedPageNotifier,
      builder: (context, selectedPage, child) {
        String getTitle() {
          switch (selectedPage) { case 0: return currentUserRole == 'Handyman' ? 'Dashboard' : 'Fix It'; case 1: return 'Bookings'; case 2: return 'Chat'; case 3: return 'Profile'; default: return 'Fix It'; }
        }
        
        // *** MODIFIED: getActions to show notification indicator and navigate ***
        List<Widget> getActions() {
          if (selectedPage == 3) {
            return [ IconButton( icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () { print('Settings tapped'); },),];
          } else if (selectedPage == 0 && currentUserRole == 'Handyman') {
            return [ IconButton( icon: const Icon(Icons.calendar_today_outlined), tooltip: 'Manage Availability', onPressed: () { print('Manage Availability Tapped'); },),];
          } else if (selectedPage == 0 && currentUserRole == 'Homeowner') {
            return [
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_outlined),
                    tooltip: 'Notifications',
                    onPressed: () {
                      // Navigate to the new notifications page
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsPage()),
                      );
                    },
                  ),
                  if (_hasUnreadNotifications)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                      ),
                    ),
                ],
              )
            ];
          } else {
            return [];
          }
        }

        Widget? buildLeading(BuildContext context) { if (selectedPage == 0) { return IconButton( icon: const Icon(Icons.menu), tooltip: 'Open Menu', onPressed: () => _scaffoldKey.currentState?.openDrawer(),); } return null; }

        return Scaffold(
          key: _scaffoldKey,
          appBar: selectedPage == 1
              ? null
              : AppBar(
                  leading: buildLeading(context),
                  automaticallyImplyLeading: false,
                  title: Text(getTitle()),
                  centerTitle: true,
                  actions: getActions(),
                  elevation: 1.0,
                ),
          drawer: (selectedPage == 0) ? _buildDrawer(context, currentUserRole) : null,
          body: getPages(currentUserRole).elementAt(selectedPage),
          bottomNavigationBar: NavbarWidget(userRole: currentUserRole),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, String currentUserRole) { /* ... drawer logic remains same ... */ List<Widget> menuItems; if (currentUserRole == 'Handyman') { menuItems = [ ListTile( leading: const Icon(Icons.dashboard_outlined), title: const Text('Dashboard'), onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.calendar_month_outlined), title: const Text('Bookings'), onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.chat_bubble_outline), title: const Text('Chat'), onTap: () { selectedPageNotifier.value = 2; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.build_outlined), title: const Text('My Services'), onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); print('My Services tapped'); },), ListTile( leading: const Icon(Icons.event_available_outlined), title: const Text('Manage Availability'), onTap: () { /* TODO */ Navigator.pop(context); print('Manage Availability tapped'); },), ListTile( leading: const Icon(Icons.wallet_outlined), title: const Text('Earnings & Payouts'), onTap: () { /* TODO */ Navigator.pop(context); print('Earnings tapped'); },), ListTile( leading: const Icon(Icons.bar_chart_outlined), title: const Text('Statistics'), onTap: () { /* TODO */ Navigator.pop(context); print('Statistics tapped'); },), const Divider(), ListTile( leading: const Icon(Icons.help_outline), title: const Text('Help & Support'), onTap: () { /* TODO */ Navigator.pop(context); print('Help tapped'); },), ListTile( leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { /* TODO */ Navigator.pop(context); print('Settings tapped'); },), _buildLogoutTile(context),]; } else { menuItems = [ ListTile( leading: const Icon(Icons.payment_outlined), title: const Text('Payment Methods'), onTap: () { /* TODO */ Navigator.pop(context); print('Payment Methods tapped'); },), ListTile( leading: const Icon(Icons.history_outlined), title: const Text('Booking History'), onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.chat_bubble_outline), title: const Text('Chat'), onTap: () { selectedPageNotifier.value = 2; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.favorite_border_outlined), title: const Text('Favorite Handymen'), onTap: () { /* TODO */ Navigator.pop(context); print('Favorites tapped'); },), ListTile( leading: const Icon(Icons.local_offer_outlined), title: const Text('Promotions'), onTap: () { /* TODO */ Navigator.pop(context); print('Promotions tapped'); },), const Divider(), ListTile( leading: const Icon(Icons.help_outline), title: const Text('Help & Support'), onTap: () { /* TODO */ Navigator.pop(context); print('Help tapped'); },), ListTile( leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { /* TODO */ Navigator.pop(context); print('Settings tapped'); },), _buildLogoutTile(context),]; } return Drawer( child: ListView( padding: EdgeInsets.zero, children: <Widget>[ UserAccountsDrawerHeader( accountName: Text(_drawerUserName), accountEmail: Text(_drawerUserEmail), currentAccountPicture: CircleAvatar( backgroundColor: Theme.of(context).colorScheme.primaryContainer, backgroundImage: (_drawerUserPhotoUrl != null && _drawerUserPhotoUrl!.isNotEmpty) ? NetworkImage(_drawerUserPhotoUrl!) : null, child: (_drawerUserPhotoUrl == null || _drawerUserPhotoUrl!.isEmpty) ? Text( _drawerUserName.isNotEmpty ? _drawerUserName[0].toUpperCase() : "?", style: const TextStyle(fontSize: 40.0)) : null,), decoration: BoxDecoration( color: Theme.of(context).colorScheme.primary ),), if (_isLoadingDrawerData) const Padding( padding: EdgeInsets.all(20.0), child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),) else ...menuItems,],),); }
  Widget _buildLogoutTile(BuildContext context) { /* ... logout logic remains same ... */ return ListTile( leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Logout', style: TextStyle(color: Colors.red)), onTap: () async { final navigator = Navigator.of(context); final scaffoldMessenger = ScaffoldMessenger.of(context); try { print('Attempting to sign out...'); if (navigator.canPop()) { navigator.pop(); } await FirebaseAuth.instance.signOut(); print('Sign out successful.'); navigator.pushAndRemoveUntil( MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false,); } catch (e) { print("Error logging out: $e"); if (scaffoldMessenger.mounted) { scaffoldMessenger.showSnackBar(SnackBar(content: Text('Logout failed: ${e.toString()}'))); } if (navigator.canPop()) { navigator.pop(); } } },); }
}
