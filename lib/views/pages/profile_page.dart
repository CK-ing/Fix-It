import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'auth/welcome_screen.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = 'Loading...';
  String email = '';
  String profileImageUrl = 'assets/images/default_profile.png';
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

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          name = data['name'] ?? 'Unknown';
          email = data['email'] ?? '';
          profileImageUrl = data['profilePicture'] ?? 'assets/images/default_profile.png';
        });
      } else {
        setState(() {
          name = 'No data found';
        });
      }
    }
  }

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _onListTileTap(String title) {
    if (title == 'Edit profile') {
      Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const EditProfilePage()),
); // ✅ Use the correct route name
    } else if (title == 'Log out') {
      _logout(context);
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
          _buildListTile(Icons.favorite_border, 'Favourites'),
          _buildListTile(Icons.notifications_none, 'Notifications'),
          _buildListTile(Icons.lock_outline, 'Change Password'),

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