import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/dashboard_screen.dart';
import 'screens/new_stock_screen.dart';
import 'screens/process_sale_screen.dart';
import 'screens/history_screen.dart';
import 'screens/login_screen.dart';
import 'services/database_helper.dart';
import 'services/supabase_service.dart';
import 'utils/colors.dart';

// Credentials extracted from user's .env file
const supabaseUrl = 'https://jhucvkqwenhyiveqsmtf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpodWN2a3F3ZW5oeWl2ZXFzbXRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NzI5MjIsImV4cCI6MjA4NTU0ODkyMn0.yXju47Ly5ak8Gm4D0OI42O89qTsc0nYtkmAb7dGFCC8';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

  // Early DB initialization if already logged in
  final currentUserId = Supabase.instance.client.auth.currentUser?.id;
  if (currentUserId != null) {
    await DatabaseHelper.instance.switchDatabase(currentUserId);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventory App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primaryGreen),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: _getInitialScreen(),
    );
  }

  Widget _getInitialScreen() {
      // Check if logged in
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
          return const MainScreen();
      } else {
          return const LoginScreen();
      }
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 2; // Default to Dashboard

  @override
  void initState() {
    super.initState();
    _initDatabase();
  }

  Future<void> _initDatabase() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await SupasService.instance.migrateLegacyDatabase();
      await DatabaseHelper.instance.switchDatabase(userId);
      // Trigger a sync in background too
      SupasService.instance.syncDatabase();
    }
  }

  final List<Widget> _screens = [
    NewStockScreen(),
    ProcessSaleScreen(),
    DashboardScreen(),
    HistoryScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
        _selectedIndex = index;
    });
  }
  
  @override
  Widget build(BuildContext context) {
      // If index is out of bounds (e.g. initial), safe check
      final safeIndex = (_selectedIndex >= 0 && _selectedIndex < _screens.length) ? _selectedIndex : 2;
      
    return Scaffold(
      body: _screens[safeIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            activeIcon: Icon(Icons.add_box),
            label: 'New Stock',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            activeIcon: Icon(Icons.shopping_cart),
            label: 'Sales',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'In Stock',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
        currentIndex: safeIndex,
        selectedItemColor: AppColors.primaryGreen,
        unselectedItemColor: AppColors.textSecondary, // Was grey
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
        backgroundColor: Colors.white,
        elevation: 8,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
    );
  }
}
