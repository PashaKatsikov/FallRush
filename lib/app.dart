import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

class FallRushApp extends StatelessWidget {
  const FallRushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fall Rush',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05060F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF00C8),
          surface: Color(0xFF0C1024),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
