import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:fixit_app_a186687/views/pages/bookings_page.dart';
import 'package:flutter/material.dart';
import 'pages/handyman_page.dart';
import 'pages/homeowner_home_page.dart';
import 'pages/handyman_home_page.dart';
import 'pages/jobs_page.dart';
import 'pages/profile_page.dart';
import 'widgets/navbar_widget.dart';

// You can later switch pages based on userRole
List<Widget> getPages(String userRole) {
  return [
    userRole == "Handyman" ? HandymanHomePage() : HomeownerHomePage(),
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
    return ValueListenableBuilder<int>(
      valueListenable: selectedPageNotifier,
      builder: (context, selectedPage, child) {
        String getTitle() {
          switch (selectedPage) {
            case 0:
              return 'Home';
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

        List<Widget> getActions() {
          if (selectedPage == 3) {
            return [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  // Implement settings navigation if needed
                },
              ),
            ];
          } else if (selectedPage == 0 && userRole == 'Handyman') {
            return [
              IconButton(
                icon: const Icon(Icons.calendar_today),
                tooltip: 'Manage Availability',
                onPressed: () {
                  // Implement calendar logic
                },
              ),
            ];
          } else {
            return [
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
              ),
            ];
          }
        }

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(
              getTitle(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            actions: getActions(),
          ),
          body: getPages(userRole).elementAt(selectedPage),
          bottomNavigationBar: NavbarWidget(userRole: userRole),
        );
      },
    );
  }
}