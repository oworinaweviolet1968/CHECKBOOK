import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/passcode_service.dart';
import '../utils/colors.dart';

class PasscodeSetupScreen extends StatefulWidget {
  const PasscodeSetupScreen({super.key});

  @override
  State<PasscodeSetupScreen> createState() => _PasscodeSetupScreenState();
}

class _PasscodeSetupScreenState extends State<PasscodeSetupScreen> {
  int _step = 1; // 1: Verify, 2: Create, 3: Confirm
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passcodeController = TextEditingController();
  final _confirmPasscodeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _tempPasscode;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController.text = Supabase.instance.client.auth.currentUser?.email ?? "";
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passcodeController.dispose();
    _confirmPasscodeController.dispose();
    super.dispose();
  }

  void _verifyOwnership() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter your account password.', style: GoogleFonts.outfit()),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: password,
      );
      setState(() {
        _step = 2;
        _errorMessage = null;
      });
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message, style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: Invalid credentials', style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToConfirm() {
    if (_passcodeController.text.length != 6) {
      setState(() => _errorMessage = 'Passcode must be 6 digits');
      return;
    }
    setState(() {
      _errorMessage = null;
      _tempPasscode = _passcodeController.text;
      _step = 3;
    });
  }

  void _completeSetup() async {
    if (_confirmPasscodeController.text != _tempPasscode) {
      setState(() => _errorMessage = 'Passcodes do not match');
      return;
    }
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    await PasscodeService.instance.setPasscode(_tempPasscode!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Passcode created successfully!', style: GoogleFonts.outfit()),
          backgroundColor: AppColors.primaryGreen,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Setup Passcode',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProgressIndicator(),
              const SizedBox(height: 32),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_step == 1) _buildVerifyStep(),
                      if (_step == 2) _buildCreateStep(),
                      if (_step == 3) _buildConfirmStep(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_step == 1
                          ? _verifyOwnership
                          : (_step == 2 ? _goToConfirm : _completeSetup)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: const Color(0x3300D09C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          _step == 1
                              ? 'Verify Account'
                              : (_step == 2 ? 'Next Step' : 'Confirm & Save'),
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Modern 3-Step Wizard Progress Indicator Bar
  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neutralBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStepPill(stepNum: 1, label: 'Verify', active: _step == 1, completed: _step > 1),
          _buildStepDivider(active: _step > 1),
          _buildStepPill(stepNum: 2, label: 'Create', active: _step == 2, completed: _step > 2),
          _buildStepDivider(active: _step > 2),
          _buildStepPill(stepNum: 3, label: 'Confirm', active: _step == 3, completed: false),
        ],
      ),
    );
  }

  Widget _buildStepPill({
    required int stepNum,
    required String label,
    required bool active,
    required bool completed,
  }) {
    final Color fgColor = completed
        ? const Color(0xFF166534)
        : (active ? AppColors.primaryGreen : const Color(0xFF64748B));

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: active ? AppColors.primaryGreen : (completed ? const Color(0xFF10B981) : const Color(0xFFCBD5E1)),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: completed
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '$stepNum',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: active || completed ? FontWeight.bold : FontWeight.w500,
            color: fgColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider({required bool active}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        height: 2,
        color: active ? AppColors.primaryGreen : const Color(0xFFE2E8F0),
      ),
    );
  }

  Widget _buildVerifyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Header Circular Cyan Badge
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.lightCyan,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.shield_rounded,
            color: AppColors.primaryGreen,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Verify Ownership',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Please enter your account password to authorize passcode creation.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 28),

        // Readonly Email Field
        Text(
          'Account Email',
          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          readOnly: true,
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primaryGreen, size: 20),
            filled: true,
            fillColor: const Color(0xFFF1F5F9),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Password Field with Visibility Toggle
        Text(
          'Account Password',
          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w500, color: const Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: 'Enter password',
            hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14),
            prefixIcon: const Icon(Icons.lock_outlined, color: AppColors.primaryGreen, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: const Color(0xFF94A3B8),
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2.0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.lightCyan,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.lock_rounded,
            color: AppColors.primaryGreen,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Create Passcode',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Set a 6-digit PIN code to secure metrics and administrative actions.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _passcodeController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          obscureText: true,
          textAlign: TextAlign.center,
          autofocus: true,
          style: GoogleFonts.outfit(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
          decoration: InputDecoration(
            counterText: "",
            hintText: "••••••",
            hintStyle: GoogleFonts.outfit(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.normal, color: const Color(0xFFCBD5E1)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2.0),
            ),
          ),
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConfirmStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: AppColors.lightCyan,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.verified_user_rounded,
            color: AppColors.primaryGreen,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Confirm Passcode',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Re-enter your 6-digit PIN code to confirm setup.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _confirmPasscodeController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          obscureText: true,
          textAlign: TextAlign.center,
          autofocus: true,
          style: GoogleFonts.outfit(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
          decoration: InputDecoration(
            counterText: "",
            hintText: "••••••",
            hintStyle: GoogleFonts.outfit(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.normal, color: const Color(0xFFCBD5E1)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2.0),
            ),
          ),
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }
}
