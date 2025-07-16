// =============================================
// Mewsage - Cat Meow Translator App
// Main Application Entry Point
// =============================================

import 'package:flutter/material.dart';
import 'home.dart'; // This should contain MeowTalkHomePage

// =============================================
// Application Entry Point
// =============================================
void main() {
  debugPrint("Application starting...");
  runApp(const CatMeowTranslatorApp());
}

// =============================================
// Root Application Widget
// =============================================
class CatMeowTranslatorApp extends StatelessWidget {
  const CatMeowTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mewsage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const MeowTalkHomePage(),
    );
  }
}



