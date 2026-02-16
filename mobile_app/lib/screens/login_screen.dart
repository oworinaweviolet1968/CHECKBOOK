import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../main.dart'; // To navigate to MainScreen
import '../utils/colors.dart';

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

      await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      
      // Sync on login
      // Wait for sync or show progress? 
      // For now, simple wait.
      await SupasService.instance.syncDatabase();

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
                    const Icon(Icons.inventory_2, size: 80, color: AppColors.primaryGreen),
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
                ],
            )
        )
      ),
    );
  }
}
