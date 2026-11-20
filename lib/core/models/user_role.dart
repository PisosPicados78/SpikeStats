enum UserRole {
  coach,
  analyst;

  String get label {
    switch (this) {
      case UserRole.coach:
        return 'Entrenador';
      case UserRole.analyst:
        return 'Analista';
    }
  }
}
