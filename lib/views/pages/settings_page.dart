import 'package:fixit_app_a186687/services/settings_service.dart';
import 'package:fixit_app_a186687/views/pages/ai_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// Define the enum at the top level of the file, not inside the class.
enum FontSizeOption { small, medium, large }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'Version ${packageInfo.version} (Build ${packageInfo.buildNumber})';
      });
    }
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('English'),
                onTap: () {
                  SettingsService.saveLanguage('en');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Bahasa Melayu'),
                onTap: () {
                  SettingsService.saveLanguage('ms');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('中文 (Chinese)'),
                onTap: () {
                  SettingsService.saveLanguage('zh');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _handleListItemTap(String title) {
    Widget? pageToNavigate;
    // Use a non-translatable key for logic if needed, or check against the English version
    if (title == AppLocalizations.of(context)!.helpSupport) {
      pageToNavigate = const AiChatPage();
    }
    
    if (pageToNavigate != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AiChatPage()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title feature coming soon!')),
      );
    }
  }


  // Helper to get the current language name for display
  String _getCurrentLanguageName(Locale locale) {
    switch (locale.languageCode) {
      case 'ms':
        return 'Bahasa Melayu';
      case 'zh':
        return '中文 (Chinese)';
      case 'en':
      default:
        return 'English';
    }
  }

  // Helper to map font scale to our enum
  FontSizeOption _getFontSizeOption(double scale) {
    if (scale < 0.9) return FontSizeOption.small;
    if (scale > 1.1) return FontSizeOption.large;
    return FontSizeOption.medium;
  }

  // Helper to map our enum back to a font scale
  double _getScaleFromOption(FontSizeOption option) {
    switch (option) {
      case FontSizeOption.small:
        return 0.85;
      case FontSizeOption.large:
        return 1.15;
      case FontSizeOption.medium:
      default:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
          _buildSectionTitle(context, l10n.appearance),
          _buildThemeSelector(context, l10n),
          ValueListenableBuilder<Locale>(
            valueListenable: localeNotifier,
            builder: (context, currentLocale, child) {
              return _buildListTile(
                icon: Icons.translate,
                title: l10n.language,
                subtitle: _getCurrentLanguageName(currentLocale),
                onTap: _showLanguagePicker,
              );
            }
          ),
          _buildFontSizeSelector(context, l10n),
          _buildSectionTitle(context, l10n.accountSecurity),
          _buildListTile(
            icon: Icons.password_outlined,
            title: l10n.changePassword,
            onTap: () => _handleListItemTap(l10n.changePassword),
          ),
          _buildListTile(
            icon: Icons.link_outlined,
            title: l10n.manageLinkedAccounts,
            onTap: () => _handleListItemTap(l10n.manageLinkedAccounts),
          ),
          _buildSectionTitle(context, l10n.supportAbout),
          _buildListTile(
            icon: Icons.help_outline,
            title: l10n.helpSupport,
            onTap: () => _handleListItemTap(l10n.helpSupport),
          ),
          _buildListTile(
            icon: Icons.flag_outlined,
            title: l10n.reportProblem,
            onTap: () => _handleListItemTap(l10n.reportProblem),
          ),
          _buildListTile(
            icon: Icons.gavel_outlined,
            title: l10n.termsPolicies,
            onTap: () => _handleListItemTap(l10n.termsPolicies),
          ),
          _buildListTile(
            icon: Icons.privacy_tip_outlined,
            title: l10n.privacyPolicy,
            onTap: () => _handleListItemTap(l10n.privacyPolicy),
          ),
          const SizedBox(height: 40),
          Center(
            child: Text(
              _appVersion,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildListTile({required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }

  Widget _buildThemeSelector(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.theme, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (_, mode, __) {
              return SegmentedButton<ThemeMode>(
                segments: <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(value: ThemeMode.light, label: Text(l10n.light), icon: const Icon(Icons.light_mode_outlined)),
                  ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text(l10n.dark), icon: const Icon(Icons.dark_mode_outlined)),
                ],
                selected: {mode},
                onSelectionChanged: (newSelection) {
                  // Use the service to save the new theme
                  SettingsService.saveTheme(newSelection.first);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFontSizeSelector(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.fontSize, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ValueListenableBuilder<double>(
            valueListenable: fontSizeNotifier,
            builder: (_, currentScale, __) {
              return SegmentedButton<FontSizeOption>(
                segments: <ButtonSegment<FontSizeOption>>[
                  ButtonSegment<FontSizeOption>(value: FontSizeOption.small, label: Text(l10n.fontSmall)),
                  ButtonSegment<FontSizeOption>(value: FontSizeOption.medium, label: Text(l10n.fontDefault)),
                  ButtonSegment<FontSizeOption>(value: FontSizeOption.large, label: Text(l10n.fontLarge)),
                ],
                selected: {_getFontSizeOption(currentScale)},
                onSelectionChanged: (newSelection) {
                  // Convert the enum option back to a double scale and save it
                  final newScale = _getScaleFromOption(newSelection.first);
                  SettingsService.saveFontSize(newScale);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
