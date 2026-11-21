import 'package:flutter/material.dart';

import 'core/airports.dart';
import 'core/i18n.dart';
import 'services/native.dart';
import 'services/notifier.dart';
import 'services/store.dart';
import 'ui/home_shell.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.init();
  await Future.wait([store.load(), Airports.load()]);
  Native.init();
  runApp(const NflightApp());
}

class NflightApp extends StatelessWidget {
  const NflightApp({super.key});

  static const seed = Color(0xFF2B5CE6);

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        key: ValueKey(currentLang),
        navigatorKey: navigatorKey,
        title: 'Nflight',
        debugShowCheckedModeBanner: false,
        themeMode: store.themeMode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const HomeShell(),
      ),
    );
  }
}
