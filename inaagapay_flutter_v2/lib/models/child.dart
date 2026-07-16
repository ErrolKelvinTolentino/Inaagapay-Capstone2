// lib/models/child.dart

class Child {
  final String id;
  final String name;
  final DateTime birthDate;
  final String gender;
  final DateTime dateAdded;

  Child({
    required this.id,
    required this.name,
    required this.birthDate,
    required this.gender,
    required this.dateAdded,
  });

  int getAgeInWeeks() {
    final now = DateTime.now();
    final difference = now.difference(birthDate);
    return (difference.inDays / 7).floor();
  }
}