
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PhProvince {
  final String code;
  final String name;

  PhProvince({required this.code, required this.name});

  factory PhProvince.fromJson(Map<String, dynamic> json) {
    return PhProvince(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class PhCity {
  final String code;
  final String name;

  PhCity({required this.code, required this.name});

  factory PhCity.fromJson(Map<String, dynamic> json) {
    return PhCity(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class PhBarangay {
  final String code;
  final String name;

  PhBarangay({required this.code, required this.name});

  factory PhBarangay.fromJson(Map<String, dynamic> json) {
    return PhBarangay(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class PhAddressService {
  static const String baseUrl = 'https://psgc.gitlab.io/api';

  // In-memory cache to avoid redundant API hits
  static List<PhProvince> _cachedProvinces = [];
  static final Map<String, List<PhCity>> _cachedCities = {}; // provinceCode -> cities
  static final Map<String, List<PhBarangay>> _cachedBarangays = {}; // cityCode -> barangays

  // 1. Static list of all Philippine provinces for instant & offline-ready load
  static final List<PhProvince> _offlineProvinces = [
    PhProvince(code: '031400000', name: 'Bulacan'),
    PhProvince(code: '034900000', name: 'Pampanga'),
    PhProvince(code: '034900001', name: 'Nueva Ecija'),
    PhProvince(code: '045800000', name: 'Rizal'),
    PhProvince(code: '043400000', name: 'Laguna'),
    PhProvince(code: '042100000', name: 'Cavite'),
    PhProvince(code: '041000000', name: 'Batangas'),
    PhProvince(code: '133900000', name: 'Metro Manila'),
    PhProvince(code: '012800000', name: 'Ilocos Norte'),
    PhProvince(code: '012900000', name: 'Ilocos Sur'),
    PhProvince(code: '013300000', name: 'La Union'),
    PhProvince(code: '015500000', name: 'Pangasinan'),
    PhProvince(code: '020900000', name: 'Batanes'),
    PhProvince(code: '021500000', name: 'Cagayan'),
    PhProvince(code: '023100000', name: 'Isabela'),
    PhProvince(code: '025700000', name: 'Nueva Vizcaya'),
    PhProvince(code: '026900000', name: 'Quirino'),
    PhProvince(code: '030800000', name: 'Bataan'),
    PhProvince(code: '037700000', name: 'Tarlac'),
    PhProvince(code: '039500000', name: 'Zambales'),
    PhProvince(code: '030200000', name: 'Aurora'),
    PhProvince(code: '045600000', name: 'Quezon'),
    PhProvince(code: '174000000', name: 'Marinduque'),
    PhProvince(code: '175100000', name: 'Occidental Mindoro'),
    PhProvince(code: '175200000', name: 'Oriental Mindoro'),
    PhProvince(code: '175900000', name: 'Romblon'),
    PhProvince(code: '175300000', name: 'Palawan'),
    PhProvince(code: '051600000', name: 'Camarines Norte'),
    PhProvince(code: '051700000', name: 'Camarines Sur'),
    PhProvince(code: '052000000', name: 'Catanduanes'),
    PhProvince(code: '056200000', name: 'Sorsogon'),
    PhProvince(code: '054100000', name: 'Masbate'),
    PhProvince(code: '050500000', name: 'Albay'),
    PhProvince(code: '060400000', name: 'Aklan'),
    PhProvince(code: '060600000', name: 'Antique'),
    PhProvince(code: '061900000', name: 'Capiz'),
    PhProvince(code: '063000000', name: 'Iloilo'),
    PhProvince(code: '067900000', name: 'Guimaras'),
    PhProvince(code: '064500000', name: 'Negros Occidental'),
    PhProvince(code: '071200000', name: 'Bohol'),
    PhProvince(code: '072200000', name: 'Cebu'),
    PhProvince(code: '074600000', name: 'Negros Oriental'),
    PhProvince(code: '076100000', name: 'Siquijor'),
    PhProvince(code: '082600000', name: 'Eastern Samar'),
    PhProvince(code: '083700000', name: 'Leyte'),
    PhProvince(code: '084800000', name: 'Northern Samar'),
    PhProvince(code: '086000000', name: 'Samar'),
    PhProvince(code: '086400000', name: 'Southern Leyte'),
    PhProvince(code: '087800000', name: 'Biliran'),
    PhProvince(code: '097200000', name: 'Zamboanga del Norte'),
    PhProvince(code: '097300000', name: 'Zamboanga del Sur'),
    PhProvince(code: '098300000', name: 'Zamboanga Sibugay'),
    PhProvince(code: '101300000', name: 'Bukidnon'),
    PhProvince(code: '101800000', name: 'Camiguin'),
    PhProvince(code: '103500000', name: 'Lanao del Norte'),
    PhProvince(code: '104200000', name: 'Misamis Occidental'),
    PhProvince(code: '104300000', name: 'Misamis Oriental'),
    PhProvince(code: '112300000', name: 'Davao del Norte'),
    PhProvince(code: '112400000', name: 'Davao del Sur'),
    PhProvince(code: '112500000', name: 'Davao Oriental'),
    PhProvince(code: '118200000', name: 'Davao de Oro'),
    PhProvince(code: '118600000', name: 'Davao Occidental'),
    PhProvince(code: '124700000', name: 'Cotabato'),
    PhProvince(code: '126300000', name: 'South Cotabato'),
    PhProvince(code: '126500000', name: 'Sultan Kudarat'),
    PhProvince(code: '128000000', name: 'Sarangani'),
    PhProvince(code: '160200000', name: 'Agusan del Norte'),
    PhProvince(code: '160300000', name: 'Agusan del Sur'),
    PhProvince(code: '166700000', name: 'Surigao del Norte'),
    PhProvince(code: '166800000', name: 'Surigao del Sur'),
    PhProvince(code: '168500000', name: 'Dinagat Islands'),
    PhProvince(code: '140100000', name: 'Abra'),
    PhProvince(code: '141100000', name: 'Benguet'),
    PhProvince(code: '143200000', name: 'Ifugao'),
    PhProvince(code: '144200000', name: 'Kalinga'),
    PhProvince(code: '144400000', name: 'Mountain Province'),
    PhProvince(code: '148100000', name: 'Apayao'),
    PhProvince(code: '190700000', name: 'Basilan'),
    PhProvince(code: '193600000', name: 'Lanao del Sur'),
    PhProvince(code: '196600000', name: 'Sulu'),
    PhProvince(code: '198100000', name: 'Tawi-Tawi'),
  ];

  // 2. Static list of cities for Bulacan
  static final List<PhCity> _offlineBulacanCities = [
    PhCity(code: '031401000', name: 'Baliwag'),
    PhCity(code: '031402000', name: 'Bocaue'),
    PhCity(code: '031403000', name: 'Bustos'),
    PhCity(code: '031404000', name: 'Calumpit'),
    PhCity(code: '031405000', name: 'Doña Remedios Trinidad'),
    PhCity(code: '031406000', name: 'Guiguinto'),
    PhCity(code: '031407000', name: 'Hagonoy'),
    PhCity(code: '031408000', name: 'Malolos'),
    PhCity(code: '031409000', name: 'Marilao'),
    PhCity(code: '031410000', name: 'Meycauayan'),
    PhCity(code: '031411000', name: 'Norzagaray'),
    PhCity(code: '031412000', name: 'Obando'),
    PhCity(code: '031413000', name: 'Pandi'),
    PhCity(code: '031414000', name: 'Paombong'),
    PhCity(code: '031415000', name: 'Plaridel'),
    PhCity(code: '031416000', name: 'Pulilan'),
    PhCity(code: '031417000', name: 'San Ildefonso'),
    PhCity(code: '031418000', name: 'San Jose del Monte'),
    PhCity(code: '031419000', name: 'San Miguel'),
    PhCity(code: '031420000', name: 'San Rafael'),
    PhCity(code: '031421000', name: 'Santa Maria'),
  ];

  // 3. Static list of barangays for Baliwag, Bulacan
  static final List<PhBarangay> _offlineBaliwagBarangays = [
    PhBarangay(code: '031401001', name: 'Bagong Nayon'),
    PhBarangay(code: '031401002', name: 'Barangay I'),
    PhBarangay(code: '031401003', name: 'Barangay II'),
    PhBarangay(code: '031401004', name: 'Calantipay'),
    PhBarangay(code: '031401005', name: 'Catulinan'),
    PhBarangay(code: '031401006', name: 'Concepcion'),
    PhBarangay(code: '031401007', name: 'Hinukay'),
    PhBarangay(code: '031401008', name: 'Makinabang'),
    PhBarangay(code: '031401009', name: 'Matangtubig'),
    PhBarangay(code: '031401010', name: 'Pagala'),
    PhBarangay(code: '031401011', name: 'Paitan'),
    PhBarangay(code: '031401012', name: 'Pinagbarilan'),
    PhBarangay(code: '031401013', name: 'Poblacion'),
    PhBarangay(code: '031401014', name: 'Sabang'),
    PhBarangay(code: '031401015', name: 'San Jose'),
    PhBarangay(code: '031401016', name: 'San Roque'),
    PhBarangay(code: '031401017', name: 'Santa Barbara'),
    PhBarangay(code: '031401018', name: 'Santo Cristo'),
    PhBarangay(code: '031401019', name: 'Santo Niño'),
    PhBarangay(code: '031401020', name: 'Subic'),
    PhBarangay(code: '031401021', name: 'Sulivan'),
    PhBarangay(code: '031401022', name: 'Tangos'),
    PhBarangay(code: '031401023', name: 'Tarcan'),
    PhBarangay(code: '031401024', name: 'Tibag'),
    PhBarangay(code: '031401025', name: 'Tiaong'),
  ];

  // Predefined streets for Baliwag BHC Barangays
  static const Map<String, List<String>> bhcBarangayStreets = {
    'Sta Barbara': [
      'Sta. Barbara Street',
      'M. Ponce Street',
      'Dr. B.V. Aldaba Street',
      'Calle Rizal',
      'Peralta Lane',
    ],
    'Santa Barbara': [
      'Sta. Barbara Street',
      'M. Ponce Street',
      'Dr. B.V. Aldaba Street',
      'Calle Rizal',
      'Peralta Lane',
    ],
    'Tarcan': [
      'Tarcan Road',
      'Doña Remedios Trinidad Highway (DRT)',
      'Tarcan Subdivision Street',
      'Dahlia Lane',
    ],
    'San Jose': [
      'San Jose Street',
      'J.P. Rizal Street',
      'F. Vergel de Dios Street',
      'P. Damaso Street',
      'Kapitbahayan Compound',
    ],
    'Tiaong': [
      'Tiaong Road',
      'Tiaong-Tarcan Road',
      'Purok 1 Road',
      'Purok 2 Road',
      'Purok 3 Street',
    ],
    'Pinagbarilan': [
      'Pinagbarilan Road',
      'Purok 4 Bypass',
      'Pinagbarilan Elementary Road',
      'Bypass Highway Access',
    ],
  };

  // Fetch all provinces
  static Future<List<PhProvince>> getProvinces() async {
    if (_cachedProvinces.isNotEmpty) return _cachedProvinces;

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/provinces'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final list = data.map((json) => PhProvince.fromJson(json)).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        // Make sure Bulacan is at the top or in the list
        _cachedProvinces = list;
        return _cachedProvinces;
      }
    } catch (e) {
      debugPrint('Error fetching provinces from API: $e. Using offline fallback.');
    }

    // Return sorted offline provinces if API fails
    final list = List<PhProvince>.from(_offlineProvinces);
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // Fetch cities/municipalities for a province
  static Future<List<PhCity>> getCities(String provinceCodeOrName) async {
    // Resolve code if the input is a name
    String code = provinceCodeOrName;
    if (!RegExp(r'^\d+$').hasMatch(provinceCodeOrName)) {
      final match = _offlineProvinces.firstWhere(
        (p) => p.name.toLowerCase() == provinceCodeOrName.toLowerCase(),
        orElse: () => PhProvince(code: '', name: ''),
      );
      if (match.code.isNotEmpty) {
        code = match.code;
      } else {
        // Find in cached provinces
        final matchCached = _cachedProvinces.firstWhere(
          (p) => p.name.toLowerCase() == provinceCodeOrName.toLowerCase(),
          orElse: () => PhProvince(code: '', name: ''),
        );
        code = matchCached.code;
      }
    }

    if (code.isEmpty) {
      if (provinceCodeOrName.toLowerCase() == 'bulacan') {
        return _offlineBulacanCities;
      }
      return [];
    }

    if (_cachedCities.containsKey(code)) return _cachedCities[code]!;

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/provinces/$code/cities-municipalities'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final list = data.map((json) => PhCity.fromJson(json)).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _cachedCities[code] = list;
        return list;
      }
    } catch (e) {
      debugPrint('Error fetching cities for $code: $e');
    }

    // Offline fallbacks
    if (code == '031400000' || provinceCodeOrName.toLowerCase() == 'bulacan') {
      return _offlineBulacanCities;
    }

    return [];
  }

  // Fetch barangays for a city/municipality
  static Future<List<PhBarangay>> getBarangays(String cityCodeOrName) async {
    String code = cityCodeOrName;
    if (!RegExp(r'^\d+$').hasMatch(cityCodeOrName)) {
      final match = _offlineBulacanCities.firstWhere(
        (c) => c.name.toLowerCase() == cityCodeOrName.toLowerCase(),
        orElse: () => PhCity(code: '', name: ''),
      );
      if (match.code.isNotEmpty) {
        code = match.code;
      } else {
        // Try searching in all cached cities
        for (final list in _cachedCities.values) {
          final found = list.firstWhere(
            (c) => c.name.toLowerCase() == cityCodeOrName.toLowerCase(),
            orElse: () => PhCity(code: '', name: ''),
          );
          if (found.code.isNotEmpty) {
            code = found.code;
            break;
          }
        }
      }
    }

    if (code.isEmpty) {
      if (cityCodeOrName.toLowerCase() == 'baliwag') {
        return _offlineBaliwagBarangays;
      }
      return [];
    }

    if (_cachedBarangays.containsKey(code)) return _cachedBarangays[code]!;

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/cities-municipalities/$code/barangays'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final list = data.map((json) => PhBarangay.fromJson(json)).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _cachedBarangays[code] = list;
        return list;
      }
    } catch (e) {
      debugPrint('Error fetching barangays for $code: $e');
    }

    if (code == '031401000' || cityCodeOrName.toLowerCase() == 'baliwag') {
      return _offlineBaliwagBarangays;
    }

    return [];
  }

  // Get fallback streets for a barangay
  static List<String> getStreetsForBarangay(String barangayName) {
    // Normalise name (e.g. 'Sta Barbara' or 'Santa Barbara')
    for (final key in bhcBarangayStreets.keys) {
      if (key.toLowerCase() == barangayName.toLowerCase()) {
        return bhcBarangayStreets[key]!;
      }
      // Handle variations like "Barangay Sta. Barbara"
      if (barangayName.toLowerCase().contains(key.toLowerCase())) {
        return bhcBarangayStreets[key]!;
      }
    }
    return [];
  }
}