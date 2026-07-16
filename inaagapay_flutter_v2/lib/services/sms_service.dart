import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SmsService {
  static String get apiKey => dotenv.env['SEMAPHORE_API_KEY'] ?? '';
  static String get baseUrl => dotenv.env['SEMAPHORE_BASE_URL'] ?? 'https://api.semaphore.co/api/v4';
  static String get senderName => dotenv.env['SEMAPHORE_SENDER_NAME'] ?? 'SEMAPHORE';

  // Send general SMS message
  static Future<bool> sendSmsMessage(String phoneNumber, String message) async {
    try {
      // Validate Philippine phone number
      if (!isValidPhilippineNumber(phoneNumber)) {
        if (kDebugMode) print('Invalid Philippine phone number: $phoneNumber');
        return false;
      }

      // Format to international format
      final formattedNumber = formatPhilippineNumber(phoneNumber);
      
      final response = await http.post(
        Uri.parse('$baseUrl/messages'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'apikey': apiKey,
          'number': formattedNumber,
          'message': message,
          'sendername': senderName,
        },
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('SMS API Response: ${response.statusCode} - ${response.body}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        // Check for success in response
        if (data is List && data.isNotEmpty) {
          final firstMessage = data[0];
          if (firstMessage['status'] == 'Pending' || 
              firstMessage['status'] == 'Sent' ||
              firstMessage['message_id'] != null) {
            return true;
          }
        }
        return false;
      }
      
      return false;
    } catch (e) {
      if (kDebugMode) print('Error sending SMS message: $e');
      return false;
    }
  }

  // Send OTP via SMS
  static Future<bool> sendOtp(String phoneNumber, String code) async {
    try {
      // Validate Philippine phone number
      if (!isValidPhilippineNumber(phoneNumber)) {
        if (kDebugMode) print('Invalid Philippine phone number: $phoneNumber');
        return false;
      }

      // Format to international format
      final formattedNumber = formatPhilippineNumber(phoneNumber);
      
      final message = 'Your INAAGAPAY verification code is: $code\n\nThis code expires in 10 minutes.';
      
      final response = await http.post(
        Uri.parse('$baseUrl/messages'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'apikey': apiKey,
          'number': formattedNumber,
          'message': message,
          'sendername': senderName,  // Your approved sender name
        },
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('SMS API Response: ${response.statusCode} - ${response.body}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        // Check for success in response
        if (data is List && data.isNotEmpty) {
          final firstMessage = data[0];
          if (firstMessage['status'] == 'Pending' || 
              firstMessage['status'] == 'Sent' ||
              firstMessage['message_id'] != null) {
            return true;
          }
        }
        return false;
      }
      
      return false;
    } catch (e) {
      if (kDebugMode) print('Error sending SMS: $e');
      return false;
    }
  }

  // Send OTP using the dedicated OTP endpoint (more reliable for verification codes)
  static Future<bool> sendOtpViaPriority(String phoneNumber, String code) async {
    try {
      if (!isValidPhilippineNumber(phoneNumber)) {
        return false;
      }

      final formattedNumber = formatPhilippineNumber(phoneNumber);
      
      final response = await http.post(
        Uri.parse('$baseUrl/otp'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: {
          'apikey': apiKey,
          'number': formattedNumber,
          'message': 'Your INAAGAPAY verification code is: {otp}. This code expires in 10 minutes.',
          'code': code, // Pass our own OTP code
          'sendername': senderName,
        },
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('SMS OTP API Response: ${response.statusCode} - ${response.body}');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty) {
          return true;
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('Error sending OTP via priority: $e');
      return false;
    }
  }

  // Check SMS credits/balance
  static Future<int?> getCreditBalance() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/account?apikey=$apiKey'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['credit_balance'] as int?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('Error checking SMS balance: $e');
      return null;
    }
  }

  // Get approved sender names
  static Future<List<String>> getSenderNames() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/account/sendernames?apikey=$apiKey'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => item['name'] as String).toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('Error getting sender names: $e');
      return [];
    }
  }

  // Validate Philippine phone number
  static bool isValidPhilippineNumber(String phoneNumber) {
    // Remove all non-digit characters
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Check if it matches Philippine format:
    // 09XXXXXXXXX (11 digits starting with 09)
    // or +639XXXXXXXXX (13 digits)
    // or 639XXXXXXXXX (12 digits)
    final regex = RegExp(r'^(09|\+639|639)\d{9}$');
    return regex.hasMatch(cleaned);
  }

  // Format to standard Philippine international format
  static String formatPhilippineNumber(String phoneNumber) {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (cleaned.startsWith('09')) {
      return '+63${cleaned.substring(1)}';
    } else if (cleaned.startsWith('639')) {
      return '+$cleaned';
    } else if (cleaned.startsWith('63')) {
      return '+$cleaned';
    }
    
    return '+63$cleaned';
  }

  // Format for display (09XXXXXXXXX)
  static String formatDisplayNumber(String phoneNumber) {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (cleaned.startsWith('63')) {
      return '0${cleaned.substring(2)}';
    } else if (cleaned.startsWith('9')) {
      return '0$cleaned';
    }
    
    return cleaned;
  }

  // Send automated immunization confirmation and next checkup/vaccine schedule
  static Future<void> sendAutomatedVaccineSms({
    required int childId,
    required List<String> recordedVaccines,
  }) async {
    try {
      final client = Supabase.instance.client;

      // 1. Fetch child, mother and BHC details in a single query
      final childDetails = await client
          .from('children')
          .select('''
            first_name,
            last_name,
            mother:mother_id (
              mother_id,
              assigned_bhc_id,
              bhc:assigned_bhc_id (bhc_name),
              account:account_id (
                first_name,
                last_name,
                phone_number
              )
            )
          ''')
          .eq('child_id', childId)
          .maybeSingle();

      if (childDetails == null) return;

      final childFirstName = childDetails['first_name']?.toString() ?? 'Child';
      final childLastName = childDetails['last_name']?.toString() ?? '';
      final childName = '$childFirstName $childLastName'.trim();

      final mother = childDetails['mother'] as Map<String, dynamic>?;
      if (mother == null) return;

      final motherAccount = mother['account'] as Map<String, dynamic>?;
      if (motherAccount == null) return;

      final motherFirstName = motherAccount['first_name']?.toString() ?? 'Mother';

      final phone = motherAccount['phone_number']?.toString();
      if (phone == null || phone.isEmpty) return;

      final bhc = mother['bhc'] as Map<String, dynamic>?;
      final bhcName = bhc?['bhc_name']?.toString() ?? 'Barangay Health Center';

      // 2. Fetch birthdate to calculate child age in months
      final birthRes = await client
          .from('birth_details')
          .select('birthdate')
          .eq('child_id', childId)
          .maybeSingle();

      DateTime? birthdate;
      if (birthRes != null && birthRes['birthdate'] != null) {
        birthdate = DateTime.parse(birthRes['birthdate']);
      }

      double ageMonths = 0;
      if (birthdate != null) {
        final diffDays = DateTime.now().difference(birthdate).inDays;
        ageMonths = diffDays / 30.43;
      }

      // 3. Fetch all child vaccines
      final vaccinesRes = await client
          .from('vaccines')
          .select('vaccine_id, vaccine_name, dose_number, recommended_age_months')
          .eq('target_recipients', 'child');

      final List<Map<String, dynamic>> allVaccines = List<Map<String, dynamic>>.from(vaccinesRes);

      // 4. Fetch already taken vaccines (which includes the newly inserted record(s))
      final recordsRes = await client
          .from('immunization_record')
          .select('vaccine_id')
          .eq('child_id', childId);

      final Set<int> completedVaccineIds = List<Map<String, dynamic>>.from(recordsRes)
          .map((r) => r['vaccine_id'] as int)
          .toSet();

      // 5. Calculate due/overdue vaccines
      final List<Map<String, dynamic>> dueVaccines = [];
      for (final v in allVaccines) {
        final vaccineId = v['vaccine_id'] as int;
        final recommendedAge = (v['recommended_age_months'] as num).toDouble();
        if (ageMonths >= recommendedAge && !completedVaccineIds.contains(vaccineId)) {
          dueVaccines.add(v);
        }
      }

      String nextVaccinesStr = '';
      if (dueVaccines.isNotEmpty) {
        nextVaccinesStr = dueVaccines.map((v) => '${v['vaccine_name']} (Dose ${v['dose_number']})').join(', ');
      } else {
        // Find next upcoming vaccines in sequence
        final List<Map<String, dynamic>> upcomingVaccines = [];
        double? nextAge;
        for (final v in allVaccines) {
          final vaccineId = v['vaccine_id'] as int;
          final recommendedAge = (v['recommended_age_months'] as num).toDouble();
          if (recommendedAge > ageMonths && !completedVaccineIds.contains(vaccineId)) {
            if (nextAge == null || recommendedAge < nextAge) {
              nextAge = recommendedAge;
              upcomingVaccines.clear();
              upcomingVaccines.add(v);
            } else if (recommendedAge == nextAge) {
              upcomingVaccines.add(v);
            }
          }
        }
        if (upcomingVaccines.isNotEmpty && nextAge != null) {
          final vaccinesList = upcomingVaccines.map((v) => '${v['vaccine_name']} (Dose ${v['dose_number']})').join(', ');
          String ageLabel = '';
          if (nextAge == 0) {
            ageLabel = 'at birth';
          } else if (nextAge < 1) {
            ageLabel = 'at ${(nextAge * 4).round()} weeks';
          } else {
            ageLabel = 'at ${nextAge.toStringAsFixed(0)} months';
          }
          nextVaccinesStr = '$vaccinesList ($ageLabel)';
        }
      }

      // 6. Construct the automated confirmation and recommendation message
      final recordedStr = recordedVaccines.join(', ');
      
      String smsMessage = '';
      if (nextVaccinesStr.isNotEmpty) {
        smsMessage = 'InaAgapay: Magandang araw po Nanay $motherFirstName! Naitala po sa $bhcName na si $childName ay nakatanggap ng bakuna ngayong araw: $recordedStr. Ang susunod na irerekomendang bakuna ay: $nextVaccinesStr. Mangyaring bisitahin ang inyong Barangay Health Center para dito. Salamat po at mag-ingat kayo!';
      } else {
        smsMessage = 'InaAgapay: Magandang araw po Nanay $motherFirstName! Naitala po sa $bhcName na si $childName ay nakatanggap ng bakuna ngayong araw: $recordedStr. Binabati po namin kayo dahil kumpleto na po ang inirerekomendang bakuna ni $childName para sa kanyang edad. Salamat po at mag-ingat kayo!';
      }

      // Dispatch the SMS in background
      await sendSmsMessage(phone, smsMessage);
    } catch (e) {
      if (kDebugMode) print('Error sending automated vaccine SMS: $e');
    }
  }
}