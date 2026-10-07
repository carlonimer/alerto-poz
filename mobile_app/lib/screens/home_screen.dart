import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
import '../main.dart';
import 'sos_chat_screen.dart';
import 'call_screen.dart';
import 'login_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  UserModel? _user;
  List<dynamic> _incidents = [];
  List<dynamic> _responders = [];
  List<dynamic> _broadcasts = [];
  LatLng? _myLocation;
  bool _showBroadcastBanner = false;
  Map<String, dynamic>? _latestBroadcast;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // SOS Flow variables
  Timer? _sosTimer;

  // Hazard Map Overlays
  bool _showFloodOverlay = false;
  bool _showWaterOverlay = false;

  // Map settings
  String _selectedMapType = 'default';

  static const LatLng _pozCenter = LatLng(16.1086, 120.5424);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _loadUser();
    _initSocket();
    _loadData();
    _getMyLocation();
  }

  @override
  void dispose() {
    SocketService.off('broadcast-alert');
    SocketService.off('incident-ack');
    _pulseController.dispose();
    _sosTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final data = await ApiService.getUser();
    if (data != null && mounted) {
      final user = UserModel.fromJson(data);
      setState(() {
        _user = user;
        if (user.mapSettings != null && user.mapSettings!['map_type'] != null) {
          _selectedMapType = user.mapSettings!['map_type'];
        }
      });
      _checkActiveIncident();
    }
  }

  Future<void> _checkActiveIncident() async {
    if (_user == null) return;
    try {
      final res = await ApiService.checkActiveIncident(_user!.id.toString());
      if (res['success'] == true && res['active'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have an active emergency incident.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch(e) {}
  }

  void _initSocket() {
    SocketService.init();
    SocketService.onBroadcastAdvisory((data) {
      if (!mounted) return;
      setState(() {
        _latestBroadcast = data as Map<String, dynamic>;
        _broadcasts.insert(0, data);
        _showBroadcastBanner = true;
      });
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) setState(() => _showBroadcastBanner = false);
      });
    });
    SocketService.onIncidentAck((data) {
      if (!mounted) return;
      _loadData();
    });
    SocketService.on('incident-updated', (data) {
      if (!mounted) return;
      _loadData();
    });
    SocketService.on('new-incident-alert', (data) {
      if (!mounted) return;
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final incidents = await ApiService.getIncidents();
    final responders = await ApiService.getResponders();
    final broadcasts = await ApiService.getBroadcasts();
    if (mounted) {
      setState(() {
        _incidents = incidents;
        _responders = responders;
        _broadcasts = broadcasts;
      });
    }
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(
        begin: _mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: _mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(
        begin: _mapController.camera.zoom, end: destZoom);

    final controller = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    
    final Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      _mapController.move(
          LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
          zoomTween.evaluate(animation));
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  Future<void> _getMyLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _myLocation = LatLng(pos.latitude, pos.longitude);
      });
      _animatedMapMove(_myLocation!, 17);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not fetch location. Please enable GPS.')),
      );
    }
  }

  void _ensureAuthenticated(VoidCallback action) {
    if (_user != null) {
      action();
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      ).then((_) => _loadUser());
    }
  }


  Future<void> _pickProfileImage() async {
    final ImagePicker picker = ImagePicker();
    
    // Show options for Camera or Gallery
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select Image Source', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? image = await picker.pickImage(source: source);
      if (image == null) return;
      
      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Picture',
            toolbarColor: Colors.white,
            toolbarWidgetColor: Colors.black,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Crop Profile Picture',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
        ],
      );

      if (croppedFile == null) return;

      if (!mounted) return;
      if (_user?.id != null) {
        final res = await ApiService.updateProfilePicture(_user!.id.toString(), croppedFile.path);
        if (!mounted) return;
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated successfully!')),
          );
          _loadUser(); // Refresh user data to show new image
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Failed to upload image')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload image. Please check permissions.')),
      );
    }
  }


  Future<void> _logout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign Out', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to sign out?', style: GoogleFonts.outfit()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.clearSession();
      SocketService.disconnect();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    }
  }

  Color _getBroadcastColor(String severity) {
    switch (severity) {
      case 'evacuate':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  bool get _showLabels => (_user?.mapSettings?['show_labels'] ?? 1) == 1 || _user?.mapSettings?['show_labels'] == true;
  bool get _showRoutes => (_user?.mapSettings?['show_routes'] ?? 1) == 1 || _user?.mapSettings?['show_routes'] == true;
  bool get _showMarkers => (_user?.mapSettings?['show_markers'] ?? 1) == 1 || _user?.mapSettings?['show_markers'] == true;
  bool get _locationControls => (_user?.mapSettings?['location_controls'] ?? 1) == 1 || _user?.mapSettings?['location_controls'] == true;

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // My location
    if (_myLocation != null) {
      markers.add(
        Marker(
          point: _myLocation!,
          width: 100,
          height: 100,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer waving radar circle
                  Container(
                    width: 40 + (60 * _pulseAnimation.value),
                    height: 40 + (60 * _pulseAnimation.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 1.0 - _pulseAnimation.value),
                        width: 2,
                      ),
                      color: Colors.blue.withValues(alpha: (1.0 - _pulseAnimation.value) * 0.1),
                    ),
                  ),
                  // Inner logo instead of solid dot
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      image: const DecorationImage(
                        image: AssetImage('assets/logo.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              );
            }
          ),
        ),
      );
    }

    if (!_showMarkers) return markers;

    // Responder markers
    for (final r in _responders) {
      final lat = (r['lat'] as num?)?.toDouble() ?? 0;
      final lng = (r['lng'] as num?)?.toDouble() ?? 0;
      final type = r['type'] as String? ?? 'medical';
      Color c = type == 'medical'
          ? Colors.green
          : type == 'fire'
              ? Colors.orange
              : Colors.blue;
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
            ),
            child: Icon(
              type == 'medical'
                  ? Icons.local_hospital_rounded
                  : type == 'fire'
                      ? Icons.local_fire_department_rounded
                      : Icons.local_police_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }

    return markers;
  }

  void _showIncidentSheet(Map<String, dynamic> incident) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.warning_rounded, color: Colors.red),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incident['category']?.toString().toUpperCase() ??
                            'INCIDENT',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Status: ${incident['status'] ?? 'Active'}',
                        style: GoogleFonts.outfit(
                            fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow(Icons.person_outline_rounded,
                incident['reporter_name']?.toString() ?? 'Unknown'),
            _infoRow(Icons.phone_outlined,
                incident['reporter_phone']?.toString() ?? ''),
            if (incident['notes'] != null && incident['notes'].toString().isNotEmpty)
              _infoRow(Icons.notes_rounded, incident['notes'].toString()),
            if (incident['assignedUnit'] != null && incident['assignedUnit'].toString().isNotEmpty)
              _infoRow(Icons.group_outlined, 'Assigned Unit: ${incident['assignedUnit']}'),
            if (incident['assignedVehicle'] != null && incident['assignedVehicle'].toString().isNotEmpty)
              _infoRow(Icons.directions_car_outlined, 'Assigned Vehicle: ${incident['assignedVehicle']}'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      user: _user,
                      isVideo: false,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.phone_rounded),
              label: const Text('Call Command Center'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.outfit(
                      fontSize: 14, color: Colors.grey[700]))),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: _pozCenter,
            initialZoom: 13,
          ),
          children: [
            TileLayer(
              urlTemplate: _selectedMapType == 'satellite'
                  ? (_showLabels ? 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}' : 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}')
                  : _selectedMapType == 'terrain'
                      ? 'https://mt1.google.com/vt/lyrs=p&x={x}&y={y}&z={z}'
                      : 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              additionalOptions: const {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
            ),
            PolygonLayer(
              polygons: [
                if (_showFloodOverlay)
                  Polygon(
                    points: const [
                      LatLng(16.1450, 120.5350),
                      LatLng(16.1360, 120.5550),
                      LatLng(16.1280, 120.5700),
                      LatLng(16.1320, 120.5750),
                      LatLng(16.1480, 120.5450),
                    ],
                    color: Colors.red.withValues(alpha: 0.25),
                    borderColor: Colors.red,
                    borderStrokeWidth: 2,
                  ),
                if (_showWaterOverlay)
                  Polygon(
                    points: const [
                      LatLng(16.1150, 120.5400),
                      LatLng(16.1150, 120.5550),
                      LatLng(16.1050, 120.5550),
                      LatLng(16.1050, 120.5400),
                    ],
                    color: Colors.blue.withValues(alpha: 0.18),
                    borderColor: Colors.blue,
                    borderStrokeWidth: 1.5,
                  ),
              ],
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
        // Search Pill
        Positioned(
          top: (_showBroadcastBanner && _latestBroadcast != null) ? 100 : 16,
          left: 16,
          right: 16,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.search, color: Colors.grey),
                const SizedBox(width: 12),
                const Icon(Icons.location_on, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '16.1160, 120.5615 (Pozorrubio, PG)',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_locationControls)
                  GestureDetector(
                    onTap: _getMyLocation,
                    child: const Icon(Icons.near_me, color: Colors.blue),
                  ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
        // Hazard map pills
        Positioned(
          top: (_showBroadcastBanner && _latestBroadcast != null) ? 156 : 72,
          left: 16,
          right: 16,
          child: Row(
            children: [
              _buildMapPill(
                icon: Icons.waves,
                label: 'Flood Map',
                isActive: _showFloodOverlay,
                activeColor: Colors.blue,
                onTap: () {
                  setState(() => _showFloodOverlay = !_showFloodOverlay);
                  if (_showFloodOverlay) {
                    _animatedMapMove(const LatLng(16.1400, 120.5550), 13.5);
                  }
                },
              ),
              const SizedBox(width: 8),
              _buildMapPill(
                icon: Icons.water,
                label: 'Water Levels',
                isActive: _showWaterOverlay,
                activeColor: Colors.blue,
                onTap: () {
                  setState(() => _showWaterOverlay = !_showWaterOverlay);
                  if (_showWaterOverlay) {
                    _animatedMapMove(const LatLng(16.1100, 120.5475), 14.0);
                  }
                },
              ),
              const Spacer(),
              GestureDetector(
                onTap: _showMapTypeDialog,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: const Icon(Icons.layers, color: Colors.black87, size: 20),
                ),
              ),
            ],
          ),
        ),
        // Broadcast banner
        if (_showBroadcastBanner && _latestBroadcast != null)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: GestureDetector(
              onTap: () => setState(() => _showBroadcastBanner = false),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getBroadcastColor(
                      _latestBroadcast!['severity'] as String? ?? 'info'),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.campaign_rounded,
                        color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _latestBroadcast!['title']?.toString() ??
                                'Emergency Alert',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            _latestBroadcast!['message']?.toString() ?? '',
                            style: GoogleFonts.outfit(
                                color: Colors.white70, fontSize: 12),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.close, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),
        // SOS FAB
        Positioned(
          bottom: 32,
          right: 20,
          child: Tooltip(
          message: 'Trigger Emergency SOS',
          child: GestureDetector(
            onTap: () => _ensureAuthenticated(() {
              _triggerSos();
            }),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Expanding wave 1
                      Container(
                        width: 80 + (40 * _pulseAnimation.value),
                        height: 80 + (40 * _pulseAnimation.value),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFF44336).withValues(alpha: 1.0 - _pulseAnimation.value),
                            width: 2,
                          ),
                          color: const Color(0xFFF44336).withValues(alpha: (1.0 - _pulseAnimation.value) * 0.2),
                        ),
                      ),
                      // Inner Solid SOS Button
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF44336),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF44336).withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset('assets/logo.png', width: 28, height: 28, color: Colors.white),
                            const SizedBox(height: 2),
                            Text(
                              'SOS',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
            ),
          ),
          ),
        ),
      ],
    );
  }

  void _showMapTypeDialog() {
    final settings = _user?.mapSettings ?? {};
    
    String capFirst(String? s) {
      if (s == null || s.isEmpty) return 'Default';
      return s[0].toUpperCase() + s.substring(1);
    }
    
    String mapType = capFirst(settings['map_type']);
    if (mapType == 'Default') mapType = 'Standard';
    if (!['Standard', 'Satellite', 'Terrain'].contains(mapType)) {
      mapType = 'Standard';
    }

    String navPref = settings['navigation_preference'] ?? 'Fastest Route';
    double notifRadius = (settings['notification_radius'] ?? 500).toDouble();
    double alertRadius = (settings['emergency_alert_radius'] ?? 1000).toDouble();
    bool liveLoc = settings['live_location'] == 1 || settings['live_location'] == true;
    bool gpsAccess = settings['gps_enabled'] == 1 || settings['gps_enabled'] == true || settings['gps_enabled'] == null;
    bool showLabels = settings['show_labels'] == 1 || settings['show_labels'] == true || settings['show_labels'] == null;
    bool showRoutes = settings['show_routes'] == 1 || settings['show_routes'] == true || settings['show_routes'] == null;
    bool showMarkers = settings['show_markers'] == 1 || settings['show_markers'] == true || settings['show_markers'] == null;
    bool locationControls = settings['location_controls'] == 1 || settings['location_controls'] == true || settings['location_controls'] == null;
    bool autoRefresh = settings['auto_refresh'] == 1 || settings['auto_refresh'] == true || settings['auto_refresh'] == null;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Map Settings', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      Container(height: 2, width: double.infinity, color: const Color(0xFFF4B400)),
                      const SizedBox(height: 16),
                      Text('Map Type', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      _buildDialogDropdown(
                        mapType,
                        ['Standard', 'Satellite', 'Terrain'],
                        (v) {
                          if (v != null) setStateDialog(() => mapType = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Navigation Preference', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      _buildDialogDropdown(
                        navPref,
                        ['Fastest Route', 'Shortest Route', 'Avoid Tolls'],
                        (v) {
                          if (v != null) setStateDialog(() => navPref = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Notification Radius (Meters: ${notifRadius.toInt()})', style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 13)),
                      Slider(
                        value: notifRadius,
                        min: 0,
                        max: 2000,
                        activeColor: Colors.blue,
                        onChanged: (v) => setStateDialog(() => notifRadius = v),
                      ),
                      Text('Emergency Alert Radius (Meters: ${alertRadius.toInt()})', style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 13)),
                      Slider(
                        value: alertRadius,
                        min: 0,
                        max: 5000,
                        activeColor: Colors.blue,
                        onChanged: (v) => setStateDialog(() => alertRadius = v),
                      ),
                      const SizedBox(height: 8),
                      _buildCheckbox('Show Labels', showLabels, (v) => setStateDialog(() => showLabels = v ?? false)),
                      _buildCheckbox('Show Routes', showRoutes, (v) => setStateDialog(() => showRoutes = v ?? false)),
                      _buildCheckbox('Show Markers', showMarkers, (v) => setStateDialog(() => showMarkers = v ?? false)),
                      _buildCheckbox('Location Controls', locationControls, (v) => setStateDialog(() => locationControls = v ?? false)),
                      _buildCheckbox('Enable Live Location', liveLoc, (v) => setStateDialog(() => liveLoc = v ?? false)),
                      _buildCheckbox('Allow GPS Access', gpsAccess, (v) => setStateDialog(() => gpsAccess = v ?? false)),
                      _buildCheckbox('Auto-Refresh Map', autoRefresh, (v) => setStateDialog(() => autoRefresh = v ?? false)),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isLoading ? null : () => Navigator.pop(context),
                            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isLoading ? null : () async {
                              if (_user == null) return;
                              setStateDialog(() => isLoading = true);
                              try {
                                final mapData = {
                                  'user_id': _user!.id,
                                  'map_type': mapType == 'Standard' ? 'default' : mapType.toLowerCase(),
                                  'show_labels': showLabels ? 1 : 0,
                                  'show_routes': showRoutes ? 1 : 0,
                                  'show_markers': showMarkers ? 1 : 0,
                                  'location_controls': locationControls ? 1 : 0,
                                  'live_location': liveLoc ? 1 : 0,
                                  'gps_enabled': gpsAccess ? 1 : 0,
                                  'navigation_preference': navPref,
                                  'notification_radius': notifRadius.toInt(),
                                  'emergency_alert_radius': alertRadius.toInt(),
                                  'auto_refresh': autoRefresh ? 1 : 0,
                                };
                                final res = await ApiService.saveMapSettings(mapData);
                                if (res['success'] == true && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Map settings saved!')));
                                  final updatedUser = _user!.copyWith(mapSettings: mapData);
                                  setState(() {
                                    _user = updatedUser;
                                    _selectedMapType = mapData['map_type'] as String? ?? 'default';
                                  });
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Failed to save settings')));
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                              } finally {
                                if (mounted) setStateDialog(() => isLoading = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF5A623),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDialogDropdown(String value, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.outfit()))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildCheckbox(String title, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFF5A623),
          ),
        ),
        const SizedBox(width: 12),
        Text(title, style: GoogleFonts.outfit(fontSize: 14)),
      ],
    );
  }

  Widget _buildMapPill({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.15) : Colors.white,
          border: Border.all(
            color: isActive ? activeColor : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: isActive ? [] : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? activeColor : Colors.grey[800]),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? activeColor : Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _triggerSos() {
    // Check if there is already an active incident for this user
    if (_user != null) {
      ApiService.checkActiveIncident(_user!.id.toString()).then((res) {
        if (!mounted) return;
        if (res['success'] == true && res['active'] == true) {
          // Show draft conflict modal
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: const Color(0xFFF9EAE1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_rounded, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text('Active Report', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.black87)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'You already have an ongoing emergency report. Do you want to continue with your current report or start a new one?',
                      style: GoogleFonts.outfit(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _navigateToChat(null); // Start new
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                                side: const BorderSide(color: Color(0xFF8B3A3A), width: 1.5),
                              ),
                            ),
                            child: Text('Start New', style: GoogleFonts.outfit(color: const Color(0xFF8B3A3A), fontWeight: FontWeight.w700, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _navigateToChat(null, res['incident'] as Map<String, dynamic>?);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF05023),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                              elevation: 2,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text('Continue', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                              ]
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        } else {
          _navigateToChat(null);
        }
      }).catchError((e) {
        _navigateToChat(null);
      });
    } else {
      _navigateToChat(null);
    }
  }

  void _navigateToChat(String? category, [Map<String, dynamic>? activeIncident]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SosChatScreen(
          user: _user,
          initialCategory: category,
          activeIncident: activeIncident,
        ),
      ),
    ).then((_) => _loadData());
  }

  Widget _buildAlertsTab() {
    return _broadcasts.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_off,
                    size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'No active broadcast alerts received in this session yet.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                        color: Colors.grey[500], fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _broadcasts.length,
            itemBuilder: (_, i) {
              final b = _broadcasts[i] as Map<String, dynamic>;
              final severity = b['severity'] as String? ?? 'info';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border(
                    left: BorderSide(
                      color: _getBroadcastColor(severity),
                      width: 5,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        _getBroadcastColor(severity).withValues(alpha: 0.15),
                    child: Icon(Icons.campaign_rounded,
                        color: _getBroadcastColor(severity)),
                  ),
                  title: Text(
                    b['title']?.toString() ?? 'Alert',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    b['message']?.toString() ?? '',
                    style: GoogleFonts.outfit(
                        fontSize: 13, color: Colors.grey[600]),
                    maxLines: 2,
                  ),
                ),
              );
            },
          );
  }

  void _showAlertsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Alerts', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            Expanded(child: _buildAlertsTab()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Text('ALERTO -POZ',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black)),
            const SizedBox(width: 4),
            const Icon(Icons.sensors, color: Color(0xFFFF5722), size: 22),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.black87),
            onPressed: () {
              _ensureAuthenticated(() {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.85,
                    child: HistoryScreen(user: _user!),
                  ),
                );
              });
            },
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _broadcasts.isNotEmpty,
              label: Text(_broadcasts.length.toString()),
              child: const Icon(Icons.notifications_rounded, color: Colors.black87),
            ),
            onPressed: _showAlertsSheet,
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _user == null
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    ).then((_) => _loadData());
                  }
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          user: _user,
                          onLogout: () async {
                            await ApiService.clearSession();
                            SocketService.disconnect();
                            if (!mounted) return;
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => const AuthGate()),
                              (_) => false,
                            );
                          },
                          onPickImage: _pickProfileImage,
                          onUserUpdated: (updatedUser) {
                            setState(() {
                              _user = updatedUser;
                              if (updatedUser.mapSettings != null && updatedUser.mapSettings!['map_type'] != null) {
                                _selectedMapType = updatedUser.mapSettings!['map_type'];
                              }
                            });
                          },
                        ),
                      ),
                    );
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'PROFILE',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _buildMapTab(),
    );
  }
}
