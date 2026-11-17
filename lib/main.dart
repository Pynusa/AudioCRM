import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(ChangeNotifierProvider.value(value: state, child: const EchoScriptApp()));
}

class EchoScriptApp extends StatelessWidget {
  const EchoScriptApp({super.key});

  static const seed = Color(0xFF4F46E5);

  ThemeData _theme(Brightness b) {
    final cs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: b,
      primary: b == Brightness.light ? seed : const Color(0xFF818CF8),
    );
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: dark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:
            dark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: dark ? const Color(0xFF0F172A) : Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF0F172A) : Colors.white,
        indicatorColor: cs.primaryContainer,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'EchoScript AI',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}
