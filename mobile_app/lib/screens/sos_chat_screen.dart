import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import 'call_screen.dart';

/// Colour tokens for the ALERTO-POZ emergency chat (orange emergency theme).
class _C {
  static const orange = Color(0xFFFF9800);
  static const red = Color(0xFFE53935);
  static const redDeep = Color(0xFFD32F2F);
  static const ink = Color(0xFF1F2937);
  static const inkSoft = Color(0xFF4B5563);
  static const muted = Color(0xFF6B7280);
  static const background = Color(0xFFF3F4F6);
  static const divider = Color(0xFFE5E7EB);
  static const chip = Color(0xFFEEF0F4);
  static const botBubble = Color(0xFFB8C9E0);
  static const userBubble = Color(0xFF0B63CE);
  static const send = Color(0xFF22C55E);
  static const online = Color(0xFF16A34A);
  static const pending = Color(0xFFF59E0B);
}

class SosChatScreen extends StatefulWidget {
  final UserModel? user;
  final Map<String, dynamic>? activeIncident;
  final String? initialCategory;

  const SosChatScreen({super.key, required this.user, this.activeIncident, this.initialCategory});

  @override
  State<SosChatScreen> createState() => _SosChatScreenState();
}

class _SosChatScreenState extends State<SosChatScreen> with TickerProviderStateMixin {
  final _commentCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final MapController _mapController = MapController();
  late final AnimationController _pulseCtrl;

  static const LatLng _defaultCenter = LatLng(16.1086, 120.5424); // Pozorrubio
  static const String _fallbackAddress = 'Buneg, Pozorrubio, Pangasinan';

  String? _incidentId;
  String? _selectedCategory;
  String? _ticketCode;
  String? _assignedUnit;
  bool _sent = false;
  bool _sending = false;
  bool _cancelled = false; // New cancelled state
  bool _hasText = false;
  DateTime _createdAt = DateTime.now();
  final List<Map<String, dynamic>> _chatFeed = [];
  final List<String> _attachedImages = []; // base64 strings

  bool _isMapExpanded = true;
  String _mapLayer = 'Standard'; // Standard, Satellite, Terrain
  Position? _currentPos;
  LatLng? _incidentPos;
  String _currentAddress = 'Locating...';

  static const List<Map<String, dynamic>> _categories = [
    {'key': 'medical', 'label': 'MEDICAL', 'icon': Icons.medical_services_rounded, 'color': Color(0xFFE53935)},
    {'key': 'fire', 'label': 'FIRE', 'icon': Icons.local_fire_department_rounded, 'color': Color(0xFFF4511E)},
    {'key': 'police', 'label': 'POLICE', 'icon': Icons.shield_rounded, 'color': Color(0xFF1D4ED8)},
    {'key': 'barangay', 'label': 'BARANGAY', 'icon': Icons.house_rounded, 'color': Color(0xFF059669)},
    {'key': 'road_crash', 'label': 'ROADCRASH', 'icon': Icons.car_crash_rounded, 'color': Color(0xFFD97706)},
    {'key': 'report', 'label': 'REPORT', 'icon': Icons.error_rounded, 'color': Color(0xFF475569)},
  ];

