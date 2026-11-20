import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/auth_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../home/presentation/pages/role_selection_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkActiveSession();
  }

  void _checkActiveSession() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (AuthService.instance.currentUser != null) {
        _goToRoleSelection();
      }
    });
  }

  void _goToRoleSelection() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailPassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isLogin) {
      final pass = _passwordController.text;
      final hasLower = RegExp(r'(?=.*[a-z])').hasMatch(pass);
      final hasUpper = RegExp(r'(?=.*[A-Z])').hasMatch(pass);
      final hasDigit = RegExp(r'(?=.*\d)').hasMatch(pass);
      final hasSpecial = RegExp(r'(?=.*[\W_])').hasMatch(pass);
      if (pass.length < 8 || !hasLower || !hasUpper || !hasDigit || !hasSpecial) {
        setState(() {
          _errorMessage = 'La contraseña no cumple con los requisitos mínimos de seguridad.';
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        await AuthService.instance.signInWithEmail(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        await AuthService.instance.registerWithEmail(
          _emailController.text,
          _passwordController.text,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_offline', false);
      SyncService.instance.setForceOffline(false);
      if (mounted) {
        _goToRoleSelection();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _parseAuthError(e.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await AuthService.instance.signInWithGoogle();
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_offline', false);
        SyncService.instance.setForceOffline(false);
        if (mounted) {
          _goToRoleSelection();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al conectar con Google: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _continueOffline() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_offline', true);
      SyncService.instance.setForceOffline(true);
      await AuthService.instance.signInOffline();
      if (mounted) {
        _goToRoleSelection();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Error al iniciar modo local: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _parseAuthError(String error) {
    if (error.contains('user-not-found')) {
      return 'No existe un usuario con este correo electrónico.';
    } else if (error.contains('wrong-password')) {
      return 'Contraseña incorrecta.';
    } else if (error.contains('email-already-in-use')) {
      return 'Este correo ya está registrado. Por favor inicia sesión.';
    } else if (error.contains('weak-password')) {
      return 'La contraseña es muy débil (mínimo 6 caracteres).';
    } else if (error.contains('invalid-email')) {
      return 'Formato de correo electrónico no válido.';
    }
    return 'Error de autenticación. Verifica tus credenciales o conexión.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo y título de la App
                    const Center(
                      child: Icon(
                        Icons.sports_volleyball,
                        color: Colors.cyanAccent,
                        size: 70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'VOLLEYBALL SCOUTING',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sincronización en Tiempo Real & Análisis Táctico',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Selector de Modo (Iniciar Sesión vs Crear Cuenta)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _isLogin = true;
                                _errorMessage = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _isLogin ? AppTheme.blueDiversity : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'INICIAR SESIÓN',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _isLogin ? AppTheme.blueFounders : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _isLogin = false;
                                _errorMessage = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !_isLogin ? AppTheme.blueDiversity : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'CREAR CUENTA',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: !_isLogin ? AppTheme.blueFounders : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Mensaje de Error
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.2),
                          border: Border.all(color: Colors.redAccent, width: 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Formulario
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Correo electrónico',
                              labelStyle: const TextStyle(color: Colors.white70),
                              prefixIcon: const Icon(Icons.email_outlined, color: Colors.cyanAccent),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white24, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Ingresa tu correo';
                              if (!val.contains('@') || !val.contains('.')) return 'Correo inválido';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              labelStyle: const TextStyle(color: Colors.white70),
                              prefixIcon: const Icon(Icons.lock_outline, color: Colors.cyanAccent),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.white70,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white24, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'Ingresa tu contraseña';
                              if (_isLogin) {
                                if (val.length < 6) return 'Mínimo 6 caracteres';
                                return null;
                              }
                              // Validación estricta con expresiones regulares para Crear Cuenta
                              if (val.length < 8) {
                                return 'La contraseña debe tener mínimo 8 caracteres';
                              }
                              final hasLower = RegExp(r'(?=.*[a-z])').hasMatch(val);
                              final hasUpper = RegExp(r'(?=.*[A-Z])').hasMatch(val);
                              final hasDigit = RegExp(r'(?=.*\d)').hasMatch(val);
                              final hasSpecial = RegExp(r'(?=.*[\W_])').hasMatch(val);

                              if (!hasLower || !hasUpper || !hasDigit || !hasSpecial) {
                                return 'La contraseña no cumple con los requisitos mínimos';
                              }
                              return null;
                            },
                          ),
                          if (!_isLogin) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline, size: 15, color: Colors.grey[400]),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'La contraseña debe tener mínimo 8 caracteres e incluir: 1 mayúscula, 1 minúscula, 1 número y 1 carácter especial (ej. @, #, \$, %).',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[400],
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Confirmar contraseña',
                                labelStyle: const TextStyle(color: Colors.white70),
                                prefixIcon: const Icon(Icons.lock_outline, color: Colors.cyanAccent),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.08),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Colors.white24, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: Colors.cyanAccent, width: 2),
                                ),
                              ),
                              validator: (val) {
                                if (val != _passwordController.text) return 'Las contraseñas no coinciden';
                                return null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Botón Principal
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.blueDiversity,
                        foregroundColor: AppTheme.blueFounders,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 6,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _isLoading ? null : _submitEmailPassword,
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black87),
                            )
                          : Text(
                              _isLogin ? 'INICIAR SESIÓN' : 'CREAR CUENTA',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                    ),
                    const SizedBox(height: 20),

                    // Separador
                    Row(
                      children: const [
                        Expanded(child: Divider(color: Colors.white24, thickness: 1)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text('o continúa con', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        ),
                        Expanded(child: Divider(color: Colors.white24, thickness: 1)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Botón Destacado de Google
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Colors.black12, width: 1),
                        ),
                      ),
                      onPressed: _isLoading ? null : _continueWithGoogle,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF4285F4),
                              ),
                              child: const Text(
                                'G',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Continuar rápido con Google',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Botón Modo Local / Sin Conexión
                    TextButton(
                      onPressed: _isLoading ? null : _continueOffline,
                      child: const Text(
                        'Continuar en modo local (sin conexión)',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
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
