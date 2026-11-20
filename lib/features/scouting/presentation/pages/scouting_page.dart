import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/team.dart';
import '../../../../core/models/player.dart';
import '../../../../core/models/match.dart';
import '../../../../core/models/scouting_action.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/services/sync_service.dart';
import '../../../matches/presentation/pages/lineup_selection_page.dart';

class ScoutingPage extends StatefulWidget {
  final ValueChanged<bool>? onEditingModeChanged;
  const ScoutingPage({super.key, this.onEditingModeChanged});

  @override
  State<ScoutingPage> createState() => _ScoutingPageState();
}

class _ScoutingPageState extends State<ScoutingPage> {
  final PageController _pageController = PageController();
  Match? _activeMatch;
  List<ScoutingAction> _actions = [];
  Map<String, List<Player>> _lineups = {};
  bool _isLoading = true;
  String? _activeTeamId;

  String? _pendingAction;
  Player? _selectedPlayer;

  Timer? _matchTimer;
  int _elapsedSeconds = 0;
  DateTime? _matchStartTime;

  // Lógica de alargue por set
  bool? _setDeuceAlargue;
  int _deuceSetNumber = -1;

  // Conexión y sincronización en la nube (Entrenador / Analista)
  String? _coachCode;
  bool _isAnalyst = false;
  bool _isIdExpanded = false;
  StreamSubscription<Match?>? _matchSubscription;
  StreamSubscription<List<ScoutingAction>>? _actionsSubscription;

  // Estado de interacción de botones (Modo Edición por botón)
  String? _editingButtonId;
  bool get _isEditingModeActive => _editingButtonId != null;

  void _setEditingButtonId(String? id) {
    setState(() {
      _editingButtonId = id;
    });
    widget.onEditingModeChanged?.call(id != null);
  }

  // Posiciones y escalas de botones personalizables
  Map<String, Offset> _buttonPositions = {};
  Map<String, double> _buttonScales = {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    _loadData();
    _loadButtonPreferences();
    _initCloudSync();
  }

  Future<void> _initCloudSync() async {
    final connected = await SyncService.instance.getConnectedCoachCode();
    if (connected != null && connected.isNotEmpty) {
      _coachCode = connected;
      _isAnalyst = true;
    } else {
      _coachCode = await SyncService.instance.getOrCreateCoachCode();
      _isAnalyst = false;
    }
    if (mounted) setState(() {});

    if (_coachCode != null && SyncService.instance.isCloudAvailable) {
      _matchSubscription?.cancel();
      _matchSubscription = SyncService.instance.watchActiveMatch(_coachCode!).listen(
        (remoteMatch) async {
          if (remoteMatch != null && mounted) {
            await DatabaseHelper.instance.updateMatchState(remoteMatch);
            setState(() {
              _activeMatch = remoteMatch;
            });
            _subscribeToActions(remoteMatch.id);
          }
        },
        onError: (Object error) {
          debugPrint('Error en suscripción de partido remoto: $error');
        },
      );
      if (_activeMatch != null) {
        _subscribeToActions(_activeMatch!.id);
      }
    }
  }

  void _subscribeToActions(String matchId) {
    if (_coachCode == null || !SyncService.instance.isCloudAvailable) return;
    _actionsSubscription?.cancel();
    _actionsSubscription = SyncService.instance.watchActions(_coachCode!, matchId).listen(
      (remoteActions) {
        if (mounted && remoteActions.isNotEmpty) {
          setState(() {
            _actions = remoteActions;
          });
        }
      },
      onError: (Object error) {
        debugPrint('Error en suscripción de acciones remotas: $error');
      },
    );
  }

