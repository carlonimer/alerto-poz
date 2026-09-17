import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Set this to your computer's IP address when testing on physical device
  // e.g. 'http://192.168.1.X:3000' or Render URL
  // static const String baseUrl = 'https://alerto-poz.onrender.com'; // Production
  // static const String baseUrl = 'http://localhost:3000'; // Web / iOS Emulator
  static const String baseUrl = 'http://192.168.100.131:3000'; // Local Network IP (Works for Web & Physical Phone)

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

  /// Web: fetch(`${SERVER_URL}/api/auth/register`, { method: "POST", body: JSON.stringify({name, email, phone, password, registrationMethod}) })
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
        'phone': phone.isNotEmpty ? phone : null,
        'email': email.isNotEmpty ? email : null,
        'password': password,
        'registrationMethod': phone.isNotEmpty ? 'phone' : 'email',
      }),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Web: fetch(`${SERVER_URL}/api/auth/login`, { method: "POST", body: JSON.stringify({loginId, password}) })
  /// NOTE: Web response returns {otpRequired: true, target: ...} when OTP is needed (NOT {success: true})
  static Future<Map<String, dynamic>> login({
    required String identifier, // phone or email
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: await _getHeaders(),
      body: jsonEncode({'loginId': identifier, 'password': password}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    // Include HTTP status code so callers can check for errors
    data['_statusCode'] = res.statusCode;
    return data;
  }

  /// Web: fetch(`${SERVER_URL}/api/auth/verify-otp`, { method: "POST", body: JSON.stringify({target, code, type}) })
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

  /// Web: fetch(`${SERVER_URL}/api/auth/resend-otp`, { method: "POST", body: JSON.stringify({target, type}) })
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

  /// Web: fetch(`${SERVER_URL}/api/auth/forgot-password`, { method: "POST", body: JSON.stringify({target}) })
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

  /// Web: fetch(`${SERVER_URL}/api/auth/reset-password`, { method: "POST", body: JSON.stringify({target, token, password}) })
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
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final res = await http.post(
      Uri.parse('$baseUrl/api/auth/validate'),
      headers: await _getHeaders(),
      body: jsonEncode({'token': token}),
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

  /// Web: fetch(`${SERVER_URL}/api/user/passcode`, { method: "POST", body: JSON.stringify({id, currentPasscode, newPasscode}) })
  /// Matches web's savePasscode() which sends currentPasscode + newPasscode
  static Future<Map<String, dynamic>> savePasscode({
    required String userId,
    String? currentPasscode,
    required String newPasscode,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/user/passcode'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode({
        'id': userId,
        'currentPasscode': currentPasscode ?? '',
        'newPasscode': newPasscode,
      }),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Legacy — kept for backward compatibility
  static Future<Map<String, dynamic>> setupPasscode(String userId, String passcode) async {
    return savePasscode(userId: userId, newPasscode: passcode);
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

  /// Web: fetch(`${SERVER_URL}/api/incidents/draft`, { method: 'POST', body: JSON.stringify({reporterId, reporterPhone, lat, lng, reporter, createdAt}) })
  static Future<Map<String, dynamic>> createDraftIncident(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/incidents/draft'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode(data),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    body['_statusCode'] = res.statusCode;
    return body;
  }

  static Future<Map<String, dynamic>> deleteDraftIncident(String userId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/incidents/draft/$userId'),
      headers: await _getHeaders(auth: true),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Web: fetch(`${SERVER_URL}/api/incidents/${id}/cancel`, { method: 'POST', body: JSON.stringify({userId, phone, passcode}) })
  /// Returns 401 + {passcodeRequired: true} if passcode needed
  static Future<Map<String, dynamic>> cancelIncident(
    String incidentId, {
    required String userId,
    required String phone,
    String? passcode,
  }) async {
    final body = <String, dynamic>{
      'userId': userId,
      'phone': phone,
    };
    if (passcode != null && passcode.isNotEmpty) {
      body['passcode'] = passcode;
    }

    final res = await http.post(
      Uri.parse('$baseUrl/api/incidents/$incidentId/cancel'),
      headers: await _getHeaders(auth: true),
      body: jsonEncode(body),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    data['_statusCode'] = res.statusCode;
    return data;
  }

  /// Web: fetch(`${SERVER_URL}/api/incidents/${id}/messages`)
  static Future<Map<String, dynamic>> fetchMessages(String incidentId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/incidents/$incidentId/messages'),
      headers: await _getHeaders(auth: true),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Web: POST /api/incidents/${id}/messages with FormData containing senderId, senderRole, messageType, messageContent/media
  static Future<Map<String, dynamic>> sendMessage(
    String incidentId,
    Map<String, dynamic> data, {
    String? mediaPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/incidents/$incidentId/messages'),
    );
    // Don't set Content-Type for multipart — it's auto-set with boundary
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Always include senderRole and messageType matching web's postMessagesAndMedia()
    request.fields['senderId'] = data['senderId']?.toString() ?? '';
    request.fields['senderRole'] = data['senderRole']?.toString() ?? 'Citizen App';
    request.fields['messageType'] = data['messageType']?.toString() ?? 'text';
    if (data['messageContent'] != null) {
      request.fields['messageContent'] = data['messageContent'].toString();
    }

    if (mediaPath != null) {
      request.files.add(await http.MultipartFile.fromPath('media', mediaPath));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ───────── History ─────────

  /// Web: fetch(`${SERVER_URL}/api/user/history/${this.activeUser.id}`)
  static Future<List<dynamic>> getHistory(String userId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/user/history/$userId'),
        headers: await _getHeaders(auth: true),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) return data;
        if (data is Map && data['incidents'] != null) return data['incidents'] as List;
        return [];
      }
      return [];
    } catch (_) {
      return [];
    }
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
