// lib/widgets/comparison_card.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/language_service.dart';

class ComparisonCard extends StatelessWidget {
  final int week;

  const ComparisonCard({
    super.key,
    required this.week,
  });

  // Data source with image names
  static const Map<int, Map<String, String>> _comparisonData = {
    4: {'label': 'Baby is as small as', 'name': 'A Poppy Seed', 'image': 'poppy.png'},
    5: {'label': 'Baby is about as big as', 'name': 'A Sesame Seed', 'image': 'sesame.png'},
    6: {'label': 'Baby is about as big as', 'name': 'A Green Pea', 'image': 'pea.png'},
    7: {'label': 'Baby is about as big as', 'name': 'A Coffee Bean', 'image': 'coffee.png'},
    8: {'label': 'Baby is now as big as', 'name': 'A Blueberry', 'image': 'blueberry.png'},
    9: {'label': 'Baby is now as big as', 'name': 'A Raspberry', 'image': 'raspberry.png'},
    10: {'label': 'Baby is now as big as', 'name': 'A Cherry', 'image': 'cherry.png'},
    11: {'label': 'Baby is now as big as', 'name': 'A Strawberry', 'image': 'strawberry.png'},
    12: {'label': 'Baby is about as big as', 'name': 'A Lime', 'image': 'lime.png'},
    13: {'label': 'Baby is about as big as', 'name': 'A Plum', 'image': 'plum.png'},
    14: {'label': 'Baby is about as big as', 'name': 'A Lemon', 'image': 'lemon.png'},
    15: {'label': 'Baby is about as big as', 'name': 'A Peach', 'image': 'peach.png'},
    16: {'label': 'Baby is about as big as', 'name': 'An Apple', 'image': 'apple.png'},
    17: {'label': 'Baby is about as big as', 'name': 'An Avocado', 'image': 'avocado.png'},
    18: {'label': 'Baby is about as big as', 'name': 'A Large White Onion', 'image': 'onion.png'},
    19: {'label': 'Baby is about as big as', 'name': 'A Beetroot', 'image': 'beetroot.png'},
    20: {'label': 'Baby is about as big as', 'name': 'A Sweet Potato', 'image': 'sweet potato.png'},
    21: {'label': 'Baby is about as big as', 'name': 'A Taro (Gabi)', 'image': 'taro.png'},
    22: {'label': 'Baby is about as big as', 'name': 'A Carrot', 'image': 'carrot.png'},
    23: {'label': 'Baby is about as big as', 'name': 'A Banana', 'image': 'banana.png'},
    24: {'label': 'Baby is about as big as', 'name': 'An Ear of Corn', 'image': 'corn.png'},
    25: {'label': 'Baby is about as big as', 'name': 'A Cucumber', 'image': 'cucumber.png'},
    26: {'label': 'Baby is about as big as', 'name': 'An Eggplant', 'image': 'eggplant.png'},
    27: {'label': 'Baby is about as big as', 'name': 'A Lettuce Leaf', 'image': 'lettuce.png'},
    28: {'label': 'Baby is about as big as', 'name': 'A Cauliflower', 'image': 'cauliflower.png'},
    29: {'label': 'Baby is about as big as', 'name': 'A Cabbage', 'image': 'cabbage.png'},
    30: {'label': 'Baby is about as big as', 'name': 'A Coconut', 'image': 'coconut.png'},
    31: {'label': 'Baby is about as big as', 'name': 'A Pomelo', 'image': 'pomelo.png'},
    32: {'label': 'Baby is about as big as', 'name': 'A Pineapple', 'image': 'pineapple.png'},
    33: {'label': 'Baby is about as big as', 'name': 'A Melon', 'image': 'melon.png'},
    34: {'label': 'Baby is about as big as', 'name': 'A Papaya', 'image': 'papaya.png'},
    35: {'label': 'Baby is about as big as', 'name': 'A Kabocha Squash', 'image': 'kabocha.png'},
    36: {'label': 'Baby is about as big as', 'name': 'A Durian', 'image': 'durian.png'},
    37: {'label': 'Baby is about as big as', 'name': 'A Pumpkin', 'image': 'pumpkin.png'},
    38: {'label': 'Baby is about as big as', 'name': 'A Watermelon', 'image': 'watermelon.png'},
    39: {'label': 'Baby is about as big as', 'name': 'A Watermelon', 'image': 'watermelon.png'},
    40: {'label': 'Baby is about as big as', 'name': 'A Watermelon', 'image': 'watermelon.png'},
  };

  String _getAssetPath(String imageName) {
    return 'assets/images/$imageName';
  }

  String _localizedLabel(String label) {
    switch (label) {
      case 'Baby will soon be as small as':
        return LanguageService.translate(
            label, 'Malapit nang maging kasing liit ng');
      case 'Baby is as small as':
        return LanguageService.translate(label, 'Ang sanggol ay kasing liit ng');
      case 'Baby is about as big as':
        return LanguageService.translate(
            label, 'Ang sanggol ay halos kasing laki ng');
      case 'Baby is now as big as':
        return LanguageService.translate(
            label, 'Ang sanggol ay kasing laki na ng');
      default:
        return label;
    }
  }

  String _localizedName(String name) {
    const filipinoNames = {
      'A Poppy Seed': 'Buto ng Poppy',
      'A Sesame Seed': 'Linga',
      'A Green Pea': 'Berdeng Gisantes',
      'A Coffee Bean': 'Butil ng Kape',
      'A Blueberry': 'Blueberry',
      'A Raspberry': 'Raspberry',
      'A Cherry': 'Cherry',
      'A Strawberry': 'Strawberry',
      'A Lime': 'Dayap',
      'A Plum': 'Plum',
      'A Lemon': 'Lemon',
      'A Peach': 'Peach',
      'An Apple': 'Mansanas',
      'An Avocado': 'Abukado',
      'A Large White Onion': 'Malaking Puting Sibuyas',
      'A Beetroot': 'Beetroot',
      'A Sweet Potato': 'Kamote',
      'A Taro (Gabi)': 'Gabi',
      'A Carrot': 'Karot',
      'A Banana': 'Saging',
      'An Ear of Corn': 'Mais',
      'A Cucumber': 'Pipino',
      'An Eggplant': 'Talong',
      'A Lettuce Leaf': 'Litsugas',
      'A Cauliflower': 'Cauliflower',
      'A Cabbage': 'Repolyo',
      'A Coconut': 'Niyog',
      'A Pomelo': 'Suha',
      'A Pineapple': 'Pinya',
      'A Melon': 'Melon',
      'A Papaya': 'Papaya',
      'A Kabocha Squash': 'Kalabasa',
      'A Durian': 'Durian',
      'A Pumpkin': 'Kalabasa',
      'A Watermelon': 'Pakwan',
    };
    return LanguageService.isFilipino ? filipinoNames[name] ?? name : name;
  }

  @override
  Widget build(BuildContext context) {
    final data = _comparisonData[week];
    if (data == null) return const SizedBox.shrink();

    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.bgSecondary.withValues(alpha: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _localizedLabel(data['label']!),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _localizedName(data['name']!),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  _getAssetPath(data['image']!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.food_bank,
                      size: 40,
                      color: AppColors.brandPrimary,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
