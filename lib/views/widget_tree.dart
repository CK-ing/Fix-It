import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:fixit_app_a186687/views/pages/bookings_page.dart';
import 'package:flutter/material.dart';
import 'pages/handyman_page.dart';
import 'pages/home_page.dart';
import 'pages/jobs_page.dart';
import 'pages/profile_page.dart';
import 'widgets/navbar_widget.dart';

// You can later switch pages based on userRole
List<Widget> getPages(String userRole) {
  return [
    HomePage(),
    BookingsPage(), // Bookings Page
    userRole == "Handyman" ? JobsPage() : HandymanPage(), // Jobs or Handyman Page
    ProfilePage(),
  ];
}

class WidgetTree extends StatelessWidget {
  final String userRole;

  const WidgetTree({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fix It'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              isDarkModeNotifier.value = !isDarkModeNotifier.value;
            },
            icon: ValueListenableBuilder(
              valueListenable: isDarkModeNotifier,
              builder: (context, isDarkMode, child) {
                return Icon(
                  isDarkMode ? Icons.light_mode : Icons.dark_mode,
                );
              },
            ),
          )
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: selectedPageNotifier,
        builder: (context, selectedPage, child) {
          return getPages(userRole).elementAt(selectedPage);
        },
      ),
      bottomNavigationBar: NavbarWidget(userRole: userRole),
    );
  }
}