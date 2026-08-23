import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'screens/dashboard_screen.dart';
import 'screens/process_sale_screen.dart';
import 'screens/history_screen.dart';
import 'screens/account_screen.dart';
import 'screens/login_screen.dart';
import 'services/database_helper.dart';
import 'services/supabase_service.dart';
import 'services/passcode_service.dart';
import 'services/shorebird_service.dart';
import 'widgets/device_pairing_dialog.dart';
import 'utils/colors.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");

  String? title = message.notification?.title ?? message.data['title'];
  String? body = message.notification?.body ?? message.data['message'] ?? message.data['body'];

  String fullMessage = '';
  if (body != null && body.isNotEmpty) {
    fullMessage = body;
  } else if (title != null && title.isNotEmpty) {
    fullMessage = title;
  }

  if (fullMessage.isNotEmpty) {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      final db = await DatabaseHelper.instance.database;
      final recent = await db.rawQuery(
        "SELECT id FROM notifications WHERE message = ? AND created_at >= datetime('now', '-10 seconds')",
        [fullMessage]
      );
      if (recent.isEmpty) {
        String syncId = DatabaseHelper.generateUUID();
        await db.rawInsert(
          "INSERT INTO notifications (message, source, sync_id) VALUES (?, ?, ?)",
          [fullMessage, 'Desktop', syncId]
        );
      }
    } catch (e) {
      debugPrint("Error saving background FCM notification: $e");
    }
  }
}

