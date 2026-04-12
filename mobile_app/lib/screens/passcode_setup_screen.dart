import 'package:flutter/material.dart';
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
  String? _tempPasscode;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailController.text = Supabase.instance.client.auth.currentUser?.email ?? "";
  }

  void _verifyOwnership() async {
    setState(() => _isLoading = true);
    try {
      // Re-authenticate to verify ownership
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      setState(() => _step = 2);
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: Invalid credentials'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
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
        const SnackBar(content: Text('Passcode created successfully!'), backgroundColor: AppColors.primaryGreen),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Setup Passcode', style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProgressIndicator(),
            const SizedBox(height: 40),
            if (_step == 1) _buildVerifyStep(),
            if (_step == 2) _buildCreateStep(),
            if (_step == 3) _buildConfirmStep(),
            const Spacer(),
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            else
              ElevatedButton(
                onPressed: _step == 1 ? _verifyOwnership : (_step == 2 ? _goToConfirm : _completeSetup),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_step == 3 ? 'Confirm & Save' : 'Next', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: [
        _buildDot(active: _step >= 1),
        _buildLine(active: _step >= 2),
        _buildDot(active: _step >= 2),
        _buildLine(active: _step >= 3),
        _buildDot(active: _step >= 3),
      ],
    );
  }

  Widget _buildDot({required bool active}) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: active ? AppColors.primaryGreen : Colors.grey.shade300,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildLine({required bool active}) {
    return Expanded(
      child: Container(
        height: 2,
        color: active ? AppColors.primaryGreen : Colors.grey.shade300,
      ),
    );
  }

  Widget _buildVerifyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Verify Ownership', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Please verify your account details to continue.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
        ),
      ],
    );
  }

  Widget _buildCreateStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Create Passcode', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Setup a 6-digit passcode to secure your metrics.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 32),
        TextField(
          controller: _passcodeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            counterText: "",
            hintText: "create passcode",
            hintStyle: TextStyle(fontSize: 16, letterSpacing: 0, fontWeight: FontWeight.normal, color: Colors.grey),
          ),
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              _errorMessage!, 
              style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)
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
        const Text('Confirm Passcode', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Please re-enter your passcode.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 32),
        TextField(
          controller: _confirmPasscodeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          obscureText: true,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            counterText: "",
            hintText: "confirm passcode",
            hintStyle: TextStyle(fontSize: 16, letterSpacing: 0, fontWeight: FontWeight.normal, color: Colors.grey),
          ),
          onChanged: (_) {
            if (_errorMessage != null) setState(() => _errorMessage = null);
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              _errorMessage!, 
              style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)
            ),
          ),
        ],
      ],
    );
  }
}
