import 'package:flutter/material.dart';

import '../../../../core/models/user_role.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/pages/login_page.dart';
import 'home_page.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  Future<void> _continueAsCoach(BuildContext context) async {
    final coachCode = await SyncService.instance.getOrCreateCoachCode();
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomePage(role: UserRole.coach)),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sesión como Entrenador iniciada. ID: $coachCode'),
          backgroundColor: Colors.blueAccent,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showAnalystConnectionDialog(BuildContext context) async {
    final currentCode = await SyncService.instance.getConnectedCoachCode();
    final controller = TextEditingController(text: currentCode ?? '');
    String? errorText;

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.wifi_tethering, color: Colors.cyanAccent, size: 28),
              SizedBox(width: 8),
              Text('Conectar con Entrenador', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresa el ID del Entrenador para sincronizar las estadísticas en tiempo real:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'EJ. CUN789',
                  errorText: errorText,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.qr_code),
                ),
                onChanged: (_) {
                  if (errorText != null) {
                    setDialogState(() => errorText = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.blueDiversity,
                foregroundColor: AppTheme.blueFounders,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final code = controller.text.trim().toUpperCase();
                if (code.length < 4) {
                  setDialogState(() => errorText = 'Ingresa un código válido de 6 dígitos');
                  return;
                }
                await SyncService.instance.setConnectedCoachCode(code);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomePage(role: UserRole.analyst)),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Conectado exitosamente al Entrenador: $code'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Conectar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await AuthService.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
                label: Text(
                  user.displayName ?? user.email ?? 'Cerrar Sesión',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                onPressed: () => _logout(context),
              ),
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F2027),
              Color(0xFF203A43),
              Color(0xFF2C5364),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.sports_volleyball,
                      color: Colors.cyanAccent,
                      size: 80,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '¿Cómo ingresarás?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Selecciona tu rol para adaptar la experiencia de scouting.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 32),
                    _RoleCard(
                      icon: Icons.sports,
                      title: 'Entrenador',
                      description: 'Gestiona equipos, genera tu ID de partido y registra acciones en vivo.',
                      color: AppTheme.blueDiversity,
                      foregroundColor: AppTheme.blueFounders,
                      onTap: () => _continueAsCoach(context),
                    ),
                    const SizedBox(height: 16),
                    _RoleCard(
                      icon: Icons.analytics_outlined,
                      title: 'Analista',
                      description: 'Conéctate mediante el ID del Entrenador para scouting y estadísticas en tiempo real.',
                      color: AppTheme.greenSolidarity,
                      foregroundColor: AppTheme.blueFounders,
                      onTap: () => _showAnalystConnectionDialog(context),
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

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: foregroundColor, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