// Credentials extracted from user's .env file
const supabaseUrl = 'https://jhucvkqwenhyiveqsmtf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpodWN2a3F3ZW5oeWl2ZXFzbXRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NzI5MjIsImV4cCI6MjA4NTU0ODkyMn0.yXju47Ly5ak8Gm4D0OI42O89qTsc0nYtkmAb7dGFCC8';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('FlutterError: ${details.exception}');
    };

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

        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
          RemoteNotification? notification = message.notification;
          String? title = notification?.title ?? message.data['title'];
          String? body = notification?.body ?? message.data['message'] ?? message.data['body'];

          String fullMessage = '';
          if (body != null && body.isNotEmpty) {
            fullMessage = body;
          } else if (title != null && title.isNotEmpty) {
            fullMessage = title;
          }

          if (fullMessage.isNotEmpty) {
            await DatabaseHelper.instance.addNotification(fullMessage, 'Desktop', title: title);
          }
        });

        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
          String? title = message.notification?.title ?? message.data['title'];
          String? body = message.notification?.body ?? message.data['message'] ?? message.data['body'];
          String fullMessage = body ?? title ?? '';
          if (fullMessage.isNotEmpty) {
            await DatabaseHelper.instance.addNotification(fullMessage, 'Desktop', title: title);
          }
        });

        FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) async {
          if (message != null) {
            String? title = message.notification?.title ?? message.data['title'];
            String? body = message.notification?.body ?? message.data['message'] ?? message.data['body'];
            String fullMessage = body ?? title ?? '';
            if (fullMessage.isNotEmpty) {
              await DatabaseHelper.instance.addNotification(fullMessage, 'Desktop', title: title);
            }
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

      bool sessionValid = false;
      try {
        await Supabase.instance.client.auth.refreshSession();
        debugPrint('Startup: Session refreshed successfully');
        sessionValid = true;
      } on AuthApiException catch (e) {
        debugPrint('Startup: AuthApiException during session refresh (${e.code}): ${e.message}');
        final msg = e.message.toLowerCase();
        if (e.statusCode == '400' ||
            e.code == 'invalid_grant' ||
            msg.contains('invalid refresh token') ||
            msg.contains('refresh_token_not_found') ||
            msg.contains('already used')) {
          debugPrint('Startup: Clearing stale local session due to explicitly invalid refresh token.');
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (_) {}
          sessionValid = false;
        } else {
          debugPrint('Startup: Transient AuthApiException (${e.code}). Preserving session for offline/cached use.');
          sessionValid = true;
        }
      } catch (e) {
        debugPrint('Startup: Network or system error during session refresh: $e. Preserving session for offline use.');
        sessionValid = true;
      }

      if (sessionValid) {
        await DatabaseHelper.instance.switchDatabase(userId);
        await SupasService.instance.downloadReceiptSettings();
        await PasscodeService.instance.init();

        // Pre-refresh metadata
        unawaited(SupasService.instance.refreshUserMetadata());
      }
    }

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
        textTheme: GoogleFonts.outfitTextTheme(Theme.of(context).textTheme),
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

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _screens = [
      DashboardScreen(key: _dashboardKey),
      ProcessSaleScreen(),
      HistoryScreen(),
      AccountScreen(),
    ];
    _initDatabase();
    _listenForLoginRequests();
    _startPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShorebirdService.instance.checkForUpdate(context);
    });
  }

  Future<void> _initDatabase() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await SupasService.instance.refreshUserMetadata();
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
    // Poll for login requests every 2 seconds for immediate approval prompt
    _loginPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollLoginRequests());
    _pollLoginRequests();

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
      await SupasService.instance.checkDesktopPresence();
      if (!mounted) return;

      // Presence status updated on SupasService.instance.desktopStatus notifier.
      // We do NOT pollute persistent notification DB or spam snackbars on status checks.
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

  final Set<String> _handledRequestIds = {};

  void _showLoginApprovalDialog(Map<String, dynamic> request) async {
    final sessionId = request['id']?.toString() ?? '';
    if (sessionId.isNotEmpty && _handledRequestIds.contains(sessionId)) return;
    if (_isDialogOpen) return;
    _isDialogOpen = true;

    if (sessionId.isNotEmpty) {
      _handledRequestIds.add(sessionId);
    }

    String displayCid = request['checkbook_id']?.toString() ?? '';
    if (displayCid.isEmpty || displayCid.contains('*')) {
      final itemEmail = request['email']?.toString() ?? '';
      if (itemEmail.toUpperCase().startsWith('CK-')) {
        displayCid = itemEmail.toUpperCase();
      }
    }
    if (displayCid.isEmpty || displayCid.contains('*')) {
      displayCid = SupasService.instance.userMetadata.value?['checkbook_id']?.toString() ??
          SupasService.instance.client.auth.currentUser?.userMetadata?['checkbook_id']?.toString() ??
          'CK-872017';
    }

    final deviceName = request['device_name']?.toString() ?? 'Desktop PC';

    await DevicePairingDialog.show(
      context,
      sessionId: sessionId,
      checkbookId: displayCid,
      deviceName: deviceName,
    );

    _isDialogOpen = false;
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
        int parseInt(dynamic val) {
          if (val == null) return 0;
          if (val is int) return val;
          if (val is num) return val.toInt();
          if (val is String) return int.tryParse(val) ?? 0;
          return 0;
        }

        final now = DateTime.now().millisecondsSinceEpoch;

        // 1. Ownership & 7-Day Free Trial Check
        final isAccessValid = isOwnershipOrTrialValid(meta);

        if (!isAccessValid && meta != null) {
          // Trigger ownership popup only if trial has expired and license is unpaid
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showOwnershipRequiredDialog();
          });
        }

        // 2. Backup Subscription Banner
        final isBackupEnabled = meta?['monthly_cloud_backup'] as bool? ?? true;
        final backupExpiry = parseInt(meta?['backup_expiry']);
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
                icon: Icon(Icons.shopping_cart_outlined),
                activeIcon: Icon(Icons.shopping_cart),
                label: 'Sales',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history),
                label: 'History',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Account',
              ),
            ],
            currentIndex: safeIndex,
            selectedItemColor: AppColors.primaryGreen,
            unselectedItemColor: const Color(0xFF94A3B8),
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
            onTap: _onItemTapped,
            backgroundColor: Colors.white,
            elevation: 8,
            selectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 12),
          ),
        );
      },
    );
  }

  bool _isDialogOpen = false;

  bool isOwnershipOrTrialValid(Map<String, dynamic>? meta) {
    if (meta == null) return true; // Default allow if meta loading/null
    final now = DateTime.now().millisecondsSinceEpoch;

    int parseInt(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 0;
      return 0;
    }

    // 1. Check paid license ownership
    final isOwnershipEnabled = meta['ownership_payment'] as bool? ?? false;
    final ownershipExpiry = parseInt(meta['ownership_expiry']);
    if (isOwnershipEnabled && (ownershipExpiry == 0 || ownershipExpiry > now)) {
      return true;
    }

    // 2. Check explicit trial/subscription status
    final subStatus = (meta['subscription_status'] ?? meta['account_status'] ?? '').toString().toUpperCase();
    if (subStatus == 'TRIAL_ACTIVE' || subStatus == 'ACTIVE') {
      return true;
    }

    // 3. Check explicit trial_expires_at timestamp
    final trialExpiresVal = meta['trial_expires_at'];
    if (trialExpiresVal != null) {
      int expMs = 0;
      if (trialExpiresVal is String) {
        expMs = DateTime.tryParse(trialExpiresVal)?.millisecondsSinceEpoch ?? 0;
      } else if (trialExpiresVal is num) {
        expMs = trialExpiresVal.toInt();
      }
      if (expMs > now) {
        return true;
      }
    }

    // 4. Check account age: trial_end_at = created_at + 7 days
    final createdVal = meta['trial_started_at'] ?? meta['created_at'];
    int createdMs = 0;
    if (createdVal != null) {
      if (createdVal is String) {
        createdMs = DateTime.tryParse(createdVal)?.millisecondsSinceEpoch ?? 0;
      } else if (createdVal is num) {
        createdMs = createdVal.toInt();
      }
    }

    // If created_at timestamp is null/0 or brand new account, default to active trial (7 days)
    if (createdMs == 0) {
      return true;
    }

    final sevenDaysMs = 7 * 24 * 3600 * 1000;
    if ((now - createdMs) < sevenDaysMs) {
      return true; // Unrestricted access during 7-day free trial
    }

    return false; // Trial expired & no paid license
  }

  void _showOwnershipRequiredDialog() {
    if (_isDialogOpen) return;
    _isDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.red),
              SizedBox(width: 8),
              Text('Free Trial Expired'),
            ],
          ),
          content: const Text(
            'Your 7-Day Free Trial has expired. Please contact support (076 031 5703) to activate your license and continue using the app.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await SupasService.instance.refreshUserMetadata();
                final meta = SupasService.instance.userMetadata.value;
                if (isOwnershipOrTrialValid(meta)) {
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
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
