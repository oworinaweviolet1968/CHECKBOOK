import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/passcode_service.dart';
import '../utils/colors.dart';
import 'passcode_dialog.dart';

class PasscodeModal extends StatefulWidget {
  final bool canUseBiometrics;

  const PasscodeModal({
    super.key,
    this.canUseBiometrics = false,
  });

  static Future<bool> show(BuildContext context) async {
    return PasscodeDialog.show(context, reason: "Enter passcode to unlock metrics");
  }

  @override
  State<PasscodeModal> createState() => _PasscodeModalState();
}

class _PasscodeModalState extends State<PasscodeModal> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  bool _hasError = false;
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    // Request focus automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    if (_isSubmitting) return;

    if (_hasError) {
      setState(() {
        _hasError = false;
        _errorMessage = null;
      });
    }

    if (val.length == 6) {
      _submitPin(val);
    } else {
      setState(() {});
    }
  }

  Future<void> _submitPin(String pin) async {
    setState(() {
      _isSubmitting = true;
    });

    final isValid = await PasscodeService.instance.verifyPasscode(pin);

    if (!mounted) return;

    if (isValid) {
      Navigator.of(context).pop(true);
    } else {
      _shakeController.forward(from: 0.0);
      setState(() {
        _hasError = true;
        _errorMessage = "Incorrect passcode. Try again.";
        _isSubmitting = false;
      });

      // Auto-clear PIN after shake
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _controller.clear();
          setState(() {});
        }
      });
    }
  }

  Future<void> _triggerBiometrics() async {
    final success = await PasscodeService.instance.authenticateWithBiometrics();
    if (mounted && success) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinLength = _controller.text.length;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Top-Right Close Button
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
                  onPressed: () => Navigator.of(context).pop(false),
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),

                  // Header Lock Icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: AppColors.primaryGreen,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title & Subtitle
                  Text(
                    'Enter Passcode',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter your 6-digit passcode to unlock metrics',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF666666),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Hidden TextField to receive native keyboard input
                  SizedBox(
                    width: 1,
                    height: 1,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      autofocus: true,
                      obscureText: true,
                      onChanged: _onChanged,
                      decoration: const InputDecoration(
                        counterText: "",
                        border: InputBorder.none,
                      ),
                    ),
                  ),

                  // 6 PIN Digit Indicators with Expanded layout (prevents overflow)
                  GestureDetector(
                    onTap: () => _focusNode.requestFocus(),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(_shakeAnimation.value, 0),
                          child: child,
                        );
                      },
                      child: Row(
                        children: List.generate(6, (index) {
                          final isFilled = index < pinLength;
                          final isError = _hasError;

                          Color borderColor = const Color(0xFFE0E0E0);
                          Color fillColor = Colors.white;

                          if (isError) {
                            borderColor = AppColors.accentPink;
                          } else if (isFilled) {
                            borderColor = AppColors.primaryGreen;
                            fillColor = AppColors.primaryGreen.withValues(alpha: 0.05);
                          }

                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              height: 48,
                              decoration: BoxDecoration(
                                color: fillColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: borderColor,
                                  width: isFilled || isError ? 2.0 : 1.5,
                                ),
                              ),
                              child: Center(
                                child: isFilled
                                    ? Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: isError ? AppColors.accentPink : AppColors.primaryGreen,
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),

                  // Error Message
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 20,
                    child: _errorMessage != null
                        ? Text(
                            _errorMessage!,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accentPink,
                            ),
                          )
                        : null,
                  ),

                  // Biometrics Action Button (if enabled)
                  if (widget.canUseBiometrics) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _triggerBiometrics,
                      icon: const Icon(Icons.fingerprint, color: AppColors.primaryGreen, size: 20),
                      label: Text(
                        'Use Biometrics',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
