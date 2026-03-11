import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/services/google_auth_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = ref.watch(authServiceProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Icon(
                Icons.photo_library_rounded,
                size: 120,
                color: Color(0xFF1A73E8),
              ),
              const SizedBox(height: 40),
              const Text(
                'GPhotos Album Uploader',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF202124),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '智慧比對並將您的照片與影片安全備份至 Google Photos。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF5F6368),
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 2),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final account = await authService.signIn();
                    if (account != null && context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const DashboardScreen(),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('登入失敗: $e'),
                          duration: const Duration(seconds: 5),
                          behavior: SnackBarBehavior.floating,
                          action: SnackBarAction(label: '關閉', onPressed: () {}),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.login),
                label: const Text('使用 Google 帳號登入'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
