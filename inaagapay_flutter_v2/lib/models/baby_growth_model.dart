// lib/models/baby_growth_model.dart

class BabyGrowth {
  final String size; // length (cm)
  final String weight; // weight (g / kg)

  const BabyGrowth({
    required this.size,
    required this.weight,
  });
}

/// Ideal / typical baby size & weight per week
/// Source: aggregated medical references (ACOG, BabyCenter-style averages)
class BabyGrowthData {
  static const Map<int, BabyGrowth> byWeek = {
    // Week 1-3 - Very early development
    1: BabyGrowth(size: '0.01 cm', weight: '< 1 g'),
    2: BabyGrowth(size: '0.05 cm', weight: '< 1 g'),
    3: BabyGrowth(size: '0.10 cm', weight: '< 1 g'),
    
    // Week 4-13 - First Trimester
    4: BabyGrowth(size: '0.1 cm', weight: '< 1 g'),
    5: BabyGrowth(size: '0.2 cm', weight: '< 1 g'),
    6: BabyGrowth(size: '0.4 cm', weight: '< 1 g'),
    7: BabyGrowth(size: '1.0 cm', weight: '< 1 g'),
    8: BabyGrowth(size: '1.6 cm', weight: '1 g'),
    9: BabyGrowth(size: '2.3 cm', weight: '2 g'),
    10: BabyGrowth(size: '3.1 cm', weight: '4 g'),
    11: BabyGrowth(size: '4.1 cm', weight: '7 g'),
    12: BabyGrowth(size: '5.4 cm', weight: '14 g'),
    13: BabyGrowth(size: '7.4 cm', weight: '23 g'),
    
    // Week 14-27 - Second Trimester
    14: BabyGrowth(size: '8.7 cm', weight: '43 g'),
    15: BabyGrowth(size: '10.1 cm', weight: '70 g'),
    16: BabyGrowth(size: '11.6 cm', weight: '100 g'),
    17: BabyGrowth(size: '13.0 cm', weight: '140 g'),
    18: BabyGrowth(size: '14.2 cm', weight: '190 g'),
    19: BabyGrowth(size: '15.3 cm', weight: '240 g'),
    20: BabyGrowth(size: '16.4 cm', weight: '300 g'),
    21: BabyGrowth(size: '26.7 cm', weight: '360 g'),
    22: BabyGrowth(size: '27.8 cm', weight: '430 g'),
    23: BabyGrowth(size: '28.9 cm', weight: '500 g'),
    24: BabyGrowth(size: '30.0 cm', weight: '600 g'),
    25: BabyGrowth(size: '34.6 cm', weight: '660 g'),
    26: BabyGrowth(size: '35.6 cm', weight: '760 g'),
    27: BabyGrowth(size: '36.6 cm', weight: '875 g'),
    
    // Week 28-40 - Third Trimester
    28: BabyGrowth(size: '37.6 cm', weight: '1.0 kg'),
    29: BabyGrowth(size: '38.6 cm', weight: '1.2 kg'),
    30: BabyGrowth(size: '39.9 cm', weight: '1.3 kg'),
    31: BabyGrowth(size: '41.1 cm', weight: '1.5 kg'),
    32: BabyGrowth(size: '42.4 cm', weight: '1.7 kg'),
    33: BabyGrowth(size: '43.7 cm', weight: '1.9 kg'),
    34: BabyGrowth(size: '45.0 cm', weight: '2.1 kg'),
    35: BabyGrowth(size: '46.2 cm', weight: '2.4 kg'),
    36: BabyGrowth(size: '47.4 cm', weight: '2.6 kg'),
    37: BabyGrowth(size: '48.6 cm', weight: '2.9 kg'),
    38: BabyGrowth(size: '49.8 cm', weight: '3.1 kg'),
    39: BabyGrowth(size: '50.7 cm', weight: '3.3 kg'),
    40: BabyGrowth(size: '51.2 cm', weight: '3.4 kg'),
  };

  static BabyGrowth getForWeek(int week) {
    // Clamp week between 1 and 40
    final clampedWeek = week.clamp(1, 40);
    return byWeek[clampedWeek] ?? const BabyGrowth(size: '—', weight: '—');
  }
}