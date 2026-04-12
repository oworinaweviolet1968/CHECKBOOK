import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/database_helper.dart';
import '../main.dart'; // To navigate to MainScreen
import '../utils/colors.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      
      if (email.isEmpty || password.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill in all fields')));
          return;
      }

      final response = await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      final userId = response.user?.id;
      
      if (userId != null) {
          // 1. Migrate legacy data if this is the first user-specific login
          await SupasService.instance.migrateLegacyDatabase();
          
          // 2. Switch to user-specific DB
          await DatabaseHelper.instance.switchDatabase(userId);
          
          // 3. Ensure cloud metadata exists
          await SupasService.instance.ensureUserMetadataExists(email);
          
          // 4. Run Sync
          await SupasService.instance.syncDatabase();
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } on AuthException catch (error) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message), backgroundColor: Colors.red));
    } catch (error) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $error'), backgroundColor: Colors.red));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Image.asset('assets/images/app_icon.png', height: 80),
                    const SizedBox(height: 24),
                    const Text('Welcome Back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    const Text('Sign in to continue', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 48),
                    
                    TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                    ),
                    const SizedBox(height: 24),
                    
                    SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                            child: _isLoading 
                                ? const CircularProgressIndicator(color: Colors.white) 
                                : const Text('Login', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () async {
                        final url = Uri.parse('https://beckhamz777.github.io/cb/#/checkout');
                        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not open website'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: const Text(
                        'Create an Account',
                        style: TextStyle(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
            )
        )
      ),
    );
  }
}
