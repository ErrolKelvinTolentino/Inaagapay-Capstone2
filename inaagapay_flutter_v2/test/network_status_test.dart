import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:inaagapay_flutter_v2/services/language_service.dart';
import 'package:inaagapay_flutter_v2/services/network_status.dart';

void main() {
  group('recognising a lost connection', () {
    test('the wrapped form Supabase throws is a network error', () {
      // What a PostgREST call raises with the phone in airplane mode: the
      // socket error arrives wrapped, so only the text survives.
      expect(
        NetworkStatus.isNetworkError(Exception(
            'ClientException with SocketException: Failed host lookup: '
            "'example.supabase.co' (OS Error: No address associated with "
            'hostname, errno = 7)')),
        isTrue,
      );
    });

    test('socket, client and timeout errors are network errors', () {
      expect(NetworkStatus.isNetworkError(const SocketException('down')), isTrue);
      expect(NetworkStatus.isNetworkError(http.ClientException('reset')), isTrue);
      expect(NetworkStatus.isNetworkError(TimeoutException('slow')), isTrue);
    });

    test('a refusal from the server is not', () {
      expect(
        NetworkStatus.isNetworkError(
            Exception('duplicate key value violates unique constraint')),
        isFalse,
      );
    });
  });

  group('what the person is shown', () {
    tearDown(() => LanguageService.selectedLanguage.value = AppLanguage.english);

    test('never the exception text', () {
      final message = NetworkStatus.friendlyError(
        Exception('PostgrestException(message: relation "x" does not exist)'),
        english: 'Could not load.',
        filipino: 'Hindi ma-load.',
      );
      expect(message, 'Could not load.');
    });

    test('the connection sentence, in the chosen language', () {
      LanguageService.selectedLanguage.value = AppLanguage.filipino;
      expect(
        NetworkStatus.friendlyError(const SocketException('down')),
        startsWith('Walang koneksyon sa internet'),
      );
    });
  });
}