  Future<void> _loadButtonPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final actions = ['Ataque', 'Armado', 'Defensa', 'Bloqueo', 'Saque', 'Tiempo Fuera'];
    final positions = <String, Offset>{};
    final scales = <String, double>{};
    for (final a in actions) {
      final x = prefs.getDouble('action_btn_${a}_x');
      final y = prefs.getDouble('action_btn_${a}_y');
      final s = prefs.getDouble('action_btn_${a}_scale');
      if (x != null && y != null) {
        positions[a] = Offset(x, y);
      }
      if (s != null) {
        scales[a] = s;
      }
    }
    if (mounted) {
      setState(() {
        _buttonPositions = positions;
        _buttonScales = scales;
      });
    }
  }

  Future<void> _saveButtonPosition(String action, Offset pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('action_btn_${action}_x', pos.dx);
    await prefs.setDouble('action_btn_${action}_y', pos.dy);
  }

  Future<void> _saveButtonScale(String action, double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('action_btn_${action}_scale', scale);
  }

  Future<void> _resetButtonPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final actions = ['Ataque', 'Armado', 'Defensa', 'Bloqueo', 'Saque', 'Tiempo Fuera'];
    for (final a in actions) {
      await prefs.remove('action_btn_${a}_x');
      await prefs.remove('action_btn_${a}_y');
      await prefs.remove('action_btn_${a}_scale');
    }
    setState(() {
      _buttonPositions.clear();
      _buttonScales.clear();
      _editingButtonId = null;
    });
    widget.onEditingModeChanged?.call(false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posiciones y tamaños de botones restablecidos')),
      );
    }
  }

  Future<void> _loadData() async {
    final activeMatch = await DatabaseHelper.instance.getActiveMatch();
    final actions = activeMatch == null
        ? <ScoutingAction>[]
        : await DatabaseHelper.instance.getScoutingActions(activeMatch.id);
    final lineups = activeMatch == null
        ? <String, List<Player>>{}
        : await DatabaseHelper.instance.getMatchLineups(activeMatch.id);
    if (!mounted) return;
    setState(() {
      _activeMatch = activeMatch;
      _actions = actions;
      _lineups = lineups;
      _activeTeamId ??= activeMatch?.localTeam.id;
      _isLoading = false;

      if (_actions.isNotEmpty && _matchTimer == null) {
        _matchStartTime = _actions.first.createdAt;
        _startTimer();
      }
    });
  }

  void _startTimer() {
    if (_matchStartTime == null) return;
    _matchTimer?.cancel();
    _elapsedSeconds = DateTime.now().difference(_matchStartTime!).inSeconds;
    if (_elapsedSeconds < 0) _elapsedSeconds = 0;
    _matchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(_matchStartTime!).inSeconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _matchSubscription?.cancel();
    _actionsSubscription?.cancel();
    _matchTimer?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLocal = _activeMatch != null && _activeTeamId == _activeMatch!.localTeam.id;
    final scaffoldColor = isLocal ? Colors.blue.withOpacity(0.05) : Colors.red.withOpacity(0.05);
    final isShortLandscape = MediaQuery.of(context).size.height < 480;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _activeMatch != null ? scaffoldColor : null,
      appBar: AppBar(
        toolbarHeight: isShortLandscape ? 46 : kToolbarHeight,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _activeMatch == null
                  ? 'Scouting en Vivo'
                  : '${_activeMatch!.localTeam.name} vs ${_activeMatch!.visitorTeam.name}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_coachCode != null)
              GestureDetector(
                onTap: () {
                  setState(() => _isIdExpanded = !_isIdExpanded);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isAnalyst ? Icons.link : Icons.badge,
                      size: 13,
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(width: 4),
                    if (_isIdExpanded) ...[
                      Text(
                        _isAnalyst ? 'Analista de: $_coachCode' : 'ID Entrenador: $_coachCode',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _coachCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('ID ${_isAnalyst ? "Conectado" : "Entrenador"}: $_coachCode copiado'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: const Icon(Icons.copy, size: 11, color: Colors.cyanAccent),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_less, size: 14, color: Colors.cyanAccent),
                    ] else ...[
                      const Icon(Icons.lock, size: 11, color: Colors.cyanAccent),
                      const SizedBox(width: 2),
                      const Icon(Icons.expand_more, size: 14, color: Colors.cyanAccent),
                    ],
                  ],
                ),
              ),
          ],
        ),
        actions: [
          if (_coachCode != null)
            IconButton(
              icon: const Icon(Icons.qr_code, size: 20),
              tooltip: 'Copiar ID Entrenador ($_coachCode)',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _coachCode!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ID $_coachCode copiado al portapapeles')),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Restablecer botones',
            onPressed: _resetButtonPositions,
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Deshacer última acción',
            onPressed: _actions.isNotEmpty ? _undoLastAction : null,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Mantén presionado un botón para moverlo o ajustar su tamaño con + y -.'),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeMatch == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay un partido activo. Un entrenador debe crear o abrir un partido antes de iniciar el scouting.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : !_hasCompleteLineups
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Configura las alineaciones de 6 titulares para ambos equipos antes de iniciar el scouting.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: _isEditingModeActive
                        ? const NeverScrollableScrollPhysics()
                        : const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildHalfCourtView(),
                      _buildFullCourtView(),
                      _buildLogView(),
                    ],
                  ),
                ),
                _buildActionTicker(),
              ],
            ),
    );
  }

  Widget _buildActionTicker() {
    if (_actions.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 30,
      color: Colors.black12,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _actions.length > 3 ? 3 : _actions.length,
        itemBuilder: (context, index) {
          final action = _actions[index];
          final team = action.teamId == _activeMatch!.localTeam.id ? _activeMatch!.localTeam : _activeMatch!.visitorTeam;
          final player = team.players.firstWhere((p) => p.id == action.playerId, orElse: () => Player(id: '', name: 'Equipo', number: 0, position: ''));
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text(
              '[${action.matchTime ?? "00:00"} | ${action.realTime ?? ""}] ${action.actionType}: ${player.name} (${action.result})',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHalfCourtView() {
    final activeMatch = _activeMatch!;
    return _courtBackground(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 360;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Marcador y selectores de equipo
              Positioned(
                top: compact ? 4 : 8,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildScoreboard(compact: compact),
                      ),
                    ),
                    SizedBox(height: compact ? 4 : 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _teamToggleButton(activeMatch.localTeam.id, activeMatch.localTeam.name, compact),
                        const SizedBox(width: 14),
                        _teamToggleButton(activeMatch.visitorTeam.id, activeMatch.visitorTeam.name, compact),
                      ],
                    ),
                  ],
                ),
              ),
              // Botones de acción arrastrables y redimensionables
              ..._buildDraggableActionButtons(constraints, compact),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildDraggableActionButtons(BoxConstraints constraints, bool compact) {
    final activeMatch = _activeMatch!;
    final team = _activeTeamId == activeMatch.localTeam.id ? activeMatch.localTeam : activeMatch.visitorTeam;

    final actionDefs = [
      _ActionBtnData(
        title: 'Ataque',
        icon: Icons.sports_kabaddi,
        color: AppTheme.blueFounders,
        foregroundColor: Colors.white,
        onPressed: () => _onActionSelected('Ataque'),
      ),
      _ActionBtnData(
        title: 'Armado',
        icon: Icons.front_hand,
        color: Colors.purple.shade700,
        foregroundColor: Colors.white,
        onPressed: () => _onActionSelected('Armado'),
      ),
      _ActionBtnData(
        title: 'Defensa',
        icon: Icons.shield,
        color: AppTheme.blueDiversity,
        foregroundColor: Colors.white,
        onPressed: () => _onActionSelected('Defensa'),
      ),
      _ActionBtnData(
        title: 'Bloqueo',
        icon: Icons.pan_tool,
        color: AppTheme.greenSolidarity,
        foregroundColor: AppTheme.blueFounders,
        onPressed: () => _onActionSelected('Bloqueo'),
      ),
      _ActionBtnData(
        title: 'Saque',
        icon: Icons.sports_volleyball,
        color: AppTheme.greenFreedom,
        foregroundColor: AppTheme.blueFounders,
        onPressed: () => _onActionSelected('Saque'),
      ),
      _ActionBtnData(
        title: 'Tiempo Fuera',
        icon: Icons.timer,
        color: Colors.orange,
        foregroundColor: Colors.white,
        onPressed: () {
          _saveQuickAction('Tiempo Fuera', 'Solicitado', team, null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tiempo Fuera registrado para ${team.name}')),
          );
        },
      ),
    ];

    final isEditingMode = _editingButtonId != null;
    final List<Widget> widgets = [];

    // 2. Overlay blanco semitransparente (solo visible si isEditing == true)
    if (isEditingMode) {
      widgets.add(
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              // Absorbe toques no deseados hasta que se presione el botón ✔
            },
            child: Container(
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ),
      );
    }

    _ActionBtnData? editingDef;
    for (final def in actionDefs) {
      if (def.title == _editingButtonId) {
        editingDef = def;
        break;
      }
    }

    // 3. Los botones de acción que NO se están editando
    for (final def in actionDefs) {
      if (def.title != _editingButtonId) {
        final rawPos = _buttonPositions[def.title] ?? _getDefaultButtonPosition(def.title, constraints, compact);
        final scale = _buttonScales[def.title] ?? 1.0;
        final btnBaseW = (compact ? 96.0 : 120.0) * scale;
        final btnBaseH = (compact ? 36.0 : 46.0) * scale;
        final pos = Offset(
          rawPos.dx.clamp(0.0, (constraints.maxWidth - btnBaseW).clamp(0.0, double.infinity)),
          rawPos.dy.clamp(0.0, (constraints.maxHeight - btnBaseH).clamp(0.0, double.infinity)),
        );

        widgets.add(
          Positioned(
            left: pos.dx,
            top: pos.dy,
            child: IgnorePointer(
              ignoring: isEditingMode,
              child: Opacity(
                opacity: isEditingMode ? 0.35 : 1.0,
                child: GestureDetector(
                  onLongPress: () {
                    HapticFeedback.heavyImpact();
                    _setEditingButtonId(def.title);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Modo Edición: Arrastra "${def.title}" o calibra su tamaño con [+] y [-]. Toca ✔ al terminar.'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.center,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 5,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: def.color,
                        borderRadius: BorderRadius.circular(12),
                        elevation: 5,
                        shadowColor: Colors.black45,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: def.onPressed,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 9 : 14,
                              vertical: compact ? 7 : 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(def.icon, size: compact ? 18 : 24, color: def.foregroundColor),
                                const SizedBox(width: 5),
                                Text(
                                  def.title,
                                  style: TextStyle(
                                    color: def.foregroundColor,
                                    fontSize: compact ? 12.5 : 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // 4. El botón que SÍ se está editando (envuelto en su GestureDetector para el onPanUpdate)
    if (isEditingMode && editingDef != null) {
      final editing = editingDef;
      final rawPos = _buttonPositions[editing.title] ?? _getDefaultButtonPosition(editing.title, constraints, compact);
      final scale = _buttonScales[editing.title] ?? 1.0;
      final btnBaseWidth = compact ? 96.0 : 120.0;
      final btnBaseHeight = compact ? 36.0 : 46.0;
      final actualWidth = btnBaseWidth * scale;
      final actualHeight = btnBaseHeight * scale;
      final pos = Offset(
        rawPos.dx.clamp(0.0, (constraints.maxWidth - actualWidth).clamp(0.0, double.infinity)),
        rawPos.dy.clamp(0.0, (constraints.maxHeight - actualHeight).clamp(0.0, double.infinity)),
      );

      widgets.add(
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              setState(() {
                final currentPos = _buttonPositions[editing.title] ??
                    _getDefaultButtonPosition(editing.title, constraints, compact);
                final maxX = (constraints.maxWidth - actualWidth).clamp(0.0, double.infinity);
                final maxY = (constraints.maxHeight - actualHeight).clamp(0.0, double.infinity);
                final newX = (currentPos.dx + details.delta.dx).clamp(0.0, maxX);
                final newY = (currentPos.dy + details.delta.dy).clamp(0.0, maxY);
                _buttonPositions[editing.title] = Offset(newX, newY);
              });
            },
            onPanEnd: (_) {
              final current = _buttonPositions[editing.title];
              if (current != null) {
                _saveButtonPosition(editing.title, current);
              }
            },
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amberAccent, width: 2.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amberAccent.withOpacity(0.8),
                      blurRadius: 18,
                      spreadRadius: 3,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: editing.color,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 14,
                  shadowColor: Colors.amberAccent,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 9 : 14,
                      vertical: compact ? 7 : 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.open_with, size: 15, color: Colors.amberAccent),
                        const SizedBox(width: 4),
                        Icon(editing.icon, size: compact ? 18 : 24, color: editing.foregroundColor),
                        const SizedBox(width: 5),
                        Text(
                          editing.title,
                          style: TextStyle(
                            color: editing.foregroundColor,
                            fontSize: compact ? 12.5 : 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // 5. Por encima de todo, la fila (Row) con los controles +, - y ✔
      final toolbarWidth = 220.0;
      final toolbarHeight = 44.0;
      final double toolbarY;
      if (pos.dy >= toolbarHeight + 10) {
        toolbarY = pos.dy - toolbarHeight - 8;
      } else {
        toolbarY = (pos.dy + actualHeight + 8).clamp(0.0, (constraints.maxHeight - toolbarHeight).clamp(0.0, double.infinity));
      }
      final toolbarX = (pos.dx + (actualWidth - toolbarWidth) / 2).clamp(
        4.0,
        (constraints.maxWidth - toolbarWidth - 4.0).clamp(4.0, double.infinity),
      );

      widgets.add(
        Positioned(
          left: toolbarX,
          top: toolbarY,
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xFF1E1E1E),
            child: Container(
              width: toolbarWidth,
              height: toolbarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.amberAccent, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black87,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Botón [-]
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        final currentScale = _buttonScales[editing.title] ?? 1.0;
                        final newScale = (currentScale - 0.1).clamp(0.5, 2.0);
                        final rounded = double.parse(newScale.toStringAsFixed(2));
                        setState(() {
                          _buttonScales[editing.title] = rounded;
                        });
                        _saveButtonScale(editing.title, rounded);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.remove, size: 18, color: Colors.amberAccent),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${((_buttonScales[editing.title] ?? 1.0) * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Botón [+]
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        final currentScale = _buttonScales[editing.title] ?? 1.0;
                        final newScale = (currentScale + 0.1).clamp(0.5, 2.0);
                        final rounded = double.parse(newScale.toStringAsFixed(2));
                        setState(() {
                          _buttonScales[editing.title] = rounded;
                        });
                        _saveButtonScale(editing.title, rounded);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, size: 18, color: Colors.amberAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón Confirmar (✔)
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final currentScale = _buttonScales[editing.title] ?? 1.0;
                        final currentPos = _buttonPositions[editing.title] ??
                            _getDefaultButtonPosition(editing.title, constraints, compact);
                        await _saveButtonPosition(editing.title, currentPos);
                        await _saveButtonScale(editing.title, currentScale);
                        _setEditingButtonId(null);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Botón "${editing.title}" configurado y guardado.'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green[700],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check, size: 16, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'Listo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Offset _getDefaultButtonPosition(String action, BoxConstraints constraints, bool compact) {
    final actions = ['Ataque', 'Armado', 'Defensa', 'Bloqueo', 'Saque', 'Tiempo Fuera'];
    final index = actions.indexOf(action);
    if (index < 0) return Offset(20, constraints.maxHeight - 60);

    // Altura reservada para el bloque superior (marcador + selector de equipos)
    // Garantiza que los botones por defecto nunca se superpongan al selector de equipos
    // incluso cuando la barra superior de ID Entrenador está abierta.
    final reservedTop = compact ? 88.0 : 134.0;
    final freeTop = reservedTop.clamp(0.0, (constraints.maxHeight * 0.62).clamp(0.0, double.infinity));

    final btnHeight = compact ? 36.0 : 46.0;
    final singleRowWidths = compact
        ? <double>[90.0, 92.0, 94.0, 94.0, 84.0, 122.0]
        : <double>[110.0, 112.0, 114.0, 114.0, 102.0, 146.0];
    final totalSingleRowWidth = singleRowWidths.fold<double>(0.0, (a, b) => a + b);

    if (constraints.maxWidth >= (totalSingleRowWidth + 28.0)) {
      final spacing = (constraints.maxWidth - totalSingleRowWidth) / (actions.length + 1);
      double x = spacing;
      for (int i = 0; i < index; i++) {
        x += singleRowWidths[i] + spacing;
      }
      final maxY = (constraints.maxHeight - btnHeight - 4.0).clamp(0.0, double.infinity);
      final preferredY = (constraints.maxHeight - btnHeight - 14.0);
      final safeMinY = freeTop.clamp(0.0, maxY);
      final y = preferredY.clamp(safeMinY, maxY);
      return Offset(x.clamp(4.0, (constraints.maxWidth - singleRowWidths[index] - 4.0).clamp(4.0, double.infinity)), y);
    } else {
      // 2 filas de 3 botones dentro del área libre debajo del selector de equipos
      final btnWidth = compact ? 104.0 : 124.0;
      final col = index % 3;
      final row = index ~/ 3;
      final colWidth = constraints.maxWidth / 3;
      final x = (col * colWidth + (colWidth - btnWidth) / 2)
          .clamp(4.0, (constraints.maxWidth - btnWidth - 4.0).clamp(4.0, double.infinity));

      final availableHeight = (constraints.maxHeight - freeTop - 6.0).clamp(0.0, double.infinity);
      final gapY = ((availableHeight - btnHeight * 2) / 3).clamp(4.0, 12.0);
      final maxY = (constraints.maxHeight - btnHeight - 4.0).clamp(0.0, double.infinity);
      final safeMinY = freeTop.clamp(0.0, maxY);

      final bottomAnchoredRow0 = constraints.maxHeight - (btnHeight * 2 + gapY + 8.0);
      final row0Y = bottomAnchoredRow0.clamp(safeMinY, maxY);
      final row1Y = (row0Y + btnHeight + gapY).clamp(safeMinY, maxY);
      final y = row == 0 ? row0Y : row1Y;
      return Offset(x, y);
    }
  }

  Widget _teamToggleButton(String teamId, String teamName, bool compact) {
    final isSelected = _activeTeamId == teamId;
    return InkWell(
      onTap: () {
        setState(() => _activeTeamId = teamId);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 24, vertical: compact ? 5 : 10),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
        child: Text(
          teamName.toUpperCase(),
          style: TextStyle(
            color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: compact ? 13 : 17,
          ),
        ),
      ),
    );
  }

  Player? _getBenchedCentral(Team team, int rotation, bool hasLibero, {bool forceServing = false}) {
    if (!hasLibero) return null;
    final isServing = forceServing || _activeMatch!.servingTeamId == team.id;
    final lineup = _playersForTeam(team);
    if (lineup.length < 6) return null;
    final rotatedPlayers = List.generate(6, (index) => lineup[(index + rotation) % 6]);
    final liberos = team.players.where((p) => p.position.toLowerCase() == 'líbero' || p.position.toLowerCase() == 'libero');
    if (liberos.isEmpty) return null;
    final backRowIndices = isServing ? [4, 5] : [0, 4, 5];
    for (int i in backRowIndices) {
      if (rotatedPlayers[i].position.toLowerCase() == 'central') {
        return rotatedPlayers[i];
      }
    }
    return null;
  }

  Widget _buildFullCourtView() {
    final activeMatch = _activeMatch!;

    final localBenched = _getBenchedCentral(activeMatch.localTeam, activeMatch.localRotation, activeMatch.localHasLibero);
    final visitorBenched = _getBenchedCentral(activeMatch.visitorTeam, activeMatch.visitorRotation, activeMatch.visitorHasLibero);

    return _courtBackground(
      child: Row(
        children: [
          // Mitad Izquierda (Equipo 1)
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.white, width: 2),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Text(
                      activeMatch.localTeam.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  _buildCourtHalf(
                    _playersForTeam(activeMatch.localTeam),
                    team: activeMatch.localTeam,
                    rotation: activeMatch.localRotation,
                    isLeft: true,
                    hasLibero: activeMatch.localHasLibero,
                  ),
                  Positioned(
                    bottom: -10,
                    left: -10,
                    child: FloatingActionButton(
                      heroTag: 'sub_local',
                      mini: true,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      child: const Icon(Icons.swap_horiz),
                      onPressed: () => _showSubstitutionDialog(activeMatch.localTeam),
                    ),
                  ),
                  Positioned(
                    bottom: -10,
                    right: 10,
                    child: FloatingActionButton(
                      heroTag: 'timeout_local',
                      mini: true,
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.timer),
                      onPressed: () => _showTimeoutDialog(activeMatch.localTeam),
                    ),
                  ),
                  if (localBenched != null)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Opacity(
                        opacity: 0.7,
                        child: _playerWidget(localBenched),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Mitad Derecha (Equipo 2)
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.white, width: 2),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Text(
                      activeMatch.visitorTeam.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  _buildCourtHalf(
                    _playersForTeam(activeMatch.visitorTeam),
                    team: activeMatch.visitorTeam,
                    rotation: activeMatch.visitorRotation,
                    isLeft: false,
                    hasLibero: activeMatch.visitorHasLibero,
                  ),
                  Positioned(
                    bottom: -10,
                    right: -10,
                    child: FloatingActionButton(
                      heroTag: 'sub_visitor',
                      mini: true,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      child: const Icon(Icons.swap_horiz),
                      onPressed: () => _showSubstitutionDialog(activeMatch.visitorTeam),
                    ),
                  ),
                  Positioned(
                    bottom: -10,
                    left: 10,
                    child: FloatingActionButton(
                      heroTag: 'timeout_visitor',
                      mini: true,
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.timer),
                      onPressed: () => _showTimeoutDialog(activeMatch.visitorTeam),
                    ),
                  ),
                  if (visitorBenched != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Opacity(
                        opacity: 0.7,
                        child: _playerWidget(visitorBenched),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourtHalf(
    List<Player> lineup, {
    required Team team,
    required int rotation,
    required bool isLeft,
    required bool hasLibero,
    void Function(Player)? onPlayerTap,
  }) {
    final rotatedPlayers = List.generate(
      6,
      (index) => lineup[(index + rotation) % 6],
    );

    final hasLibero = team.id == _activeMatch!.localTeam.id ? _activeMatch!.localHasLibero : _activeMatch!.visitorHasLibero;
    final isServing = _activeMatch!.servingTeamId == team.id;

    if (hasLibero) {
      final liberos = team.players.where(
        (p) => p.position.toLowerCase() == 'líbero' || p.position.toLowerCase() == 'libero'
      );
      final libero = liberos.isEmpty ? null : liberos.first;

      if (libero != null) {
        final backRowIndices = isServing ? [4, 5] : [0, 4, 5];
        for (int i in backRowIndices) {
          if (rotatedPlayers[i].position.toLowerCase() == 'central') {
            rotatedPlayers[i] = libero;
          }
        }
      }
    }

    Widget p(int index, double x, double y) {
      final player = rotatedPlayers[index];
      return Align(
        alignment: Alignment(x, y),
        child: _playerWidget(player, onTap: onPlayerTap != null ? () => onPlayerTap(player) : null),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fondo de la cancha
        Container(
          width: double.infinity,
          height: double.infinity,
          color: AppTheme.courtGreen,
        ),
        if (isLeft) ...[
          p(4, -0.68, -0.80), // Zona 5
          p(5, -0.68, 0.0),   // Zona 6
          p(0, -0.68, 0.80),  // Zona 1
          p(3, 0.52, -0.80),  // Zona 4
          p(2, 0.52, 0.0),    // Zona 3
          p(1, 0.52, 0.80),   // Zona 2
        ] else ...[
          p(0, 0.68, -0.80),  // Zona 1
          p(5, 0.68, 0.0),    // Zona 6
          p(4, 0.68, 0.80),   // Zona 5
          p(1, -0.52, -0.80), // Zona 2
          p(2, -0.52, 0.0),   // Zona 3
          p(3, -0.52, 0.80),  // Zona 4
        ],
      ],
    );
  }

  Widget _playerWidget(Player player, {VoidCallback? onTap, bool disabled = false}) {
    if (player.id.isEmpty) return const SizedBox(width: 44, height: 44);

    final label = Formatters.formatPlayerLabel(player.name, player.position);
    
    Widget avatar = CircleAvatar(
      radius: 20, // Slightly reduced to eliminate vertical overlaps
      backgroundColor: disabled ? Colors.grey : Theme.of(context).colorScheme.primary,
      child: Text(
        player.number.toString(),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: disabled ? Colors.white54 : Colors.white,
          fontSize: 16,
        ),
      ),
    );

    if (onTap != null && !disabled) {
      avatar = GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatar,
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: disabled ? Colors.black38 : Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: disabled ? Colors.white54 : Colors.white,
              fontSize: 9, // Slightly smaller font for maximum space
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogView() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VISTA 3: Resumen de Acciones (Log)',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const Divider(),
          Expanded(
            child: _actions.isEmpty
                ? const Center(child: Text('Aún no hay acciones registradas.'))
                : ListView.builder(
                    itemCount: _actions.length,
                    itemBuilder: (context, index) {
                      final action = _actions[index];
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: Text('${action.actionType}: ${action.result}'),
                        subtitle: Text(
                          '${_playerName(action.playerId)} · ${_teamName(action.teamId)}',
                        ),
                        trailing: Text(_formatTime(action.createdAt)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreboard({bool compact = false}) {
    final match = _activeMatch!;
    final servingTeam = match.servingTeamId == match.localTeam.id
        ? match.localTeam.name
        : match.visitorTeam.name;
    final timerText =
        '${(_elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(_elapsedSeconds % 60).toString().padLeft(2, '0')}';

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'SETS ${match.localSets} - ${match.visitorSets}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.timer, color: Colors.yellowAccent, size: 14),
              const SizedBox(width: 3),
              Text(
                timerText,
                style: const TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                'Saque: $servingTeam',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${match.localTeam.name}  ${match.localScore}  -  ${match.visitorScore}  ${match.visitorTeam.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(
              'SETS ${match.localSets} - ${match.visitorSets}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 16),
            Row(
              children: [
                const Icon(Icons.timer, color: Colors.yellowAccent, size: 20),
                const SizedBox(width: 4),
                Text(
                  timerText,
                  style: const TextStyle(
                    color: Colors.yellowAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${match.localTeam.name}  ${match.localScore}  -  ${match.visitorScore}  ${match.visitorTeam.name}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Saque: $servingTeam',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  Widget _courtBackground({required Widget child}) {
    final isLocal = _activeMatch != null && _activeTeamId == _activeMatch!.localTeam.id;
    final courtColor = isLocal ? Colors.green[600]! : Colors.green[800]!;

    return GestureDetector(
      onTap: () {
        if (_editingButtonId != null) {
          final pos = _buttonPositions[_editingButtonId];
          if (pos != null) _saveButtonPosition(_editingButtonId!, pos);
          final sc = _buttonScales[_editingButtonId];
          if (sc != null) _saveButtonScale(_editingButtonId!, sc);
          _setEditingButtonId(null);
        }
      },
      behavior: HitTestBehavior.translucent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: courtColor,
          border: Border.all(color: AppTheme.courtLine, width: 2),
        ),
        child: child,
      ),
    );
  }

  void _onActionSelected(String actionType) {
    final team = _activeTeamId == _activeMatch!.localTeam.id ? _activeMatch!.localTeam : _activeMatch!.visitorTeam;
    final rotation = team.id == _activeMatch!.localTeam.id ? _activeMatch!.localRotation : _activeMatch!.visitorRotation;
    final hasLibero = team.id == _activeMatch!.localTeam.id ? _activeMatch!.localHasLibero : _activeMatch!.visitorHasLibero;
    final lineup = _playersForTeam(team);
    final isServingTeam = _activeMatch!.servingTeamId == team.id;

    Player? initialPlayer;
    if (actionType == 'Saque' && isServingTeam && lineup.isNotEmpty) {
      initialPlayer = lineup[rotation % lineup.length]; // Jugador en Zona 1 (Saque)
    } else if (actionType == 'Armado') {
      initialPlayer = lineup.cast<Player?>().firstWhere(
        (p) {
          if (p == null) return false;
          final pos = p.position.trim().toUpperCase();
          return pos == 'ARM' || pos.contains('ARMAD');
        },
        orElse: () => null,
      );
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ActionScoutingDialog(
          actionType: actionType,
          team: team,
          rotation: rotation,
          hasLibero: hasLibero,
          isServingTeam: isServingTeam,
          initialPlayer: initialPlayer,
          benchedCentral: _getBenchedCentral(
            team,
            rotation,
            hasLibero,
            forceServing: actionType == 'Saque',
          ),
          lineup: lineup,
          onComplete: (player, result) {
            _pendingAction = actionType;
            _selectedPlayer = player;
            _executeAction(result);
          },
        );
      },
    );
  }

  void _executeAction(String result) {
    final team = _activeTeamId == _activeMatch!.localTeam.id ? _activeMatch!.localTeam : _activeMatch!.visitorTeam;
    _saveQuickAction(_pendingAction!, result, team, _selectedPlayer);
    setState(() {
      _pendingAction = null;
      _selectedPlayer = null;
    });
  }

  String _teamName(String teamId) {
    final match = _activeMatch!;
    return teamId == match.localTeam.id
        ? match.localTeam.name
        : match.visitorTeam.name;
  }

  String _playerName(String playerId) {
    final players = _lineups.values.expand((lineup) => lineup);
    for (final player in players) {
      if (player.id == playerId) return '#${player.number} ${player.name}';
    }
    return 'Jugador no disponible';
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }



  List<Player> _playersForTeam(Team team) => _lineups[team.id] ?? [];

  bool get _hasCompleteLineups {
    final match = _activeMatch;
    return match != null &&
        _playersForTeam(match.localTeam).length == 6 &&
        _playersForTeam(match.visitorTeam).length == 6;
  }

  String? _scoringTeamId(ScoutingAction action) {
    if (action.actionType == 'Armado' || action.actionType == 'Defensa') {
      return null;
    }
    if (action.result == 'Punto a favor') {
      return action.teamId;
    }
    if (action.result == 'Error') {
      final match = _activeMatch!;
      return action.teamId == match.localTeam.id
          ? match.visitorTeam.id
          : match.localTeam.id;
    }
    return null;
  }

  Future<void> _applyScoreForAction(ScoutingAction action) async {
    final scoringTeamId = _scoringTeamId(action);
    if (scoringTeamId == null) return;

    final match = _activeMatch!;
    final localScored = scoringTeamId == match.localTeam.id;
    var localScore = match.localScore + (localScored ? 1 : 0);
    var visitorScore = match.visitorScore + (localScored ? 0 : 1);
    var localSets = match.localSets;
    var visitorSets = match.visitorSets;
    var localRotation = match.localRotation;
    var visitorRotation = match.visitorRotation;
    final isTieBreak = match.totalSets > 1 && (localSets + visitorSets) == (match.totalSets - 1);
    final targetScore = isTieBreak ? match.tiebreakPoints : match.pointsPerSet;
    final winnerScore = localScored ? localScore : visitorScore;
    final loserScore = localScored ? visitorScore : localScore;

    // Lógica de Deuce / Alargue
    final deuceTrigger = targetScore - 1;
    final currentSetNumber = localSets + visitorSets + 1;
    if (localScore == deuceTrigger && visitorScore == deuceTrigger && (_setDeuceAlargue == null || _deuceSetNumber != currentSetNumber)) {
      if (mounted) {
        final chooseAlargue = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('¡Punto de Set Empatado!'),
            content: Text(
              'Ambos equipos están empatados $deuceTrigger - $deuceTrigger.\n\n'
              '¿Desea jugar alargue (diferencia de 2 puntos) o muerte súbita (primer equipo en llegar a $targetScore)?',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Jugar Alargue'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Muerte Súbita'),
              ),
            ],
          ),
        );
        _setDeuceAlargue = chooseAlargue ?? true;
        _deuceSetNumber = currentSetNumber;
      }
    }

    bool setWon;
    if (_setDeuceAlargue == false && _deuceSetNumber == currentSetNumber) {
      setWon = winnerScore >= targetScore;
    } else {
      setWon = winnerScore >= targetScore && (winnerScore - loserScore) >= 2;
    }

    String nextServingTeamId = scoringTeamId;
    bool isMatchOver = false;

    if (setWon) {
      if (localScored) {
        localSets++;
      } else {
        visitorSets++;
      }
      final winningTeam = localScored ? match.localTeam : match.visitorTeam;
      final setFinalScore = '$winnerScore - $loserScore';
      final setsToWin = (match.totalSets / 2).ceil();
      isMatchOver = localSets >= setsToWin || visitorSets >= setsToWin;

      localScore = 0;
      visitorScore = 0;
      localRotation = 0;
      visitorRotation = 0;
      _setDeuceAlargue = null;
      _deuceSetNumber = -1;

      // Determinar quién saca en el siguiente set
      final totalSetsPlayed = localSets + visitorSets;
      if (totalSetsPlayed < match.totalSets) {
        final actions = await DatabaseHelper.instance.getScoutingActions(match.id);
        final firstServe = actions.cast<ScoutingAction?>().lastWhere(
          (a) => a?.actionType == 'Saque', 
          orElse: () => null,
        );
        final firstServingTeamOfMatch = firstServe?.teamId ?? scoringTeamId;
        if (totalSetsPlayed % 2 == 0) {
          nextServingTeamId = firstServingTeamOfMatch;
        } else {
          nextServingTeamId = firstServingTeamOfMatch == match.localTeam.id ? match.visitorTeam.id : match.localTeam.id;
        }
      }

      Match updatedMatch = match.copyWith(
        localScore: localScore,
        visitorScore: visitorScore,
        localSets: localSets,
        visitorSets: visitorSets,
        servingTeamId: nextServingTeamId,
        localRotation: localRotation,
        visitorRotation: visitorRotation,
        isActive: !isMatchOver,
      );
      await DatabaseHelper.instance.updateMatchState(updatedMatch);
      if (_coachCode != null) {
        SyncService.instance.syncActiveMatch(updatedMatch, _coachCode!);
      }

      // Mostrar diálogo de fin de set
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.emoji_events, color: Colors.amber, size: 36),
                SizedBox(width: 8),
                Text('¡Fin del Set!', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '¡Set para ${winningTeam.name.toUpperCase()}!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Marcador del set: $setFinalScore',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sets globales: ${match.localTeam.name} $localSets - $visitorSets ${match.visitorTeam.name}',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                if (isMatchOver) ...[
                  const SizedBox(height: 16),
                  Text(
                    '¡${winningTeam.name.toUpperCase()} HA GANADO EL PARTIDO!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('CONTINUAR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }

      // Si el partido no ha terminado, abrir configuración de alineación para el nuevo set
      if (!isMatchOver && mounted) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => LineupSelectionPage(
              match: updatedMatch,
              isNewSet: true,
            ),
          ),
        );
        await _loadData();
        return;
      }
    } else if (match.servingTeamId != scoringTeamId) {
      if (localScored) {
        localRotation = (localRotation + 1) % 6;
      } else {
        visitorRotation = (visitorRotation + 1) % 6;
      }

      Match updatedMatch = match.copyWith(
        localScore: localScore,
        visitorScore: visitorScore,
        localSets: localSets,
        visitorSets: visitorSets,
        servingTeamId: nextServingTeamId,
        localRotation: localRotation,
        visitorRotation: visitorRotation,
      );
      await DatabaseHelper.instance.updateMatchState(updatedMatch);
      if (_coachCode != null) {
        SyncService.instance.syncActiveMatch(updatedMatch, _coachCode!);
      }
    } else {
      Match updatedMatch = match.copyWith(
        localScore: localScore,
        visitorScore: visitorScore,
        localSets: localSets,
        visitorSets: visitorSets,
        servingTeamId: nextServingTeamId,
        localRotation: localRotation,
        visitorRotation: visitorRotation,
      );
      await DatabaseHelper.instance.updateMatchState(updatedMatch);
      if (_coachCode != null) {
        SyncService.instance.syncActiveMatch(updatedMatch, _coachCode!);
      }
    }

    if (mounted) {
      setState(() => _activeTeamId = nextServingTeamId);
    }
  }

  Future<void> _undoLastAction() async {
    if (_actions.isEmpty) return;
    final lastAction = _actions.first;
    final match = _activeMatch!;
    await DatabaseHelper.instance.deleteScoutingAction(lastAction.id);
    if (_coachCode != null) {
      SyncService.instance.deleteScoutingAction(match.id, lastAction.id, _coachCode!);
    }

    // Reconstruir estado
    Match rebuilt = match.copyWith(
      localScore: 0,
      visitorScore: 0,
      localSets: 0,
      visitorSets: 0,
      localRotation: 0,
      visitorRotation: 0,
      servingTeamId: match.initialServingTeamId,
    );

    final remainingActions = await DatabaseHelper.instance.getScoutingActions(match.id);
    // getScoutingActions returns DESC (newest first). We need ASC for replay.
    final ascActions = remainingActions.reversed.toList();

    for (final action in ascActions) {
      final scoringTeamId = _scoringTeamId(action);
      if (scoringTeamId == null) continue;

      final localScored = scoringTeamId == rebuilt.localTeam.id;
      var localScore = rebuilt.localScore + (localScored ? 1 : 0);
      var visitorScore = rebuilt.visitorScore + (localScored ? 0 : 1);
      var localSets = rebuilt.localSets;
      var visitorSets = rebuilt.visitorSets;
      var localRotation = rebuilt.localRotation;
      var visitorRotation = rebuilt.visitorRotation;
      
      final isTieBreak = match.totalSets > 1 && (localSets + visitorSets) == (match.totalSets - 1);
      final targetScore = isTieBreak ? match.tiebreakPoints : match.pointsPerSet;
      final winnerScore = localScored ? localScore : visitorScore;
      final loserScore = localScored ? visitorScore : localScore;
      final setWon = winnerScore >= targetScore && winnerScore - loserScore >= 2;

      String nextServingTeamId = scoringTeamId;

      if (setWon) {
        if (localScored) localSets++; else visitorSets++;
        localScore = 0; visitorScore = 0; localRotation = 0; visitorRotation = 0;

        final totalSetsPlayed = localSets + visitorSets;
        if (totalSetsPlayed < match.totalSets) {
          if (totalSetsPlayed == match.totalSets - 1) {
            // Si llegamos a tiebreak al reproducir, asumimos que el saque inicial guardado en la base de datos es correcto.
          } else {
            final firstServe = ascActions.firstWhere((a) => a.actionType == 'Saque', orElse: () => action);
            final firstServingTeamOfMatch = firstServe.teamId;
            if (totalSetsPlayed % 2 == 0) {
              nextServingTeamId = firstServingTeamOfMatch;
            } else {
              nextServingTeamId = firstServingTeamOfMatch == match.localTeam.id ? match.visitorTeam.id : match.localTeam.id;
            }
          }
        }
      } else if (rebuilt.servingTeamId != scoringTeamId) {
        if (localScored) localRotation = (localRotation + 1) % 6;
        else visitorRotation = (visitorRotation + 1) % 6;
      }

      rebuilt = rebuilt.copyWith(
        localScore: localScore,
        visitorScore: visitorScore,
        localSets: localSets,
        visitorSets: visitorSets,
        servingTeamId: nextServingTeamId,
        localRotation: localRotation,
        visitorRotation: visitorRotation,
      );
    }
    
    // Restaurar si en tiebreak hubo un override (simplificado)
    if (remainingActions.isNotEmpty && match.totalSets > 1 && (rebuilt.localSets + rebuilt.visitorSets) == (match.totalSets - 1)) {
        // En tie-break, mantener el servingTeamId del estado actual si ya se había sorteado,
        // a menos que hayamos deshecho el último punto que provocó el tie-break.
    }

    await DatabaseHelper.instance.updateMatchState(rebuilt);
    if (_coachCode != null) {
      SyncService.instance.syncActiveMatch(rebuilt, _coachCode!);
    }
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Última acción deshecha')));
    }
  }



  Future<void> _saveQuickAction(String actionType, String result, Team team, Player? player) async {
    if (player == null && actionType != 'Tiempo Fuera') return;
    final match = _activeMatch!;
    if (actionType == 'Saque' && _matchTimer == null) {
      _matchStartTime = DateTime.now();
      _startTimer();
    }

    final now = DateTime.now();
    final realTimeString = '${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour)}:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? "PM" : "AM"}';
    final matchTimeString = '${(_elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(_elapsedSeconds % 60).toString().padLeft(2, '0')}';

    String? attackZone;
    if (actionType == 'Ataque' && player != null) {
      final rotation = team.id == match.localTeam.id ? match.localRotation : match.visitorRotation;
      final lineup = _playersForTeam(team);
      final rotatedPlayers = List.generate(
        6,
        (index) => lineup.length > (index + rotation) % 6 ? lineup[(index + rotation) % 6] : null,
      );
      final playerRotIndex = rotatedPlayers.indexWhere((p) => p?.id == player.id);
      if (playerRotIndex == 0 || playerRotIndex == 4 || playerRotIndex == 5) {
        attackZone = 'Zaguero';
      } else if (playerRotIndex == 1 || playerRotIndex == 2 || playerRotIndex == 3) {
        attackZone = 'Delantero';
      } else {
        attackZone = player.position.toLowerCase().contains('lib') ? 'Zaguero' : 'Delantero';
      }
    }

    final action = ScoutingAction(
      id: now.microsecondsSinceEpoch.toString(),
      matchId: match.id,
      teamId: team.id,
      playerId: player?.id ?? '',
      actionType: actionType,
      result: result,
      createdAt: now,
      matchTime: matchTimeString,
      realTime: realTimeString,
      attackZone: attackZone,
    );
    await DatabaseHelper.instance.insertScoutingAction(action);
    if (_coachCode != null) {
      SyncService.instance.syncScoutingAction(action, _coachCode!);
    }
    await _applyScoreForAction(action);

    // Automatización Táctica 2: Transición de Balón (Cambio de Equipo)
    // Si la acción registrada es "Saque" o "Ataque" Y el resultado es "Neutro" (el balón pasó la red pero el rally continúa),
    // cambia automáticamente el estado del equipo seleccionado en la pantalla principal al equipo contrario.
    if ((actionType == 'Saque' || actionType == 'Ataque') && result == 'Neutro') {
      final oppositeTeamId = team.id == match.localTeam.id
          ? match.visitorTeam.id
          : match.localTeam.id;
      _activeTeamId = oppositeTeamId;
      if (mounted) {
        setState(() {});
      }
    }

    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    
    // Alertas de rendimiento (MVP)
    if (player != null && actionType != 'Armado' && actionType != 'Defensa') {
      int puntos = result == 'Punto a favor' ? 1 : 0;
      int errores = result == 'Error' ? 1 : 0;
      for (var a in _actions) {
        if (a.playerId == player.id) {
          if (a.result == 'Punto a favor') puntos++;
          if (a.result == 'Error') errores++;
        }
      }
      
      final umbral = match.pointsPerSet / 3;
      if (result == 'Punto a favor' && puntos > umbral) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('¡Atención! ${player.name} está destacando (Racha de puntos: $puntos)'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ));
      } else if (result == 'Error' && errores > umbral) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('¡Revisión táctica! ${player.name} acumula varios errores ($errores)'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ));
      }
    }

    await _loadData();
  }

  Future<void> _showSubstitutionDialog(Team team) async {
    final currentLineup = _playersForTeam(team);
    final bench = team.players.where((p) => !currentLineup.any((cp) => cp.id == p.id)).toList();

    Player? playerOut;
    Player? playerIn;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Sustitución - ${team.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Jugador a salir:', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<Player>(
                  isExpanded: true,
                  value: playerOut,
                  hint: const Text('Seleccionar titular'),
                  items: currentLineup.map((p) => DropdownMenuItem(
                    value: p,
                    child: Text('#${p.number} ${p.name} (${p.position})'),
                  )).toList(),
                  onChanged: (v) => setStateDialog(() => playerOut = v),
                ),
                const SizedBox(height: 16),
                const Text('Jugador a entrar:', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<Player>(
                  isExpanded: true,
                  value: playerIn,
                  hint: const Text('Seleccionar banca'),
                  items: bench.map((p) => DropdownMenuItem(
                    value: p,
                    child: Text('#${p.number} ${p.name} (${p.position})'),
                  )).toList(),
                  onChanged: (v) => setStateDialog(() => playerIn = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: (playerOut != null && playerIn != null)
                  ? () async {
                      final match = _activeMatch!;
                      final newLineup = List<Player>.from(currentLineup);
                      final index = newLineup.indexWhere((p) => p.id == playerOut!.id);
                      if (index != -1) {
                        newLineup[index] = playerIn!;
                        await DatabaseHelper.instance.saveMatchLineup(
                          match.id,
                          team.id,
                          newLineup.map((p) => p.id).toList(),
                        );
                        // Registrar acción de sustitución (opcional pero útil)
                        final action = ScoutingAction(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          matchId: match.id,
                          teamId: team.id,
                          playerId: playerIn!.id,
                          actionType: 'Sustitución',
                          result: 'Entra por #${playerOut!.number}',
                          createdAt: DateTime.now(),
                        );
                        await DatabaseHelper.instance.insertScoutingAction(action);
                        await _loadData();
                        if (mounted) Navigator.pop(context);
                      }
                    }
                  : null,
              child: const Text('Realizar Cambio'),
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _showTimeoutDialog(Team team) async {
    _saveQuickAction('Tiempo Fuera', 'Solicitado', team, null);
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _TimeoutDialog(team: team);
      },
    );
  }
}

class _ActionBtnData {
  final String title;
  final IconData icon;
  final Color color;
  final Color foregroundColor;
  final VoidCallback onPressed;

  _ActionBtnData({
    required this.title,
    required this.icon,
    required this.color,
    required this.foregroundColor,
    required this.onPressed,
  });
}

class _TimeoutDialog extends StatefulWidget {
  final Team team;
  const _TimeoutDialog({required this.team});

  @override
  State<_TimeoutDialog> createState() => _TimeoutDialogState();
}

class _TimeoutDialogState extends State<_TimeoutDialog> {
  int _secondsLeft = 60;
  bool _timerActive = true;
  
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() async {
    while (_secondsLeft > 0 && _timerActive && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _secondsLeft--;
        });
      }
    }
    if (_secondsLeft == 0 && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timerActive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Tiempo Fuera - ${widget.team.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tiempo restante:'),
          const SizedBox(height: 16),
          Text(
            '$_secondsLeft',
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          const SizedBox(height: 8),
          const Text('segundos'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _timerActive = false;
            Navigator.pop(context);
          },
          child: const Text('Omitir / Cerrar'),
        ),
      ],
    );
  }
}



class _ActionScoutingDialog extends StatefulWidget {
  final String actionType;
  final Team team;
  final int rotation;
  final bool hasLibero;
  final bool isServingTeam;
  final Player? initialPlayer;
  final Player? benchedCentral;
  final List<Player> lineup;
  final void Function(Player?, String) onComplete;

  const _ActionScoutingDialog({
    required this.actionType,
    required this.team,
    required this.rotation,
    required this.hasLibero,
    this.isServingTeam = true,
    this.initialPlayer,
    this.benchedCentral,
    required this.lineup,
    required this.onComplete,
  });

  @override
  _ActionScoutingDialogState createState() => _ActionScoutingDialogState();
}

class _ActionScoutingDialogState extends State<_ActionScoutingDialog> {
  Player? _selectedPlayer;
  String? _selectedResult;

  @override
  void initState() {
    super.initState();
    _selectedPlayer = widget.initialPlayer;
    if (_selectedPlayer == null && widget.actionType == 'Armado') {
      _selectedPlayer = widget.lineup.cast<Player?>().firstWhere(
        (p) {
          if (p == null) return false;
          final pos = p.position.trim().toUpperCase();
          return pos == 'ARM' || pos.contains('ARMAD');
        },
        orElse: () => null,
      );
    } else if (_selectedPlayer == null &&
        widget.actionType == 'Saque' &&
        widget.isServingTeam &&
        widget.lineup.isNotEmpty) {
      _selectedPlayer = widget.lineup[widget.rotation % widget.lineup.length];
    }
  }

  void _checkComplete() {
    if (_selectedPlayer != null && _selectedResult != null) {
      widget.onComplete(_selectedPlayer, _selectedResult!);
    }
  }

  void _onPlayerSelected(Player player) {
    setState(() {
      _selectedPlayer = player;
    });
    _checkComplete();
  }

  void _onResultSelected(String result) {
    setState(() {
      _selectedResult = result;
    });
    _checkComplete();
  }

  bool _isPlayerDisabled(Player? player, int zone, {Player? server}) {
    if (player == null || player.id.isEmpty) return true;
    if (widget.actionType == 'Saque') {
      // Si no hay un sacador válido resuelto (ej. equipo no al saque o desajuste),
      // habilitar todos los jugadores en cancha como respaldo seguro.
      if (server == null || server.id.isEmpty) return false;
      return player.id != server.id;
    } else if (widget.actionType == 'Bloqueo') {
      return zone != 2 && zone != 3 && zone != 4;
    }
    return false;
  }

  bool _isBenchedDisabled() {
    return widget.actionType == 'Saque' || widget.actionType == 'Bloqueo';
  }

  Widget _playerWidget(Player player, {bool isBenched = false, bool disabled = false}) {
    if (player.id.isEmpty) return const SizedBox(width: 56, height: 56);

    final isSelected = _selectedPlayer?.id == player.id && !disabled;
    
    // Format "CEN Daniel"
    String pos = player.position.toUpperCase();
    if (pos.length > 3) pos = pos.substring(0, 3);
    final shortName = player.name.split(' ').first;
    final label = '$pos $shortName';
    
    Widget avatar = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? Colors.yellowAccent : (disabled ? Colors.white24 : Colors.white.withOpacity(0.85)),
          width: isSelected ? 3.0 : 1.5,
        ),
        boxShadow: [
          if (!disabled)
            BoxShadow(
              color: isSelected ? Colors.yellowAccent.withOpacity(0.6) : Colors.black38,
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: CircleAvatar(
        radius: 28, // Radio táctil grande
        backgroundColor: disabled 
            ? Colors.grey.shade700 
            : (isSelected ? Colors.yellowAccent : Colors.blue.shade700), // Azul principal Colors.blue[700]
        child: Text(
          player.number.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: disabled ? Colors.white38 : (isSelected ? Colors.black : Colors.white),
            fontSize: 22,
          ),
        ),
      ),
    );

    if (!disabled) {
      avatar = GestureDetector(
        onTap: () => _onPlayerSelected(player),
        child: avatar,
      );
    } else {
      avatar = IgnorePointer(child: avatar);
    }

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isBenched)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: disabled ? Colors.grey.shade800 : Colors.redAccent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'BANCA',
                style: TextStyle(
                  color: disabled ? Colors.white38 : Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          avatar,
          const SizedBox(height: 2),
          SizedBox(
            width: 60,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.yellowAccent : Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? Colors.black : Colors.white24,
                  width: 1,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.black : (disabled ? Colors.white54 : Colors.white),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourtHalf() {
    final rotatedPlayers = List<Player>.generate(
      widget.lineup.length,
      (i) => widget.lineup[(i + widget.rotation) % widget.lineup.length],
    );

    bool liberoSubstituted = false;
    if (widget.hasLibero && widget.benchedCentral != null) {
      final libero = widget.team.players.firstWhere(
        (p) => p.position.toLowerCase() == 'líbero' || p.position.toLowerCase() == 'libero',
        orElse: () => Player(id: '', name: '', number: 0, position: 'Líbero'),
      );
      if (libero.id.isNotEmpty) {
        for (int i = 0; i < rotatedPlayers.length; i++) {
          if (rotatedPlayers[i].id == widget.benchedCentral!.id) {
            rotatedPlayers[i] = libero;
            liberoSubstituted = true;
          }
        }
      }
    }

    String getRole(Player p) {
      final pos = p.position.toLowerCase().trim();
      if (pos == 'central' || pos.startsWith('cen')) return 'CEN';
      if (pos == 'auxiliar' || pos.startsWith('aux') || pos.contains('punta') || pos.contains('rec')) return 'AUX';
      if (pos == 'armador' || pos.startsWith('arm') || pos.contains('col') || pos.contains('pas')) return 'ARM';
      if (pos == 'opuesto' || pos.startsWith('ope') || pos.startsWith('opu')) return 'OPE';
      if (pos == 'líbero' || pos == 'libero' || pos.startsWith('lib')) return 'LIB';
      return pos.toUpperCase();
    }

    // Índices de rotación: delanteros son 1, 2, 3 (Zonas 2, 3, 4); zagueros son 0, 4, 5 (Zonas 1, 6, 5)
    bool isDelantero(int idx) => idx == 1 || idx == 2 || idx == 3;
    bool isZaguero(int idx) => idx == 0 || idx == 4 || idx == 5;
    int indexOfPlayer(Player p) => rotatedPlayers.indexWhere((rp) => rp.id == p.id);

    // 1. Auxiliares (AUX):
    // Si índice real es delantero (1, 2 o 3) -> Zona 4: Alignment(-0.7, -0.6)
    // Si índice real es zaguero (0, 4 o 5) -> Zona 6: Alignment(0.0, 0.6)
    final auxPlayers = rotatedPlayers.where((p) => getRole(p) == 'AUX').toList();
    Player? auxDel = auxPlayers.cast<Player?>().firstWhere(
      (p) => p != null && isDelantero(indexOfPlayer(p)),
      orElse: () => null,
    );
    Player? auxZag = auxPlayers.cast<Player?>().firstWhere(
      (p) => p != null && isZaguero(indexOfPlayer(p)) && p.id != auxDel?.id,
      orElse: () => null,
    );
    if (auxDel == null && auxPlayers.isNotEmpty) {
      auxDel = auxPlayers.cast<Player?>().firstWhere(
        (p) => p != null && p.id != auxZag?.id,
        orElse: () => null,
      );
    }
    if (auxZag == null && auxPlayers.isNotEmpty) {
      auxZag = auxPlayers.cast<Player?>().firstWhere(
        (p) => p != null && p.id != auxDel?.id,
        orElse: () => null,
      );
    }

    // 2. Centrales (CEN) y Líbero (LIB):
    // Si Central tiene índice delantero (1, 2 o 3) -> Zona 3: Alignment(0.0, -0.6)
    // El Líbero SOLO ocupa Zona 5 si efectivamente está en cancha (en rotatedPlayers).
    // Así, cuando el Central está sacando en Zona 1 (sin ser sustituido por el Líbero),
    // el Central zaguero permanece en cancha y habilitado para registrar su saque.
    final cenPlayers = rotatedPlayers.where(
      (p) => getRole(p) == 'CEN' && (!liberoSubstituted || widget.benchedCentral == null || p.id != widget.benchedCentral!.id),
    ).toList();
    Player? cenDel = cenPlayers.cast<Player?>().firstWhere(
      (p) => p != null && isDelantero(indexOfPlayer(p)),
      orElse: () => cenPlayers.isNotEmpty ? cenPlayers.first : null,
    );

    Player? libOrCenZag;
    if (widget.hasLibero && rotatedPlayers.any((p) => getRole(p) == 'LIB')) {
      libOrCenZag = rotatedPlayers.firstWhere((p) => getRole(p) == 'LIB');
    }
    // Si el líbero no está en cancha (ej. Central al saque), el Central zaguero ocupa Zona 5
    libOrCenZag ??= cenPlayers.cast<Player?>().firstWhere(
      (p) => p != null && isZaguero(indexOfPlayer(p)) && p.id != cenDel?.id,
      orElse: () => cenPlayers.cast<Player?>().firstWhere(
        (p) => p != null && p.id != cenDel?.id,
        orElse: () => null,
      ),
    );

    // 3. Armador (ARM) y Opuesto (OPE) [Lógica Cruzada]:
    // Si Armador es delantero -> Zona 2: Armador, Zona 1: Opuesto
    // Si Opuesto es delantero -> Zona 2: Opuesto, Zona 1: Armador
    final arm = rotatedPlayers.cast<Player?>().firstWhere((p) => p != null && getRole(p) == 'ARM', orElse: () => null);
    final ope = rotatedPlayers.cast<Player?>().firstWhere((p) => p != null && getRole(p) == 'OPE', orElse: () => null);

    final armIdx = arm != null ? indexOfPlayer(arm) : -1;
    final opeIdx = ope != null ? indexOfPlayer(ope) : -1;

    Player? delRight; // Zona 2 (Alignment(0.7, -0.6))
    Player? zagRight; // Zona 1 (Alignment(0.7, 0.6))

    if (arm != null && isDelantero(armIdx)) {
      delRight = arm;
      zagRight = (ope != null && ope.id != arm.id) ? ope : null;
    } else if (ope != null && isDelantero(opeIdx)) {
      delRight = ope;
      zagRight = (arm != null && arm.id != ope.id) ? arm : null;
    } else if (arm != null && isZaguero(armIdx)) {
      zagRight = arm;
      delRight = (ope != null && ope.id != arm.id) ? ope : null;
    } else if (ope != null && isZaguero(opeIdx)) {
      zagRight = ope;
      delRight = (arm != null && arm.id != ope.id) ? arm : null;
    } else {
      delRight = ope ?? arm;
      zagRight = (arm != null && arm.id != delRight?.id) ? arm : null;
    }

    // Asegurar que los 6 jugadores en cancha queden siempre asignados sin duplicados
    final assignedIds = <String>{};
    if (auxDel != null) assignedIds.add(auxDel.id);
    if (cenDel != null) assignedIds.add(cenDel.id);
    if (delRight != null) assignedIds.add(delRight.id);
    if (libOrCenZag != null) assignedIds.add(libOrCenZag.id);
    if (auxZag != null) assignedIds.add(auxZag.id);
    if (zagRight != null) assignedIds.add(zagRight.id);

    final unassigned = rotatedPlayers.where(
      (p) => !assignedIds.contains(p.id) && (!liberoSubstituted || widget.benchedCentral == null || p.id != widget.benchedCentral!.id),
    ).toList();

    auxDel ??= (unassigned.isNotEmpty ? unassigned.removeAt(0) : null);
    cenDel ??= (unassigned.isNotEmpty ? unassigned.removeAt(0) : null);
    delRight ??= (unassigned.isNotEmpty ? unassigned.removeAt(0) : null);
    libOrCenZag ??= (unassigned.isNotEmpty ? unassigned.removeAt(0) : null);
    auxZag ??= (unassigned.isNotEmpty ? unassigned.removeAt(0) : null);
    zagRight ??= (unassigned.isNotEmpty ? unassigned.removeAt(0) : null);

    // Determinar el sacador esperado (Zona 1 = rotatedPlayers[0]) cuando corresponde
    Player? resolvedServer;
    if (widget.actionType == 'Saque' && widget.isServingTeam) {
      resolvedServer = widget.initialPlayer ??
          (rotatedPlayers.isNotEmpty ? rotatedPlayers[0] : null);
    }

    final courtSpots = <(Player?, int, double, double)>[
      (auxDel, 4, -0.7, -0.6),      // Zona 4: Auxiliar Delantero
      (cenDel, 3, 0.0, -0.6),       // Zona 3: Central Delantero
      (delRight, 2, 0.7, -0.6),     // Zona 2: Delantero Derecho (ARM u OPE)
      (libOrCenZag, 5, -0.7, 0.6),  // Zona 5: Líbero (o Central Zaguero)
      (auxZag, 6, 0.0, 0.6),        // Zona 6: Auxiliar Zaguero
      (zagRight, 1, 0.7, 0.6),      // Zona 1: Zaguero Derecho (OPE o ARM)
    ];

    // Respaldo seguro: verificar que al menos 1 jugador en cancha quede habilitado.
    // Si por cualquier motivo (rotación, equipo al saque, etc.) ninguno coincide,
    // habilitar a todos los jugadores en cancha en lugar de bloquearlos a todos.
    final bool hasAnyEnabled = courtSpots.any(
      (s) => s.$1 != null && s.$1!.id.isNotEmpty && !_isPlayerDisabled(s.$1, s.$2, server: resolvedServer),
    );
    final bool fallbackEnableAll = !hasAnyEnabled;

    Widget spot(Player? player, int zone, double x, double y) {
      if (player == null) return const SizedBox.shrink();
      final isDisabled = fallbackEnableAll
          ? player.id.isEmpty
          : _isPlayerDisabled(player, zone, server: resolvedServer);
      return Align(
        alignment: Alignment(x, y),
        child: _playerWidget(player, disabled: isDisabled),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF388E3C), // Verde vibrante de cancha
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Línea divisoria central / ataque horizontal
          Align(
            alignment: const Alignment(0, 0.0),
            child: Container(
              width: double.infinity,
              height: 2,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          // Línea de red (borde superior)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: double.infinity,
              height: 6,
              color: Colors.white,
            ),
          ),
          // Indicador de red
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'RED',
                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ),
          ),
          // Posiciones Tácticas Fijas por Rol y Rotación Real (Modal)
          spot(auxDel, 4, -0.7, -0.6),      // Zona 4: Auxiliar Delantero
          spot(cenDel, 3, 0.0, -0.6),       // Zona 3: Central Delantero
          spot(delRight, 2, 0.7, -0.6),     // Zona 2: Delantero Derecho (ARM u OPE)
          spot(libOrCenZag, 5, -0.7, 0.6),  // Zona 5: Líbero (o Central Zaguero)
          spot(auxZag, 6, 0.0, 0.6),        // Zona 6: Auxiliar Zaguero
          spot(zagRight, 1, 0.7, 0.6),      // Zona 1: Zaguero Derecho (OPE o ARM)
          // Central en banca
          if (widget.benchedCentral != null)
            Align(
              alignment: const Alignment(-0.95, 0.0),
              child: _playerWidget(widget.benchedCentral!, isBenched: true, disabled: _isBenchedDisabled()),
            ),
        ],
      ),
    );
  }

  Widget _modalSideButton({
    required String label, 
    required String resultValue,
    required Color color, 
    required IconData icon, 
    required VoidCallback onTap,
  }) {
    final isSelected = _selectedResult == resultValue;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Material(
          color: color,
          elevation: 6,
          shadowColor: Colors.black87,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: isSelected 
                    ? Border.all(color: Colors.yellowAccent, width: 4) 
                    : Border.all(color: Colors.white24, width: 1.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isQualitative = widget.actionType == 'Armado' || widget.actionType == 'Defensa';

    return Material(
      color: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.black87,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48), // Balance for center alignment
                      Expanded(
                        child: Text(
                          'REGISTRAR ${widget.actionType.toUpperCase()} / TOCA UN JUGADOR',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent,
                          boxShadow: [
                            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 26),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Cerrar',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Body
                  Expanded(
                    child: Row(
                      children: [
                        // Izquierda (Expanded flex: 2): En contra o Negativo
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _modalSideButton(
                                label: isQualitative ? 'Negativo (Mal)' : 'En contra',
                                resultValue: isQualitative ? 'Negativo' : 'Error',
                                color: Colors.redAccent,
                                icon: Icons.error_outline,
                                onTap: () => _onResultSelected(isQualitative ? 'Negativo' : 'Error'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Centro (Expanded flex: 7): Media Cancha
                        Expanded(
                          flex: 7,
                          child: _buildCourtHalf(),
                        ),
                        const SizedBox(width: 8),
                        // Derecha (Expanded flex: 2): Neutro y A Favor / Positivo
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _modalSideButton(
                                label: 'Neutro',
                                resultValue: 'Neutro',
                                color: Colors.grey.shade700,
                                icon: Icons.remove_circle_outline,
                                onTap: () => _onResultSelected('Neutro'),
                              ),
                              _modalSideButton(
                                label: isQualitative ? 'Positivo (Bien)' : 'A favor',
                                resultValue: isQualitative ? 'Positivo' : 'Punto a favor',
                                color: Colors.greenAccent.shade700,
                                icon: Icons.check_circle_outline,
                                onTap: () => _onResultSelected(isQualitative ? 'Positivo' : 'Punto a favor'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
