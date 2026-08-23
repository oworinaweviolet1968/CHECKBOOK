import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/colors.dart';

class WebVerificationRequiredScreen extends StatelessWidget {
  final String? customMessage;
  final String? portalUrl;

  const WebVerificationRequiredScreen({
    super.key,
    this.customMessage,
    this.portalUrl,
  });

  Future<void> _launchWebPortal(BuildContext context) async {
    final url = Uri.parse(portalUrl ?? 'https://checkbookug.vercel.app/#/checkout');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not launch web portal in browser.', style: GoogleFonts.outfit()),
              backgroundColor: AppColors.accentRed,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error launching browser: $e', style: GoogleFonts.outfit()),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Security Shield & Web Lock Icon Container (White & Green Theme)
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 48,
                  color: AppColors.darkGreen,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                'Web Verification Required',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),

              // Message Body Card
              Container(
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAF9), // Soft clean white-green tinted fill
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Text(
                  customMessage ??
                      'Direct new user registration is disabled on the mobile app.\n\nPlease complete your initial account registration, billing phone setup, and 7-day free trial verification on our web portal before logging in here.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // Action Button: Open Web Portal
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => _launchWebPortal(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    shadowColor: AppColors.primaryGreen.withValues(alpha: 0.4),
                  ),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 22, color: Colors.white),
                  label: Text(
                    'Complete Web Verification',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Secondary Button: Back to Login
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Back to Login',
                  style: GoogleFonts.outfit(
                    color: AppColors.darkGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

