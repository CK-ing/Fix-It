import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:fixit_app_a186687/views/pages/bookings_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // Import Realtime Database

// Import Page Widgets (ensure paths are correct)
import 'pages/handyman_page.dart';
import 'pages/homeowner_home_page.dart';
import 'pages/handyman_home_page.dart';
import 'pages/jobs_page.dart';
import 'pages/profile_page.dart';
import 'widgets/navbar_widget.dart';
import 'pages/auth/welcome_screen.dart'; // Import WelcomeScreen

// getPages function remains the same
List<Widget> getPages(String userRole) {
  return [
    userRole == "Handyman" ? const HandymanHomePage() : const HomeownerHomePage(),
    const BookingsPage(),
    userRole == "Handyman" ? const JobsPage() : const HandymanPage(),
    const ProfilePage(),
  ];
}

// Convert WidgetTree to StatefulWidget to fetch drawer data
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

  // State variables for drawer data
  String _drawerUserName = "User";
  String _drawerUserEmail = "";
  String? _drawerUserPhotoUrl; // URL fetched from Realtime DB profileImageUrl
  bool _isLoadingDrawerData = true; // Loading state for drawer data

  @override
  void initState() {
    super.initState();
    _loadDrawerData(); // Fetch data when the widget initializes
  }

  // Fetch essential user data for the drawer header from Realtime DB
  Future<void> _loadDrawerData() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingDrawerData = false);
      return;
    }

    try {
      final snapshot = await _db.child('users').child(user.uid).get();
      if (mounted && snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          // Use DB data first, fallback to Auth data if DB field is null/missing
          _drawerUserName = data['name'] ?? user.displayName ?? "User";
          _drawerUserEmail = data['email'] ?? user.email ?? "";
          // *** Use 'profileImageUrl' from Database ***
          _drawerUserPhotoUrl = data['profileImageUrl'];
          _isLoadingDrawerData = false;
        });
      } else {
         // Data not found in DB, use Auth data as fallback
         if (mounted) {
            setState(() {
              _drawerUserName = user.displayName ?? "User";
              _drawerUserEmail = user.email ?? "";
              _drawerUserPhotoUrl = user.photoURL; // Fallback to Auth photoURL
              _isLoadingDrawerData = false;
            });
         }
      }
    } catch (e) {
      print("Error loading drawer data: $e");
      // Use Auth data as fallback on error
       if (mounted) {
          setState(() {
            _drawerUserName = user.displayName ?? "User";
            _drawerUserEmail = user.email ?? "";
            _drawerUserPhotoUrl = user.photoURL; // Fallback to Auth photoURL
            _isLoadingDrawerData = false;
          });
       }
    }
  }


  @override
  Widget build(BuildContext context) {
    // Use widget.userRole as it's passed to the StatefulWidget
    final String currentUserRole = widget.userRole;

    return ValueListenableBuilder<int>(
      valueListenable: selectedPageNotifier,
      builder: (context, selectedPage, child) {
        // --- Function to determine AppBar Title ---
        String getTitle() {
          switch (selectedPage) {
            case 0: return currentUserRole == 'Handyman' ? 'Dashboard' : 'Fix It';
            case 1: return 'Bookings';
            case 2: return currentUserRole == 'Handyman' ? 'My Jobs' : 'Browse Handymen';
            case 3: return 'Profile';
            default: return 'Fix It';
          }
        }

        // --- Function to determine AppBar Actions ---
        List<Widget> getActions() {
           if (selectedPage == 3) { // Profile Page
            return [ IconButton( icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: () { /* TODO */ print('Settings tapped'); },),];
          } else if (selectedPage == 0 && currentUserRole == 'Handyman') { // Handyman Home
            return [ IconButton( icon: const Icon(Icons.calendar_today_outlined), tooltip: 'Manage Availability', onPressed: () { /* TODO */ print('Manage Availability Tapped'); },),];
          } else if (selectedPage == 0 && currentUserRole == 'Homeowner') { // Homeowner Home
             return [ IconButton( icon: const Icon(Icons.notifications_none_outlined), tooltip: 'Notifications', onPressed: () { /* TODO */ print('Notifications tapped'); },),];
          } else { return []; }
        }

        // --- Function to build the Leading Widget (Menu Button) ---
         Widget? buildLeading(BuildContext context) {
           if (selectedPage == 0) { // Show menu on page 0 for both roles
              return IconButton( icon: const Icon(Icons.menu), tooltip: 'Open Menu', onPressed: () => _scaffoldKey.currentState?.openDrawer(),);
           }
           return null;
         }
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            leading: buildLeading(context),
            automaticallyImplyLeading: false, // Always hide default back button
            title: Text(getTitle()),
            centerTitle: true,
            actions: getActions(),
            elevation: 1.0,
          ),
          // Build drawer on Page 0 for BOTH roles, passing the role
          drawer: (selectedPage == 0)
                 ? _buildDrawer(context, currentUserRole) // Pass role
                 : null,
          body: getPages(currentUserRole).elementAt(selectedPage), // Use currentUserRole
          bottomNavigationBar: NavbarWidget(userRole: currentUserRole), // Use currentUserRole
        );
      },
    );
  }

  // --- Helper Widget to Build the Drawer (Uses state variables now) ---
  Widget _buildDrawer(BuildContext context, String currentUserRole) {

     // Define menu items based on role
     List<Widget> menuItems;

     // --- Role-Specific Menu Item Logic (remains the same) ---
     if (currentUserRole == 'Handyman') {
        menuItems = [
           ListTile( leading: const Icon(Icons.dashboard_outlined), title: const Text('Dashboard'), onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); },),
           ListTile( leading: const Icon(Icons.calendar_month_outlined), title: const Text('Bookings'), onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },),
           ListTile( leading: const Icon(Icons.list_alt_outlined), title: const Text('Job Requests'), onTap: () { selectedPageNotifier.value = 2; Navigator.pop(context); },),
           ListTile( leading: const Icon(Icons.build_outlined), title: const Text('My Services'), onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); print('My Services tapped'); },),
           ListTile( leading: const Icon(Icons.event_available_outlined), title: const Text('Manage Availability'), onTap: () { /* TODO */ Navigator.pop(context); print('Manage Availability tapped'); },),
           ListTile( leading: const Icon(Icons.wallet_outlined), title: const Text('Earnings & Payouts'), onTap: () { /* TODO */ Navigator.pop(context); print('Earnings tapped'); },),
           ListTile( leading: const Icon(Icons.bar_chart_outlined), title: const Text('Statistics'), onTap: () { /* TODO */ Navigator.pop(context); print('Statistics tapped'); },),
           const Divider(),
           ListTile( leading: const Icon(Icons.help_outline), title: const Text('Help & Support'), onTap: () { /* TODO */ Navigator.pop(context); print('Help tapped'); },),
           ListTile( leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { /* TODO */ Navigator.pop(context); print('Settings tapped'); },),
           _buildLogoutTile(context), // Use helper for logout tile
        ];
     } else { // Homeowner
        menuItems = [
           ListTile( leading: const Icon(Icons.payment_outlined), title: const Text('Payment Methods'), onTap: () { /* TODO */ Navigator.pop(context); print('Payment Methods tapped'); },),
           ListTile( leading: const Icon(Icons.history_outlined), title: const Text('Booking History'), onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },),
           ListTile( leading: const Icon(Icons.favorite_border_outlined), title: const Text('Favorite Handymen'), onTap: () { /* TODO */ Navigator.pop(context); print('Favorites tapped'); },),
           ListTile( leading: const Icon(Icons.local_offer_outlined), title: const Text('Promotions'), onTap: () { /* TODO */ Navigator.pop(context); print('Promotions tapped'); },),
           const Divider(),
           ListTile( leading: const Icon(Icons.help_outline), title: const Text('Help & Support'), onTap: () { /* TODO */ Navigator.pop(context); print('Help tapped'); },),
           ListTile( leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: () { /* TODO */ Navigator.pop(context); print('Settings tapped'); },),
           _buildLogoutTile(context), // Use helper for logout tile
        ];
     }

     // Build the Drawer UI
     return Drawer(
        child: ListView(
           padding: EdgeInsets.zero,
           children: <Widget>[
              // Use UserAccountsDrawerHeader with fetched data
              UserAccountsDrawerHeader(
                 accountName: Text(_drawerUserName), // Use state variable
                 accountEmail: Text(_drawerUserEmail), // Use state variable
                 currentAccountPicture: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    // *** Use fetched _drawerUserPhotoUrl (from profileImageUrl) ***
                    backgroundImage: (_drawerUserPhotoUrl != null && _drawerUserPhotoUrl!.isNotEmpty)
                                     ? NetworkImage(_drawerUserPhotoUrl!) // Use NetworkImage for DB URL
                                     : null, // No background image if URL is null/empty
                    child: (_drawerUserPhotoUrl == null || _drawerUserPhotoUrl!.isEmpty)
                           ? Text( // Show initials if no photo URL
                               _drawerUserName.isNotEmpty ? _drawerUserName[0].toUpperCase() : "?",
                               style: const TextStyle(fontSize: 40.0)
                             )
                           : null, // Don't show text if image exists
                 ),
                 decoration: BoxDecoration( color: Theme.of(context).colorScheme.primary ),
              ),
              // Show loading indicator for menu items while fetching header data
              if (_isLoadingDrawerData)
                 const Padding(
                   padding: EdgeInsets.all(20.0),
                   child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
                 )
              else // Add the role-specific menu items once data is loaded
                 ...menuItems,
           ],
        ),
     );
  }

  // Helper for Logout Tile (no changes needed here)
  Widget _buildLogoutTile(BuildContext context) {
     return ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text('Logout', style: TextStyle(color: Colors.red)),
        onTap: () async {
           final navigator = Navigator.of(context);
           final scaffoldMessenger = ScaffoldMessenger.of(context);
           try {
              print('Attempting to sign out...');
              // Close the drawer BEFORE starting async operation
              if (navigator.canPop()) { navigator.pop(); }

              await FirebaseAuth.instance.signOut();
              print('Sign out successful.');

              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                (Route<dynamic> route) => false,
              );

           } catch (e) {
              print("Error logging out: $e");
              if (scaffoldMessenger.mounted) {
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text('Logout failed: ${e.toString()}')));
              }
              // Ensure drawer is closed even if logout fails
              if (navigator.canPop()) { navigator.pop(); }
           }
        },
     );
  }
}