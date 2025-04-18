import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:fixit_app_a186687/views/pages/bookings_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth

// Import Page Widgets (ensure paths are correct)
import 'pages/handyman_page.dart';
import 'pages/homeowner_home_page.dart';
import 'pages/handyman_home_page.dart';
import 'pages/jobs_page.dart';
import 'pages/profile_page.dart';
import 'widgets/navbar_widget.dart';
import 'pages/auth/welcome_screen.dart'; // Import WelcomeScreen

// You can later switch pages based on userRole
List<Widget> getPages(String userRole) {
  return [
    userRole == "Handyman" ? const HandymanHomePage() : const HomeownerHomePage(),
    const BookingsPage(),
    userRole == "Handyman" ? const JobsPage() : const HandymanPage(),
    const ProfilePage(),
  ];
}

class WidgetTree extends StatelessWidget {
  final String userRole;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  WidgetTree({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: selectedPageNotifier,
      builder: (context, selectedPage, child) {
        // --- Function to determine AppBar Title ---
        String getTitle() {
          switch (selectedPage) {
            case 0:
              return userRole == 'Handyman' ? 'Dashboard' : 'Fix It';
            case 1:
              return 'Bookings';
            case 2:
              return userRole == 'Handyman' ? 'My Jobs' : 'Browse Handymen';
            case 3:
              return 'Profile';
            default:
              return 'Fix It';
          }
        }

        // --- Function to determine AppBar Actions ---
        List<Widget> getActions() {
          if (selectedPage == 3) { // Profile Page
            return [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () { /* TODO: Implement settings */ print('Settings tapped'); },
              ),
            ];
          } else if (selectedPage == 0 && userRole == 'Handyman') { // Handyman Home
            return [
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                tooltip: 'Manage Availability',
                onPressed: () { /* TODO: Implement calendar */ print('Manage Availability Tapped'); },
              ),
            ];
          } else if (selectedPage == 0 && userRole == 'Homeowner') { // Homeowner Home
             return [
              IconButton(
                icon: const Icon(Icons.notifications_none_outlined),
                tooltip: 'Notifications',
                onPressed: () { /* TODO: Navigate to Notifications */ print('Notifications tapped'); },
              ),
            ];
          } else { // Other pages
             return [];
          }
        }

        // --- Function to build the Leading Widget (Menu Button) ---
         Widget? buildLeading(BuildContext context) {
           // Show menu button on Page 0 for BOTH roles
           if (selectedPage == 0) {
              return IconButton(
                 icon: const Icon(Icons.menu),
                 tooltip: 'Open Menu',
                 onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              );
           }
           return null;
         }


        // --- Main Scaffold ---
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
                 ? _buildDrawer(context, userRole) // Pass userRole here
                 : null,
          body: getPages(userRole).elementAt(selectedPage),
          bottomNavigationBar: NavbarWidget(userRole: userRole),
        );
      },
    );
  }

  // --- Helper Widget to Build the Drawer (Now accepts userRole) ---
  Widget _buildDrawer(BuildContext context, String currentUserRole) { // Accept role
     final user = FirebaseAuth.instance.currentUser;
     final String userName = user?.displayName ?? "User";
     final String userEmail = user?.email ?? "";
     final String? userPhotoUrl = user?.photoURL;

     // Define menu items based on role
     List<Widget> menuItems;

     if (currentUserRole == 'Handyman') {
        // --- Handyman Menu Items ---
        menuItems = [
           ListTile( // Link to Dashboard/Home
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              onTap: () { selectedPageNotifier.value = 0; Navigator.pop(context); },
           ),
           ListTile( // Link to Bookings
              leading: const Icon(Icons.calendar_month_outlined), // Or Icons.book_online
              title: const Text('Bookings'),
              onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },
           ),
           ListTile( // Link to Job Requests
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('Job Requests'),
              onTap: () { selectedPageNotifier.value = 2; Navigator.pop(context); },
           ),
            ListTile( // Link to Manage Services (could be Home page or dedicated page)
              leading: const Icon(Icons.build_outlined),
              title: const Text('My Services'),
              onTap: () {
                 // Option 1: Go to Home tab
                 selectedPageNotifier.value = 0;
                 Navigator.pop(context);
                 // Option 2: Navigate to a dedicated Manage Services page if you create one
                 // Navigator.push(context, MaterialPageRoute(builder: (context) => ManageServicesPage()));
                 print('My Services tapped');
              },
           ),
           ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Manage Availability'),
              onTap: () { /* TODO: Navigate to Availability Page */ Navigator.pop(context); print('Manage Availability tapped'); },
           ),
           ListTile(
              leading: const Icon(Icons.wallet_outlined), // Or Icons.attach_money
              title: const Text('Earnings & Payouts'),
              onTap: () { /* TODO: Navigate to Earnings Page */ Navigator.pop(context); print('Earnings tapped'); },
           ),
           ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Statistics'),
              onTap: () { /* TODO: Navigate to Statistics Page */ Navigator.pop(context); print('Statistics tapped'); },
           ),
           // Common Items
           const Divider(),
           ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              onTap: () { /* TODO: Navigate */ Navigator.pop(context); print('Help tapped'); },
           ),
           ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () { /* TODO: Navigate */ Navigator.pop(context); print('Settings tapped'); },
           ),
           ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async { /* Logout logic remains the same */
                 final navigator = Navigator.of(context);
                 final scaffoldMessenger = ScaffoldMessenger.of(context);
                 try {
                    print('Attempting to sign out...');
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
                    if (navigator.canPop()) { navigator.pop(); } // Close drawer even if logout fails
                 }
              },
           ),
        ];
     } else {
        // --- Homeowner Menu Items (Original List) ---
        menuItems = [
           ListTile(
              leading: const Icon(Icons.payment_outlined),
              title: const Text('Payment Methods'),
              onTap: () { /* TODO: Navigate */ Navigator.pop(context); print('Payment Methods tapped'); },
           ),
           ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Booking History'),
              onTap: () { selectedPageNotifier.value = 1; Navigator.pop(context); },
           ),
            ListTile(
              leading: const Icon(Icons.favorite_border_outlined),
              title: const Text('Favorite Handymen'),
              onTap: () { /* TODO: Navigate */ Navigator.pop(context); print('Favorites tapped'); },
           ),
           ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: const Text('Promotions'),
              onTap: () { /* TODO: Navigate */ Navigator.pop(context); print('Promotions tapped'); },
           ),
           const Divider(),
           ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              onTap: () { /* TODO: Navigate */ Navigator.pop(context); print('Help tapped'); },
           ),
           ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () { /* TODO: Navigate */ Navigator.pop(context); print('Settings tapped'); },
           ),
           ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async { /* Logout logic remains the same */
                 final navigator = Navigator.of(context);
                 final scaffoldMessenger = ScaffoldMessenger.of(context);
                 try {
                    print('Attempting to sign out...');
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
                    if (navigator.canPop()) { navigator.pop(); }
                 }
              },
           ),
        ];
     }


     // Build the Drawer with the determined menu items
     return Drawer(
        child: ListView(
           padding: EdgeInsets.zero,
           children: <Widget>[
              UserAccountsDrawerHeader(
                 accountName: Text(userName),
                 accountEmail: Text(userEmail),
                 currentAccountPicture: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    backgroundImage: (userPhotoUrl != null) ? NetworkImage(userPhotoUrl) : null,
                    child: (userPhotoUrl == null)
                           ? Text( userName.isNotEmpty ? userName[0].toUpperCase() : "?", style: const TextStyle(fontSize: 40.0))
                           : null,
                 ),
                 decoration: BoxDecoration( color: Theme.of(context).colorScheme.primary ),
              ),
              // Add the role-specific menu items
              ...menuItems,
           ],
        ),
     );
  }
}
