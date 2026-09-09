import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Set this to your computer's IP address when testing on physical device
  // e.g. 'http://192.168.1.X:3000' or Render URL
  static const String baseUrl = 'https://alerto-poz.onrender.com';

  static Future<Map<String, String>> _getHeaders({bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // ───────── Auth ─────────

  static Future<Map<String, dynamic>> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'name': name,
        'phone': phone,
        'email': email,
        'password': password,
      }),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> login({
    required String identifier, // phone or email
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: await _getHeaders(),
      body: jsonEncode({'identifier': identifier, 'password': password}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyOtp({
    required String identifier,
    required String otp,
    required String type,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-otp'),
      headers: await _getHeaders(),
      body: jsonEncode({'target': identifier, 'code': otp, 'type': type}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> resendOtp({
    required String identifier,
    required String type,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/resend-otp'),
      headers: await _getHeaders(),
      body: jsonEncode({'target': identifier, 'type': type}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> forgotPassword({
    required String identifier,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: await _getHeaders(),
      body: jsonEncode({'target': identifier}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> resetPassword({
    required String identifier,
    required String token,
    required String newPassword,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/reset-password'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'target': identifier,
        'token': token,
        'password': newPassword,
      }),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> validateSession() async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/validate'),
      headers: await _getHeaders(auth: true),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ───────── User Profile & Settings ─────────

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/user/profile'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode(data),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateProfilePicture(String userId, String filePath) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/user/profile-picture'),
    );
    final headers = await _getHeaders(auth: true);
    request.headers.addAll(headers);
    request.fields['id'] = userId;
    request.files.add(await http.MultipartFile.fromPath('profile_image', filePath));
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> saveMapSettings(String userId, String mapType) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/user/map-settings'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode({'id': userId, 'mapType': mapType}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> submitFeedback(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/feedback'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode(data),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> setupPasscode(String userId, String passcode) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/user/passcode'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode({'id': userId, 'passcode': passcode}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyPasscode(String userId, String passcode) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/user/passcode/verify'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode({'id': userId, 'passcode': passcode}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ───────── Incidents ─────────

  static Future<List<dynamic>> getIncidents() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/incidents'),
        headers: await _getHeaders(auth: true),
      );
      final data = jsonDecode(res.body);
      return data['incidents'] ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> checkActiveIncident(String userId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/incidents/active/$userId'),
      headers: await _getHeaders(auth: true),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createDraftIncident(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/incidents/draft'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode(data),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> deleteDraftIncident(String userId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/incidents/draft/$userId'),
      headers: await _getHeaders(auth: true),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> cancelIncident(String incidentId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/incidents/$incidentId/cancel'),
      headers: await _getHeaders(auth: true),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> fetchMessages(String incidentId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/incidents/$incidentId/messages'),
      headers: await _getHeaders(auth: true),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> sendMessage(String incidentId, Map<String, dynamic> data, {String? mediaPath}) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/incidents/$incidentId/messages'),
    );
    final headers = await _getHeaders(auth: true);
    request.headers.addAll(headers);
    
    data.forEach((key, value) {
      if (value != null) {
        request.fields[key] = value.toString();
      }
    });

    if (mediaPath != null) {
      request.files.add(await http.MultipartFile.fromPath('media', mediaPath));
    }
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ───────── Responders ─────────

  static Future<List<dynamic>> getResponders() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/responders'),
        headers: await _getHeaders(auth: true),
      );
      final data = jsonDecode(res.body);
      return data['responders'] ?? [];
    } catch (_) {
      return [];
    }
  }

  // ───────── Broadcasts ─────────

  static Future<List<dynamic>> getBroadcasts() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/broadcasts'),
        headers: await _getHeaders(auth: true),
      );
      final data = jsonDecode(res.body);
      return data['broadcasts'] ?? [];
    } catch (_) {
      return [];
    }
  }

  // ───────── Session helpers ─────────

  static Future<void> saveSession({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_data', jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data');
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
  }
}
