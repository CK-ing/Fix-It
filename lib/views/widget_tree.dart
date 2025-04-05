import 'package:fixit_app_a186687/data/notifiers.dart';
import 'package:fixit_app_a186687/views/pages/home_page.dart';
import 'package:fixit_app_a186687/views/pages/profile_page.dart';
import 'package:flutter/material.dart';

import 'widgets/navbar_widget.dart';

List<Widget> pages = [
  HomePage(),
  ProfilePage(),
];

class WidgetTree extends StatelessWidget {
  const WidgetTree({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
          appBar: AppBar(
            title: Text('Fix It'),
            centerTitle: true,
            actions: [
              IconButton(
                onPressed: () {
                isDarkModeNotifier.value = !isDarkModeNotifier.value;
              }, 
              icon: ValueListenableBuilder(valueListenable: isDarkModeNotifier, builder: (context, isDarkMode, child) {
                return Icon(
                isDarkMode ? Icons.light_mode : Icons.dark_mode,
                );
              },)
              )
            ],
          ),
          body: ValueListenableBuilder(valueListenable: selectedPageNotifier, builder: (context, selectedPage, child) {
            return pages.elementAt(selectedPage);
          },),
          bottomNavigationBar: NavbarWidget()
        );
  }
}