import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:flutter/material.dart';

class NavbarWidget extends StatelessWidget {
  const NavbarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: selectedPageNotifier, builder: (context, selectedPage, child) {
      return NavigationBar(
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home), 
              label: 'Home'
            ),
            NavigationDestination(
              icon: Icon(Icons.person), 
              label: 'Profile'
            )
          ],
          onDestinationSelected: (int value) {
          selectedPageNotifier.value = value;
          },
          selectedIndex: selectedPage,
        );
    },);
  }
}