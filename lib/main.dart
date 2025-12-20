import 'package:flutter/material.dart';
import 'main_page.dart';
import 'models/app_settings_model.dart';
import 'services/setting_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  final SettingsService _settingsService = SettingsService();

  AppSettings _currentSettings = AppSettings.defaults;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadSettings();
  }

  Future<void> loadSettings() async {
    final settings = await _settingsService.getSettings();
    setState(() {
      _currentSettings = settings;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'ConnSSH',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: MainPage(
        settingsService: _settingsService,
        onSettingsChanged: loadSettings,
      ),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(),
          child: child!,
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    Color seedColor;
    final _isdark = brightness == Brightness.light;

    switch (_currentSettings.defaultPageTheme) {
      case 'orange':
        seedColor = Colors.orange;
        break;
      case 'green':
        seedColor = Colors.green;
        break;
      case 'yellow':
        seedColor = Colors.yellow;
        break;
      case 'monochrome':
        seedColor = _isdark ? Colors.black : Colors.white;
        break;
      case 'default':
      default:
        seedColor = Colors.blueAccent;
    }

    return ThemeData(
      fontFamily: 'hmossans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      useMaterial3: true,
    );
  }
}
