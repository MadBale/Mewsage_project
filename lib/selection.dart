// =============================================
// Mewsage - Mode Selection Screen
// Allows users to choose between real-time and file picker modes
// =============================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'realtime.dart';
import 'file_picker.dart';
import 'home.dart';

// =============================================
// Mode Selection Page Widget
// =============================================
class ChooseModePage extends StatelessWidget {
  const ChooseModePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF6F0),
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            _buildHeader(),
            const SizedBox(height: 16),
            _buildCatImage(),
            const SizedBox(height: 16),
            _buildBottomPanel(context),
          ],
        ),
      ),
    );
  }

  // =============================================
  // App Bar with Back Button and Info
  // =============================================
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.black87),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MeowTalkHomePage()),
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.black87),
          tooltip: 'Instructions',
          onPressed: () => _showInstructionsDialog(context),
        ),
      ],
    );
  }

  // =============================================
  // Header Text Section
  // =============================================
  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'Welcome to',
          style: GoogleFonts.poppins(fontSize: 20, color: Colors.black87),
        ),
        Text(
          'MeowTalk',
          style: GoogleFonts.pacifico(
            fontSize: 36,
            color: const Color(0xFFFF7B54),
          ),
        ),
      ],
    );
  }

  // =============================================
  // Cat Image Display
  // =============================================
  Widget _buildCatImage() {
    return Image.asset('assets/cat.png', height: 160);
  }

  // =============================================
  // Bottom Panel with Mode Selection
  // =============================================
  Widget _buildBottomPanel(BuildContext context) {
    return Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        decoration: const BoxDecoration(
          color: Color(0xFFFF7B54),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Choose Your Mode',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            _buildModeButtons(context),
            const Spacer(),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // =============================================
  // Mode Selection Buttons
  // =============================================
  Widget _buildModeButtons(BuildContext context) {
    return Column(
      children: [
        ModeButton(
          text: '🎙️  Real-time Mode',
          color: const Color(0xFFB0E1FF),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RealTimePage()),
            );
          },
        ),
        const SizedBox(height: 16),
        ModeButton(
          text: '📁  File Picker Mode',
          color: const Color(0xFFFCD5CE),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FilePickerPage()),
            );
          },
        ),
      ],
    );
  }

  // =============================================
  // Footer Section
  // =============================================
  Widget _buildFooter() {
    return Column(
      children: [
        const Divider(thickness: 1, color: Colors.white70),
        const SizedBox(height: 8),
        Text(
          'You can switch modes anytime!',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // =============================================
  // Instructions Dialog
  // =============================================
  void _showInstructionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How to Use'),
        content: const Text(
          '🧡 Real-time Mode:\nSpeak to your cat and get instant translations.\n\n'
          '📁 File Picker Mode:\nUpload a recorded meow to see the translation.\n\n'
          'You can switch modes anytime using the buttons below.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }
}

// =============================================
// Mode Selection Button Widget
// =============================================
class ModeButton extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onPressed;

  const ModeButton({
    super.key,
    required this.text,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black87,
          elevation: 4,
          textStyle: const TextStyle(fontSize: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
