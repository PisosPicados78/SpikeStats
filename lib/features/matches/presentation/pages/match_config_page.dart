import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/models/match.dart';
import '../../../../core/models/team.dart';
import '../../../../core/theme/gradient_background.dart';
import '../../../../core/services/sync_service.dart';
import 'lineup_selection_page.dart';

class MatchConfigPage extends StatefulWidget {
  const MatchConfigPage({super.key});

  @override
  State<MatchConfigPage> createState() => _MatchConfigPageState();
}

class _MatchConfigPageState extends State<MatchConfigPage> {
  List<Team> _teams = [];
  List<Match> _matches = [];
  String? _localTeamId;
  String? _visitorTeamId;
  String? _servingTeamId;
  DateTime _matchDate = DateTime.now();
  bool _isLoading = true;
  final _tournamentController = TextEditingController();

  int _totalSets = 3;
  int _pointsPerSet = 25;
  int _tiebreakPoints = 15;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tournamentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final teams = await DatabaseHelper.instance.getTeams();
    final matches = await DatabaseHelper.instance.getMatches();
    if (!mounted) return;
    setState(() {
      _teams = teams;
      _matches = matches;
      _isLoading = false;
    });
  }

  Future<void> _selectDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _matchDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selectedDate != null && mounted) {
      setState(() => _matchDate = selectedDate);
    }
  }

  Future<void> _startMatch() async {
    if (_localTeamId == null || _visitorTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona ambos equipos')),
      );
      return;
    }
    if (_localTeamId == _visitorTeamId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Un equipo no puede jugar contra sí mismo'),
        ),
      );
      return;
    }
    if (_tournamentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el nombre del torneo o fase')),
      );
      return;
    }

    final localTeam = _teams.firstWhere((team) => team.id == _localTeamId);
    final visitorTeam = _teams.firstWhere((team) => team.id == _visitorTeamId);
    final match = Match(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      localTeam: localTeam,
      visitorTeam: visitorTeam,
      date: _matchDate,
      tournament: _tournamentController.text.trim(),
      servingTeamId: _servingTeamId ?? localTeam.id,
      totalSets: _totalSets,
      pointsPerSet: _pointsPerSet,
      tiebreakPoints: _tiebreakPoints,
    );
    await DatabaseHelper.instance.insertMatch(match);
    await _openMatch(match, showMessage: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Partido activo: ${localTeam.name} vs ${visitorTeam.name}',
        ),
      ),
    );
  }

  Future<void> _openMatch(Match match, {bool showMessage = true}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LineupSelectionPage(match: match)),
    );

    if (result == true) {
      await DatabaseHelper.instance.setActiveMatch(match.id);
      final active = await DatabaseHelper.instance.getActiveMatch();
      final coachCode = await SyncService.instance.getConnectedCoachCode() ?? await SyncService.instance.getCoachCode();
      if (active != null && coachCode != null) {
        SyncService.instance.syncActiveMatch(active, coachCode);
      }
      await _loadData();
      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Partido activo: ${match.localTeam.name} vs ${match.visitorTeam.name}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _configureLineup(Match match) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LineupSelectionPage(match: match)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Configuración de Partido')),
      body: Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.lightBlueAccent,
            secondary: Colors.tealAccent,
          ),
        ),
        child: GradientBackground(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Datos del Encuentro',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _tournamentController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del Torneo / Fase',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.emoji_events),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_teams.length < 2)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Registra al menos dos equipos en la pestaña Equipos para crear un partido.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Equipo Local',
                            border: OutlineInputBorder(),
                          ),
                          value: _localTeamId,
                          items: _teams.map((team) {
                            return DropdownMenuItem(
                              value: team.id,
                              child: Text(team.name),
                            );
                          }).toList(),
                          onChanged: _teams.isEmpty
                              ? null
                              : (value) => setState(() {
                                  _localTeamId = value;
                                  _servingTeamId = value;
                                }),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'VS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Equipo Visitante',
                            border: OutlineInputBorder(),
                          ),
                          value: _visitorTeamId,
                          items: _teams.map((team) {
                            return DropdownMenuItem(
                              value: team.id,
                              child: Text(team.name),
                            );
                          }).toList(),
                          onChanged: _teams.isEmpty
                              ? null
                              : (value) =>
                                    setState(() => _visitorTeamId = value),
                        ),
                      ),
                    ],
                  ),
                  if (_localTeamId != null && _visitorTeamId != null) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _servingTeamId ?? _localTeamId,
                      decoration: const InputDecoration(
                        labelText: 'Saque inicial',
                        border: OutlineInputBorder(),
                      ),
                      items: _teams
                          .where(
                            (team) =>
                                team.id == _localTeamId ||
                                team.id == _visitorTeamId,
                          )
                          .map(
                            (team) => DropdownMenuItem(
                              value: team.id,
                              child: Text(team.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _servingTeamId = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _totalSets,
                          decoration: const InputDecoration(
                            labelText: 'Mejor de (Sets)',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 Set')),
                            DropdownMenuItem(value: 3, child: Text('3 Sets')),
                            DropdownMenuItem(value: 5, child: Text('5 Sets')),
                          ],
                          onChanged: (value) => setState(() => _totalSets = value ?? 3),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _pointsPerSet,
                          decoration: const InputDecoration(
                            labelText: 'Puntos por Set',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 15, child: Text('15 pts')),
                            DropdownMenuItem(value: 18, child: Text('18 pts')),
                            DropdownMenuItem(value: 21, child: Text('21 pts')),
                            DropdownMenuItem(value: 25, child: Text('25 pts')),
                          ],
                          onChanged: (value) => setState(() => _pointsPerSet = value ?? 25),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _selectDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      'Fecha: ${_matchDate.day.toString().padLeft(2, '0')}/${_matchDate.month.toString().padLeft(2, '0')}/${_matchDate.year}',
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _startMatch,
                    icon: const Icon(Icons.play_circle_fill),
                    label: const Text(
                      'CREAR PARTIDO',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Partidos guardados',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_matches.isEmpty)
                    const Text('Aún no hay partidos creados.')
                  else
                    ..._matches.map(
                      (match) => Card(
                        child: ListTile(
                          leading: Icon(
                            match.isActive
                                ? Icons.play_circle_fill
                                : Icons.sports_volleyball,
                          ),
                          title: Text(
                            '${match.localTeam.name} vs ${match.visitorTeam.name}',
                          ),
                          subtitle: Text(
                            '${match.tournament} · ${match.date.day.toString().padLeft(2, '0')}/${match.date.month.toString().padLeft(2, '0')}/${match.date.year}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.groups),
                                tooltip: 'Configurar alineaciones',
                                onPressed: () => _configureLineup(match),
                              ),
                              if (match.isActive)
                                const Chip(label: Text('Activo'))
                              else
                                IconButton(
                                  icon: const Icon(Icons.play_arrow),
                                  tooltip: 'Abrir partido',
                                  onPressed: () => _openMatch(match),
                                ),
                              PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'reiniciar') {
                                    bool confirm = await showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Reiniciar partido'),
                                        content: const Text('¿Estás seguro? Se borrarán todas las acciones (puntos, sets, etc) pero se conservarán los equipos.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reiniciar', style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    ) ?? false;

                                    if (confirm) {
                                      await DatabaseHelper.instance.deleteScoutingActionsForMatch(match.id);
                                      final restartedMatch = match.copyWith(
                                        localScore: 0,
                                        visitorScore: 0,
                                        localSets: 0,
                                        visitorSets: 0,
                                        localRotation: 0,
                                        visitorRotation: 0,
                                        isActive: false,
                                      );
                                      await DatabaseHelper.instance.insertMatch(restartedMatch);
                                      _loadData();
                                    }
                                  } else if (value == 'eliminar') {
                                    bool confirm = await showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Eliminar partido'),
                                        content: const Text('¿Estás seguro? Se borrará el partido y todo su historial de forma permanente.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    ) ?? false;

                                    if (confirm) {
                                      await DatabaseHelper.instance.deleteMatch(match.id);
                                      _loadData();
                                    }
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'reiniciar',
                                    child: Row(
                                      children: [
                                        Icon(Icons.restart_alt, color: Colors.orange),
                                        SizedBox(width: 8),
                                        Text('Reiniciar (0-0)'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'eliminar',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Eliminar partido'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ),
      ),
    );
  }
}
