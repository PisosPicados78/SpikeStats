import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:volleyball_scouting/features/teams/presentation/pages/teams_page.dart';
import 'package:volleyball_scouting/features/matches/presentation/pages/match_config_page.dart';
import 'package:volleyball_scouting/features/scouting/presentation/pages/scouting_page.dart';
import 'package:volleyball_scouting/features/statistics/presentation/pages/statistics_page.dart';

import '../../../../core/models/user_role.dart';
import '../../../../core/services/sync_service.dart';
import 'role_selection_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.role});

  final UserRole role;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  String? _displayCode;
  bool _isIdExpanded = false;
  bool _isScoutingEditing = false;

  @override
  void initState() {
    super.initState();
    _loadSyncCode();
  }

  Future<void> _loadSyncCode() async {
    if (widget.role == UserRole.coach) {
      final code = await SyncService.instance.getOrCreateCoachCode();
      if (mounted) setState(() => _displayCode = code);
    } else {
      final code = await SyncService.instance.getConnectedCoachCode();
      if (mounted) setState(() => _displayCode = code);
    }
  }

  List<Widget> get _pages => widget.role == UserRole.coach
      ? [
          const TeamsPage(),
          const MatchConfigPage(),
          ScoutingPage(
            onEditingModeChanged: (active) {
              if (mounted) setState(() => _isScoutingEditing = active);
            },
          ),
          const StatisticsPage(),
        ]
      : [
          ScoutingPage(
            onEditingModeChanged: (active) {
              if (mounted) setState(() => _isScoutingEditing = active);
            },
          ),
          const StatisticsPage(),
        ];

  List<BottomNavigationBarItem> get _navigationItems =>
      widget.role == UserRole.coach
      ? const [
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Equipos'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Partido'),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_volleyball),
            label: 'Scouting',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Estadísticas',
          ),
        ]
      : const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_volleyball),
            label: 'Scouting',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Estadísticas',
          ),
        ];

  void _onItemTapped(int index) {
    if (_isScoutingEditing) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildTopSyncBadge() {
    if (_displayCode == null) return const SizedBox.shrink();
    final isCoach = widget.role == UserRole.coach;

    return Container(
      color: isCoach ? const Color(0xFF0D47A1) : const Color(0xFF004D40),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () {
                setState(() => _isIdExpanded = !_isIdExpanded);
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCoach ? Icons.badge : Icons.link,
                      size: 16,
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(width: 6),
                    if (_isIdExpanded) ...[
                      Text(
                        isCoach
                            ? 'ID ENTRENADOR: $_displayCode'
                            : 'CONECTADO A: $_displayCode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _displayCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Código $_displayCode copiado'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.copy, size: 14, color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_less, size: 18, color: Colors.cyanAccent),
                    ] else ...[
                      Text(
                        isCoach ? 'ID Entrenador' : 'Analista',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.lock, size: 13, color: Colors.cyanAccent),
                      const SizedBox(width: 2),
                      const Icon(Icons.expand_more, size: 16, color: Colors.cyanAccent),
                    ],
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Cambiar Rol',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        label: 'Sesión iniciada como ${widget.role.label}',
        child: Column(
          children: [
            _buildTopSyncBadge(),
            Expanded(child: _pages.elementAt(_selectedIndex)),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: _navigationItems,
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
      ),
    );
  }
}
