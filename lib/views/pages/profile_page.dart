import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'auth/welcome_screen.dart';
import 'edit_profile_page.dart';
import 'favourites_page.dart';
import 'handyman_reviews_page.dart';
import 'job_requests_page.dart';
import 'my_custom_requests_page.dart';
import 'notifications_page.dart';
import 'statistics_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = 'Loading...';
  String email = '';
  String profileImageUrl = 'assets/images/default_profile.png';
  String _role = '';
  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (user != null) {
      final ref = FirebaseDatabase.instance.ref().child('users').child(user!.uid);
      final snapshot = await ref.get();

      
      if(mounted){
        if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          name = data['name'] ?? 'Unknown';
          email = data['email'] ?? '';
          profileImageUrl = (data['profileImageUrl'] as String?) ?? 'assets/images/default_profile.png';
          _role = data['role'] ?? '';
        });
      } else {
        setState(() {
          name = 'No data found';
        });
      }
      }
    }
  }

  void _logout(BuildContext context) async {
    // Simply sign out. The authStateChanges listener in WidgetTree will handle the navigation.
    await FirebaseAuth.instance.signOut();
  }

  void _onListTileTap(String title) {
    if (title == 'Edit profile') {
      Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const EditProfilePage()),
      ); 
    } else if (title == 'Notifications') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationsPage()),
        );
    }
     else if (title == 'Favourites') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FavouritesPage()),
      );
    } 
      else if (title == 'Statistics') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StatisticsPage()),
        );
      }
      else if (title == 'My Reviews') {
        // This will only be tapped by Handymen
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HandymanReviewsPage()),
        );
      }
       else if (title == 'My Custom Requests') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyCustomRequestsPage()),
          );
        } else if (title == 'Job Requests') {
              // For Handyman
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JobRequestsPage()),
              );
            }
          else if (title == 'Log out') {
          _logout(context);
          }
          else {
            // Placeholder for other buttons
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$title feature coming soon!'))
            );
          }
  }

  Widget _buildListTile(IconData icon, String title) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: Icon(icon, color: Colors.grey[800]),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      onTap: () => _onListTileTap(title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.white,
                backgroundImage: profileImageUrl.startsWith('http')
                    ? NetworkImage(profileImageUrl)
                    : AssetImage(profileImageUrl) as ImageProvider,
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 30),

          _buildSectionTitle('Account'),
          _buildListTile(Icons.person_outline, 'Edit profile'),
          _buildListTile(Icons.notifications_none, 'Notifications'),
          if (_role == 'Homeowner') ...[
            _buildListTile(Icons.favorite_border, 'Favourites'),
            _buildListTile(Icons.assignment_outlined, 'My Custom Requests'),
          ]
          else if (_role == 'Handyman') ...[
            _buildListTile(Icons.bar_chart_outlined, 'Statistics'),
            _buildListTile(Icons.reviews_outlined, 'My Reviews'),
            _buildListTile(Icons.assignment_outlined, 'Job Requests'),
          ],

          const SizedBox(height: 20),
          _buildSectionTitle('Support & About'),
          _buildListTile(Icons.flag_outlined, 'Report a problem'),
          _buildListTile(Icons.help_outline, 'Help & Support'),
          _buildListTile(Icons.info_outline, 'Terms and Policies'),

          const SizedBox(height: 20),
          _buildSectionTitle('Actions'),
          _buildListTile(Icons.menu_book_outlined, 'User Manual'),
          _buildListTile(Icons.group_add_outlined, 'Add account'),
          _buildListTile(Icons.logout, 'Log out'),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}