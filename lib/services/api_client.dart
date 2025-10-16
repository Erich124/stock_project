import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;
  ApiClient({String? baseUrl})
      : baseUrl = baseUrl ?? 'http://127.0.0.1:8000'; // change to 10.0.2.2 on Android

  Future<List<dynamic>> getReddit(String t, {int days=14, int limit=50}) async {
    final u = Uri.parse('$baseUrl/reddit?ticker=$t&days=$days&limit=$limit');
    final r = await http.get(u);
    if (r.statusCode != 200) return [];
    return jsonDecode(r.body) as List;
  }

  Future<Map<String,dynamic>> getSentiment(String t, {int days=14}) async {
    final u = Uri.parse('$baseUrl/sentiment?ticker=$t&days=$days');
    final r = await http.get(u);
    if (r.statusCode != 200) return {"series": [], "summary": {"avg":0,"label":"Neutral"}, "count":0};
    return jsonDecode(r.body) as Map<String,dynamic>;
  }
}
