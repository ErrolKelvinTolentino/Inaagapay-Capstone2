import 'package:http/http.dart' as http;

// Web: the browser owns the connection and its timeouts, and there is no
// lookup to make, so the answer is left to the requests themselves.
http.Client createHttpClient(Duration connectTimeout) => http.Client();

bool isSocketError(Object error) => false;

Future<bool> canReachServer() async => true;
