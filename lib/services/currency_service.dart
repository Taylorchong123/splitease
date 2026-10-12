import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches exchange rates (units per 1 USD) from a free public endpoint.
/// Swap the URL for your preferred provider; cache the result in production.
class CurrencyService {
  CurrencyService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Map<String, double>? _cache;
  DateTime? _fetchedAt;

  Future<Map<String, double>> latestRates() async {
    final fresh = _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(hours: 6);
    if (_cache != null && fresh) return _cache!;

    final res = await _client.get(Uri.parse('https://open.er-api.com/v6/latest/USD'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load exchange rates (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final rates = (body['rates'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
    _cache = rates;
    _fetchedAt = DateTime.now();
    return rates;
  }
}