  static const Map<String, String> _tileUrls = {
    'Standard': 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
    'Satellite': 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
    'Terrain': 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}',
  };

  // ───────────────────────── Lifecycle ─────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _commentCtrl.addListener(() {
      final has = _commentCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });

    _initLocation();

    if (widget.activeIncident != null) {
      final inc = widget.activeIncident!;
      _incidentId = inc['_id']?.toString() ?? inc['id']?.toString();
      _selectedCategory = inc['category'];
      _ticketCode = inc['ticketCode']?.toString() ?? inc['id']?.toString() ?? _incidentId;
      _assignedUnit = inc['assignedUnit']?.toString();
      _createdAt = DateTime.tryParse((inc['timestamp'] ?? inc['createdAt'] ?? '').toString())?.toLocal() ?? DateTime.now();
      final lat = double.tryParse('${inc['lat'] ?? ''}');
      final lng = double.tryParse('${inc['lng'] ?? ''}');
      if (lat != null && lng != null) _incidentPos = LatLng(lat, lng);
      _sent = true;
      if (inc['status'] == 'cancelled') {
        _cancelled = true;
      }
      _chatFeed.add({
        'role': 'bot',
        'type': 'system',
        'content': 'Emergency report prepared by ${(widget.user?.name ?? 'USER').toUpperCase()}',
      });
      _fetchHistory();
    } else {
      _chatFeed.add({
        'role': 'bot',
        'type': 'system',
        'content': 'Ano ang maipaglilingkod namin?',
      });

      if (widget.initialCategory != null) {
        final cat = _categories.firstWhere((c) => c['key'] == widget.initialCategory, orElse: () => _categories.last);
        _selectCategory(cat['key'] as String, cat['label'] as String);
      }
    }

    SocketService.on('chat-message', _onChatMessage);
    SocketService.on('incident-cancelled', _onIncidentCancelled);
    SocketService.on('incident-updated', _onIncidentUpdated);
  }

  @override
  void dispose() {
    SocketService.off('chat-message', _onChatMessage);
    SocketService.off('incident-cancelled', _onIncidentCancelled);
    SocketService.off('incident-updated', _onIncidentUpdated);
    _pulseCtrl.dispose();
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────── Socket handlers ─────────────────────────

  void _onChatMessage(dynamic data) {
    if (data is! Map || data['incident_id'] != _incidentId || !mounted) return;
    setState(() {
      _chatFeed.add({
        'role': data['sender_id'] == widget.user?.id.toString() ? 'user' : 'bot',
        'type': data['is_media'] == true ? 'image' : 'text',
        'content': data['message'],
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();
  }

  void _onIncidentCancelled(dynamic data) {
    if (data is! Map || data['id'] != _incidentId || !mounted) return;
    setState(() => _cancelled = true);
    // We do not pop the context here to match web app behavior where user sees the cancelled message
    _toast('Incident has been cancelled.');
  }

  void _onIncidentUpdated(dynamic data) {
    if (data is! Map || _incidentId == null || data['id']?.toString() != _incidentId || !mounted) return;
    setState(() {
      final unit = data['assignedUnit']?.toString();
      if (unit != null && unit.isNotEmpty) _assignedUnit = unit;
      if ((data['status'] ?? '').toString().toLowerCase() == 'cancelled') _cancelled = true;
    });
  }

  // ───────────────────────── Location ─────────────────────────

  LatLng? get _markerPos =>
      _currentPos != null ? LatLng(_currentPos!.latitude, _currentPos!.longitude) : _incidentPos;

  Future<void> _initLocation() async {
    if (mounted && _currentPos == null) setState(() => _currentAddress = 'Locating...');
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _currentPos = pos;
        _currentAddress = 'Locating...';
      });
      _moveMap(LatLng(pos.latitude, pos.longitude), 15.0);
      _resolveAddress(pos.latitude, pos.longitude);
    } else if (_incidentPos != null) {
      setState(() => _currentAddress = 'Locating...');
      _moveMap(_incidentPos!, 15.0);
      _resolveAddress(_incidentPos!.latitude, _incidentPos!.longitude);
    } else {
      setState(() => _currentAddress = 'Location unavailable · tap to retry');
    }
  }

  /// Best-effort reverse geocode to "Barangay, Town, Province".
  Future<void> _resolveAddress(double lat, double lng) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1');
      final res = await http
          .get(uri, headers: {'User-Agent': 'com.alertopoz.app', 'Accept-Language': 'en'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
         if (mounted && _currentAddress == 'Locating...') setState(() => _currentAddress = 'Unknown Location');
         return;
      }
      final addr = Map<String, dynamic>.from(jsonDecode(res.body)['address'] ?? {});
      
      var barangay = addr['village'] ?? addr['suburb'] ?? addr['quarter'] ?? addr['hamlet'] ?? addr['neighbourhood'] ?? addr['city_district'] ?? '';
      var town = addr['town'] ?? addr['municipality'] ?? addr['city'] ?? addr['county'] ?? '';
      var province = addr['province'] ?? addr['state'] ?? addr['region'] ?? '';

      var brgyStr = barangay.toString();
      if (brgyStr.toLowerCase().startsWith('barangay ')) {
        brgyStr = brgyStr.substring(9).trim();
      }

      final parts = <String>[];
      if (brgyStr.isNotEmpty) parts.add(brgyStr);
      if (town.toString().isNotEmpty) parts.add(town.toString());
      if (province.toString().isNotEmpty) parts.add(province.toString());
      
      if (parts.isNotEmpty && mounted) {
        setState(() => _currentAddress = parts.join(', '));
      } else if (mounted) {
        setState(() => _currentAddress = 'Unknown Location');
      }
    } catch (_) {
      if (mounted && _currentAddress == 'Locating...') setState(() => _currentAddress = 'Unknown Location');
    }
  }

  void _moveMap(LatLng target, double zoom) {
    try {
      _mapController.move(target, zoom);
    } catch (_) {
      // Map not attached yet – initialCenter will handle the first frame.
    }
  }

  void _recenterMap() {
    final p = _markerPos;
    if (p == null) {
      _initLocation();
      return;
    }
    if (!_isMapExpanded) setState(() => _isMapExpanded = true);
    _moveMap(p, 16.0);
  }

  void _zoomBy(double delta) {
    try {
      final cam = _mapController.camera;
      _mapController.move(cam.center, (cam.zoom + delta).clamp(3.0, 19.0));
    } catch (_) {}
  }

  // ───────────────────────── Chat logic ─────────────────────────

  Future<void> _fetchHistory() async {
    if (_incidentId == null) return;
    try {
      final res = await ApiService.fetchMessages(_incidentId!);
      if (res['success'] == true && mounted) {
        final msgs = res['messages'] as List;
        setState(() {
          for (var msg in msgs) {
            _chatFeed.add({
              'role': msg['senderId']?.toString() == widget.user?.id.toString() ? 'user' : 'bot',
              'type': msg['isMedia'] == true ? 'image' : 'text',
              'content': msg['content'],
              'timestamp': msg['createdAt'] ?? DateTime.now().toIso8601String(),
            });
          }
        });
        _scrollToBottom();
      }
    } catch (e) {/* best-effort: ignore network errors */}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.outfit()),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
  }

  void _copyTicket() {
    final code = _sent ? (_ticketCode ?? _incidentId) : 'DRAFT-5';
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    _toast('Copied $code');
  }

  void _selectCategory(String key, String label) async {
    if (_sent || _sending) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedCategory = key;
      _chatFeed.add({
        'role': 'user',
        'type': 'text',
        'content': 'Selected Category: $label',
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();
    _sendSos(); // Directly trigger transmission to match UI flow
  }

  Future<void> _attachGalleryImage() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (file != null) {
      await _handleImageTaken(file.path);
    }
  }

  Future<void> _handleImageTaken(String path) async {
    final bytes = await File(path).readAsBytes();
    final b64 = base64Encode(bytes);

    if (!mounted) return;
    setState(() {
      _attachedImages.add(b64);
      _chatFeed.add({
        'role': 'user',
        'type': 'image',
        'content': b64,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();

    if (!_sent) {
      _selectedCategory = 'other';
      final pos = await LocationService.getCurrentPosition();
      await _doTransmit(pos);
    }

    if (_sent && _incidentId != null) {
      try {
        await ApiService.sendMessage(
          _incidentId!,
          {'senderId': widget.user?.id, 'content': 'Image Attachment'},
          mediaPath: path,
        );
      } catch (e) {/* best-effort: ignore network errors */}
    }
  }

  Future<void> _sendSos() async {
    if (_selectedCategory == null) return;
    final pos = await LocationService.getCurrentPosition();
    await _doTransmit(pos);
  }

  /// Emits the SOS report and waits for the server acknowledgement so we get
  /// the real ticket number (used as the incident id for follow-up messages).
  Future<void> _doTransmit(dynamic pos) async {
    if (_sending) return;
    setState(() => _sending = true);
    _scrollToBottom();

    final payload = {
      'id': _incidentId,
      'reporterId': widget.user?.id ?? 0,
      'reporterName': widget.user?.name ?? 'Citizen',
      'reporterPhone': widget.user?.phone ?? '',
      'category': _selectedCategory,
      'lat': pos?.latitude ?? _markerPos?.latitude ?? _defaultCenter.latitude,
      'lng': pos?.longitude ?? _markerPos?.longitude ?? _defaultCenter.longitude,
      'notes': _commentCtrl.text.trim(),
      'attachments': _attachedImages,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    };

    final completer = Completer<dynamic>();
    SocketService.emitSosReportWithAck(payload, (res) {
      if (!completer.isCompleted) completer.complete(res);
    });

    dynamic res;
    try {
      res = await completer.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      res = null;
    }
    if (res is List && res.isNotEmpty) res = res.first;
    final ticket = (res is Map && res['success'] == true) ? res['ticketNumber']?.toString() : null;

    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
      _createdAt = DateTime.now();
      if (ticket != null) {
        _incidentId = ticket;
        _ticketCode = ticket;
      } else {
        _ticketCode ??= 'ALERTOPOZ-26-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
      }
      _chatFeed.add({
        'role': 'bot',
        'type': 'activated',
        'content': '',
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();
  }

  Future<void> _sendChatMessage() async {
    final txt = _commentCtrl.text.trim();
    if (txt.isEmpty) return;

    setState(() {
      _chatFeed.add({
        'role': 'user',
        'type': 'text',
        'content': txt,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    _commentCtrl.clear();
    _scrollToBottom();

    if (!_sent) {
      _selectedCategory = 'other';
      final pos = await LocationService.getCurrentPosition();
      await _doTransmit(pos);
    }

    if (_incidentId != null) {
      try {
        await ApiService.sendMessage(_incidentId!, {
          'senderId': widget.user?.id,
          'content': txt,
        });
      } catch (e) {/* best-effort: ignore network errors */}
    }
  }

  Future<void> _cancelIncident() async {
    if (_incidentId == null) return;
    try {
      await ApiService.cancelIncident(
        _incidentId!,
        userId: widget.user?.id.toString() ?? '',
        phone: widget.user?.phone ?? '',
      );
      if (mounted) {
        setState(() {
          _cancelled = true;
          _chatFeed.add({
            'role': 'bot',
            'type': 'system',
            'content': 'Incident has been marked as cancelled by the command center. Session will end shortly.',
            'timestamp': DateTime.now().toIso8601String(),
          });
          _chatFeed.add({
            'role': 'bot',
            'type': 'system',
            'content': '✅ Incident Cancelled Your incident has been successfully closed.',
            'timestamp': DateTime.now().toIso8601String(),
          });
        });
        _scrollToBottom();
      }
    } catch (e) {/* best-effort: ignore network errors */}
  }

  void _openCall({required bool video}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CallScreen(user: widget.user, isVideo: video)),
    );
  }

  // ───────────────────────── Dialogs ─────────────────────────

  void _showCameraDialog() {
    String? tempImagePath;
    bool useFrontCamera = false;

    Widget actionBtn(String label, Color color, VoidCallback onTap) => Expanded(
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(label, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          Future<void> capture() async {
            final picker = ImagePicker();
            final file = await picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 60,
              preferredCameraDevice: useFrontCamera ? CameraDevice.front : CameraDevice.rear,
            );
            if (file != null) setDialogState(() => tempImagePath = file.path);
          }

          return Dialog(
            backgroundColor: const Color(0xFF232736),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Capture Photo',
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            Container(height: 3, width: 48, color: _C.orange, margin: const EdgeInsets.only(top: 6)),
                          ],
                        ),
                      ),
                      Material(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setDialogState(() => useFrontCamera = !useFrontCamera),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                Text(useFrontCamera ? 'Front' : 'Rear',
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: tempImagePath == null ? capture : null,
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: tempImagePath != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Image.file(File(tempImagePath!), fit: BoxFit.cover, width: double.infinity),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.camera_alt_rounded, color: Colors.white38, size: 48),
                                  const SizedBox(height: 8),
                                  Text('Tap to open camera',
                                      style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (tempImagePath == null)
                    Row(children: [
                      actionBtn('Capture', const Color(0xFF2196F3), capture),
                      const SizedBox(width: 10),
                      actionBtn('Cancel', const Color(0xFFF44336), () => Navigator.pop(context)),
                    ])
                  else
                    Row(children: [
                      actionBtn('Retake', _C.orange, () => setDialogState(() => tempImagePath = null)),
                      const SizedBox(width: 8),
                      actionBtn('Confirm', const Color(0xFF10B981), () {
                        Navigator.pop(context); // Close dialog
                        _handleImageTaken(tempImagePath!); // Send image
                      }),
                      const SizedBox(width: 8),
                      actionBtn('Cancel', const Color(0xFFF44336), () => Navigator.pop(context)),
                    ]),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _showCloseIncidentDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Close Incident', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                Container(height: 2, width: double.infinity, color: _C.orange),
                const SizedBox(height: 16),
                Text(
                    'Are you sure you want to cancel this incident?\nThis will notify the Command Center that you have cancelled the emergency.',
                    style: GoogleFonts.outfit(color: Colors.black87, fontSize: 14)),
                const SizedBox(height: 16),
                Text('Enter Passcode:', style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 8),
                TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _C.orange),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _cancelIncident();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF44336),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Text('Confirm Close Incident',
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openImage(ImageProvider image) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Stack(
          children: [
            Center(child: InteractiveViewer(child: Image(image: image))),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Formatting ─────────────────────────

  String _formatDate(DateTime d) => DateFormat('MMM dd, yyyy, hh:mm a').format(d);

  String _formatStamp(String? isoDate) {
    if (isoDate == null) return '';
    final d = DateTime.tryParse(isoDate)?.toLocal() ?? DateTime.now();
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    return DateFormat(sameDay ? 'hh:mm a' : 'MMM dd, hh:mm a').format(d);
  }

  String get _responderLabel {
    if (_cancelled) return 'Incident closed';
    if (_assignedUnit != null && _assignedUnit!.isNotEmpty) return 'Responder: $_assignedUnit';
    return _sent ? 'Awaiting responder…' : 'No active responder';
  }

  Color get _responderColor {
    if (_cancelled) return Colors.grey;
    if (_assignedUnit != null && _assignedUnit!.isNotEmpty) return _C.online;
    return _sent ? _C.pending : Colors.grey;
  }

  // ───────────────────────── Header ─────────────────────────

  PreferredSizeWidget _buildAppBar() {
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      leadingWidth: 44,
      titleSpacing: canPop ? 0 : 16,
      leading: canPop
          ? IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _C.inkSoft),
              onPressed: () => Navigator.maybePop(context),
            )
          : null,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cell_tower_rounded, color: _C.red, size: 20),
              const SizedBox(width: 4),
              Flexible(
                child: Text('Alerto-poz',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 20, color: _C.ink)),
              ),
              const SizedBox(width: 6),
              _buildStatusLabel(),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: _responderColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(_responderLabel,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(color: _C.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Voice call',
          icon: const Icon(Icons.phone_rounded, color: _C.inkSoft),
          onPressed: () => _openCall(video: false),
        ),
        IconButton(
          tooltip: 'Video call',
          icon: const Icon(Icons.videocam_rounded, color: _C.inkSoft),
          onPressed: () => _openCall(video: true),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded, color: _C.inkSoft),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (value) {
            switch (value) {
              case 'recenter':
                _recenterMap();
                break;
              case 'copy':
                _copyTicket();
                break;
              case 'close':
                _showCloseIncidentDialog();
                break;
              case 'discard':
                Navigator.maybePop(context);
                break;
            }
          },
          itemBuilder: (context) => [
            _menuItem('recenter', Icons.my_location_rounded, 'Recenter map'),
            if (_sent) _menuItem('copy', Icons.copy_rounded, 'Copy ticket code'),
            if (_sent && !_cancelled) _menuItem('close', Icons.cancel_rounded, 'Close Incident', color: Colors.red),
            if (!_sent) _menuItem('discard', Icons.delete_outline_rounded, 'Discard draft', color: Colors.red),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: _C.divider),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {Color color = _C.ink}) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStatusLabel() {
    if (!_sent && !_cancelled) {
      return Text('draft', style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 17, color: _C.inkSoft));
    }
    final label = _cancelled ? 'cancelled' : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12, color: _C.redDeep)),
    );
  }

  // ───────────────────────── Location bar & map ─────────────────────────

  Widget _buildLocationBar() {
    return Material(
      color: _C.orange,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _recenterMap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: _C.redDeep, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_currentAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(color: _C.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Map layers',
              icon: const Icon(Icons.layers_rounded, color: _C.ink, size: 22),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (value) => setState(() {
                _mapLayer = value;
                _isMapExpanded = true;
              }),
              itemBuilder: (_) => [
                _buildLayerMenuItem('Standard', Icons.map_outlined),
                _buildLayerMenuItem('Satellite', Icons.satellite_alt_outlined),
                _buildLayerMenuItem('Terrain', Icons.terrain_outlined),
              ],
            ),
            IconButton(
              tooltip: _isMapExpanded ? 'Hide map' : 'Show map',
              onPressed: () => setState(() => _isMapExpanded = !_isMapExpanded),
              icon: AnimatedRotation(
                turns: _isMapExpanded ? 0 : 0.5,
                duration: const Duration(milliseconds: 250),
                child: const Icon(Icons.keyboard_arrow_up_rounded, color: _C.ink, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildLayerMenuItem(String title, IconData icon) {
    final isSelected = _mapLayer == title;
    return PopupMenuItem<String>(
      value: title,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? _C.orange.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFFE65100) : _C.ink, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: GoogleFonts.outfit(
                      color: isSelected ? const Color(0xFFE65100) : _C.ink,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
            ),
            if (isSelected) const Icon(Icons.check_rounded, color: Color(0xFFE65100), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(double height, double fullHeight) {
    final marker = _markerPos;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: height,
      child: ClipRect(
        // Keep the map at a constant size while the container animates so the
        // MapController stays attached and tiles don't re-layout at 0 height.
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: fullHeight,
          maxHeight: fullHeight,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: marker ?? _defaultCenter,
                  initialZoom: 15.0,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                ),
                children: [
                  TileLayer(
                    key: ValueKey(_mapLayer),
                    urlTemplate: _tileUrls[_mapLayer],
                    userAgentPackageName: 'com.alertopoz.app',
                  ),
                  if (marker != null)
                    MarkerLayer(
                      markers: [
                        Marker(point: marker, width: 64, height: 64, child: _buildPulseMarker()),
                      ],
                    ),
                ],
              ),
              if (marker == null)
                Positioned(
                  left: 12,
                  top: 12,
                  child: _mapPill(
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(
                          width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: _C.orange)),
                      const SizedBox(width: 8),
                      Text('Finding your location…',
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: _C.ink)),
                    ]),
                  ),
                ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Column(
                  children: [
                    _mapButton(Icons.add_rounded, 'Zoom in', () => _zoomBy(1)),
                    const SizedBox(height: 6),
                    _mapButton(Icons.remove_rounded, 'Zoom out', () => _zoomBy(-1)),
                    const SizedBox(height: 6),
                    _mapButton(Icons.my_location_rounded, 'My location', _recenterMap, accent: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPulseMarker() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        final t = _pulseCtrl.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 18 + 44 * t,
              height: 18 + 44 * t,
              decoration: BoxDecoration(
                color: _C.red.withValues(alpha: 0.35 * (1 - t)),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: _C.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mapPill(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _mapButton(IconData icon, String tooltip, VoidCallback onTap, {bool accent = false}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 20, color: accent ? const Color(0xFFE65100) : _C.ink),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Incident meta bar ─────────────────────────

  Widget _buildIncidentMetaBar() {
    final code = _sent ? (_ticketCode ?? 'PENDING') : 'DRAFT-5';
    final dotColor = _cancelled ? _C.redDeep : (_sent ? _C.pending : Colors.grey);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _C.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded, size: 15, color: _C.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_formatDate(_createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(color: _C.inkSoft, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Material(
            color: _C.chip,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _copyTicket,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.42),
                      child: Text(code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.robotoMono(
                              color: _C.ink, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded, size: 13, color: _C.muted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Chat feed widgets ─────────────────────────

  Widget _buildAlertopozAvatar() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B4A), Color(0xFFE53935)],
        ),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: _C.red.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 15),
          Text('SOS',
              style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 7, height: 1.0, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _botRow({required Widget child}) {
    final maxW = MediaQuery.of(context).size.width * 0.78;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAlertopozAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text('alertopoz',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 12, color: _C.inkSoft)),
                ),
                ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _bubbleDecoration(bool isUser) {
    return BoxDecoration(
      color: isUser ? _C.userBubble : _C.botBubble,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(isUser ? 18 : 4),
        topRight: Radius.circular(isUser ? 4 : 18),
        bottomLeft: const Radius.circular(18),
        bottomRight: const Radius.circular(18),
      ),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final type = msg['type'] as String;
    final timeStr = _formatStamp(msg['timestamp'] as String?);
    final maxW = MediaQuery.of(context).size.width * 0.75;

    if (type == 'image') {
      final raw = msg['content'].toString();
      final isUrl = raw.startsWith('http') || raw.startsWith('/uploads');
      final ImageProvider provider = isUrl
          ? NetworkImage(raw.startsWith('http') ? raw : '${ApiService.baseUrl}$raw')
          : MemoryImage(base64Decode(raw));
      final side = (maxW * 0.8).clamp(140.0, 240.0);
      final image = GestureDetector(
        onTap: () => _openImage(provider),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Image(
              image: provider,
              width: side,
              height: side,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(
                width: side,
                height: side,
                color: _C.chip,
                child: const Icon(Icons.broken_image_rounded, size: 40, color: _C.muted),
              ),
            ),
          ),
        ),
      );
      if (!isUser) return _botRow(child: image);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Align(alignment: Alignment.centerRight, child: image),
      );
    }

    if (type == 'activated') {
      return _botRow(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: _bubbleDecoration(false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🚨 INCIDENT ACTIVATED',
                  style: GoogleFonts.outfit(color: _C.redDeep, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              InkWell(
                onTap: _copyTicket,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text('Ticket Code: $_ticketCode',
                            style: GoogleFonts.outfit(color: _C.ink, fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy_rounded, size: 14, color: _C.inkSoft),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                  'Your emergency request has been received.\nKeep this ticket number for reference.\n\nYour emergency location and details have been sent to the Command Center.\nFor emergency validation, please provide:\n📸 Validation picture of the incident\n🎥 Validation video, if available\nStay calm and provide clear updates.',
                  style: GoogleFonts.outfit(color: _C.ink, fontSize: 13, height: 1.35)),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(timeStr, style: GoogleFonts.outfit(color: Colors.black54, fontSize: 10)),
              ),
            ],
          ),
        ),
      );
    }

    // 'system' and 'text' messages share the same bubble style.
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: _bubbleDecoration(isUser),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(msg['content']?.toString() ?? '',
              style: GoogleFonts.outfit(color: isUser ? Colors.white : _C.ink, fontSize: 15, height: 1.3)),
          if (msg['timestamp'] != null) ...[
            const SizedBox(height: 4),
            Text(timeStr, style: GoogleFonts.outfit(color: isUser ? Colors.white70 : Colors.black54, fontSize: 10)),
          ],
        ],
      ),
    );

    if (!isUser) return _botRow(child: bubble);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: bubble),
      ),
    );
  }

  Widget _buildSendingIndicator() {
    return _botRow(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: _bubbleDecoration(false),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _C.redDeep)),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Sending your emergency report…',
                  style: GoogleFonts.outfit(color: _C.ink, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return Padding(
      // Indent to line up with the bot bubbles (avatar 36 + gap 8).
      padding: const EdgeInsets.only(left: 44, bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.divider),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cols = w >= 480 ? 6 : (w < 220 ? 2 : 3);
            const spacing = 4.0;
            final tileW = (w - spacing * (cols - 1)) / cols;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('Select emergency type',
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: _C.muted)),
                ),
                Wrap(
                  spacing: spacing,
                  runSpacing: 4,
                  children: _categories.map((cat) => _buildCategoryTile(cat, tileW)).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> cat, double width) {
    final color = cat['color'] as Color;
    final selected = _selectedCategory == cat['key'];
    final enabled = !_sending && !_sent;
    return SizedBox(
      width: width,
      child: Opacity(
        opacity: enabled || selected ? 1 : 0.45,
        child: Material(
          color: selected ? color.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: ValueKey('category_${cat['key']}'),
            borderRadius: BorderRadius.circular(14),
            splashColor: color.withValues(alpha: 0.18),
            onTap: enabled ? () => _selectCategory(cat['key'] as String, cat['label'] as String) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: color.withValues(alpha: selected ? 0.8 : 0.22), width: selected ? 2 : 1),
                    ),
                    child: Icon(cat['icon'] as IconData, color: color, size: 26),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cat['label'] as String,
                      maxLines: 1,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: _C.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Input bar ─────────────────────────

  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _C.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Container(
            padding: const EdgeInsets.only(left: 4, right: 5, top: 4, bottom: 4),
            decoration: BoxDecoration(color: _C.chip, borderRadius: BorderRadius.circular(28)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('btn_gallery'),
                  tooltip: 'Upload image',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.image_rounded, color: _C.muted, size: 24),
                  onPressed: _attachGalleryImage,
                ),
                IconButton(
                  key: const ValueKey('btn_camera'),
                  tooltip: 'Take photo',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.camera_alt_rounded, color: _C.muted, size: 24),
                  onPressed: _showCameraDialog,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: TextField(
                      key: const ValueKey('input_message'),
                      controller: _commentCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      style: GoogleFonts.outfit(fontSize: 15, color: _C.ink),
                      decoration: InputDecoration(
                        hintText: 'Type here...',
                        hintStyle: GoogleFonts.outfit(color: _C.muted, fontSize: 15),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onTap: _scrollToBottom,
                      onSubmitted: (_) => _sendChatMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Send',
                  child: AnimatedScale(
                    scale: _hasText ? 1.0 : 0.92,
                    duration: const Duration(milliseconds: 180),
                    child: Material(
                      color: _hasText ? _C.send : _C.send.withValues(alpha: 0.75),
                      shape: const CircleBorder(),
                      elevation: _hasText ? 2 : 0,
                      child: InkWell(
                        key: const ValueKey('btn_send'),
                        customBorder: const CircleBorder(),
                        onTap: _sendChatMessage,
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClosedBanner() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _C.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 16, color: _C.muted),
              const SizedBox(width: 8),
              Flexible(
                child: Text('This incident is closed. Chat is no longer available.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: _C.muted, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final fullMapHeight = (media.size.height * 0.26).clamp(150.0, 260.0);
    // Collapse the map while typing so the chat never gets squeezed/cut off.
    final mapHeight = (_isMapExpanded && !keyboardOpen) ? fullMapHeight : 0.0;

    return Scaffold(
      backgroundColor: _C.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Orange Location Strip
          _buildLocationBar(),

          // Map View
          _buildMap(mapHeight, fullMapHeight),

          // Incident date/time + draft/ticket status
          _buildIncidentMetaBar(),

          // Chat feed
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
              children: [
                ..._chatFeed.map((msg) => _buildChatBubble(msg)),
                if (_sending) _buildSendingIndicator(),
                if (!_sent && !_cancelled) _buildCategoryGrid(),
              ],
            ),
          ),

          // Bottom Input Bar
          if (!_cancelled) _buildInputBar() else _buildClosedBanner(),
        ],
      ),
    );
  }
}
