// =============================================
// Mewsage - Home Screen
// Main landing page of the application
// =============================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'selection.dart';

// =============================================
// Home Page Widget
// =============================================
class MeowTalkHomePage extends StatelessWidget {
  const MeowTalkHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildMainContainer(),
    );
  }

  // =============================================
  // Main Container with Gradient Background
  // =============================================
  Widget _buildMainContainer() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFDF7F3), Color(0xFFFFE4D2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              _buildPawIcon(),
              const SizedBox(height: 10),
              _buildWelcomeText(),
              const SizedBox(height: 30),
              _buildMainCard(),
              const Spacer(),
              _buildStartButton(context),
            ],
          ),
        ),
      ),
    );
  }

  // =============================================
  // Decorative Paw Icon
  // =============================================
  Widget _buildPawIcon() {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.pets, size: 36, color: Color(0xFFFF7B54)),
      ),
    );
  }

  // =============================================
  // Welcome Text Section
  // =============================================
  Widget _buildWelcomeText() {
    return Column(
      children: [
        Text(
          'Welcome to',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Mewsage',
          style: GoogleFonts.pacifico(
            fontSize: 42,
            color: Color(0xFFFF7B54),
          ),
        ),
      ],
    );
  }

  // =============================================
  // Main Card with Cat Image
  // =============================================
  Widget _buildMainCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE97438),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color.fromRGBO(0, 0, 0, 1),
            offset: const Offset(0, 6),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCatImageWithBubble(),
          const SizedBox(height: 20),
          _buildPawIcons(),
        ],
      ),
    );
  }

  // =============================================
  // Cat Image with Speech Bubble
  // =============================================
  Widget _buildCatImageWithBubble() {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        Center(
          child: Image.asset(
            'assets/cat.png',
            height: 180,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Text(
              'Hello!',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  // =============================================
  // Decorative Paw Icons
  // =============================================
  Widget _buildPawIcons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.pets, color: Colors.white, size: 28),
        SizedBox(width: 12),
        Icon(Icons.pets, color: Colors.white, size: 28),
      ],
    );
  }

  // =============================================
  // Start Button
  // =============================================
  Widget _buildStartButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChooseModePage()),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF7B54),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          elevation: 6,
          textStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(color: Colors.white, width: 2),
          ),
        ),
        child: const Text("Let's Get Started"),
      ),
    );
  }
}
