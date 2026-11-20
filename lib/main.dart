import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/services/firebase_service.dart';
import 'core/services/auth_service.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/home/presentation/pages/role_selection_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  await AuthService.instance.initSession();
  runApp(const VolleyballScoutingApp());
}

class VolleyballScoutingApp extends StatelessWidget {
  const VolleyballScoutingApp({super.key});

  @override
  Widget build(BuildContext context) {
    final hasActiveSession = AuthService.instance.currentUser != null;

    return MaterialApp(
      title: 'Volleyball Scouting',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: hasActiveSession ? const RoleSelectionPage() : const LoginPage(),
    );
  }
}
