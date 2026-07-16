// lib/services/location_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class LocationService {
  static const String _baseUrl = 'https://psgc.gitlab.io/api';
  
  // Fetch all provinces
  static Future<List<Map<String, dynamic>>> fetchProvinces() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/provinces/'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((province) => {
          'code': province['code'],
          'name': province['name'],
          'region_code': province['region_code'],
        }).toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching provinces: $e');
      return [];
    }
  }
  
  // Fetch cities/municipalities by province code
  static Future<List<Map<String, dynamic>>> fetchCitiesMunicipalities(String provinceCode) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/provinces/$provinceCode/cities-municipalities/'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((city) => {
          'code': city['code'],
          'name': city['name'],
        }).toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching cities: $e');
      return [];
    }
  }
  
  // Fetch barangays by city/municipality code
  static Future<List<Map<String, dynamic>>> fetchBarangays(String cityCode) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/cities-municipalities/$cityCode/barangays/'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((barangay) => {
          'code': barangay['code'],
          'name': barangay['name'],
        }).toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('Error fetching barangays: $e');
      return [];
    }
  }
}