import 'package:flutter/material.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/models/match.dart';
import '../../../../core/models/player.dart';
import '../../../../core/models/team.dart';
import '../../../../core/utils/formatters.dart';

class LineupSelectionPage extends StatefulWidget {
  const LineupSelectionPage({super.key, required this.match, this.isNewSet = false});

  final Match match;
  final bool isNewSet;

  @override
  State<LineupSelectionPage> createState() => _LineupSelectionPageState();
}

class _LineupSelectionPageState extends State<LineupSelectionPage> {
  Map<String, List<Player?>> _savedLineups = {};
  bool _isLoading = true;
  late bool _localHasLibero;
  late bool _visitorHasLibero;
  late String _servingTeamId;

  @override
  void initState() {
    super.initState();
    _localHasLibero = widget.match.localHasLibero;
    _visitorHasLibero = widget.match.visitorHasLibero;
    _servingTeamId = widget.match.servingTeamId.isNotEmpty
        ? widget.match.servingTeamId
        : widget.match.localTeam.id;
    _loadLineups();
  }

  Future<void> _loadLineups() async {
    final lineups = await DatabaseHelper.instance.getMatchLineups(
      widget.match.id,
    );
    if (!mounted) return;
    setState(() {
      _savedLineups = {
        for (final entry in lineups.entries)
          entry.key: [
            ...entry.value,
            ...List<Player?>.filled(6 - entry.value.length, null),
          ],
      };
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final teams = [widget.match.localTeam, widget.match.visitorTeam];
    for (final team in teams) {
      final lineup = _savedLineups[team.id] ?? List<Player?>.filled(6, null);
      if (lineup.any((player) => player == null) ||
          lineup
                  .whereType<Player>()
                  .map((player) => player.id)
                  .toSet()
                  .length !=
              6) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${team.name} debe tener 6 titulares diferentes.'),
          ),
        );
        return;
      }
    }
    for (final team in teams) {
      await DatabaseHelper.instance.saveMatchLineup(
        widget.match.id,
        team.id,
        _savedLineups[team.id]!
            .whereType<Player>()
            .map((player) => player.id)
            .toList(),
      );
    }
    
    final updatedMatch = widget.match.copyWith(
      localHasLibero: _localHasLibero,
      visitorHasLibero: _visitorHasLibero,
      servingTeamId: _servingTeamId,
      localScore: widget.isNewSet ? 0 : widget.match.localScore,
      visitorScore: widget.isNewSet ? 0 : widget.match.visitorScore,
      localRotation: widget.isNewSet ? 0 : widget.match.localRotation,
      visitorRotation: widget.isNewSet ? 0 : widget.match.visitorRotation,
    );
    await DatabaseHelper.instance.updateMatchState(updatedMatch);

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final titleText = widget.isNewSet
        ? 'Alineación Set ${widget.match.localSets + widget.match.visitorSets + 1}'
        : 'Alineaciones titulares';

    return Scaffold(
      appBar: AppBar(title: Text(titleText)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.isNewSet
                      ? 'Revisa y ajusta la alineación inicial y el saque para el siguiente set.'
                      : 'Selecciona los 6 jugadores que estarán en cancha por equipo.',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 16),
                Card(
                  color: isDark ? theme.colorScheme.surface : theme.colorScheme.primaryContainer,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<String>(
                      value: _servingTeamId,
                      decoration: const InputDecoration(
                        labelText: 'Primer saque del set',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.sports_volleyball),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: widget.match.localTeam.id,
                          child: Text('Local: ${widget.match.localTeam.name}'),
                        ),
                        DropdownMenuItem(
                          value: widget.match.visitorTeam.id,
                          child: Text('Visitante: ${widget.match.visitorTeam.name}'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _servingTeamId = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _teamLineup(widget.match.localTeam, isDark, _localHasLibero, (v) => setState(() => _localHasLibero = v)),
                const SizedBox(height: 16),
                _teamLineup(widget.match.visitorTeam, isDark, _visitorHasLibero, (v) => setState(() => _visitorHasLibero = v)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: Icon(widget.isNewSet ? Icons.play_circle_fill : Icons.save),
                  label: Text(
                    widget.isNewSet ? 'CONFIRMAR E INICIAR SET' : 'GUARDAR ALINEACIONES',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
    );
  }

  void _showPlayerSelection(Team team, int index, List<Player?> players, Set<String> selectedIds, bool hasLibero) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 16.0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Selecciona jugador para posición',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: team.players.where((p) {
                    if (hasLibero && (p.position.toLowerCase() == 'líbero' || p.position.toLowerCase() == 'libero')) {
                      return false;
                    }
                    return true;
                  }).map((player) {
                    final isSelected = players[index]?.id == player.id;
                    final isAlreadyInLineup = selectedIds.contains(player.id) && !isSelected;

                    return ChoiceChip(
                      label: Text(Formatters.formatPlayerLabel(player.name, player.position)),
                      selected: isSelected,
                      onSelected: isAlreadyInLineup
                          ? null
                          : (selected) {
                              if (selected) {
                                setState(() {
                                  final updated = List<Player?>.from(players);
                                  updated[index] = player;
                                  _savedLineups[team.id] = updated;
                                });
                                Navigator.pop(context);
                              }
                            },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _teamLineup(Team team, bool isDark, bool hasLibero, ValueChanged<bool> onChangedLibero) {
    final players = _savedLineups[team.id] ?? List<Player?>.filled(6, null);
    final selectedIds = players
        .whereType<Player>()
        .map((player) => player.id)
        .toSet();

    Widget positionButton(int index, String posName) {
      final player = players[index];
      final theme = Theme.of(context);
      return Expanded(
        child: InkWell(
          onTap: () => _showPlayerSelection(team, index, players, selectedIds, hasLibero),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
              border: Border.all(
                color: player != null ? theme.colorScheme.primary : theme.colorScheme.outline,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pos $posName',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  player != null ? Formatters.formatPlayerLabel(player.name, player.position) : 'Seleccionar',
                  style: TextStyle(
                    fontSize: 11,
                    color: player != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                    fontWeight: player != null ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Card(
      color: isDark ? theme.colorScheme.surface : theme.colorScheme.primaryContainer,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    team.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? theme.colorScheme.onSurface : theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Juega con Líbero',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Switch(
                      value: hasLibero,
                      onChanged: onChangedLibero,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'RED',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
              ),
            ),
            Divider(
              color: isDark ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onPrimaryContainer.withOpacity(0.5),
              thickness: 2,
            ),
            Row(
              children: [
                positionButton(3, '4'),
                positionButton(2, '3'),
                positionButton(1, '2'),
              ],
            ),
            Row(
              children: [
                positionButton(4, '5'),
                positionButton(5, '6'),
                positionButton(0, '1'),
              ],
            ),
            const SizedBox(height: 8),
            if (team.players.length < 6)
              Text(
                'Este equipo necesita al menos 6 jugadores.',
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }
}
