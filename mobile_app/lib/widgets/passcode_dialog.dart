import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/passcode_service.dart';
import '../utils/colors.dart';

class PasscodeDialog extends StatefulWidget {
  final String reason;
  final bool canUseBiometrics;

  const PasscodeDialog({
    super.key,
    this.reason = "Confirm authorization to proceed",
    this.canUseBiometrics = true,
  });

  /// Displays the unified iOS-style security verification dialog.
  /// Returns `true` if authorized, `false` or `null` if canceled or invalid.
  static Future<bool> show(
    BuildContext context, {
    String reason = "Confirm authorization to proceed",
  }) async {
    // If no passcode is set in settings, default auto-authorize
    if (!PasscodeService.instance.hasPasscode) {
      return true;
    }

    final canBio = await PasscodeService.instance.canCheckBiometrics() &&
        PasscodeService.instance.isBiometricsEnabled.value;

    if (!context.mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) => PasscodeDialog(reason: reason, canUseBiometrics: canBio),
    );

    return result ?? false;
  }

  @override
  State<PasscodeDialog> createState() => _PasscodeDialogState();
}

class _PasscodeDialogState extends State<PasscodeDialog> with SingleTickerProviderStateMixin {
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
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -14.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -14.0, end: 14.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 14.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -5.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        if (widget.canUseBiometrics) {
          _triggerBiometrics();
        }
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
      _verifyPin(val);
    } else {
      setState(() {});
    }
  }

  Future<void> _verifyPin([String? optionalPin]) async {
    final pin = optionalPin ?? _controller.text.trim();
    if (pin.isEmpty) return;

    setState(() {
      _isSubmitting = true;
    });

    final isValid = await PasscodeService.instance.verifyPasscode(pin);

    if (!mounted) return;

    if (isValid) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } else {
      // Trigger iOS horizontal shake + haptic vibration
      HapticFeedback.vibrate();
      _shakeController.forward(from: 0.0);
      setState(() {
        _hasError = true;
        _errorMessage = "Incorrect passcode. Try again.";
        _isSubmitting = false;
      });

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
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Security Badge (56x56 Circular Cyan Badge)
              Center(
                child: Container(
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
              ),
              const SizedBox(height: 16),

              // Title & Context Reason
              Text(
                'Security Verification',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                widget.reason,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Hidden Native Numeric Keyboard Receiver TextField
              SizedBox(
                width: 1,
                height: 1,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  autofocus: true,
                  obscureText: true,
                  onChanged: _onChanged,
                  decoration: const InputDecoration(
                    counterText: "",
                    border: InputBorder.none,
                  ),
                ),
              ),

              // iOS 6 PIN Indicator Dots Row with Shake Animation
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(6, (index) {
                          final isFilled = index < pinLength;
                          final isError = _hasError;

                          Color borderColor = const Color(0xFFCBD5E1);
                          Color fillColor = Colors.white;

                          if (isError) {
                            borderColor = const Color(0xFFEF4444);
                            fillColor = const Color(0xFFFEE2E2);
                          } else if (isFilled) {
                            borderColor = AppColors.primaryGreen;
                            fillColor = AppColors.primaryGreen.withValues(alpha: 0.1);
                          }

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            width: 38,
                            height: 46,
                            decoration: BoxDecoration(
                              color: fillColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: borderColor,
                                width: isFilled || isError ? 2.0 : 1.2,
                              ),
                            ),
                            child: Center(
                              child: isFilled
                                  ? AnimatedScale(
                                      scale: 1.0,
                                      duration: const Duration(milliseconds: 120),
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: isError ? const Color(0xFFEF4444) : AppColors.primaryGreen,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          );
                        }),
                      ),
                      if (widget.canUseBiometrics) ...[
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: _triggerBiometrics,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.lightCyan,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF00A389).withValues(alpha: 0.3)),
                            ),
                            child: const Icon(
                              Icons.fingerprint,
                              color: AppColors.primaryGreen,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Error Message Text
              SizedBox(
                height: 28,
                child: Center(
                  child: _errorMessage != null
                      ? Text(
                          _errorMessage!,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFEF4444),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),

              // Action Buttons Row (Cancel & Verify)
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFFF1F5F9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : () => _verifyPin(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Verify',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
