import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/database_helper.dart';
import '../main.dart'; // To navigate to MainScreen
import '../utils/colors.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  late AnimationController _shakeController;

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;

  // Forgot Password Cooldown & Debouncing
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;
  bool _isSendingReset = false;

  // Quick-Account Selector
  List<String> _recentAccounts = [];
  String? _selectedAccount;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
    _loadRecentAccounts();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _shakeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
  }

  Future<void> _loadRecentAccounts() async {
    try {
      final jsonStr = await DatabaseHelper.instance.getSetting('recent_accounts');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            _recentAccounts = list.cast<String>();
            if (_recentAccounts.isNotEmpty) {
              _selectAccount(_recentAccounts.first);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading recent accounts: $e');
    }
  }

  Future<void> _saveRecentAccount(String email) async {
    try {
      final normalized = email.trim().toLowerCase();
      List<String> updated = List.from(_recentAccounts);
      updated.removeWhere((e) => e.toLowerCase() == normalized);
      updated.insert(0, normalized);
      if (updated.length > 4) {
        updated = updated.sublist(0, 4);
      }
      await DatabaseHelper.instance.saveSetting('recent_accounts', jsonEncode(updated));
      if (mounted) {
        setState(() {
          _recentAccounts = updated;
        });
      }
    } catch (e) {
      debugPrint('Error saving recent account: $e');
    }
  }

  Future<void> _removeRecentAccount(String email) async {
    try {
      final normalized = email.trim().toLowerCase();
      List<String> updated = List.from(_recentAccounts);
      updated.removeWhere((e) => e.toLowerCase() == normalized);
      await DatabaseHelper.instance.saveSetting('recent_accounts', jsonEncode(updated));
      if (mounted) {
        setState(() {
          _recentAccounts = updated;
          if (_selectedAccount?.toLowerCase() == normalized) {
            _selectedAccount = null;
            _emailController.clear();
          }
        });
      }
    } catch (e) {
      debugPrint('Error removing recent account: $e');
    }
  }

  void _selectAccount(String email) {
    setState(() {
      _selectedAccount = email.trim().toLowerCase();
      _emailController.text = _selectedAccount!;
      _emailError = null;
    });
    _passwordFocusNode.requestFocus();
  }

  void _clearSelectedAccount() {
    setState(() {
      _selectedAccount = null;
      _emailController.clear();
      _emailError = null;
    });
  }

  String _maskEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) return trimmed;
    final parts = trimmed.split('@');
    final name = parts[0];
    final domain = parts[1];

    if (name.length <= 2) {
      return '${name[0]}***@$domain';
    }
    return '${name[0]}***${name[name.length - 1]}@$domain';
  }

  String _getCleanErrorMessage(dynamic error) {
    final errString = error.toString().toLowerCase();
    if (errString.contains('invalid_credentials') ||
        errString.contains('invalid login credentials') ||
        errString.contains('invalid_grant') ||
        errString.contains('400')) {
      return 'Incorrect password. Please try again.';
    }
    if (errString.contains('email_not_confirmed') || errString.contains('email not confirmed')) {
      return 'Please verify your email address before logging in.';
    }
    if (errString.contains('user_not_found') || errString.contains('user not found')) {
      return 'This email is not registered with Checkbook yet.';
    }
    if (errString.contains('too_many_requests') ||
        errString.contains('over_email_send_rate_limit') ||
        errString.contains('429') ||
        errString.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment before trying again.';
    }
    if (errString.contains('socketexception') ||
        errString.contains('handshakeexception') ||
        errString.contains('network') ||
        errString.contains('connection failed')) {
      return 'Unable to connect to server. Please check your internet connection.';
    }
    return 'Authentication failed. Please try again.';
  }

  bool _validateFormat() {
    setState(() {
      _emailError = null;
      _passwordError = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    bool isValid = true;

    if (email.isEmpty) {
      _emailError = 'Email is required';
      isValid = false;
    } else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _emailError = 'Please enter a valid email address';
      isValid = false;
    }

    if (password.isEmpty) {
      _passwordError = 'Password is required';
      isValid = false;
    } else if (password.length < 6) {
      _passwordError = 'Password must be at least 6 characters';
      isValid = false;
    }

    if (!isValid) {
      _triggerShake();
    }

    setState(() {});
    return isValid;
  }

  /// Checks if an email exists using the SECURITY DEFINER RPC `check_email_exists`.
  /// Returns `false` if explicitly not found, `true` if found, and `null` if RPC call fails or is unconfigured.
  Future<bool?> _checkEmailExistsRpc(String email) async {
    try {
      final res = await Supabase.instance.client
          .rpc('check_email_exists', params: {'email_input': email.trim().toLowerCase()});
      if (res is bool) {
        return res;
      }
      return null;
    } catch (e) {
      debugPrint('RPC check_email_exists info: $e');
      return null;
    }
  }

  Future<void> _login() async {
    if (!_validateFormat()) return;

    setState(() {
      _isLoading = true;
      _emailError = null;
      _passwordError = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final userId = response.user?.id;

      if (userId != null) {
        final conflict = await SupasService.instance.checkSessionConflict(userId, category: 'mobile');
        if (conflict != null && mounted) {
          final shouldSwitch = await showCupertinoDialog<bool>(
            context: context,
            builder: (ctx) => CupertinoAlertDialog(
              title: const Text('Active Session Found'),
              content: Text(
                'You are currently logged in on ${conflict.activeDeviceName}.\n\nWould you like to log out of that device and log in here?',
              ),
              actions: [
                CupertinoDialogAction(
                  isDestructiveAction: true,
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Log Out Other Device & Continue'),
                ),
              ],
            ),
          );

          if (shouldSwitch != true) {
            await Supabase.instance.client.auth.signOut();
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            return;
          }
        }

        await SupasService.instance.registerSession(userId, category: 'mobile', force: true);
        await _saveRecentAccount(email);
        await SupasService.instance.migrateLegacyDatabase();
        await DatabaseHelper.instance.switchDatabase(userId);
        unawaited(SupasService.instance.syncDatabase());
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        _triggerShake();
        final msg = error.message.toLowerCase();
        final code = (error.code ?? '').toLowerCase();

        if (msg.contains('user not found') || msg.contains('user_not_found') || code.contains('user_not_found')) {
          setState(() {
            _emailError = 'This email is not registered with Checkbook yet.';
            _passwordError = null;
          });
        } else if (msg.contains('invalid login credentials') ||
            msg.contains('invalid_credentials') ||
            error.statusCode == '400') {
          // Perform RPC email existence check
          final exists = await _checkEmailExistsRpc(email);
          if (mounted) {
            setState(() {
              if (exists == false) {
                _emailError = 'This email is not registered with Checkbook yet.';
                _passwordError = null;
              } else {
                _emailError = null;
                _passwordError = 'Incorrect password. Please try again or tap Forgot Password.';
              }
            });
          }
        } else {
          setState(() {
            _emailError = null;
            _passwordError = _getCleanErrorMessage(error);
          });
        }
      }
    } catch (error) {
      if (mounted) {
        _triggerShake();
        setState(() {
          _emailError = null;
          _passwordError = _getCleanErrorMessage(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_cooldownSeconds > 0 || _isSendingReset) return;

    setState(() {
      _emailError = null;
      _passwordError = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _triggerShake();
      setState(() {
        _emailError = 'Please enter a valid email address first';
      });
      return;
    }

    setState(() {
      _isSendingReset = true;
    });

    // RPC check before sending reset link
    final exists = await _checkEmailExistsRpc(email);
    if (exists == false) {
      if (mounted) {
        _triggerShake();
        setState(() {
          _isSendingReset = false;
          _emailError = 'This email is not registered with Checkbook yet.';
        });
      }
      return;
    }

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Password reset link sent! Check your inbox.')),
              ],
            ),
            backgroundColor: AppColors.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        _startCooldownTimer(60);
      }
    } on AuthException catch (error) {
      if (mounted) {
        _triggerShake();
        final msg = error.message.toLowerCase();
        final code = (error.code ?? '').toLowerCase();
        if (msg.contains('user not found') || msg.contains('user_not_found') || code.contains('user_not_found')) {
          setState(() {
            _emailError = 'This email is not registered with Checkbook yet.';
          });
        } else {
          setState(() {
            _emailError = _getCleanErrorMessage(error);
          });
        }
      }
    } catch (error) {
      if (mounted) {
        _triggerShake();
        setState(() {
          _emailError = _getCleanErrorMessage(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingReset = false;
        });
      }
    }
  }

  void _startCooldownTimer(int seconds) {
    _cooldownTimer?.cancel();
    setState(() {
      _cooldownSeconds = seconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _cooldownSeconds = 0;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _cooldownSeconds--;
          });
        }
      }
    });
  }

  Widget _buildBrandingHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Image.asset('assets/images/app_icon.png', height: 60),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'CHECK',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.6,
                color: AppColors.textPrimary,
              ),
            ),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [
                  Color(0xFF06B6D4), // Cyan
                  Color(0xFF3B82F6), // Blue
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: const Text(
                'BOOK',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Inventory & Business Management',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAccountSwitcherPill() {
    if (_selectedAccount == null || _selectedAccount!.isEmpty) {
      if (_recentAccounts.isEmpty) return const SizedBox.shrink();

      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RECENT ACCOUNTS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._recentAccounts.map((accountEmail) {
                    final initial = accountEmail.isNotEmpty ? accountEmail[0].toUpperCase() : 'U';
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _selectAccount(accountEmail),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 11,
                                  backgroundColor: const Color(0xFF3B82F6),
                                  child: Text(
                                    initial,
                                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _maskEmail(accountEmail),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => _removeRecentAccount(accountEmail),
                                  child: const Icon(Icons.close, size: 14, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final initial = _selectedAccount!.isNotEmpty ? _selectedAccount![0].toUpperCase() : 'U';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _maskEmail(_selectedAccount!),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Saved Account',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _clearSelectedAccount,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Switch Account',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFD),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final shakeOffset = math.sin(_shakeController.value * math.pi * 4) * 10;
                return Transform.translate(
                  offset: Offset(shakeOffset, 0),
                  child: child,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withOpacity(0.06), width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 32,
                      spreadRadius: 0,
                      offset: Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Color(0x05000000),
                      blurRadius: 8,
                      spreadRadius: 0,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBrandingHeader(),
                    const SizedBox(height: 32),

                    _buildQuickAccountSwitcherPill(),

                    // Email Field
                    if (_selectedAccount == null) ...[
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) {
                          if (_emailError != null) {
                            setState(() {
                              _emailError = null;
                            });
                          }
                        },
                        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'name@example.com',
                          errorText: _emailError,
                          errorMaxLines: 3,
                          prefixIcon: const Icon(Icons.email_outlined, size: 20, color: Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF2F2F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Password Field
                    TextField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      obscureText: _obscurePassword,
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() {
                            _passwordError = null;
                          });
                        }
                      },
                      onSubmitted: (_) => _login(),
                      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        errorText: _passwordError,
                        errorMaxLines: 3,
                        prefixIcon: const Icon(Icons.lock_outline, size: 20, color: Color(0xFF64748B)),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 20,
                            color: const Color(0xFF64748B),
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF2F2F7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Actions Row: Forgot Password & Clear Session
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: (_cooldownSeconds > 0 || _isSendingReset) ? null : _handleForgotPassword,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isSendingReset)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6.0),
                                  child: SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              Text(
                                _cooldownSeconds > 0 ? 'Resend in ${_cooldownSeconds}s' : 'Forgot Password?',
                                style: TextStyle(
                                  color: _cooldownSeconds > 0 ? Colors.grey : const Color(0xFF3B82F6),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await Supabase.instance.client.auth.signOut();
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text('Local session cleared.'),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Session clear error: $e'),
                                    backgroundColor: const Color(0xFFEF4444),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                );
                              }
                            }
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Clear Session',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Tactile Primary Login Button
                    Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B77F), Color(0xFF0D9263)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2610B77F),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Sign Up Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                        GestureDetector(
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final url = Uri.parse('https://beckhamz777.github.io/cb/#/checkout');
                            if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text('Could not open website'),
                                    backgroundColor: const Color(0xFFEF4444),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                              color: Color(0xFF3B82F6),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
