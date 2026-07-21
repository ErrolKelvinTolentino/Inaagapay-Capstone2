import 'dart:typed_data';

class BabyMemory {
  final String id;
  final String title;
  final String caption;
  final DateTime date;
  final Uint8List? imageBytes;
  final String? assetPath;

  const BabyMemory({
    required this.id,
    required this.title,
    required this.caption,
    required this.date,
    this.imageBytes,
    this.assetPath,
  }) : assert(imageBytes != null || assetPath != null);

  String get shortDate {
    const months = <String>[
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String get fullDate {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
