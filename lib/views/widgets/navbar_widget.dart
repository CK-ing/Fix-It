import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:flutter/material.dart';

class NavbarWidget extends StatelessWidget {
  final String userRole; // This might not be needed anymore if the 3rd item is always Chat

  const NavbarWidget({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: selectedPageNotifier,
      builder: (context, selectedPage, child) {
        return NavigationBar(
          selectedIndex: selectedPage,
          onDestinationSelected: (int value) {
            selectedPageNotifier.value = value;
          },
          destinations: const [ // Made const as role is no longer needed here
            NavigationDestination(
              icon: Icon(Icons.home_outlined), // Using outlined icons
              selectedIcon: Icon(Icons.home), // Filled icon when selected
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.list_alt_outlined), // Changed icon for bookings
              selectedIcon: Icon(Icons.list_alt),
              label: 'Bookings',
            ),
            // *** MODIFIED: Third item is now Chat ***
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), // Chat icon
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chat',
            ),
            // *** END OF MODIFICATION ***
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        );
      },
    );
  }
}