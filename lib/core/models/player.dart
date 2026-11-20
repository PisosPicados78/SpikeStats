class Player {
  final String id;
  final String name;
  final int number;
  final String position;

  Player({
    required this.id,
    required this.name,
    required this.number,
    required this.position,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'number': number,
      'position': position,
    };
  }

  factory Player.fromMap(Map<String, dynamic> map) {
    final rawNumber = map['number'];
    int parsedNumber = 0;
    if (rawNumber is int) {
      parsedNumber = rawNumber;
    } else if (rawNumber is num) {
      parsedNumber = rawNumber.toInt();
    } else if (rawNumber is String) {
      parsedNumber = int.tryParse(rawNumber) ?? 0;
    }

    return Player(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      number: parsedNumber,
      position: map['position']?.toString() ?? '',
    );
  }
}
