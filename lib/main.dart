import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/services.dart';
import 'core/theme.dart';
import 'data/database.dart';
import 'state/app_state.dart';
import 'ui/shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RootApp());
}

/// Boots services (SQLite) and settings, then hands over to MaterialApp.
class RootApp extends StatefulWidget {
  const RootApp({super.key});

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  bool _ready = false;
  bool _failed = false;
  AppSettingsController? _controller;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await Services.instance.init();
      final ctrl = AppSettingsController(
        Services.instance.settings,
        Services.instance.images,
      );
      await ctrl.load();
      if (!mounted) return;
      setState(() {
        _controller = ctrl;
        _ready = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(Brightness.light, AppPalette.teal),
        home: Scaffold(
          body: Center(
            child: _failed
                ? const Text(
                    'راه‌اندازی پایگاه‌داده ممکن نشد.\nلطفاً برنامه را دوباره باز کنید.',
                    textAlign: TextAlign.center,
                    style: TextStyle(height: 1.9),
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('LocStore'),
                    ],
                  ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: Services.instance.db),
        ChangeNotifierProvider<AppSettingsController>.value(
            value: _controller!),
      ],
      child: Consumer<AppSettingsController>(
        builder: (context, ctrl, _) => MaterialApp(
          title: 'LocStore',
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa'),
          supportedLocales: const [Locale('fa'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.build(Brightness.light, ctrl.palette),
          darkTheme: AppTheme.build(Brightness.dark, ctrl.palette),
          themeMode: ctrl.themeMode,
          home: const AppShell(),
        ),
      ),
    );
  }
}
