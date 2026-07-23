import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'screens/dashboard_screen.dart';
import 'screens/new_stock_screen.dart';
import 'screens/process_sale_screen.dart';
import 'screens/history_screen.dart';
import 'screens/login_screen.dart';
import 'services/database_helper.dart';
import 'services/supabase_service.dart';
import 'services/passcode_service.dart';
import 'utils/colors.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

// Credentials extracted from user's .env file
const supabaseUrl = 'https://jhucvkqwenhyiveqsmtf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpodWN2a3F3ZW5oeWl2ZXFzbXRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NzI5MjIsImV4cCI6MjA4NTU0ODkyMn0.yXju47Ly5ak8Gm4D0OI42O89qTsc0nYtkmAb7dGFCC8';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // Local notifications setup for foreground messages
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel', 
        'High Importance Notifications', 
        description: 'This channel is used for important notifications.', 
        importance: Importance.max,
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

        if (notification != null && android != null) {
          flutterLocalNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                icon: '@mipmap/ic_launcher',
                importance: Importance.max,
                priority: Priority.high,
              ),
            ),
          );
        }
      });

      await FirebaseMessaging.instance.subscribeToTopic('desktop_actions');
      await FirebaseMessaging.instance.subscribeToTopic('app_updates');
    } catch (e) {
      debugPrint("Firebase init error: $e");
    }
  }
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Early DB and Service initialization if session exists
  final currentSession = Supabase.instance.client.auth.currentSession;
  if (currentSession != null) {
    final userId = currentSession.user.id;
    debugPrint('Startup: Existing session found for $userId');

    // Refresh the session FIRST to get a fresh JWT before any Realtime connections
    try {
      await Supabase.instance.client.auth.refreshSession();
      debugPrint('Startup: Session refreshed successfully');
    } catch (e) {
      debugPrint('Startup: Session refresh failed: $e');
    }

    await DatabaseHelper.instance.switchDatabase(userId);
    await SupasService.instance.downloadReceiptSettings();
    await PasscodeService.instance.init();

    // Pre-refresh metadata
    unawaited(SupasService.instance.refreshUserMetadata());
  }

  // Catch any leaked async exceptions from third-party libraries
  // (e.g. Supabase Realtime websocket errors with expired JWT)
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('FlutterError: ${details.exception}');
  };
  runZonedGuarded(() {
    runApp(const MyApp());
  }, (error, stackTrace) {
    debugPrint('Uncaught async error (caught by zone): $error');
  });
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

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0; // Default to Dashboard (In Stock)
  final GlobalKey<DashboardScreenState> _dashboardKey = GlobalKey<DashboardScreenState>();
  StreamSubscription? _loginRequestSubscription;

  // Polling timers
  Timer? _loginPollTimer;
  Timer? _dataSyncTimer;
  Timer? _desktopPresenceTimer;

  // Track previous desktop status to detect transitions
  DesktopStatus _prevDesktopStatus = DesktopStatus.checking;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _screens = [
      DashboardScreen(key: _dashboardKey),
      NewStockScreen(),
      ProcessSaleScreen(),
      HistoryScreen(),
    ];
    _initDatabase();
    _listenForLoginRequests();
    _startPolling();
  }

  Future<void> _initDatabase() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await SupasService.instance.migrateLegacyDatabase();
      await DatabaseHelper.instance.switchDatabase(userId);
      await SupasService.instance.downloadReceiptSettings();
      await PasscodeService.instance.init();
      // Trigger a sync in background too
      SupasService.instance.syncDatabase();
    }
  }

  // --- REALTIME STREAM (fast path, may go stale) ---

  void _listenForLoginRequests() {
    try {
      _loginRequestSubscription = SupasService.instance.getLoginRequestsStream().listen((requests) {
        if (requests.isNotEmpty) {
          final request = requests.first;
          _showLoginApprovalDialog(request);
        }
      }, onError: (err) {
        debugPrint('Realtime stream error: $err');
        // Cancel the dead subscription — polling handles login requests as fallback.
        _loginRequestSubscription?.cancel();
        _loginRequestSubscription = null;
      }, cancelOnError: true);
    } catch (e) {
      debugPrint('Login stream init error: $e');
    }
  }

  // --- POLLING (reliable fallback) ---

  void _startPolling() {
    // Poll for login requests every 5 seconds
    _loginPollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollLoginRequests());

    // Poll for remote data changes every 30 seconds
    _dataSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollDataSync());

    // Poll desktop app presence every 15 seconds
    _desktopPresenceTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pollDesktopPresence());
    // Run immediately once on startup
    _pollDesktopPresence();
  }

  Future<void> _pollLoginRequests() async {
    try {
      final requests = await SupasService.instance.fetchPendingLoginRequests();
      if (requests.isNotEmpty) {
        _showLoginApprovalDialog(requests.first);
      }
    } catch (e) {
      // Silent fail — polling should never crash the app
    }
  }

  Future<void> _pollDataSync() async {
    try {
      final hasChanges = await SupasService.instance.checkForRemoteChanges();
      if (hasChanges && mounted) {
        // Refresh UI data since the database was updated
        _dashboardKey.currentState?.refreshData();
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _pollDesktopPresence() async {
    try {
      final newStatus = await SupasService.instance.checkDesktopPresence();
      if (!mounted) return;

      // Only notify on meaningful transitions (skip 'checking' and 'unknown')
      final prev = _prevDesktopStatus;
      _prevDesktopStatus = newStatus;

      // We only care about online ↔ offline transitions
      if (newStatus == prev) return;
      if (newStatus == DesktopStatus.checking || newStatus == DesktopStatus.unknown) return;
      if (prev == DesktopStatus.checking) return; // First check — don't notify yet

      String title;
      String body;

      if (newStatus == DesktopStatus.online) {
        title = '🟢 Desktop App Online';
        body = 'The desktop app is now connected to the internet.';
      } else {
        title = '🔴 Desktop App Offline';
        body = 'The desktop app has gone offline or was closed.';
      }

      // Android / iOS: local push notification
      if (Platform.isAndroid || Platform.isIOS) {
        const androidDetails = AndroidNotificationDetails(
          'desktop_presence_channel',
          'Desktop App Status',
          channelDescription: 'Alerts when the desktop application goes online or offline.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );
        const notifDetails = NotificationDetails(android: androidDetails);
        await flutterLocalNotificationsPlugin.show(
          newStatus.index,
          title,
          body,
          notifDetails,
        );
      } else {
        // Linux / desktop fallback: SnackBar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title — $body'),
              backgroundColor: newStatus == DesktopStatus.online
                  ? const Color(0xFF10B981)
                  : Colors.redAccent,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      // Silent fail
    }
  }

  // --- APP LIFECYCLE ---

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground — immediately check for login requests and data changes
      _pollLoginRequests();
      _pollDataSync();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _loginRequestSubscription?.cancel();
    _loginPollTimer?.cancel();
    _dataSyncTimer?.cancel();
    _desktopPresenceTimer?.cancel();
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
