import 'package:fixit_app_a186687/data/notifiers.dart';
// *** Make sure the path to BookingsPage is correct ***
import 'package:fixit_app_a186687/views/pages/bookings_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// Import Page Widgets (ensure paths are correct)
import 'pages/handyman_page.dart';
import 'pages/homeowner_home_page.dart';
import 'pages/handyman_home_page.dart';
import 'pages/jobs_page.dart';
import 'pages/profile_page.dart';
import 'widgets/navbar_widget.dart';
import 'pages/auth/welcome_screen.dart'; // Import WelcomeScreen

// Updated getPages function to pass userRole to BookingsPage
List<Widget> getPages(String userRole) {
  return [
    userRole == "Handyman" ? const HandymanHomePage() : const HomeownerHomePage(),
    // Pass userRole to BookingsPage constructor
    BookingsPage(userRole: userRole), // Ensure BookingsPage has this constructor
    userRole == "Handyman" ? const JobsPage() : const HandymanPage(),
    const ProfilePage(),
  ];
}

// WidgetTree is StatefulWidget to fetch drawer data
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

  String _drawerUserName = "User";
  String _drawerUserEmail = "";
  String? _drawerUserPhotoUrl;
  bool _isLoadingDrawerData = true;

  @override
  void initState() {
    super.initState();
    _loadDrawerData();
  }

  Future<void> _loadDrawerData() async {
    // ... load drawer data logic ...
    final user = _auth.currentUser;
    if (user == null) { if (mounted) setState(() => _isLoadingDrawerData = false); return; }
    try {
      final snapshot = await _db.child('users').child(user.uid).get();
      if (mounted && snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          _drawerUserName = data['name'] ?? user.displayName ?? "User";
          _drawerUserEmail = data['email'] ?? user.email ?? "";
          _drawerUserPhotoUrl = data['profileImageUrl'];
          _isLoadingDrawerData = false;
        });
      } else {
         if (mounted) { setState(() { _drawerUserName = user.displayName ?? "User"; _drawerUserEmail = user.email ?? ""; _drawerUserPhotoUrl = user.photoURL; _isLoadingDrawerData = false; }); }
      }
    } catch (e) {
      print("Error loading drawer data: $e");
       if (mounted && user != null) { setState(() { _drawerUserName = user.displayName ?? "User"; _drawerUserEmail = user.email ?? ""; _drawerUserPhotoUrl = user.photoURL; _isLoadingDrawerData = false; });
       } else if (mounted) { setState(() => _isLoadingDrawerData = false); }
    }
  }


  @override
  Widget build(BuildContext context) {
    final String currentUserRole = widget.userRole;
    return ValueListenableBuilder<int>(
      valueListenable: selectedPageNotifier,
      builder: (context, selectedPage, child) {
        String getTitle() {
           switch (selectedPage) { case 0: return currentUserRole == 'Handyman' ? 'Dashboard' : 'Fix It'; case 1: return 'Bookings'; case 2: return currentUserRole == 'Handyman' ? 'My Jobs' : 'Browse Handymen'; case 3: return 'Profile'; default: return 'Fix It'; }
        }
        List<Widget> getActions() {
           if (selectedPage == 3) { return [ IconButton( icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () { /* TODO */ print('Settings tapped'); },),]; }
           else if (selectedPage == 0 && currentUserRole == 'Handyman') { return [ IconButton( icon: const Icon(Icons.calendar_today_outlined), tooltip: 'Manage Availability', onPressed: () { /* TODO */ print('Manage Availability Tapped'); },),]; }
           else if (selectedPage == 0 && currentUserRole == 'Homeowner') { return [ IconButton( icon: const Icon(Icons.notifications_none_outlined), tooltip: 'Notifications', onPressed: () { /* TODO */ print('Notifications tapped'); },),]; }
           // No specific actions needed for Bookings page (index 1) in this AppBar
           else { return []; }
        }
        Widget? buildLeading(BuildContext context) {
           if (selectedPage == 0) { return IconButton( icon: const Icon(Icons.menu), tooltip: 'Open Menu', onPressed: () => _scaffoldKey.currentState?.openDrawer(),); } return null;
         }

        return Scaffold(
          key: _scaffoldKey,
          // Conditionally build AppBar based on selectedPage
          appBar: selectedPage == 1 // Check if it's the Bookings Page (index 1)
                 ? null // Don't build AppBar here, let BookingsPage handle it
                 : AppBar(
                     leading: buildLeading(context),
                     automaticallyImplyLeading: false,
                     title: Text(getTitle()),
                     centerTitle: true,
                     actions: getActions(),
                     elevation: 1.0,
                   ),
          drawer: (selectedPage == 0) ? _buildDrawer(context, currentUserRole) : null,
          body: getPages(currentUserRole).elementAt(selectedPage), // Pass role here
          bottomNavigationBar: NavbarWidget(userRole: currentUserRole),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context, String currentUserRole) { /* ... drawer logic ... */
    List<Widget> menuItems;
    if (currentUserRole == 'Handyman') { menuItems = [ ListTile( leading: const Icon(Icons.dashboard_outlined), title: const Text('Dashboard'), onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.calendar_month_outlined), title: const Text('Bookings'), onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.list_alt_outlined), title: const Text('Job Requests'), onTap: () { selectedPageNotifier.value = 2; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.build_outlined), title: const Text('My Services'), onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); print('My Services tapped'); },), ListTile( leading: const Icon(Icons.event_available_outlined), title: const Text('Manage Availability'), onTap: () { /* TODO */ Navigator.pop(context); print('Manage Availability tapped'); },), ListTile( leading: const Icon(Icons.wallet_outlined), title: const Text('Earnings & Payouts'), onTap: () { /* TODO */ Navigator.pop(context); print('Earnings tapped'); },), ListTile( leading: const Icon(Icons.bar_chart_outlined), title: const Text('Statistics'), onTap: () { /* TODO */ Navigator.pop(context); print('Statistics tapped'); },), const Divider(), ListTile( leading: const Icon(Icons.help_outline), title: const Text('Help & Support'), onTap: () { /* TODO */ Navigator.pop(context); print('Help tapped'); },), ListTile( leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { /* TODO */ Navigator.pop(context); print('Settings tapped'); },), _buildLogoutTile(context),]; }
    else { menuItems = [ ListTile( leading: const Icon(Icons.payment_outlined), title: const Text('Payment Methods'), onTap: () { /* TODO */ Navigator.pop(context); print('Payment Methods tapped'); },), ListTile( leading: const Icon(Icons.history_outlined), title: const Text('Booking History'), onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },), ListTile( leading: const Icon(Icons.favorite_border_outlined), title: const Text('Favorite Handymen'), onTap: () { /* TODO */ Navigator.pop(context); print('Favorites tapped'); },), ListTile( leading: const Icon(Icons.local_offer_outlined), title: const Text('Promotions'), onTap: () { /* TODO */ Navigator.pop(context); print('Promotions tapped'); },), const Divider(), ListTile( leading: const Icon(Icons.help_outline), title: const Text('Help & Support'), onTap: () { /* TODO */ Navigator.pop(context); print('Help tapped'); },), ListTile( leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { /* TODO */ Navigator.pop(context); print('Settings tapped'); },), _buildLogoutTile(context),]; }
    return Drawer( child: ListView( padding: EdgeInsets.zero, children: <Widget>[ UserAccountsDrawerHeader( accountName: Text(_drawerUserName), accountEmail: Text(_drawerUserEmail), currentAccountPicture: CircleAvatar( backgroundColor: Theme.of(context).colorScheme.primaryContainer, backgroundImage: (_drawerUserPhotoUrl != null && _drawerUserPhotoUrl!.isNotEmpty) ? NetworkImage(_drawerUserPhotoUrl!) : null, child: (_drawerUserPhotoUrl == null || _drawerUserPhotoUrl!.isEmpty) ? Text( _drawerUserName.isNotEmpty ? _drawerUserName[0].toUpperCase() : "?", style: const TextStyle(fontSize: 40.0)) : null,), decoration: BoxDecoration( color: Theme.of(context).colorScheme.primary ),), if (_isLoadingDrawerData) const Padding( padding: EdgeInsets.all(20.0), child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),) else ...menuItems,],),);
   }

  Widget _buildLogoutTile(BuildContext context) { /* ... logout logic ... */
     return ListTile( leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Logout', style: TextStyle(color: Colors.red)), onTap: () async { final navigator = Navigator.of(context); final scaffoldMessenger = ScaffoldMessenger.of(context); try { print('Attempting to sign out...'); if (navigator.canPop()) { navigator.pop(); } await FirebaseAuth.instance.signOut(); print('Sign out successful.'); navigator.pushAndRemoveUntil( MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false,); } catch (e) { print("Error logging out: $e"); if (scaffoldMessenger.mounted) { scaffoldMessenger.showSnackBar(SnackBar(content: Text('Logout failed: ${e.toString()}'))); } if (navigator.canPop()) { navigator.pop(); } } },);
   }
}