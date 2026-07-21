import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'sms_service.dart';

class EmailService {
  static final SupabaseClient _client = Supabase.instance.client;

  // Queue email in the database for secure server-side sending via Resend
  static Future<bool> _queueEmail({
    required String email,
    required String subject,
    required String htmlContent,
  }) async {
    try {
      await _client.from('email_queue').insert({
        'recipient': email,
        'subject': subject,
        'html_content': htmlContent,
      });
      if (kDebugMode) print('Email successfully queued for: $email');
      return true;
    } catch (e) {
      if (kDebugMode) print('Error queueing email: $e');
      return false;
    }
  }

  // Send verification code via preferred channel (email or SMS)
  static Future<bool> sendVerificationCode({
    required String contact,
    required String code,
    required String channel, // 'email' or 'sms'
  }) async {
    if (channel == 'email') {
      return sendVerificationEmail(contact, code);
    } else {
      return SmsService.sendOtp(contact, code);
    }
  }

  // Send verification code email
  static Future<bool> sendVerificationEmail(String email, String code) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head><meta charset="UTF-8"></head>
      <body style="font-family: Arial, sans-serif;">
        <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="text-align: center; margin-bottom: 20px;">
            <h1 style="color: #FF68A5; margin: 0;">INAAGAPAY</h1>
            <p style="color: #666; margin: 5px 0 0;">Maternal and Child Health Information System</p>
          </div>
          <div style="background: #f9f9f9; padding: 20px; border-radius: 10px; text-align: center;">
            <p style="font-size: 16px; color: #333;">Your verification code is:</p>
            <div style="font-size: 36px; color: #FF68A5; letter-spacing: 8px; padding: 15px; background: white; border-radius: 10px; font-weight: bold; margin: 10px 0;">
              <strong>$code</strong>
            </div>
            <p style="font-size: 14px; color: #666;">This code expires in <strong>10 minutes</strong>.</p>
          </div>
          <div style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #eee; text-align: center; font-size: 12px; color: #999;">
            <p>© 2026 INAAGAPAY. All rights reserved.</p>
            <p>This is an automated message, please do not reply.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    return _queueEmail(
      email: email,
      subject: '🔐 Verify Your Email - INAAGAPAY',
      htmlContent: html,
    );
  }

  // Send password reset code
  static Future<bool> sendPasswordResetCode({
    required String contact,
    required String code,
    required String channel,
  }) async {
    if (channel == 'email') {
      return sendPasswordResetEmail(contact, code);
    } else {
      return SmsService.sendOtp(contact, code);
    }
  }

  static Future<bool> sendPasswordResetEmail(String email, String code) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head><meta charset="UTF-8"></head>
      <body style="font-family: Arial, sans-serif;">
        <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="text-align: center; margin-bottom: 20px;">
            <h1 style="color: #FF68A5; margin: 0;">INAAGAPAY</h1>
            <p style="color: #666; margin: 5px 0 0;">Password Reset Request</p>
          </div>
          <div style="background: #f9f9f9; padding: 20px; border-radius: 10px; text-align: center;">
            <p style="font-size: 16px; color: #333;">Your password reset code is:</p>
            <div style="font-size: 36px; color: #FF68A5; letter-spacing: 8px; padding: 15px; background: white; border-radius: 10px; font-weight: bold; margin: 10px 0;">
              <strong>$code</strong>
            </div>
            <p style="font-size: 14px; color: #666;">This code expires in <strong>10 minutes</strong>.</p>
            <p style="margin-top: 15px; font-size: 13px; color: #999;">
              If you did not request this, please ignore this email.
            </p>
          </div>
          <div style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #eee; text-align: center; font-size: 12px; color: #999;">
            <p>© 2026 INAAGAPAY. All rights reserved.</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    return _queueEmail(
      email: email,
      subject: '🔑 Password Reset Code - INAAGAPAY',
      htmlContent: html,
    );
  }

  // Send account credentials email (for midwife-created accounts)
  static Future<bool> sendAccountCredentials({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final html = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <style>
          body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: linear-gradient(135deg, #FF68A5, #E6398D); padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
          .header h1 { color: white; margin: 0; font-size: 28px; }
          .content { background: #ffffff; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
          .password-box { background: #f5f5f5; padding: 15px; border-radius: 8px; text-align: center; margin: 20px 0; }
          .password { font-size: 24px; font-weight: bold; color: #FF68A5; letter-spacing: 2px; font-family: monospace; }
          .button { background: #FF68A5; color: white; padding: 12px 24px; text-decoration: none; border-radius: 25px; display: inline-block; margin: 20px 0; }
          .footer { text-align: center; padding: 20px; font-size: 12px; color: #666; }
          .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 12px; margin: 20px 0; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>🌸 Welcome to INAAGAPAY!</h1>
          </div>
          <div class="content">
            <h2>Hello $firstName $lastName!</h2>
            <p>A midwife has created an account for you on the <strong>INAAGAPAY Maternal and Child Health Information System</strong>.</p>
            
            <div class="password-box">
              <p style="margin-bottom: 10px;">Your temporary password is:</p>
              <div class="password">$password</div>
            </div>
            
            <div class="warning">
              <strong>⚠️ Important:</strong> This is a temporary password. 
              For security reasons, you will be required to change it upon your first login.
            </div>
            
            <p><strong>To access your account:</strong></p>
            <ol>
              <li>Open the INAAGAPAY mobile app</li>
              <li>Log in using your email and the temporary password above</li>
              <li>You will be prompted to create a new password</li>
              <li>Set a password that you will remember</li>
            </ol>
            
            <center>
              <a href="inaagapay://login" class="button">Open INAAGAPAY App</a>
            </center>
            
            <p>If you didn't expect this email or have any questions, please contact your barangay health center.</p>
            
            <hr>
            <p style="font-size: 14px; color: #666;">This is an automated message, please do not reply to this email.</p>
          </div>
          <div class="footer">
            <p>© 2026 INAAGAPAY - Supporting mothers every step of the way</p>
          </div>
        </div>
      </body>
      </html>
    ''';

    return _queueEmail(
      email: email,
      subject: '🎉 Welcome to INAAGAPAY - Your Account Credentials',
      htmlContent: html,
    );
  }

  // Send account credentials via SMS (for mothers with phone numbers but no email)
  static Future<bool> sendAccountCredentialsViaSms({
    required String phoneNumber,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final message = '''INAAGAPAY Welcome!

Your temporary password is:
$password

IMPORTANT: You will be asked to change this password on first login.

Log in with your phone number as username.

Questions? Contact your barangay health center.''';

      return SmsService.sendSmsMessage(phoneNumber, message);
    } catch (e) {
      if (kDebugMode) print('SMS credential error: $e');
      return false;
    }
  }
}