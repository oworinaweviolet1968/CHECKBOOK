import 'dart:async';
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
import 'services/passcode_service.dart';
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
    await PasscodeService.instance.init();
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
  int _selectedIndex = 0; // Default to Dashboard (In Stock)
  final GlobalKey<DashboardScreenState> _dashboardKey = GlobalKey<DashboardScreenState>();
  StreamSubscription? _loginRequestSubscription;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardScreen(key: _dashboardKey),
      NewStockScreen(),
      ProcessSaleScreen(),
      HistoryScreen(),
    ];
    _initDatabase();
    _listenForLoginRequests();
  }

  Future<void> _initDatabase() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await SupasService.instance.migrateLegacyDatabase();
      await DatabaseHelper.instance.switchDatabase(userId);
      await PasscodeService.instance.init();
      // Trigger a sync in background too
      SupasService.instance.syncDatabase();
    }
  }

  void _listenForLoginRequests() {
    _loginRequestSubscription = SupasService.instance.getLoginRequestsStream().listen((requests) {
      if (requests.isNotEmpty) {
        final request = requests.first;
        _showLoginApprovalDialog(request);
      }
    });
  }

  void _showLoginApprovalDialog(Map<String, dynamic> request) {
    if (_isDialogOpen) return;
    _isDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Login Approval'),
        content: Text('Approve login request for ${request['email']} on desktop application?'),
        actions: [
          TextButton(
            onPressed: () async {
              await SupasService.instance.updateLoginRequestStatus(request['id'], 'rejected');
              if (mounted) Navigator.of(context).pop();
              _isDialogOpen = false;
            },
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () async {
              await SupasService.instance.updateLoginRequestStatus(request['id'], 'approved');
              if (mounted) Navigator.of(context).pop();
              _isDialogOpen = false;
            },
            child: const Text('Approve', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _loginRequestSubscription?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == 0 && _selectedIndex == 0) {
      // Already on dashboard, maybe force refresh?
      _dashboardKey.currentState?.refreshData();
    } else if (index == 0) {
      // Navigating TO dashboard
      _dashboardKey.currentState?.refreshData();
    }

    setState(() {
        _selectedIndex = index;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    // If index is out of bounds (e.g. initial), safe check
    final safeIndex = (_selectedIndex >= 0 && _selectedIndex < _screens.length) ? _selectedIndex : 0;

    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: SupasService.instance.userMetadata,
      builder: (context, meta, child) {
        final now = DateTime.now().millisecondsSinceEpoch;

        // 1. Ownership Check
        final isOwnershipEnabled = meta?['ownership_payment'] as bool? ?? false;
        final ownershipExpiry = meta?['ownership_expiry'] as int? ?? 0;
        final isOwnershipActive = isOwnershipEnabled && (ownershipExpiry == 0 || ownershipExpiry > now);

        if (!isOwnershipActive && meta != null) {
          // Trigger ownership popup if not active
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showOwnershipRequiredDialog();
          });
        }

        // 2. Backup Subscription Banner
        final isBackupEnabled = meta?['monthly_cloud_backup'] as bool? ?? true;
        final backupExpiry = meta?['backup_expiry'] as int? ?? 0;
        final isBackupActive = isBackupEnabled && (backupExpiry == 0 || backupExpiry > now);

        return Scaffold(
          body: Column(
            children: [
              if (!isBackupActive && meta != null)
                MaterialBanner(
                  content: const Text(
                    'Backup Subscription Inactive. Your data is not being synced to the cloud.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => SupasService.instance.refreshUserMetadata(),
                      child: const Text('REFRESH', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  backgroundColor: Colors.orange.shade800,
                  elevation: 2,
                ),
              Expanded(child: _screens[safeIndex]),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Icon(Icons.inventory_2_outlined),
                activeIcon: Icon(Icons.inventory_2),
                label: 'In Stock',
              ),
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
                icon: Icon(Icons.history),
                label: 'History',
              ),
            ],
            currentIndex: safeIndex,
            selectedItemColor: AppColors.primaryGreen,
            unselectedItemColor: AppColors.textSecondary,
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
            onTap: _onItemTapped,
            backgroundColor: Colors.white,
            elevation: 8,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          ),
        );
      },
    );
  }

  bool _isDialogOpen = false;

  void _showOwnershipRequiredDialog() {
    if (_isDialogOpen) return;
    _isDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.red),
              SizedBox(width: 8),
              Text('Ownership Required'),
            ],
          ),
          content: const Text(
            'Your application ownership has expired or is not verified. Please contact support to activate your license and continue using the app.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await SupasService.instance.refreshUserMetadata();
                final meta = SupasService.instance.userMetadata.value;
                final now = DateTime.now().millisecondsSinceEpoch;
                final isOwnershipEnabled = meta?['ownership_payment'] as bool? ?? false;
                final ownershipExpiry = meta?['ownership_expiry'] as int? ?? 0;
                final isOwnershipActive = isOwnershipEnabled && (ownershipExpiry == 0 || ownershipExpiry > now);

                if (isOwnershipActive) {
                  Navigator.of(context).pop();
                  _isDialogOpen = false;
                }
              },
              child: const Text('RETRY / VERIFY'),
            ),
          ],
        ),
      ),
    );
  }
}
