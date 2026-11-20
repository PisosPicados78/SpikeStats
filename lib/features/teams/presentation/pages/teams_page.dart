import 'package:flutter/material.dart';

import '../../../../core/models/team.dart';
import '../../../../core/models/player.dart';
import '../../../../core/database/database_helper.dart';

class TeamsPage extends StatefulWidget {
  const TeamsPage({super.key});

  @override
  State<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends State<TeamsPage> {
  List<Team> _teams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  Future<void> _loadTeams() async {
    setState(() => _isLoading = true);
    final teams = await DatabaseHelper.instance.getTeams();
    setState(() {
      _teams = teams;
      _isLoading = false;
    });
  }

  void _showTeamDialog({Team? team}) {
    final nameController = TextEditingController(text: team?.name ?? '');
    final coachController = TextEditingController(text: team?.coach ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(team == null ? 'Registrar Equipo' : 'Editar Equipo'),
          content: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nombre del equipo'),
                  ),
                  TextField(
                    controller: coachController,
                    decoration: const InputDecoration(labelText: 'Entrenador'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  if (team == null) {
                    final newTeam = Team(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text,
                      coach: coachController.text,
                    );
                    await DatabaseHelper.instance.insertTeam(newTeam);
                  } else {
                    final updatedTeam = Team(
                      id: team.id,
                      name: nameController.text,
                      coach: coachController.text,
                      players: team.players,
                    );
                    await DatabaseHelper.instance.updateTeam(updatedTeam);
                  }
                  if (context.mounted) Navigator.pop(context);
                  _loadTeams();
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteTeam(Team team) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Equipo'),
        content: Text('¿Seguro que deseas eliminar el equipo "${team.name}" y todos sus jugadores?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.deleteTeam(team.id);
              if (context.mounted) Navigator.pop(context);
              _loadTeams();
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showPlayerDialog(String teamId, {Player? player}) {
    final nameController = TextEditingController(text: player?.name ?? '');
    final numberController = TextEditingController(text: player?.number.toString() ?? '');
    String? selectedPosition = player?.position;
    final positions = ['Central', 'Auxiliar', 'Opuesto', 'Armador', 'Libero'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(player == null ? 'Registrar Jugador' : 'Editar Jugador'),
              content: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                      ),
                      TextField(
                        controller: numberController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Número'),
                      ),
                      const SizedBox(height: 16),
                      const Text('Posición:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: positions.map((pos) {
                          return ChoiceChip(
                            label: Text(pos),
                            selected: selectedPosition == pos,
                            onSelected: (selected) {
                              if (selected) {
                                setStateDialog(() => selectedPosition = pos);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isNotEmpty &&
                        numberController.text.isNotEmpty &&
                        selectedPosition != null) {
                      if (player == null) {
                        final newPlayer = Player(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          name: nameController.text,
                          number: int.parse(numberController.text),
                          position: selectedPosition!,
                        );
                        await DatabaseHelper.instance.insertPlayer(newPlayer, teamId);
                      } else {
                        final updatedPlayer = Player(
                          id: player.id,
                          name: nameController.text,
                          number: int.parse(numberController.text),
                          position: selectedPosition!,
                        );
                        await DatabaseHelper.instance.updatePlayer(updatedPlayer);
                      }
                      if (context.mounted) Navigator.pop(context);
                      _loadTeams();
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeletePlayer(Player player) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Jugador'),
        content: Text('¿Seguro que deseas eliminar al jugador "${player.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.deletePlayer(player.id);
              if (context.mounted) Navigator.pop(context);
              _loadTeams();
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Equipos y Jugadores')),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A), Color(0xFF020617)],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _teams.isEmpty
            ? const Center(
                child: Text(
                  'No hay equipos registrados. Presiona + para añadir.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _teams.length,
                itemBuilder: (context, index) {
                  final team = _teams[index];
                  return Card(
                    color: Colors.white.withOpacity(0.1),
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),
                    ),
                    child: ExpansionTile(
                      iconColor: Colors.white,
                      collapsedIconColor: Colors.white70,
                      leading: const CircleAvatar(child: Icon(Icons.shield)),
                      title: Row(
                        children: [
                          Expanded(child: Text(team.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                          IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.white70), onPressed: () => _showTeamDialog(team: team)),
                          IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent), onPressed: () => _confirmDeleteTeam(team)),
                        ],
                      ),
                      subtitle: Text(
                        'Entrenador: ${team.coach} | Jugadores: ${team.players.length}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      children: [
                        ...team.players.map(
                          (player) => ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.secondary,
                              child: Text(
                                player.number.toString(),
                                style: TextStyle(color: Theme.of(context).colorScheme.onSecondary),
                              ),
                            ),
                            title: Text(player.name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(player.position, style: const TextStyle(color: Colors.white70)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.white70), onPressed: () => _showPlayerDialog(team.id, player: player)),
                                IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent), onPressed: () => _confirmDeletePlayer(player)),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextButton.icon(
                            onPressed: () => _showPlayerDialog(team.id),
                            icon: const Icon(Icons.person_add, color: Colors.lightBlueAccent),
                            label: const Text('Añadir Jugador', style: TextStyle(color: Colors.lightBlueAccent)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTeamDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
