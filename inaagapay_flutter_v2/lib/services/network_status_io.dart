import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createHttpClient(Duration connectTimeout) {
  final inner = HttpClient()..connectionTimeout = connectTimeout;
  return IOClient(inner);
}

bool isSocketError(Object error) =>
    error is SocketException ||
    error is HandshakeException ||
    error is HttpException;

Future<bool> canReachServer() async {
  final host = Uri.tryParse(dotenv.env['SUPABASE_URL']?.trim() ?? '')?.host;
  try {
    final addresses = await InternetAddress.lookup(
      (host == null || host.isEmpty) ? 'supabase.co' : host,
    ).timeout(const Duration(seconds: 5));
    return addresses.isNotEmpty && addresses.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
