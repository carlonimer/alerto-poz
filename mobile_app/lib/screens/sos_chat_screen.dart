import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../models/user.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
import '../services/barangay_service.dart';
import '../services/api_service.dart';
import '../services/video_thumbnail_service.dart';
import 'call_screen.dart';
import 'camera_screen.dart';

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

class _SosChatScreenState extends State<SosChatScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final _commentCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final MapController _mapController = MapController();
  late final AnimationController _pulseCtrl;

  static const LatLng _defaultCenter = LatLng(16.1086, 120.5424); // Pozorrubio

  String? _incidentId;
  String? _selectedCategory;
  String? _ticketCode;
  String? _assignedUnit;
  bool _sent = false;
  bool _sending = false;
  bool _isUploadingMedia = false;
  bool _queued = false;
  bool _cancelled = false; // New cancelled state
  bool _hasText = false;
  DateTime _createdAt = DateTime.now();
  final List<Map<String, dynamic>> _chatFeed = [];
  final Set<String> _seenMessageIds = {}; // Server message ids already rendered (dedupe)
  bool _isFetchingHistory = false;
  final List<String> _attachedImages = []; // base64 strings
  final List<Map<String, String>> _pendingMediaUploads = []; // Queued media files: {'path': ..., 'type': 'video'|'image'}

  bool _isMapExpanded = true;
  String _mapLayer = 'Standard'; // Standard, Satellite, Terrain
  Position? _currentPos;
  LatLng? _incidentPos;
  LatLng? _selectedPos;
  Timer? _geocodeTimer;
  String _currentAddress = 'Locating...';
  String? _resolvedBarangay;
  int _locationSeq = 0;

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

  static Color getCategoryColor(String? key) {
    if (key == null) return const Color(0xFF1D4ED8);
    final match = _categories.firstWhere(
      (c) => c['key'].toString().toLowerCase() == key.toLowerCase(),
      orElse: () => const {'color': Color(0xFF1D4ED8)},
    );
    return match['color'] as Color;
  }

  // ───────────────────────── Lifecycle ─────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _commentCtrl.addListener(() {
      final has = _commentCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });

    _loadMapLayer();

    if (widget.activeIncident != null) {
      final inc = widget.activeIncident!;
      _incidentId = inc['_id']?.toString() ?? inc['id']?.toString();
      final rawCat = inc['category']?.toString();
      _selectedCategory = (rawCat != null && rawCat.isNotEmpty && rawCat != 'draft')
          ? rawCat
          : ((widget.initialCategory != null && widget.initialCategory != 'draft') ? widget.initialCategory : null);
      _ticketCode = inc['ticketCode']?.toString() ?? inc['id']?.toString() ?? _incidentId;
      _assignedUnit = inc['assignedUnit']?.toString();
      // Incident timestamps may arrive as int ms, numeric strings (MySQL BIGINT) or ISO strings.
      // Previously numeric strings fell back to DateTime.now(), which pushed the
      // "prepared/activated" bubbles BELOW the restored history on CONTINUE.
      final parsedCreated = _parseTs(inc['timestamp'] ?? inc['createdAt'] ?? inc['created_at']);
      _createdAt = parsedCreated.millisecondsSinceEpoch > 0 ? parsedCreated : DateTime.now();
      final lat = double.tryParse('${inc['lat'] ?? ''}');
      final lng = double.tryParse('${inc['lng'] ?? ''}');
      if (lat != null && lng != null) _incidentPos = LatLng(lat, lng);
      _sent = (inc['status'] != 'draft');
      if (inc['status'] == 'cancelled') {
        _cancelled = true;
      }
      
      if (_sent) {
        _chatFeed.add({
          'role': 'bot',
          'type': 'system',
          'content': 'Emergency report prepared by ${(widget.user?.name ?? 'USER').toUpperCase()}',
          'timestamp': _createdAt.subtract(const Duration(seconds: 2)).toIso8601String(),
        });
        _chatFeed.add({
          'role': 'bot',
          'type': 'activated',
          'content': '',
          'timestamp': _createdAt.subtract(const Duration(seconds: 1)).toIso8601String(),
        });
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
          _chatFeed.add({
            'role': 'user',
            'type': 'text',
            'content': 'Selected Emergency: ${_selectedCategory!.toUpperCase()}',
            'timestamp': _createdAt.toIso8601String(),
          });
        }
        _fetchHistory();
      } else {
        _attachedImages.clear();
        _commentCtrl.clear();
        _restoreDraftFromPrefs();
        _chatFeed.add({
          'role': 'bot',
          'type': 'system',
          'content': 'Ano ang maipaglilingkod namin?',
          'timestamp': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
        });
      }
    } else {
      _restoreDraftFromPrefs();
      _chatFeed.add({
        'role': 'bot',
        'type': 'system',
        'content': 'Ano ang maipaglilingkod namin?',
        'timestamp': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
      });

      if (widget.initialCategory != null) {
        final cat = _categories.firstWhere((c) => c['key'] == widget.initialCategory, orElse: () => _categories.last);
        _selectCategory(cat['key'] as String, cat['label'] as String);
      }
    }

    if (_incidentId == null || _incidentId!.isEmpty) {
      _incidentId = 'DRAFT-${widget.user?.id ?? 0}';
    }

    _initLocation();

    SocketService.on('chat-message-receive', _onChatMessage);
    SocketService.on('incident-cancelled', _onIncidentCancelled);
    SocketService.on('incident-updated', _onIncidentUpdated);
  }

  @override
  void dispose() {
    SocketService.off('chat-message-receive', _onChatMessage);
    SocketService.off('incident-cancelled', _onIncidentCancelled);
    SocketService.off('incident-updated', _onIncidentUpdated);
    _pulseCtrl.dispose();
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMapLayer() async {
    final data = await ApiService.getUser();
    if (data != null && mounted) {
      final user = UserModel.fromJson(data);
      if (user.mapSettings != null && user.mapSettings!['map_type'] != null) {
        String mt = user.mapSettings!['map_type'];
        String newLayer = 'Standard';
        if (mt == 'satellite') newLayer = 'Satellite';
        if (mt == 'terrain') newLayer = 'Terrain';
        setState(() {
          _mapLayer = newLayer;
        });
      }
    }
  }

  Future<void> _saveMapLayer(String layer) async {
    final data = await ApiService.getUser();
    if (data != null) {
      final user = UserModel.fromJson(data);
      String dbType = 'default';
      if (layer == 'Satellite') dbType = 'satellite';
      if (layer == 'Terrain') dbType = 'terrain';
      
      final settings = Map<String, dynamic>.from(user.mapSettings ?? {});
      settings['map_type'] = dbType;
      
      final res = await ApiService.saveMapSettings({
        'user_id': user.id,
        ...settings,
      });
      if (res['success'] == true) {
        final updatedUser = user.copyWith(mapSettings: settings);
        ApiService.updateUserLocal(updatedUser.toJson());
      }
    }
  }

  // ───────────────────────── Socket handlers ─────────────────────────

  void _onChatMessage(dynamic data) {
    if (data is! Map || data['incident_id']?.toString() != _incidentId || !mounted) return;
    
    // Ignore if it's our own message because we already appended it optimistically
    if (data['sender_id']?.toString() == widget.user?.id.toString()) return;

    // Dedupe: never render the same server message twice
    final msgId = data['id']?.toString();
    if (msgId != null && msgId.isNotEmpty && _seenMessageIds.contains(msgId)) return;
    if (msgId != null && msgId.isNotEmpty) _seenMessageIds.add(msgId);

    final msgType = data['message_type']?.toString();
    final isVideo = msgType == 'video';
    final isImage = msgType == 'image' || data['is_media'] == true;
    final ts = data['timestamp'] != null ? _parseTs(data['timestamp']) : DateTime.now();

    setState(() {
      _chatFeed.add({
        'id': msgId,
        'role': 'bot',
        'type': isVideo ? 'video' : (isImage ? 'image' : 'text'),
        'content': data['media_url'] ?? data['message_content'] ?? data['message'] ?? '',
        'videoPath': isVideo ? (data['media_url'] ?? data['message_content'] ?? data['message']) : null,
        'timestamp': ts.toIso8601String(),
      });
      _sortFeed();
    });
    _scrollToBottom();
  }

  // ───────────────────────── Ordering helpers ─────────────────────────

  /// Parses any timestamp shape the backend/socket/local code may produce:
  /// int/num epoch (s or ms), numeric strings (MySQL BIGINT), ISO-8601 or
  /// MySQL DATETIME strings. Unknown values sort first (epoch 0).
  static DateTime _parseTs(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is DateTime) return v;
    if (v is num) {
      final n = v.toInt();
      // Treat 10-digit values as seconds
      return DateTime.fromMillisecondsSinceEpoch(n < 100000000000 ? n * 1000 : n);
    }
    final s = v.toString().trim();
    if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    final asNum = num.tryParse(s);
    if (asNum != null) return _parseTs(asNum);
    return DateTime.tryParse(s)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Stable ascending sort (oldest first, newest last). Dart's List.sort is not
  /// stable, so equal timestamps keep their insertion order via index tiebreak.
  void _sortFeed() {
    final indexed = _chatFeed.asMap().entries.toList();
    indexed.sort((a, b) {
      final c = _parseTs(a.value['timestamp']).compareTo(_parseTs(b.value['timestamp']));
      return c != 0 ? c : a.key.compareTo(b.key);
    });
    final sorted = indexed.map((e) => e.value).toList();
    _chatFeed
      ..clear()
      ..addAll(sorted);
  }

  /// Aligns an optimistic local message with the server's id/timestamp so it
  /// sorts consistently with history (avoids device/server clock skew).
  void _applyServerAck(Map<String, dynamic> entry, dynamic res) {
    if (res is! Map || res['success'] != true || res['message'] is! Map) return;
    final m = res['message'] as Map;
    final id = m['id']?.toString();
    if (id != null && id.isNotEmpty) {
      _seenMessageIds.add(id);
      entry['id'] = id;
    }
    if (m['timestamp'] != null) {
      entry['timestamp'] = _parseTs(m['timestamp']).toIso8601String();
    }
    if (mounted) setState(_sortFeed);
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
      _selectedPos ?? (_currentPos != null ? LatLng(_currentPos!.latitude, _currentPos!.longitude) : _incidentPos);


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _saveDraftToPrefs();
    }
  }



  Future<void> _restoreDraftFromPrefs() async {}

  void _saveDraftToPrefs() {}



  Future<void> _flushOfflineQueue() async {}


  Future<void> _initLocation() async {
    if (mounted && _currentPos == null) setState(() => _currentAddress = 'Locating...');
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _currentPos = pos;
        _selectedPos ??= _incidentPos ?? LatLng(pos.latitude, pos.longitude);
        _currentAddress = 'Locating...';
      });
      _moveMap(_selectedPos!, 15.0);
      _resolveAddress(_selectedPos!.latitude, _selectedPos!.longitude);
    } else if (_incidentPos != null) {
      setState(() {
        _selectedPos = _incidentPos;
        _currentAddress = 'Locating...';
      });
      _moveMap(_incidentPos!, 15.0);
      _resolveAddress(_incidentPos!.latitude, _incidentPos!.longitude);
    } else {
      setState(() => _currentAddress = 'Location unavailable · tap to retry');
    }
  }

  Future<void> _resolveAddress(double lat, double lng) async {
    final seq = ++_locationSeq;
    try {
      debugPrint('[SosChatScreen] Requesting address for ($lat, $lng), seq=$seq');
      final result = await BarangayService.resolveLocation(lat, lng);
      if (!mounted || seq != _locationSeq) {
        debugPrint('[SosChatScreen] Stale location response ignored (seq=$seq, current=$_locationSeq)');
        return;
      }
      setState(() {
        _currentAddress = result.formattedAddress;
        _resolvedBarangay = result.barangay;
      });
      debugPrint('[SosChatScreen] UI Location updated: $_currentAddress (Barangay: $_resolvedBarangay, Source: ${result.source})');
    } catch (e) {
      debugPrint('[SosChatScreen] Location resolution error: $e');
      if (mounted && seq == _locationSeq && _currentAddress == 'Locating...') {
        setState(() => _currentAddress = 'Unknown Location');
      }
    }
  }

  void _moveMap(LatLng target, double zoom) {
    try {
      _mapController.move(target, zoom);
    } catch (_) {
      // Map not attached yet – initialCenter will handle the first frame.
    }
  }

  Future<void> _recenterMap() async {
    if (!_isMapExpanded) setState(() => _isMapExpanded = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      final p = LatLng(pos.latitude, pos.longitude);
      if (!_sent) {
        setState(() {
          _selectedPos = p;
          _currentAddress = 'Locating...';
        });
        _resolveAddress(p.latitude, p.longitude);
      }
      _moveMap(p, 18.5);
    } else {
      _initLocation();
    }
  }

  void _zoomBy(double delta) {
    try {
      final cam = _mapController.camera;
      _mapController.move(cam.center, (cam.zoom + delta).clamp(3.0, 19.0));
    } catch (_) {}
  }

  // ───────────────────────── Chat logic ─────────────────────────

  Future<void> _fetchHistory() async {
    if (_incidentId == null || _isFetchingHistory) return;
    _isFetchingHistory = true;
    try {
      final res = await ApiService.fetchMessages(_incidentId!);
      if (res['success'] == true && mounted) {
        final msgs = (res['messages'] as List?) ?? const [];
        setState(() {
          for (var msg in msgs) {
            if (msg is! Map) continue;
            final msgId = msg['id']?.toString();
            // Dedupe by server id so refresh/restore never duplicates messages
            if (msgId != null && msgId.isNotEmpty && _seenMessageIds.contains(msgId)) {
              continue;
            }

            final rawTs = msg['timestamp'] ?? msg['createdAt'] ?? msg['created_at'];
            final mType = msg['message_type']?.toString();
            final isVideo = mType == 'video';
            final isImage = mType == 'image' || msg['isMedia'] == true;
            final isUser = msg['sender_id']?.toString() == widget.user?.id.toString() ||
                msg['sender_role'] == 'Citizen App';
            final content = msg['media_url'] ?? msg['message_content'] ?? msg['content'] ?? '';
            final parsedTime = _parseTs(rawTs).toIso8601String();

            // Detect Selected Emergency message
            final rawContentStr = (msg['message_content']?.toString() ?? msg['content']?.toString() ?? '').trim();
            final isCatMsg = rawContentStr.toUpperCase().startsWith('SELECTED EMERGENCY:') ||
                rawContentStr.toUpperCase().startsWith('SELECTED CATEGORY:');

            if (isCatMsg) {
              final catPart = rawContentStr.split(':').last.trim();
              if (catPart.isNotEmpty) {
                if (_selectedCategory == null || _selectedCategory!.isEmpty || _selectedCategory == 'draft') {
                  _selectedCategory = catPart.toLowerCase();
                }
              }

              // Check if a category bubble already exists in _chatFeed
              final existingCatIdx = _chatFeed.indexWhere((m) {
                final c = (m['content']?.toString() ?? '').toUpperCase();
                return c.startsWith('SELECTED EMERGENCY:') || c.startsWith('SELECTED CATEGORY:');
              });

              if (existingCatIdx != -1) {
                _chatFeed[existingCatIdx]['id'] = msgId;
                _chatFeed[existingCatIdx]['timestamp'] = parsedTime;
                _chatFeed[existingCatIdx]['content'] = 'Selected Emergency: ${catPart.toUpperCase()}';
                if (msgId != null && msgId.isNotEmpty) {
                  _seenMessageIds.add(msgId);
                }
                continue;
              }
            }

            // Reconcile optimistic message if already in feed
            final optIdx = _chatFeed.indexWhere((m) =>
                m['id'] == null &&
                m['role'] == (isUser ? 'user' : 'bot') &&
                m['type'] == (isVideo ? 'video' : (isImage ? 'image' : 'text')) &&
                (m['content'] == content || m['content'] == msg['message_content']));

            if (optIdx != -1) {
              _chatFeed[optIdx]['id'] = msgId;
              _chatFeed[optIdx]['timestamp'] = parsedTime;
              if (isVideo && msg['media_url'] != null) {
                _chatFeed[optIdx]['videoPath'] = msg['media_url'];
              }
              if (msgId != null && msgId.isNotEmpty) {
                _seenMessageIds.add(msgId);
              }
            } else {
              if (msgId != null && msgId.isNotEmpty) {
                _seenMessageIds.add(msgId);
              }
              _chatFeed.add({
                'id': msgId,
                'role': isUser ? 'user' : 'bot',
                'type': isVideo ? 'video' : (isImage ? 'image' : 'text'),
                'content': isCatMsg ? 'Selected Emergency: ${rawContentStr.split(':').last.trim().toUpperCase()}' : content,
                'videoPath': isVideo ? (msg['media_url'] ?? msg['message_content'] ?? msg['content']) : null,
                'timestamp': parsedTime,
              });
            }
          }
          _sortFeed();
        });
        _scrollToBottom();
      }
    } catch (e) {
      /* best-effort: ignore network errors */
    } finally {
      _isFetchingHistory = false;
    }
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

  void _selectCategory(String key, String label) {
    if (_sent || _sending) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedCategory = key;
    });
  }

  Future<void> _attachGalleryImage() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (file != null) {
      await _handleImageTaken(file.path);
    }
  }



  Future<void> _flushPendingMediaUploads() async {
    if (_incidentId == null || _pendingMediaUploads.isEmpty) return;
    final toUpload = List<Map<String, String>>.from(_pendingMediaUploads);
    _pendingMediaUploads.clear();

    for (final item in toUpload) {
      final mediaPath = item['path'];
      final mediaType = item['type'] ?? 'image';
      if (mediaPath == null || mediaPath.isEmpty) continue;

      try {
        final payload = {
          'senderId': widget.user?.id,
          'messageContent': '${mediaType == 'video' ? 'Video' : 'Image'} Attachment',
          'messageType': mediaType,
        };
        final res = await ApiService.sendMessage(
          _incidentId!,
          payload,
          mediaPath: mediaPath,
        );
        if (mediaType == 'video' && res['success'] == true && res['message'] != null) {
          final serverMediaUrl = res['message']['media_url']?.toString();
          final cachedBytes = VideoThumbnailService.getCachedThumbnailSync(mediaPath);
          if (serverMediaUrl != null && serverMediaUrl.isNotEmpty && cachedBytes != null) {
            VideoThumbnailService.cacheThumbnail(serverMediaUrl, cachedBytes);
          }
        }
      } catch (e) {
        debugPrint("Error uploading queued pending media: $e");
      }
    }
  }

  Future<void> _handleVideoTaken(String path) async {
    if (!mounted) return;

    setState(() => _isUploadingMedia = true);
    
    try {
      // 1. Try to compress video, fall back gracefully to original path if compression fails
      String uploadPath = path;
      try {
        final info = await VideoCompress.compressVideo(
          path,
          quality: VideoQuality.DefaultQuality,
          deleteOrigin: false,
        );
        if (info?.path != null && info!.path!.isNotEmpty) {
          uploadPath = info.path!;
        }
      } catch (compErr) {
        debugPrint("Video compression skipped/fallback: $compErr");
      }

      // 2. Extract representative frame thumbnail from the actual finalized video file
      Uint8List? rawThumbBytes;
      String b64Thumb = '';
      try {
        final thumbnailFile = await VideoCompress.getFileThumbnail(
          uploadPath,
          quality: 75,
          position: -1,
        );
        if (await thumbnailFile.exists() && await thumbnailFile.length() > 0) {
          rawThumbBytes = await thumbnailFile.readAsBytes();
          b64Thumb = base64Encode(rawThumbBytes);
          // Immediately cache under both original and compressed paths
          VideoThumbnailService.cacheThumbnail(uploadPath, rawThumbBytes);
          VideoThumbnailService.cacheThumbnail(path, rawThumbBytes);
        }
      } catch (thumbErr) {
        debugPrint("Thumbnail extraction error: $thumbErr");
      }

      if (!mounted) return;
      final videoEntry = <String, dynamic>{
        'role': 'user',
        'type': 'video',
        'content': uploadPath,
        'videoPath': uploadPath,
        'thumbnail': rawThumbBytes,
        'timestamp': DateTime.now().toIso8601String(),
      };
      setState(() {
        if (b64Thumb.isNotEmpty) {
          _attachedImages.add(b64Thumb);
        }
        _chatFeed.add(videoEntry);
        _sortFeed();
      });
      _scrollToBottom();
      
      // 3. Send video attachment via chat messaging flow
      final targetIncidentId = _incidentId ?? 'DRAFT-${widget.user?.id ?? 0}';
      final payload = {
        'senderId': widget.user?.id,
        'messageContent': 'Video Attachment',
        'messageType': 'video',
      };

      try {
        final res = await ApiService.sendMessage(
          targetIncidentId,
          payload,
          mediaPath: uploadPath,
        );
        _applyServerAck(videoEntry, res);
        if (res['success'] == true && res['message'] != null && rawThumbBytes != null) {
          final serverMediaUrl = res['message']['media_url']?.toString();
          if (serverMediaUrl != null && serverMediaUrl.isNotEmpty) {
            // Pre-cache under server URL so when history or updates arrive, thumbnail is instant!
            VideoThumbnailService.cacheThumbnail(serverMediaUrl, rawThumbBytes);
          }
        }
        if (res['error'] != null) {
          debugPrint("Video send warning: ${res['error']}");
        }
      } catch (uploadErr) {
        debugPrint("Video upload error: $uploadErr");
      }

      if (!_sent) {
        // Queue for association upon explicit incident activation
        _pendingMediaUploads.add({
          'type': 'video',
          'path': uploadPath,
        });
      }
    } catch (e) {
      debugPrint("Error handling video: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process and send video: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }

  Future<void> _handleImageTaken(String path) async {
    setState(() => _isUploadingMedia = true);
    try {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);

      if (!mounted) return;
      final imageEntry = <String, dynamic>{
        'role': 'user',
        'type': 'image',
        'content': b64,
        'timestamp': DateTime.now().toIso8601String(),
      };
      setState(() {
        _attachedImages.add(b64);
        _chatFeed.add(imageEntry);
        _sortFeed();
      });
      _scrollToBottom();

      final targetIncidentId = _incidentId ?? 'DRAFT-${widget.user?.id ?? 0}';
      final payload = {
        'senderId': widget.user?.id,
        'messageContent': 'Image Attachment',
        'messageType': 'image',
      };

      try {
        final res = await ApiService.sendMessage(
          targetIncidentId,
          payload,
          mediaPath: path,
        );
        _applyServerAck(imageEntry, res);
        if (res['error'] != null) {
          debugPrint("Image send warning: ${res['error']}");
        }
      } catch (uploadErr) {
        debugPrint("Image upload error: $uploadErr");
      }

      if (!_sent) {
        _pendingMediaUploads.add({
          'type': 'image',
          'path': path,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send attachment due to network error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingMedia = false);
    }
  }





  /// Emits the SOS report and waits for the server acknowledgement so we get
  /// the real ticket number (used as the incident id for follow-up messages).
  Future<void> _doTransmit({bool background = false}) async {
    if (_sending && !background) return;
    if (!background) setState(() => _sending = true);
    if (!background) _scrollToBottom();

    final transmitLat = _selectedPos?.latitude ?? _defaultCenter.latitude;
    final transmitLng = _selectedPos?.longitude ?? _defaultCenter.longitude;
    final transmitBarangay = _resolvedBarangay ?? BarangayService.findPozorrubioBarangay(transmitLat, transmitLng)?.name;

    final payload = {
      'id': _incidentId ?? 'draft',
      'status': 'pending',
      'reporterId': widget.user?.id ?? 0,
      'reporterPhone': widget.user?.phone ?? '',
      'reporter': widget.user?.name ?? 'Citizen',
      'lat': transmitLat,
      'lng': transmitLng,
      'barangay': transmitBarangay,
      'category': _selectedCategory,
      'details': _commentCtrl.text.trim(),
      'media': _attachedImages,
      'createdAt': DateTime.now().toIso8601String(),
    };

    dynamic res;
    try {
      res = await ApiService.submitSosReport(payload);
    } catch (_) {
      res = null;
    }
    final ticket = (res is Map && res['success'] == true) ? res['ticketNumber']?.toString() : null;

    if (!mounted) return;
    setState(() {
      _sending = false;
      _createdAt = DateTime.now();
      if (ticket != null) {
        _incidentId = ticket;
        _ticketCode = ticket;
        _sent = true;
        _queued = false;
        _chatFeed.add({
          'role': 'bot',
          'type': 'activated',
          'content': '',
          'timestamp': DateTime.now().toIso8601String(),
        });
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty && _selectedCategory != 'draft') {
          _chatFeed.add({
            'role': 'user',
            'type': 'text',
            'content': 'Selected Emergency: ${_selectedCategory!.toUpperCase()}',
            'timestamp': DateTime.now().add(const Duration(milliseconds: 50)).toIso8601String(),
          });
        }
        _sortFeed();
        SharedPreferences.getInstance().then((prefs) => prefs.remove('draft_incident_payload')); // Clear draft once sent
        _flushPendingMediaUploads();
      } else if (res is Map && res['_statusCode'] == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have an active emergency report. Please resolve it before creating a new one.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error: Could not connect to Command Center. Please try again.')),
        );
      }
    });
    _scrollToBottom();
  }

  Future<void> _sendChatMessage() async {
    final txt = _commentCtrl.text.trim();
    
    if (!_sent) {
      if (_selectedCategory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select an emergency type first.')),
          );
        }
        return;
      }
      await _doTransmit();
      if (_sent && txt.isNotEmpty) {
        setState(() {
          _chatFeed.add({
            'role': 'user',
            'type': 'text',
            'content': txt,
            'timestamp': DateTime.now().toIso8601String(),
          });
          _sortFeed();
        });
        _commentCtrl.clear();
        _scrollToBottom();
      }
      return;
    }

    if (txt.isEmpty) return;

    final entry = <String, dynamic>{
      'role': 'user',
      'type': 'text',
      'content': txt,
      'timestamp': DateTime.now().toIso8601String(),
    };
    setState(() {
      _chatFeed.add(entry);
      _sortFeed();
    });
    _commentCtrl.clear();
    _scrollToBottom();

    if (_incidentId != null) {
      try {
        final res = await ApiService.sendMessage(_incidentId!, {
          'senderId': widget.user?.id,
          'messageContent': txt,
        });
        _applyServerAck(entry, res);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send message due to network error.')),
          );
        }
      }
    }
  }

  Future<void> _cancelIncident({String passcode = ''}) async {
    if (_incidentId == null) return;
    try {
      var res = await ApiService.cancelIncident(
        _incidentId!,
        userId: widget.user?.id.toString() ?? '',
        phone: widget.user?.phone ?? '',
        passcode: passcode.isNotEmpty ? passcode : null,
      );

      if (res['success'] != true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? 'Failed to cancel incident.')));
        return;
      }

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

  Future<void> _openCameraDirectly() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CameraScreen(initialMode: 1)),
      );

      if (result != null && result is Map && mounted) {
        final path = result['path'] as String?;
        final type = result['type'] as String?;
        if (path != null && type != null) {
          if (type == 'video') {
            await _handleVideoTaken(path);
          } else {
            await _handleImageTaken(path);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }


  void _showCloseIncidentDialog() {
    showDialog(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
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
                  controller: ctrl,
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
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _cancelIncident(passcode: ctrl.text);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF44336),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Confirm Close Incident',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                      ),
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

  void _openVideoPlayer(String pathOrUrl) {
    if (pathOrUrl.trim().isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ChatVideoPlayerDialog(pathOrUrl: pathOrUrl),
    );
  }

  // ───────────────────────── Formatting ─────────────────────────

  String _formatDate(DateTime d) => DateFormat('MMM dd, yyyy, hh:mm a').format(d);

  String _formatStamp(dynamic val) {
    if (val == null) return '';
    final parsed = _parseTs(val);
    final d = parsed.millisecondsSinceEpoch > 0 ? parsed : DateTime.now();
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
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
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
              if (_selectedCategory != null && _selectedCategory!.isNotEmpty && _selectedCategory != 'draft') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: getCategoryColor(_selectedCategory).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: getCategoryColor(_selectedCategory).withValues(alpha: 0.35), width: 1),
                  ),
                  child: Text(
                    _selectedCategory!.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      color: getCategoryColor(_selectedCategory),
                    ),
                  ),
                ),
              ],
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
              onSelected: (value) {
                setState(() {
                  _mapLayer = value;
                  _isMapExpanded = true;
                });
                _saveMapLayer(value);
              },
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
                  onTap: (tapPosition, point) {
                    if (_sent) return;
                    setState(() {
                      _selectedPos = point;
                      _currentAddress = 'Updating location...';
                    });
                    _geocodeTimer?.cancel();
                    _geocodeTimer = Timer(const Duration(milliseconds: 800), () {
                      if (mounted && _selectedPos != null) {
                        _resolveAddress(_selectedPos!.latitude, _selectedPos!.longitude);
                      }
                    });
                  },
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
                        Marker(
                          point: marker, 
                          width: 100, 
                          height: 100, 
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              if (_sent) return;
                              try {
                                final cam = _mapController.camera;
                                final pt = cam.latLngToScreenPoint(_selectedPos ?? marker);
                                final newPt = math.Point(pt.x + details.delta.dx, pt.y + details.delta.dy);
                                final newLatLng = cam.pointToLatLng(newPt);
                                setState(() {
                                  _selectedPos = newLatLng;
                                });
                              } catch (_) {}
                            },
                            onPanEnd: (_) {
                              if (_sent) return;
                              setState(() {
                                _currentAddress = 'Updating location...';
                              });
                              _geocodeTimer?.cancel();
                              _geocodeTimer = Timer(const Duration(milliseconds: 800), () {
                                if (mounted && _selectedPos != null) {
                                  _resolveAddress(_selectedPos!.latitude, _selectedPos!.longitude);
                                }
                              });
                            },
                            child: _buildPulseMarker(),
                          ),
                        ),
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
          clipBehavior: Clip.none,
          children: [
            if (!_sent)
              Container(
                width: 40 + (60 * t),
                height: 40 + (60 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _C.red.withValues(alpha: 1.0 - t),
                    width: 2,
                  ),
                  color: _C.red.withValues(alpha: (1.0 - t) * 0.1),
                ),
              ),
            Positioned(
              bottom: 50, // Anchor the bottom of the pin to the center of the marker
              child: SizedBox(
                width: 64,
                height: 72,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Positioned(
                      bottom: 2,
                      child: Transform.rotate(
                        angle: 3.14159 / 4,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _C.red,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: _C.red, width: 3),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        image: DecorationImage(
                          image: widget.user != null && widget.user!.profileImage.isNotEmpty
                              ? (widget.user!.profileImage.startsWith('data:image')
                                  ? MemoryImage(base64Decode(widget.user!.profileImage.split(',').last)) as ImageProvider
                                  : NetworkImage(
                                      widget.user!.profileImage.startsWith('http') 
                                          ? widget.user!.profileImage 
                                          : '${ApiService.baseUrl}${widget.user!.profileImage.startsWith('/') ? '' : '/'}${widget.user!.profileImage}'))
                              : const AssetImage('assets/logo.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
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
    final code = _queued ? 'QUEUED' : (_sent ? (_ticketCode ?? 'PENDING') : 'DRAFT');
    final dotColor = _cancelled ? _C.redDeep : (_queued ? Colors.orange : (_sent ? _C.pending : Colors.grey));
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
          if (_selectedCategory != null && _selectedCategory!.isNotEmpty && _selectedCategory != 'draft') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: getCategoryColor(_selectedCategory).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: getCategoryColor(_selectedCategory).withValues(alpha: 0.35), width: 1),
              ),
              child: Text(
                _selectedCategory!.toUpperCase(),
                style: GoogleFonts.outfit(
                  color: getCategoryColor(_selectedCategory),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
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
    final timeStr = _formatStamp(msg['timestamp']);
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

    if (type == 'video') {
      final videoSrc = (msg['videoPath'] ?? msg['content'] ?? '').toString();
      Uint8List? preThumb;
      if (msg['thumbnail'] is Uint8List) {
        preThumb = msg['thumbnail'] as Uint8List;
      } else {
        final raw = msg['content']?.toString() ?? '';
        if (raw.isNotEmpty && !raw.startsWith('http') && !raw.startsWith('/') && !File(raw).existsSync()) {
          try {
            preThumb = base64Decode(raw);
          } catch (_) {}
        }
      }

      final bubbleWidth = (maxW * 0.8).clamp(180.0, 260.0);
      final videoBubble = _ChatVideoThumbnailBubble(
        videoSrc: videoSrc,
        initialThumbBytes: preThumb,
        width: bubbleWidth,
        onTap: () {
          if (videoSrc.isNotEmpty) {
            _openVideoPlayer(videoSrc);
          }
        },
      );

      if (!isUser) return _botRow(child: videoBubble);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Align(alignment: Alignment.centerRight, child: videoBubble),
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

  Widget _buildMediaUploadingIndicator() {
    return _botRow(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: _bubbleDecoration(false),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _C.orange)),
            const SizedBox(width: 10),
            Flexible(
              child: Text('Uploading attachment…',
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
    final enabled = !_sending && !_sent && !_cancelled;
    
    // Only grey out unselected categories AFTER the report is submitted (i.e. not enabled).
    final double opacity = (enabled || selected) ? 1.0 : 0.45;

    return SizedBox(
      width: width,
      child: Opacity(
        opacity: opacity,
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
                  tooltip: 'Camera',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.camera_alt_rounded, color: _C.muted, size: 24),
                  onPressed: _openCameraDirectly,
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
                Builder(
                  builder: (context) {
                    final canSend = _hasText || (!_sent && _selectedCategory != null);
                    return Tooltip(
                      message: 'Send',
                      child: AnimatedScale(
                        scale: canSend ? 1.0 : 0.92,
                        duration: const Duration(milliseconds: 180),
                        child: Material(
                          color: canSend ? _C.send : _C.send.withValues(alpha: 0.75),
                          shape: const CircleBorder(),
                          elevation: canSend ? 2 : 0,
                          child: InkWell(
                            key: const ValueKey('btn_send'),
                            customBorder: const CircleBorder(),
                            onTap: canSend ? _sendChatMessage : null,
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
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
                if (!_sent) ...[
                  if (_chatFeed.isNotEmpty) _buildChatBubble(_chatFeed.first),
                  _buildCategoryGrid(),
                  ..._chatFeed.skip(1).map((msg) => _buildChatBubble(msg)),
                ] else ...[
                  ..._chatFeed.map((msg) => _buildChatBubble(msg)),
                ],
                if (_sending) _buildSendingIndicator(),
                if (_isUploadingMedia) _buildMediaUploadingIndicator(),
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

class _ChatVideoPlayerDialog extends StatefulWidget {
  final String pathOrUrl;
  const _ChatVideoPlayerDialog({required this.pathOrUrl});

  @override
  State<_ChatVideoPlayerDialog> createState() => _ChatVideoPlayerDialogState();
}

class _ChatVideoPlayerDialogState extends State<_ChatVideoPlayerDialog> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _error = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final raw = widget.pathOrUrl;
      final isLocal = File(raw).existsSync();
      if (isLocal) {
        _controller = VideoPlayerController.file(File(raw));
      } else {
        final url = raw.startsWith('http') ? raw : '${ApiService.baseUrl}$raw';
        _controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }

      await _controller!.initialize();
      _controller!.setLooping(false);
      _controller!.play();
      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _errorMsg = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
              spreadRadius: 2,
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.black87,
              child: Row(
                children: [
                  const Icon(Icons.videocam_rounded, color: Color(0xFFFFCC00), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Video Playback',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Video Viewport
            if (_error)
              Container(
                height: 240,
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 44),
                        const SizedBox(height: 12),
                        Text(
                          'Could not play video',
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        if (_errorMsg != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _errorMsg!,
                            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else if (!_initialized)
              Container(
                height: 260,
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFCC00)),
                ),
              )
            else
              GestureDetector(
                onTap: () {
                  if (_controller != null) {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  }
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 16 / 9,
                      child: VideoPlayer(_controller!),
                    ),
                    if (!_controller!.value.isPlaying)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                  ],
                ),
              ),
            // Controls & Scrubber
            if (_initialized && _controller != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.black87,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VideoProgressIndicator(
                      _controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFFFFCC00),
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(
                            _controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              if (_controller!.value.isPlaying) {
                                _controller!.pause();
                              } else {
                                _controller!.play();
                              }
                            });
                          },
                        ),
                        Text(
                          '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Renders a real video frame thumbnail in chat bubbles with a play button overlay
/// and "VIDEO" badge, respecting aspect ratio without distortion.
class _ChatVideoThumbnailBubble extends StatefulWidget {
  final String videoSrc;
  final Uint8List? initialThumbBytes;
  final double width;
  final VoidCallback onTap;

  const _ChatVideoThumbnailBubble({
    required this.videoSrc,
    this.initialThumbBytes,
    required this.width,
    required this.onTap,
  });

  @override
  State<_ChatVideoThumbnailBubble> createState() => _ChatVideoThumbnailBubbleState();
}

class _ChatVideoThumbnailBubbleState extends State<_ChatVideoThumbnailBubble> {
  Uint8List? _thumbBytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _ChatVideoThumbnailBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoSrc != widget.videoSrc || oldWidget.initialThumbBytes != widget.initialThumbBytes) {
      _loadThumbnail();
    }
  }

  void _loadThumbnail() {
    if (widget.initialThumbBytes != null && widget.initialThumbBytes!.isNotEmpty) {
      _thumbBytes = widget.initialThumbBytes;
      return;
    }

    final cached = VideoThumbnailService.getCachedThumbnailSync(widget.videoSrc);
    if (cached != null && cached.isNotEmpty) {
      _thumbBytes = cached;
      return;
    }

    if (widget.videoSrc.trim().isEmpty) return;

    _isLoading = true;
    VideoThumbnailService.getThumbnail(widget.videoSrc).then((bytes) {
      if (mounted) {
        setState(() {
          _thumbBytes = bytes;
          _isLoading = false;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 16:9 aspect ratio standard for mobile video preview
    final height = widget.width * 9 / 16;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: widget.width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Thumbnail Image or Loading / Fallback
              if (_thumbBytes != null && _thumbBytes!.isNotEmpty)
                Image.memory(
                  _thumbBytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => _buildFallback(),
                )
              else if (_isLoading)
                Container(
                  color: const Color(0xFF1E293B),
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                )
              else
                _buildFallback(),

              // 2. Play Button Overlay in center
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),

              // 3. Video label badge at bottom left
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_rounded, color: Colors.white, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        'VIDEO',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      color: const Color(0xFF111827),
      child: const Center(
        child: Icon(Icons.videocam_rounded, size: 40, color: Colors.white38),
      ),
    );
  }
}


