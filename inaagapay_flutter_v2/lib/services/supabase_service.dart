import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bcrypt/bcrypt.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'email_service.dart';
import 'sms_service.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  // Generate 6-digit OTP code
  static String _generateOTP() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // Generate random secure password
  static String _generateSecurePassword() {
    const length = 12;
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%&*';
    final random = Random.secure();
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  // Hash password using bcrypt
  static String _hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  // Verify password against bcrypt hash
  static bool _verifyPassword(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (e) {
      return password == hash;
    }
  }

  // Test connection
  static Future<bool> testConnection() async {
    try {
      if (kDebugMode) debugPrint('Testing Supabase connection...');
      final result = await client.from('accounts').select('count').limit(1);
      if (kDebugMode) debugPrint('Connection test result: $result');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Connection test failed: $e');
      return false;
    }
  }

  // Update password
  static Future<bool> updatePassword(int accountId, String newPassword) async {
    try {
      final hashedPassword = _hashPassword(newPassword);

      await client.from('accounts').update({
        'password_hash': hashedPassword,
        'is_temporary_password': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('account_id', accountId);

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Update password error: $e');
      return false;
    }
  }

  // Clear temporary password flag
  static Future<bool> clearTemporaryPasswordFlag(int accountId) async {
    try {
      await client.from('accounts').update({
        'is_temporary_password': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('account_id', accountId);

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Clear temporary password flag error: $e');
      return false;
    }
  }

  // Validate Philippine phone number
  static bool isValidPhilippineNumber(String phoneNumber) {
    return SmsService.isValidPhilippineNumber(phoneNumber);
  }

  // Check if phone number is available
  static Future<bool> isPhoneNumberAvailable(String phoneNumber) async {
    try {
      final formatted = SmsService.formatPhilippineNumber(phoneNumber);
      final result = await client
          .from('accounts')
          .select('account_id')
          .eq('phone_number', formatted)
          .maybeSingle();
      return result == null;
    } catch (_) {
      return true;
    }
  }

  // Check if email is available
  static Future<bool> isEmailAvailable(String email) async {
    try {
      final result = await client
          .from('accounts')
          .select('account_id')
          .eq('email_address', email)
          .maybeSingle();
      return result == null;
    } catch (_) {
      return true;
    }
  }

  // Check if contact (email or phone) exists
  static Future<Map<String, dynamic>> findAccountByContact(
      String contact) async {
    try {
      final isPhone = isValidPhilippineNumber(contact);

      if (isPhone) {
        final formatted = SmsService.formatPhilippineNumber(contact);
        final result = await client
            .from('accounts')
            .select(
                'account_id, email_address, phone_number, account_type, is_verified, status')
            .eq('phone_number', formatted)
            .maybeSingle();
        return {'exists': result != null, 'data': result, 'type': 'phone'};
      } else {
        final result = await client
            .from('accounts')
            .select(
                'account_id, email_address, phone_number, account_type, is_verified, status')
            .eq('email_address', contact)
            .maybeSingle();
        return {'exists': result != null, 'data': result, 'type': 'email'};
      }
    } catch (e) {
      return {'exists': false, 'error': e.toString()};
    }
  }

  // Register with OTP (supports email or phone)
  static Future<Map<String, dynamic>> registerWithOTP({
    required String contact,
    required String password,
    required String channel, // 'email' or 'sms'
  }) async {
    try {
      if (kDebugMode) debugPrint('Registering with $channel for: $contact');

      // Validate contact format
      if (channel == 'sms' && !isValidPhilippineNumber(contact)) {
        return {
          'success': false,
          'message':
              'Please enter a valid Philippine mobile number (e.g., 09123456789)',
        };
      }
      if (channel == 'email' &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(contact)) {
        return {
          'success': false,
          'message': 'Please enter a valid email address',
        };
      }

      final field = channel == 'sms' ? 'phone_number' : 'email_address';
      final formattedContact = channel == 'sms'
          ? SmsService.formatPhilippineNumber(contact)
          : contact;

      final existing = await client
          .from('accounts')
          .select('account_id, is_verified')
          .eq(field, formattedContact)
          .maybeSingle();

      final code = _generateOTP();
      final expires =
          DateTime.now().add(const Duration(minutes: 10)).toIso8601String();

      if (existing != null) {
        if (existing['is_verified']) {
          return {
            'success': false,
            'message': 'Account already verified. Please log in.',
          };
        }

        await client.from('accounts').update({
          'password_hash': _hashPassword(password),
          'verification_code': code,
          'verification_expires': expires,
          'created_by': 'self',
        }).eq(field, formattedContact);
      } else {
        final data = {
          'password_hash': _hashPassword(password),
          'account_type': 'mother',
          'verification_code': code,
          'verification_expires': expires,
          'is_verified': false,
          'status': 'active',
          'created_by': 'self',
          'created_at': DateTime.now().toIso8601String(),
        };

        if (channel == 'sms') {
          data['phone_number'] = formattedContact;
        } else {
          data['email_address'] = formattedContact;
        }

        await client.from('accounts').insert(data);
      }

      final sent = await EmailService.sendVerificationCode(
        contact: formattedContact,
        code: code,
        channel: channel,
      );

      if (!sent) {
        return {
          'success': true,
          'message':
              'Account created but failed to send $channel code. Please use "Resend Code".',
          'code_sent': false,
        };
      }

      return {
        'success': true,
        'message': 'Verification code sent to your $channel.',
        'code_sent': true,
        'channel': channel,
        'contact': formattedContact,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('Registration error: $e');
      return {
        'success': false,
        'message': 'Registration failed: ${e.toString()}',
      };
    }
  }

  // Forgot Password (supports email or phone)
  static Future<Map<String, dynamic>> forgotPassword(String contact) async {
    try {
      if (kDebugMode) debugPrint('Sending password reset to: $contact');

      final isPhone = isValidPhilippineNumber(contact);
      final field = isPhone ? 'phone_number' : 'email_address';
      final formattedContact =
          isPhone ? SmsService.formatPhilippineNumber(contact) : contact;

      final account = await client
          .from('accounts')
          .select('account_id')
          .eq(field, formattedContact)
          .maybeSingle();

      if (account == null) {
        return {
          'success': false,
          'message':
              'No account found with this ${isPhone ? 'phone number' : 'email address'}.',
        };
      }

      final code = _generateOTP();
      final expires =
          DateTime.now().add(const Duration(minutes: 10)).toIso8601String();

      await client.from('accounts').update({
        'reset_code': code,
        'reset_expires': expires,
      }).eq(field, formattedContact);

      final sent = await EmailService.sendPasswordResetCode(
        contact: formattedContact,
        code: code,
        channel: isPhone ? 'sms' : 'email',
      );

      return {
        'success': sent,
        'message': sent
            ? 'Password reset code sent to your ${isPhone ? 'phone' : 'email'}.'
            : 'Failed to send code. Please try again.',
        'channel': isPhone ? 'sms' : 'email',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('Error sending reset code: $e');
      return {
        'success': false,
        'message': 'Failed to send reset code. Please try again.',
      };
    }
  }

  // Verify code (supports email or phone)
  static Future<bool> verifyCode(String contact, String code) async {
    try {
      final isPhone = isValidPhilippineNumber(contact);
      final field = isPhone ? 'phone_number' : 'email_address';
      final formattedContact =
          isPhone ? SmsService.formatPhilippineNumber(contact) : contact;

      final account = await client
          .from('accounts')
          .select('verification_code, verification_expires')
          .eq(field, formattedContact)
          .maybeSingle();

      if (account == null) return false;
      if (account['verification_code'] != code) return false;

      final expires = DateTime.parse(account['verification_expires']);
      if (expires.isBefore(DateTime.now())) return false;

      await client.from('accounts').update({
        'is_verified': true,
        'verification_code': null,
        'verification_expires': null,
      }).eq(field, formattedContact);

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Verification error: $e');
      return false;
    }
  }

  // Verify reset code
  static Future<bool> verifyResetCode(String contact, String code) async {
    try {
      final isPhone = isValidPhilippineNumber(contact);
      final field = isPhone ? 'phone_number' : 'email_address';
      final formattedContact =
          isPhone ? SmsService.formatPhilippineNumber(contact) : contact;

      final account = await client
          .from('accounts')
          .select('reset_code, reset_expires')
          .eq(field, formattedContact)
          .maybeSingle();

      if (account == null) return false;
      if (account['reset_code'] != code) return false;

      final expires = DateTime.parse(account['reset_expires']);
      if (expires.isBefore(DateTime.now())) return false;

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Verify reset code error: $e');
      return false;
    }
  }

  // Reset password with new password
  static Future<Map<String, dynamic>> resetPasswordWithNew(
      String contact, String newPassword) async {
    try {
      final isPhone = isValidPhilippineNumber(contact);
      final field = isPhone ? 'phone_number' : 'email_address';
      final formattedContact =
          isPhone ? SmsService.formatPhilippineNumber(contact) : contact;

      final newHash = _hashPassword(newPassword);

      await client.from('accounts').update({
        'password_hash': newHash,
        'reset_code': null,
        'reset_expires': null,
      }).eq(field, formattedContact);

      return {'success': true, 'message': 'Password reset successfully'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to reset password: ${e.toString()}'
      };
    }
  }

  // LOGIN (supports email or phone)
  static Future<Map<String, dynamic>> login(
      String identifier, String password) async {
    try {
      if (kDebugMode) debugPrint('Attempting login for: $identifier');

      final isConnected = await testConnection();
      if (!isConnected) {
        return {
          'success': false,
          'message':
              'Cannot connect to server. Please check your internet connection.'
        };
      }

      final isPhone = isValidPhilippineNumber(identifier);
      final field = isPhone ? 'phone_number' : 'email_address';
      final formattedIdentifier =
          isPhone ? SmsService.formatPhilippineNumber(identifier) : identifier;

      final accountResponse = await client.from('accounts').select('''
            account_id,
            email_address,
            phone_number,
            password_hash,
            account_type,
            is_verified,
            status,
            first_name,
            middle_name,
            last_name,
            extension_name,
            created_at,
            is_temporary_password,
            created_by
          ''').eq(field, formattedIdentifier).maybeSingle();

      if (kDebugMode) {
        debugPrint('Account query response: $accountResponse');
        debugPrint('created_by from query: ${accountResponse?['created_by']}');
      }

      if (accountResponse == null) {
        return {'success': false, 'message': 'Invalid credentials'};
      }

      if (accountResponse['account_type'] == 'admin') {
        return {
          'success': false,
          'message': 'Admin accounts must use the administrative web portal.'
        };
      }

      if (!_verifyPassword(password, accountResponse['password_hash'] ?? '')) {
        return {'success': false, 'message': 'Invalid credentials'};
      }

      if (!accountResponse['is_verified']) {
        return {'success': false, 'message': 'Account not verified'};
      }

      if (accountResponse['status'] != 'active') {
        return {'success': false, 'message': 'Account inactive'};
      }

      final createdBy = accountResponse['created_by'] as String? ?? 'self';

      if (kDebugMode) {
        debugPrint('=== CRITICAL: created_by from account = $createdBy ===');
      }

      Map<String, dynamic>? motherData;
      bool profileComplete = false;
      int? motherId;
      bool needsPasswordChange = false;

      if (accountResponse['account_type'] == 'mother') {
        try {
          motherData = await client
              .from('mothers')
              .select('mother_id, birthdate')
              .eq('account_id', accountResponse['account_id'])
              .maybeSingle();

          if (kDebugMode) debugPrint('Mother data: $motherData');

          if (motherData != null) {
            motherId = motherData['mother_id'] as int?;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error fetching mother data (non-critical): $e');
          }
        }

        if (createdBy == 'midwife') {
          profileComplete = true;
          if (kDebugMode) {
            debugPrint('✅ Midwife account detected - profileComplete = true');
          }
        } else {
          final hasFirstName = accountResponse['first_name'] != null &&
              accountResponse['first_name'].toString().isNotEmpty;
          final hasLastName = accountResponse['last_name'] != null &&
              accountResponse['last_name'].toString().isNotEmpty;
          final hasBirthdate =
              motherData != null && motherData['birthdate'] != null;
          final hasPhone = accountResponse['phone_number'] != null &&
              accountResponse['phone_number'].toString().isNotEmpty;

          profileComplete =
              hasFirstName && hasLastName && hasBirthdate && hasPhone;
          if (kDebugMode) {
            debugPrint(
                'Self-registered account - profileComplete = $profileComplete');
          }
        }

        needsPasswordChange = accountResponse['is_temporary_password'] == true;

        if (kDebugMode) {
          debugPrint('=== FINAL LOGIN VALUES ===');
          debugPrint('createdBy: $createdBy');
          debugPrint('profileComplete: $profileComplete');
          debugPrint('needsPasswordChange: $needsPasswordChange');
          debugPrint('motherId: $motherId');
        }
      }

      final token =
          _generateOTP() + DateTime.now().millisecondsSinceEpoch.toString();

      try {
        await client.from('accounts').update({
          'last_login_token': token,
          'last_login_at': DateTime.now().toIso8601String(),
        }).eq('account_id', accountResponse['account_id']);
      } catch (e) {
        if (kDebugMode) debugPrint('Error updating last login token: $e');
      }

      final userData = {
        'id': accountResponse['account_id'],
        'role': accountResponse['account_type'],
        'created_by': createdBy,
      };

      if (accountResponse['account_type'] == 'mother') {
        userData['profile_complete'] = profileComplete;
        userData['mother_id'] = motherId;
        userData['needs_password_change'] = needsPasswordChange;
      }

      if (kDebugMode) {
        debugPrint('=== RESPONSE USER DATA ===');
        debugPrint('userData: $userData');
      }

      return {
        'success': true,
        'message': 'Login successful',
        'token': token,
        'user': userData,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('Login error details: $e');

      if (e.toString().contains('SocketException') ||
          e.toString().contains('ClientException') ||
          e.toString().contains('Connection refused')) {
        return {
          'success': false,
          'message': 'Network error. Please check your internet connection.'
        };
      }

      if (e.toString().contains('timeout')) {
        return {
          'success': false,
          'message': 'Connection timeout. Server may be down.'
        };
      }

      if (e.toString().contains('apikey')) {
        return {
          'success': false,
          'message': 'API key error. Please restart the app.'
        };
      }

      return {'success': false, 'message': 'Login failed. Please try again.'};
    }
  }

  // Resend verification code
  static Future<Map<String, dynamic>> resendVerificationCode(
      String contact) async {
    try {
      final isPhone = isValidPhilippineNumber(contact);
      final field = isPhone ? 'phone_number' : 'email_address';
      final formattedContact =
          isPhone ? SmsService.formatPhilippineNumber(contact) : contact;

      final code = _generateOTP();
      final expires =
          DateTime.now().add(const Duration(minutes: 10)).toIso8601String();

      await client
          .from('accounts')
          .update({
            'verification_code': code,
            'verification_expires': expires,
          })
          .eq(field, formattedContact)
          .eq('is_verified', false);

      final sent = await EmailService.sendVerificationCode(
        contact: formattedContact,
        code: code,
        channel: isPhone ? 'sms' : 'email',
      );

      return {
        'success': sent,
        'message': sent
            ? 'New verification code sent to your ${isPhone ? 'phone' : 'email'}.'
            : 'Failed to send code. Please try again.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to resend code: ${e.toString()}',
      };
    }
  }

  // Complete mother profile (for self-registered users)
  static Future<Map<String, dynamic>> completeMotherProfile(
    int accountId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      final updateMap = {
        'first_name': profileData['first_name'],
        'middle_name': profileData['middle_name'],
        'last_name': profileData['last_name'],
        'extension_name': profileData['extension_name'],
        'phone_number': profileData['contact_number'],
      };
      if (profileData.containsKey('email_address')) {
        updateMap['email_address'] = profileData['email_address'];
      }
      await client
          .from('accounts')
          .update(updateMap)
          .eq('account_id', accountId);

      final existingMother = await client
          .from('mothers')
          .select('mother_id, assigned_bhc_id')
          .eq('account_id', accountId)
          .maybeSingle();

      String? birthDateStr;
      if (profileData['birth_date'] != null &&
          profileData['birth_date'].isNotEmpty) {
        try {
          if (profileData['birth_date'].contains('/')) {
            final parts = profileData['birth_date'].split('/');
            if (parts.length == 3) {
              final month = int.parse(parts[0]);
              final day = int.parse(parts[1]);
              final year = int.parse(parts[2]);
              birthDateStr =
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
            }
          } else {
            birthDateStr = profileData['birth_date'];
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Date parsing error: $e');
          birthDateStr = profileData['birth_date'];
        }
      }

      final lmpStr = profileData['lmp'];
      final eddStr = profileData['edd'];
      DateTime? lmp;
      DateTime? edd;

      if (lmpStr != null && lmpStr.isNotEmpty) {
        lmp = DateTime.tryParse(lmpStr);
      }
      if (eddStr != null && eddStr.isNotEmpty) {
        edd = DateTime.tryParse(eddStr);
      }

      if (existingMother == null) {
        final motherInsert = <String, dynamic>{
          'account_id': accountId,
          'birthdate': birthDateStr,
          'status': 'active',
        };
        if (profileData['height'] != null) {
          motherInsert['height'] = profileData['height'];
        }
        await client.from('mothers').insert(motherInsert);

        if (lmp != null && edd != null) {
          final motherRecord = await client
              .from('mothers')
              .select('mother_id')
              .eq('account_id', accountId)
              .maybeSingle();

          if (motherRecord != null) {
            final motherId = motherRecord['mother_id'] as int;

            final pregnancyInsert = <String, dynamic>{
              'mother_id': motherId,
              'last_menstrual_period': lmp.toIso8601String().split('T')[0],
              'expected_date_of_delivery': edd.toIso8601String().split('T')[0],
              'status': 'ongoing',
            };
            if (profileData['pre_pregnancy_weight'] != null) {
              pregnancyInsert['pre_pregnancy_weight'] =
                  profileData['pre_pregnancy_weight'];
            }

            final pregnancyRecord = await client
                .from('pregnancies')
                .insert(pregnancyInsert)
                .select('pregnancy_id')
                .maybeSingle();

            if (pregnancyRecord != null &&
                profileData['current_weight'] != null &&
                profileData['height'] != null) {
              final pregnancyId = pregnancyRecord['pregnancy_id'] as int;
              double? aogWeeks;
              aogWeeks = DateTime.now().difference(lmp).inDays / 7.0;
              await client.from('maternal_vitals').insert({
                'pregnancy_id': pregnancyId,
                'mother_id': motherId,
                'weight_kg': profileData['current_weight'],
                'height_cm': profileData['height'],
                'age_of_gestation': double.parse(aogWeeks.toStringAsFixed(1)),
                'notes': 'Initial vitals entered during profile setup',
                'recorded_at': DateTime.now().toIso8601String(),
              });
            }
          }
        }
      } else {
        final updateData = <String, dynamic>{};
        if (birthDateStr != null) updateData['birthdate'] = birthDateStr;
        if (profileData['height'] != null) {
          updateData['height'] = profileData['height'];
        }

        if (updateData.isNotEmpty) {
          await client
              .from('mothers')
              .update(updateData)
              .eq('account_id', accountId);
        }

        if (lmp != null && edd != null) {
          final existingPregnancy = await client
              .from('pregnancies')
              .select('pregnancy_id')
              .eq('mother_id', existingMother['mother_id'])
              .eq('status', 'ongoing')
              .maybeSingle();

          final motherId = existingMother['mother_id'] as int;
          int? pregnancyId;

          if (existingPregnancy == null) {
            final pregnancyInsert = <String, dynamic>{
              'mother_id': motherId,
              'last_menstrual_period': lmp.toIso8601String().split('T')[0],
              'expected_date_of_delivery': edd.toIso8601String().split('T')[0],
              'status': 'ongoing',
            };
            if (profileData['pre_pregnancy_weight'] != null) {
              pregnancyInsert['pre_pregnancy_weight'] =
                  profileData['pre_pregnancy_weight'];
            }
            final pregnancyRecord = await client
                .from('pregnancies')
                .insert(pregnancyInsert)
                .select('pregnancy_id')
                .maybeSingle();
            if (pregnancyRecord != null) {
              pregnancyId = pregnancyRecord['pregnancy_id'] as int;
            }
          } else {
            pregnancyId = existingPregnancy['pregnancy_id'] as int;
            if (profileData['pre_pregnancy_weight'] != null) {
              await client.from('pregnancies').update({
                'pre_pregnancy_weight': profileData['pre_pregnancy_weight'],
              }).eq('pregnancy_id', pregnancyId);
            }
          }

          if (pregnancyId != null &&
              profileData['current_weight'] != null &&
              profileData['height'] != null) {
            double? aogWeeks;
            aogWeeks = DateTime.now().difference(lmp).inDays / 7.0;
            await client.from('maternal_vitals').insert({
              'pregnancy_id': pregnancyId,
              'mother_id': motherId,
              'weight_kg': profileData['current_weight'],
              'height_cm': profileData['height'],
              'age_of_gestation': double.parse(aogWeeks.toStringAsFixed(1)),
              'notes': 'Initial vitals entered during profile setup',
              'recorded_at': DateTime.now().toIso8601String(),
            });
          }
        }
      }

      final finalMother = await client
          .from('mothers')
          .select('mother_id')
          .eq('account_id', accountId)
          .maybeSingle();
      final finalMotherId = finalMother?['mother_id'] as int?;

      return {
        'success': true,
        'message': 'Profile completed successfully',
        'mother_id': finalMotherId,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('Profile completion error: $e');
      return {
        'success': false,
        'message': 'Failed to complete profile: ${e.toString()}'
      };
    }
  }

  // Get greeting
  static Future<Map<String, dynamic>> getGreeting(
      int accountId, String role) async {
    try {
      final accountResponse = await client.from('accounts').select('''
            first_name,
            middle_name,
            last_name,
            extension_name
          ''').eq('account_id', accountId).maybeSingle();
      if (role == 'mother') {
        final motherResponse = await client
            .from('mothers')
            .select('assigned_bhc_id')
            .eq('account_id', accountId)
            .maybeSingle();

        String bhcName = 'No Barangay Assigned';
        final bhcId = motherResponse?['assigned_bhc_id'] as int?;
        if (bhcId != null) {
          final facility = await client
              .from('health_facilities')
              .select('name')
              .eq('facility_id', bhcId)
              .maybeSingle();
          if (facility != null && facility['name'] != null) {
            bhcName = facility['name'].toString();
          }
        }

        return {
          'success': true,
          'first_name': accountResponse?['first_name'],
          'middle_name': accountResponse?['middle_name'],
          'last_name': accountResponse?['last_name'],
          'extension_name': accountResponse?['extension_name'],
          'bhc_name': bhcName,
        };
      }

      if (role == 'midwife') {
        final midwifeResponse = await client
            .from('midwives')
            .select('assigned_bhc_id')
            .eq('account_id', accountId)
            .maybeSingle();

        String bhcName = 'No Barangay Assigned';
        final bhcId = midwifeResponse?['assigned_bhc_id'] as int?;
        if (bhcId != null) {
          final facility = await client
              .from('health_facilities')
              .select('name')
              .eq('facility_id', bhcId)
              .maybeSingle();
          if (facility != null && facility['name'] != null) {
            bhcName = facility['name'].toString();
          }
        }

        return {
          'success': true,
          'first_name': accountResponse?['first_name'],
          'middle_name': accountResponse?['middle_name'],
          'last_name': accountResponse?['last_name'],
          'extension_name': accountResponse?['extension_name'],
          'bhc_name': bhcName,
        };
      }

      return {'success': false, 'message': 'Unknown role'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Get midwife context
  static Future<Map<String, dynamic>> getMidwifeContext(int accountId) async {
    try {
      if (kDebugMode) {
        debugPrint('=== GET MIDWIFE CONTEXT ===');
        debugPrint('Account ID: $accountId');
      }

      final result = await client
          .from('midwives')
          .select('midwife_id, assigned_bhc_id')
          .eq('account_id', accountId)
          .maybeSingle();

      if (result == null) {
        // Check if account is a midwife and auto-create midwife record
        final acct = await client
            .from('accounts')
            .select('account_id, email_address, account_type')
            .eq('account_id', accountId)
            .maybeSingle();

        if (acct != null && acct['account_type'] == 'midwife') {
          final email = (acct['email_address'] ?? '').toString().toLowerCase();
          int bhcId = 1;
          if (email.contains('tarcan')) {
            bhcId = 2;
          } else if (email.contains('pinagbarilan')) {
            bhcId = 3;
          } else if (email.contains('makinabang')) {
            bhcId = 4;
          } else if (email.contains('stabarbara')) {
            bhcId = 5;
          }

          final inserted = await client
              .from('midwives')
              .insert({
                'account_id': accountId,
                'assigned_bhc_id': bhcId,
              })
              .select('midwife_id, assigned_bhc_id')
              .maybeSingle();

          if (inserted != null) {
            final facility = await client
                .from('health_facilities')
                .select('name')
                .eq('facility_id', bhcId)
                .maybeSingle();

            return {
              'success': true,
              'midwife_id': inserted['midwife_id'] as int,
              'assigned_bhc_id': bhcId,
              'bhc_name':
                  facility?['name']?.toString() ?? 'Barangay Health Center',
            };
          }
        }
        return {'success': false, 'message': 'Midwife not found'};
      }

      final assignedBhcId = result['assigned_bhc_id'] as int?;
      String bhcName = 'Unknown BHC';

      if (assignedBhcId != null) {
        final facility = await client
            .from('health_facilities')
            .select('name')
            .eq('facility_id', assignedBhcId)
            .maybeSingle();
        if (facility != null && facility['name'] != null) {
          bhcName = facility['name'].toString();
        }
      }

      return {
        'success': true,
        'midwife_id': result['midwife_id'] as int,
        'assigned_bhc_id': assignedBhcId,
        'bhc_name': bhcName,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Check if account exists and get existing data (supports email or phone lookup)
  static Future<Map<String, dynamic>> getExistingMotherAccount({
    String? email,
    String? phone,
  }) async {
    try {
      if (email == null && phone == null) return {'exists': false};

      final query = client
          .from('accounts')
          .select('''
            account_id,
            email_address,
            first_name,
            middle_name,
            last_name,
            extension_name,
            phone_number,
            created_by,
            mothers!inner (
              mother_id,
              birthdate,
              assigned_bhc_id,
              house_number,
              street,
              barangay,
              city_municipality,
              province,
              height,
              weight,
              blood_type,
              status
            )
          ''')
          .eq('account_type', 'mother');

      Map<String, dynamic>? accountData;
      if (email != null && email.isNotEmpty) {
        accountData = await query.eq('email_address', email).maybeSingle();
      }
      if (accountData == null && phone != null && phone.isNotEmpty) {
        final formatted = SmsService.formatPhilippineNumber(phone);
        accountData = await client
            .from('accounts')
            .select('''
              account_id,
              email_address,
              first_name,
              middle_name,
              last_name,
              extension_name,
              phone_number,
              created_by,
              mothers!inner (
                mother_id,
                birthdate,
                assigned_bhc_id,
                house_number,
                street,
                barangay,
                city_municipality,
                province,
                height,
                weight,
                blood_type,
                status
              )
            ''')
            .eq('account_type', 'mother')
            .eq('phone_number', formatted)
            .maybeSingle();
      }

      if (accountData == null) {
        return {'exists': false};
      }

      final motherData = accountData['mothers'] as Map<String, dynamic>?;
      final motherId = motherData?['mother_id'];

      // Fetch ongoing pregnancy data if mother exists
      Map<String, dynamic>? pregnancyData;
      if (motherId != null) {
        pregnancyData = await client
            .from('pregnancies')
            .select('pregnancy_id, last_menstrual_period, expected_date_of_delivery, pre_pregnancy_weight, status')
            .eq('mother_id', motherId)
            .eq('status', 'ongoing')
            .maybeSingle();
      }

      // Calculate pregnancy week and trimester
      int? pregnancyWeek;
      String? trimester;
      if (pregnancyData != null && pregnancyData['last_menstrual_period'] != null) {
        final lmpDate = DateTime.tryParse(pregnancyData['last_menstrual_period']);
        if (lmpDate != null) {
          final daysSinceLmp = DateTime.now().difference(lmpDate).inDays;
          pregnancyWeek = (daysSinceLmp / 7).floor();
          if (pregnancyWeek <= 13) {
            trimester = '1st Trimester';
          } else if (pregnancyWeek <= 27) {
            trimester = '2nd Trimester';
          } else {
            trimester = '3rd Trimester';
          }
        }
      }

      return {
        'exists': true,
        'account_id': accountData['account_id'],
        'mother_id': motherId,
        'has_bhc': motherData?['assigned_bhc_id'] != null,
        'created_by': accountData['created_by'] ?? 'self',
        'pregnancy': pregnancyData != null ? {
          'pregnancy_id': pregnancyData['pregnancy_id'],
          'lmp': pregnancyData['last_menstrual_period'],
          'edd': pregnancyData['expected_date_of_delivery'],
          'pre_pregnancy_weight': pregnancyData['pre_pregnancy_weight'],
          'week': pregnancyWeek,
          'trimester': trimester,
        } : null,
        'data': {
          'first_name': accountData['first_name'],
          'middle_name': accountData['middle_name'],
          'last_name': accountData['last_name'],
          'extension_name': accountData['extension_name'],
          'phone_number': accountData['phone_number'],
          'email_address': accountData['email_address'],
          'birthdate': motherData?['birthdate'],
          'house_number': motherData?['house_number'],
          'street': motherData?['street'],
          'barangay': motherData?['barangay'],
          'city_municipality': motherData?['city_municipality'],
          'province': motherData?['province'],
          'height': motherData?['height'],
          'weight': motherData?['weight'],
          'blood_type': motherData?['blood_type'],
          'assigned_bhc_id': motherData?['assigned_bhc_id'],
        },
      };
    } catch (e) {
      return {'exists': false, 'error': e.toString()};
    }
  }

  // Update existing mother account
  static Future<Map<String, dynamic>> updateExistingMotherAccount({
    required int motherId,
    required int assignedBhcId,
    String? houseNumber,
    String? street,
    String? barangay,
    String? city,
    String? province,
    double? heightCm,
    double? weightKg,
    String? bloodType,
    DateTime? lmp,
    DateTime? edd,
    List<Map<String, dynamic>> emergencyContacts = const [],
    List<Map<String, dynamic>> medicalConditions = const [],
    List<Map<String, dynamic>> allergies = const [],
    List<Map<String, dynamic>> pastPregnancies = const [],
    int fetalCount = 1,
    double? prePregnancyWeight,
    List<String> riskFactors = const [],
  }) async {
    try {
      final motherResponse = await client
          .from('mothers')
          .select('account_id')
          .eq('mother_id', motherId)
          .maybeSingle();

      if (motherResponse != null) {
        final accountId = motherResponse['account_id'] as int;

        await client
            .from('accounts')
            .update({
              'created_by': 'midwife',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('account_id', accountId)
            .eq('created_by', 'self');
      }

      await client.from('mothers').update({
        'assigned_bhc_id': assignedBhcId,
        'house_number': houseNumber,
        'street': street,
        'barangay': barangay,
        'city_municipality': city,
        'province': province,
        'height': heightCm,
        'weight': weightKg,
        'blood_type': bloodType,
        'status': 'active',
      }).eq('mother_id', motherId);

      if (emergencyContacts.isNotEmpty) {
        await client.from('emergency_contacts').insert(
              emergencyContacts
                  .map((ec) => {'mother_id': motherId, ...ec})
                  .toList(),
            );
      }

      if (medicalConditions.isNotEmpty) {
        await client.from('medical_conditions').insert(
              medicalConditions
                  .map((mc) => {'mother_id': motherId, ...mc})
                  .toList(),
            );
      }

      if (allergies.isNotEmpty) {
        await client.from('allergies').insert(
              allergies.map((al) => {'mother_id': motherId, ...al}).toList(),
            );
      }

      int? pregnancyId;
      if (lmp != null && edd != null) {
        final pregRow = await client
            .from('pregnancies')
            .insert({
              'mother_id': motherId,
              'fetal_count': fetalCount,
              'last_menstrual_period': lmp.toIso8601String().split('T')[0],
              'expected_date_of_delivery': edd.toIso8601String().split('T')[0],
              'pre_pregnancy_weight': prePregnancyWeight,
              'status': 'ongoing',
              'pregnancy_risk_level': riskFactors.isNotEmpty ? 'high' : 'low',
            })
            .select('pregnancy_id')
            .maybeSingle();

        if (pregRow != null) {
          pregnancyId = pregRow['pregnancy_id'] as int;

          if (riskFactors.isNotEmpty) {
            final assessmentRow = await client
                .from('pregnancy_risk_assessments')
                .insert({
                  'pregnancy_id': pregnancyId,
                  'risk_level': 'high',
                  'assessed_by_ai': false,
                })
                .select('pregnancy_risk_id')
                .maybeSingle();

            if (assessmentRow != null) {
              final riskId = assessmentRow['pregnancy_risk_id'] as int;
              await client.from('pregnancy_risk_factors').insert(
                    riskFactors
                        .map((f) => {
                              'pregnancy_risk_id': riskId,
                              'factor': f,
                            })
                        .toList(),
                  );
            }
          }
        }
      }

      for (final pp in pastPregnancies) {
        final pastPregRow = await client
            .from('pregnancies')
            .insert({
              'mother_id': motherId,
              'status': 'ended',
              'fetal_count': pp['fetal_count'] ?? 1,
              'gestational_age_at_end': pp['gestational_age_at_end'],
            })
            .select('pregnancy_id')
            .maybeSingle();

        if (pastPregRow == null) continue;

        final pastPregId = pastPregRow['pregnancy_id'] as int;

        final outcomes = pp['outcomes'] as List<dynamic>? ?? [];
        for (int i = 0; i < outcomes.length; i++) {
          final outcome = outcomes[i] as Map<String, dynamic>;
          final fetusNumber = i + 1;

          await client.from('pregnancy_outcomes').insert({
            'pregnancy_id': pastPregId,
            'fetus_number': fetusNumber,
            'outcome': outcome['outcome'],
            'outcome_date': outcome['outcome_date'],
            'is_outcome_date_estimated':
                outcome['is_outcome_date_estimated'] ?? false,
          });

          if (outcome['place_of_delivery'] != null ||
              outcome['delivery_method'] != null) {
            await client.from('deliveries').insert({
              'pregnancy_id': pastPregId,
              'fetus_number': fetusNumber,
              'delivery_date': outcome['outcome_date'],
              'is_delivery_date_estimated':
                  outcome['is_outcome_date_estimated'] ?? false,
              'place_of_delivery': outcome['place_of_delivery'],
              'delivery_method': outcome['delivery_method'],
            });
          }
        }
      }

      return {
        'success': true,
        'mother_id': motherId,
        'pregnancy_id': pregnancyId,
        'message': 'Mother account updated successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to update mother account: ${e.toString()}',
      };
    }
  }

  // Add mother with auto-generated password (midwife creates account)
  static Future<Map<String, dynamic>> addMotherFullByMidwifeWithAutoPassword({
    required int midwifeId,
    required int assignedBhcId,
    required String email,
    required String firstName,
    String? middleName,
    required String lastName,
    String? extensionName,
    required String phone,
    String? houseNumber,
    String? street,
    String? barangay,
    String? city,
    String? province,
    DateTime? birthdate,
    double? heightCm,
    double? weightKg,
    String? bloodType,
    DateTime? lmp,
    DateTime? edd,
    List<Map<String, dynamic>> emergencyContacts = const [],
    List<Map<String, dynamic>> medicalConditions = const [],
    List<Map<String, dynamic>> allergies = const [],
    List<Map<String, dynamic>> pastPregnancies = const [],
    int fetalCount = 1,
    double? prePregnancyWeight,
    List<String> riskFactors = const [],
  }) async {
    try {
      int accountId;
      String? generatedPassword;
      bool isExistingAccount = false;

      // Try finding existing account by email first, then by phone
      Map<String, dynamic>? existingAccount;
      if (email.isNotEmpty && !email.endsWith('@inaagapay.internal')) {
        existingAccount = await client
            .from('accounts')
            .select('account_id, account_type')
            .eq('email_address', email)
            .maybeSingle();
      }
      if (existingAccount == null && phone.isNotEmpty) {
        final formatted = SmsService.formatPhilippineNumber(phone);
        existingAccount = await client
            .from('accounts')
            .select('account_id, account_type')
            .eq('phone_number', formatted)
            .maybeSingle();
      }

      if (existingAccount != null) {
        if (existingAccount['account_type'] != 'mother') {
          return {'success': false, 'message': 'This email is already in use by a midwife or admin.'};
        }
        accountId = existingAccount['account_id'] as int;
        isExistingAccount = true;

        // Update existing account details
        await client.from('accounts').update({
          'first_name': firstName,
          'middle_name': middleName,
          'last_name': lastName,
          'extension_name': extensionName,
          'phone_number': phone,
        }).eq('account_id', accountId);
      } else {
        generatedPassword = _generateSecurePassword();
        final hashedPassword = _hashPassword(generatedPassword);

        final accountRow = await client
            .from('accounts')
            .insert({
              'email_address': email,
              'password_hash': hashedPassword,
              'account_type': 'mother',
              'first_name': firstName,
              'middle_name': middleName,
              'last_name': lastName,
              'extension_name': extensionName,
              'phone_number': phone,
              'is_verified': true,
              'status': 'active',
              'is_temporary_password': true,
              'created_by': 'midwife',
              'created_at': DateTime.now().toIso8601String(),
            })
            .select('account_id')
            .maybeSingle();

        if (accountRow == null) {
          throw Exception('Failed to create account');
        }
        accountId = accountRow['account_id'] as int;
      }

      final existingMother = await client
          .from('mothers')
          .select('mother_id')
          .eq('account_id', accountId)
          .maybeSingle();

      int motherId;
      if (existingMother != null) {
        motherId = existingMother['mother_id'] as int;
        await client.from('mothers').update({
          'assigned_bhc_id': assignedBhcId,
          'birthdate': birthdate?.toIso8601String().split('T')[0],
          'house_number': houseNumber,
          'street': street,
          'barangay': barangay,
          'city_municipality': city,
          'province': province,
          'height': heightCm,
          'weight': weightKg,
          'blood_type': bloodType,
          'status': 'active',
        }).eq('mother_id', motherId);
      } else {
        final motherRow = await client
            .from('mothers')
            .insert({
              'account_id': accountId,
              'assigned_bhc_id': assignedBhcId,
              'birthdate': birthdate?.toIso8601String().split('T')[0],
              'house_number': houseNumber,
              'street': street,
              'barangay': barangay,
              'city_municipality': city,
              'province': province,
              'height': heightCm,
              'weight': weightKg,
              'blood_type': bloodType,
              'status': 'active',
            })
            .select('mother_id')
            .maybeSingle();

        if (motherRow == null) {
          throw Exception('Failed to create mother record');
        }
        motherId = motherRow['mother_id'] as int;
      }

      if (emergencyContacts.isNotEmpty) {
        await client.from('emergency_contacts').insert(
              emergencyContacts
                  .map((ec) => {'mother_id': motherId, ...ec})
                  .toList(),
            );
      }

      if (medicalConditions.isNotEmpty) {
        await client.from('medical_conditions').insert(
              medicalConditions
                  .map((mc) => {'mother_id': motherId, ...mc})
                  .toList(),
            );
      }

      if (allergies.isNotEmpty) {
        await client.from('allergies').insert(
              allergies.map((al) => {'mother_id': motherId, ...al}).toList(),
            );
      }

      int? pregnancyId;
      if (lmp != null && edd != null) {
        bool shouldInsertPregnancy = true;

        if (isExistingAccount) {
          final existingPregnancy = await client
              .from('pregnancies')
              .select('pregnancy_id')
              .eq('mother_id', motherId)
              .eq('status', 'ongoing')
              .maybeSingle();
              
          if (existingPregnancy != null) {
            shouldInsertPregnancy = false;
            pregnancyId = existingPregnancy['pregnancy_id'] as int;
            
            // Update existing pregnancy
            await client.from('pregnancies').update({
              'fetal_count': fetalCount,
              'last_menstrual_period': lmp.toIso8601String().split('T')[0],
              'expected_date_of_delivery': edd.toIso8601String().split('T')[0],
              'pre_pregnancy_weight': prePregnancyWeight,
              'pregnancy_risk_level': riskFactors.isNotEmpty ? 'high' : 'low',
            }).eq('pregnancy_id', pregnancyId);
            
            if (riskFactors.isNotEmpty) {
              // Delete old risk factors and assessment if any, then re-insert
              await client.from('pregnancy_risk_assessments').delete().eq('pregnancy_id', pregnancyId);
              
              final assessmentRow = await client
                  .from('pregnancy_risk_assessments')
                  .insert({
                    'pregnancy_id': pregnancyId,
                    'risk_level': 'high',
                    'assessed_by_ai': false,
                  })
                  .select('pregnancy_risk_id')
                  .maybeSingle();

              if (assessmentRow != null) {
                final riskId = assessmentRow['pregnancy_risk_id'] as int;
                await client.from('pregnancy_risk_factors').insert(
                      riskFactors
                          .map((f) => {
                                'pregnancy_risk_id': riskId,
                                'factor': f,
                              })
                          .toList(),
                    );
              }
            }
          }
        }

        if (shouldInsertPregnancy) {
          final pregRow = await client
              .from('pregnancies')
              .insert({
                'mother_id': motherId,
                'fetal_count': fetalCount,
                'last_menstrual_period': lmp.toIso8601String().split('T')[0],
                'expected_date_of_delivery': edd.toIso8601String().split('T')[0],
                'pre_pregnancy_weight': prePregnancyWeight,
                'status': 'ongoing',
                'pregnancy_risk_level': riskFactors.isNotEmpty ? 'high' : 'low',
              })
              .select('pregnancy_id')
              .maybeSingle();

          if (pregRow != null) {
            pregnancyId = pregRow['pregnancy_id'] as int;

            if (riskFactors.isNotEmpty) {
              final assessmentRow = await client
                  .from('pregnancy_risk_assessments')
                  .insert({
                    'pregnancy_id': pregnancyId,
                    'risk_level': 'high',
                    'assessed_by_ai': false,
                  })
                  .select('pregnancy_risk_id')
                  .maybeSingle();

              if (assessmentRow != null) {
                final riskId = assessmentRow['pregnancy_risk_id'] as int;
                await client.from('pregnancy_risk_factors').insert(
                      riskFactors
                          .map((f) => {
                                'pregnancy_risk_id': riskId,
                                'factor': f,
                              })
                          .toList(),
                    );
              }
            }
          }
        }
      }

      for (final pp in pastPregnancies) {
        final pastPregRow = await client
            .from('pregnancies')
            .insert({
              'mother_id': motherId,
              'status': 'ended',
              'fetal_count': pp['fetal_count'] ?? 1,
              'gestational_age_at_end': pp['gestational_age_at_end'],
            })
            .select('pregnancy_id')
            .maybeSingle();

        if (pastPregRow == null) continue;

        final pastPregId = pastPregRow['pregnancy_id'] as int;

        final outcomes = pp['outcomes'] as List<dynamic>? ?? [];
        for (int i = 0; i < outcomes.length; i++) {
          final outcome = outcomes[i] as Map<String, dynamic>;
          final fetusNumber = i + 1;

          await client.from('pregnancy_outcomes').insert({
            'pregnancy_id': pastPregId,
            'fetus_number': fetusNumber,
            'outcome': outcome['outcome'],
            'outcome_date': outcome['outcome_date'],
            'is_outcome_date_estimated':
                outcome['is_outcome_date_estimated'] ?? false,
          });

          if (outcome['place_of_delivery'] != null ||
              outcome['delivery_method'] != null) {
            await client.from('deliveries').insert({
              'pregnancy_id': pastPregId,
              'fetus_number': fetusNumber,
              'delivery_date': outcome['outcome_date'],
              'is_delivery_date_estimated':
                  outcome['is_outcome_date_estimated'] ?? false,
              'place_of_delivery': outcome['place_of_delivery'],
              'delivery_method': outcome['delivery_method'],
            });
          }
        }
      }

      final isInternalEmail = email.endsWith('@inaagapay.internal');
      bool credentialsSent = false;
      String sentMethod = '';

      if (isExistingAccount) {
        return {
          'success': true,
          'mother_id': motherId,
          'pregnancy_id': pregnancyId,
          'account_id': accountId,
          'generated_password': null,
          'email_sent': false,
          'sms_sent': false,
          'credentials_delivery_method': '',
          'message': 'Mother profile successfully linked and updated under email $email.',
        };
      }

      // Try sending via email first if not internal
      if (!isInternalEmail && generatedPassword != null) {
        credentialsSent = await EmailService.sendAccountCredentials(
          email: email,
          password: generatedPassword,
          firstName: firstName,
          lastName: lastName,
        );
        if (credentialsSent) sentMethod = 'email';
      }

      // If email not sent and phone is available, try SMS
      if (!credentialsSent && phone.isNotEmpty && generatedPassword != null) {
        credentialsSent = await EmailService.sendAccountCredentialsViaSms(
          phoneNumber: phone,
          password: generatedPassword,
          firstName: firstName,
          lastName: lastName,
        );
        if (credentialsSent) sentMethod = 'sms';
      }

      return {
        'success': true,
        'mother_id': motherId,
        'pregnancy_id': pregnancyId,
        'account_id': accountId,
        'generated_password': generatedPassword,
        'email_sent': credentialsSent && sentMethod == 'email',
        'sms_sent': credentialsSent && sentMethod == 'sms',
        'credentials_delivery_method': sentMethod,
        'message': credentialsSent
            ? 'Mother account created. Credentials sent via ${sentMethod.toUpperCase()}.'
            : 'Mother account created but failed to send credentials. Please provide the password manually.',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('addMotherFullByMidwifeWithAutoPassword error: $e');
      }
      return {
        'success': false,
        'message': 'Failed to add mother: ${e.toString()}',
      };
    }
  }

  // ============================================================
  // PROFILE PICTURE METHODS
  // ============================================================

  // Upload profile picture
  static Future<String?> uploadProfilePicture(
      int motherId, Uint8List imageBytes) async {
    try {
      final motherResponse = await client
          .from('mothers')
          .select('account_id')
          .eq('mother_id', motherId)
          .maybeSingle();

      if (motherResponse == null) {
        debugPrint('Mother not found for ID: $motherId');
        return null;
      }

      final accountId = motherResponse['account_id'] as int;

      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = 'profile-pictures/$accountId/$fileName';

      await client.storage.from('files').uploadBinary(
            filePath,
            imageBytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );

      final publicUrl = client.storage.from('files').getPublicUrl(filePath);

      final existingFiles = await client
          .from('files')
          .select('file_id, file_path')
          .eq('reference_type', 'profile_photo')
          .eq('uploaded_by', accountId);

      for (var file in existingFiles) {
        try {
          await client.storage
              .from('files')
              .remove([file['file_path'] as String]);
        } catch (e) {}
        await client.from('files').delete().eq('file_id', file['file_id']);
      }

      await client.from('files').insert({
        'bucket_name': 'files',
        'file_path': filePath,
        'file_name': fileName,
        'file_category': 'profile_photo',
        'mime_type': 'image/jpeg',
        'file_size': imageBytes.length,
        'uploaded_by': accountId,
        'reference_type': 'profile_photo',
        'reference_id': motherId,
        'processing_type': 'profile_photo',
        'ai_processed': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading profile picture: $e');
      return null;
    }
  }

  // Get profile picture URL
  static Future<String?> getProfilePictureUrl(int motherId) async {
    try {
      final motherResponse = await client
          .from('mothers')
          .select('account_id')
          .eq('mother_id', motherId)
          .maybeSingle();

      if (motherResponse == null) {
        debugPrint('Mother not found for ID: $motherId');
        return null;
      }

      final accountId = motherResponse['account_id'] as int;

      final fileResponse = await client
          .from('files')
          .select('file_path, bucket_name')
          .eq('reference_type', 'profile_photo')
          .eq('uploaded_by', accountId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (fileResponse != null) {
        final bucket = fileResponse['bucket_name'] as String? ?? 'files';
        final path = fileResponse['file_path'] as String?;
        if (path != null && path.isNotEmpty) {
          return client.storage.from(bucket).getPublicUrl(path);
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error getting profile picture URL: $e');
      return null;
    }
  }

  // Delete profile picture
  static Future<bool> deleteProfilePicture(int motherId) async {
    try {
      final motherResponse = await client
          .from('mothers')
          .select('account_id')
          .eq('mother_id', motherId)
          .maybeSingle();

      if (motherResponse == null) return false;

      final accountId = motherResponse['account_id'] as int;

      final filesToDelete = await client
          .from('files')
          .select('file_id, file_path, bucket_name')
          .eq('reference_type', 'profile_photo')
          .eq('uploaded_by', accountId);

      for (var file in filesToDelete) {
        final bucket = file['bucket_name'] as String? ?? 'files';
        final path = file['file_path'] as String?;
        if (path != null) {
          try {
            await client.storage.from(bucket).remove([path]);
          } catch (e) {}
        }
        await client.from('files').delete().eq('file_id', file['file_id']);
      }

      return true;
    } catch (e) {
      debugPrint('Error deleting profile picture: $e');
      return false;
    }
  }
}
