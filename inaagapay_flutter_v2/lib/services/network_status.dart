// lib/services/network_status.dart
//
// Telling "there is no connection" apart from every other failure.
//
// Screens used to find out they were offline in one of two ways, both wrong:
// they printed the raw exception ("ClientException with SocketException:
// Failed host lookup: ...supabase.co") at a mother or a midwife, or they
// swallowed it and drew the page anyway, with "None" and "Not recorded" where
// the missing values should have been. Worse, on a Wi-Fi network that has no
// internet behind it a request did not fail at all: it waited for the
// operating system's TCP timeout, which can be minutes, and a save button sat
// on "Saving…" the whole time.
//
// This gives the Supabase client a bounded connection attempt, and gives every
// screen one way to recognise a connection failure and one way to say it.

import 'dart:async';

import 'package:http/http.dart' as http;

import 'language_service.dart';
import 'network_status_stub.dart'
    if (dart.library.io) 'network_status_io.dart' as platform;

class NetworkStatus {
  const NetworkStatus._();

  /// How long to wait for the server to accept a connection.
  ///
  /// Generous on purpose: midwives work on weak rural signal, and a slow
  /// connection that does come up must not be abandoned. It bounds only the
  /// connection attempt, never a transfer that is already moving, so a large
  /// upload is unaffected.
  static const Duration connectTimeout = Duration(seconds: 20);

  /// The HTTP client handed to Supabase.initialize.
  static http.Client httpClient() =>
      platform.createHttpClient(connectTimeout);

  /// True when [error] means the server could not be reached, as opposed to
  /// the server answering with a refusal.
  static bool isNetworkError(Object error) {
    if (error is TimeoutException) return true;
    if (error is http.ClientException) return true;
    if (platform.isSocketError(error)) return true;
    // Supabase and our own services wrap the original exception in a message,
    // so the type is often lost by the time a screen sees it.
    final text = error.toString();
    const markers = [
      'SocketException',
      'ClientException',
      'Failed host lookup',
      'Connection refused',
      'Connection reset',
      'Connection closed',
      'Connection timed out',
      'Network is unreachable',
      'HandshakeException',
      'TimeoutException',
      // GroqService's own wrapper for a ClientException. Without it a scan
      // made offline showed "Network error: Unable to reach Groq API", naming
      // the AI provider and dropping the line that the form can still be
      // filled in by hand.
      'Unable to reach',
    ];
    return markers.any(text.contains);
  }

  /// Whether the Supabase server can be reached right now.
  ///
  /// A name lookup, not a request: it costs no database egress, so it is
  /// cheap enough to repeat while a screen waits for the connection to return.
  static Future<bool> isOnline() => platform.canReachServer();

  /// The sentence shown for a connection failure, in the app's language.
  static String offlineMessage() => LanguageService.translate(
        'No internet connection. Please check your connection and try again.',
        'Walang koneksyon sa internet. Pakisuri ang koneksyon at subukan muli.',
      );

  /// What to show a person for [error]: the connection sentence when that is
  /// the cause, otherwise [english] / [filipino] -- never the exception text,
  /// which names tables, hosts and drivers and is always in English.
  static String friendlyError(
    Object error, {
    String english = 'Something went wrong. Please try again.',
    String filipino = 'May nangyaring mali. Pakisubukan muli.',
  }) {
    if (isNetworkError(error)) return offlineMessage();
    return LanguageService.translate(english, filipino);
  }
}
