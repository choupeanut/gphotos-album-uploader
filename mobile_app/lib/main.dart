import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/features/auth/services/google_auth_service.dart';
import 'src/features/ui/screens/login_screen.dart';
import 'src/features/ui/screens/dashboard_screen.dart';
import 'src/features/upload/services/upload_manager.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _isInit = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      // Eagerly initialize UploadManager so upload/notification infrastructure is ready early
      ref.read(uploadManagerProvider);

      final authService = ref.read(authServiceProvider);
      final account = await authService.signInSilently();
      
      if (mounted) {
        setState(() {
          _isLoggedIn = account != null;
          _isInit = false;
        });
      }
    } catch (e) {
      print('App initialization error: $e');
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _isInit = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPhotos Album Uploader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8), // Google Blue
          secondary: const Color(0xFF34A853), // Google Green
          surface: Colors.white,
          background: const Color(0xFFF8F9FA),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF202124),
          iconTheme: IconThemeData(color: Color(0xFF5F6368)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
          ),
          color: Colors.white,
          margin: EdgeInsets.zero,
        ),
      ),
      home: _isInit
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _isLoggedIn
              ? const DashboardScreen()
              : const LoginScreen(),
    );
  }
}
