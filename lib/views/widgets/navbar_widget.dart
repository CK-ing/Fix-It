import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:flutter/material.dart';

class NavbarWidget extends StatelessWidget {
  final String userRole; // either 'Handyman' or 'Homeowner'

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
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.build),
              label: 'Bookings',
            ),
            NavigationDestination(
              icon: Icon(userRole == 'Handyman' ? Icons.work : Icons.handyman),
              label: userRole == 'Handyman' ? 'Jobs' : 'Handyman',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        );
      },
    );
  }
}