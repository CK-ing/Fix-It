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

  String _drawerUserName = "User";
  String _drawerUserEmail = "";
  String? _drawerUserPhotoUrl;
  bool _isLoadingDrawerData = true;

  bool _hasUnreadNotifications = false;
  bool _hasUnreadChats = false;
  StreamSubscription? _notificationsSubscription;
  StreamSubscription? _chatsSubscription;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser; 
    _loadDrawerData();
    _listenForUnreadNotifications();
    _listenForUnreadChats();
    _listenForAuthStateChanges();
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    _chatsSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
  
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }
  void _listenForAuthStateChanges() {
    _authSubscription = _auth.authStateChanges().listen((User? user) {
      if (user == null && mounted) {
        // User has logged out, navigate to the Welcome Screen and clear all routes.
        print("Auth state changed: User is null. Navigating to WelcomeScreen.");
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          (Route<dynamic> route) => false,
        );
      }else if (user != null) {
      // User logged in or restored session
      print("Auth state changed: User logged in or restored session.");
      _currentUser = user;  // update cached user
      _requestAndSaveToken();  //  ensure token saved
    }
    });
  }
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
      // Gracefully handle permission denied errors on logout
      print("Chat listener error (likely on logout): $error");
    });
  }

  void _listenForUnreadChats() {
    if (_currentUser == null) return;
    final query = _db.child('chats').orderByChild('users/${_currentUser!.uid}').equalTo(true);

    _chatsSubscription = query.onValue.listen((event) {
      if (!mounted || !event.snapshot.exists) {
        setStateIfMounted(() => _hasUnreadChats = false);
        return;
      }
      
      int totalUnread = 0;
      final chatsData = Map<String, dynamic>.from(event.snapshot.value as Map);
      
      for (var chatValue in chatsData.values) {
        if (chatValue is Map && chatValue['unreadCount'] is Map) {
          final unreadMap = Map<String, dynamic>.from(chatValue['unreadCount']);
          totalUnread += (unreadMap[_currentUser!.uid] as int?) ?? 0;
        }
      }
      
      setStateIfMounted(() {
        _hasUnreadChats = totalUnread > 0;
      });
    },onError: (error) {
      // Gracefully handle permission denied errors on logout
      print("Chat listener error (likely on logout): $error");
    });
  }

  Future<void> _loadDrawerData() async {final user = _auth.currentUser; if (user == null) { if (mounted) setState(() => _isLoadingDrawerData = false); return; } try { final snapshot = await _db.child('users').child(user.uid).get(); if (mounted && snapshot.exists && snapshot.value != null) { final data = Map<String, dynamic>.from(snapshot.value as Map); setState(() { _drawerUserName = data['name'] ?? user.displayName ?? "User"; _drawerUserEmail = data['email'] ?? user.email ?? ""; _drawerUserPhotoUrl = data['profileImageUrl']; _isLoadingDrawerData = false; }); } else { if (mounted) { setState(() { _drawerUserName = user.displayName ?? "User"; _drawerUserEmail = user.email ?? ""; _drawerUserPhotoUrl = user.photoURL; _isLoadingDrawerData = false; }); } } } catch (e) { print("Error loading drawer data: $e"); if (mounted && user != null) { setState(() { _drawerUserName = user.displayName ?? "User"; _drawerUserEmail = user.email ?? ""; _drawerUserPhotoUrl = user.photoURL; _isLoadingDrawerData = false; }); } else if (mounted) { setState(() => _isLoadingDrawerData = false); } }}
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
          switch (selectedPage) { case 0: return currentUserRole == 'Handyman' ? 'Dashboard' : 'FixIt'; case 1: return 'Bookings'; case 2: return 'Chat'; case 3: return 'Profile'; default: return 'FixIt'; }
        }
        List<Widget> getActions() {
          // Settings button on Profile page
          if (selectedPage == 3) {
            return [ IconButton( icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () { print('Settings tapped'); },),];
          } 
          // Notification button for both roles on their respective homepages
          else if (selectedPage == 0) {
            return [
              Stack(
                alignment: Alignment.center,
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
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                      ),
                    ),
                ],
              )
            ];
          }
          // No actions on other pages
          else {
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
          bottomNavigationBar: NavbarWidget(
            userRole: currentUserRole,
            hasUnreadChats: _hasUnreadChats,
            ),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, String currentUserRole) { List<Widget> menuItems; if (currentUserRole == 'Handyman') { menuItems = [ ListTile( leading: const Icon(Icons.dashboard_outlined), title: const Text('Dashboard'), onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.calendar_month_outlined), title: const Text('Bookings'), onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.chat_bubble_outline), title: const Text('Chat'), onTap: () { selectedPageNotifier.value = 2; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.build_outlined), title: const Text('My Services'), onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); print('My Services tapped'); },), ListTile( leading: const Icon(Icons.event_available_outlined), title: const Text('Manage Availability'), onTap: () { /* TODO */ Navigator.pop(context); print('Manage Availability tapped'); },), ListTile( leading: const Icon(Icons.wallet_outlined), title: const Text('Earnings & Payouts'), onTap: () { /* TODO */ Navigator.pop(context); print('Earnings tapped'); },), ListTile( leading: const Icon(Icons.bar_chart_outlined), title: const Text('Statistics'), onTap: () { /* TODO */ Navigator.pop(context); print('Statistics tapped'); },), const Divider(), ListTile( leading: const Icon(Icons.help_outline), title: const Text('Help & Support'), onTap: () { /* TODO */ Navigator.pop(context); print('Help tapped'); },), ListTile( leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { /* TODO */ Navigator.pop(context); print('Settings tapped'); },), _buildLogoutTile(context),]; } else { menuItems = [ ListTile( leading: const Icon(Icons.payment_outlined), title: const Text('Payment Methods'), onTap: () { /* TODO */ Navigator.pop(context); print('Payment Methods tapped'); },), ListTile( leading: const Icon(Icons.history_outlined), title: const Text('Booking History'), onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.chat_bubble_outline), title: const Text('Chat'), onTap: () { selectedPageNotifier.value = 2; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.favorite_border_outlined), title: const Text('Favorite Handymen'), onTap: () { /* TODO */ Navigator.pop(context); print('Favorites tapped'); },), ListTile( leading: const Icon(Icons.local_offer_outlined), title: const Text('Promotions'), onTap: () { /* TODO */ Navigator.pop(context); print('Promotions tapped'); },), const Divider(), ListTile( leading: const Icon(Icons.help_outline), title: const Text('Help & Support'), onTap: () { /* TODO */ Navigator.pop(context); print('Help tapped'); },), ListTile( leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { /* TODO */ Navigator.pop(context); print('Settings tapped'); },), _buildLogoutTile(context),]; } return Drawer( child: ListView( padding: EdgeInsets.zero, children: <Widget>[ UserAccountsDrawerHeader( accountName: Text(_drawerUserName), accountEmail: Text(_drawerUserEmail), currentAccountPicture: CircleAvatar( backgroundColor: Theme.of(context).colorScheme.primaryContainer, backgroundImage: (_drawerUserPhotoUrl != null && _drawerUserPhotoUrl!.isNotEmpty) ? NetworkImage(_drawerUserPhotoUrl!) : null, child: (_drawerUserPhotoUrl == null || _drawerUserPhotoUrl!.isEmpty) ? Text( _drawerUserName.isNotEmpty ? _drawerUserName[0].toUpperCase() : "?", style: const TextStyle(fontSize: 40.0)) : null,), decoration: BoxDecoration( color: Theme.of(context).colorScheme.primary ),), if (_isLoadingDrawerData) const Padding( padding: EdgeInsets.all(20.0), child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),) else ...menuItems,],),); }
  Widget _buildLogoutTile(BuildContext context) { return ListTile( leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Logout', style: TextStyle(color: Colors.red)), onTap: () async { final navigator = Navigator.of(context); final scaffoldMessenger = ScaffoldMessenger.of(context); try { print('Attempting to sign out...'); if (navigator.canPop()) { navigator.pop(); } await FirebaseAuth.instance.signOut(); print('Sign out successful.'); navigator.pushAndRemoveUntil( MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false,); } catch (e) { print("Error logging out: $e"); if (scaffoldMessenger.mounted) { scaffoldMessenger.showSnackBar(SnackBar(content: Text('Logout failed: ${e.toString()}'))); } if (navigator.canPop()) { navigator.pop(); } } },); }
}
