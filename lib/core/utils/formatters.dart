class Formatters {
  static String formatPlayerLabel(String name, String position) {
    final Map<String, String> abbrs = {
      'central': 'CEN',
      'auxiliar': 'AUX',
      'opuesto': 'OPE',
      'armador': 'ARM',
      'líbero': 'LIB',
      'libero': 'LIB',
    };

    final posNorm = position.toLowerCase();
    final abbr = abbrs[posNorm] ?? (position.length >= 3 ? position.substring(0, 3).toUpperCase() : position.toUpperCase());

    String formattedName = name.trim();
    if (formattedName.length > 8) {
      formattedName = formattedName
          .split(' ')
          .where((p) => p.isNotEmpty)
          .map((p) => '${p[0].toUpperCase()}.')
          .join('');
    }

    return '$abbr $formattedName';
  }
}
