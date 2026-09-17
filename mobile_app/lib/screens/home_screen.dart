import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
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
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
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
      setState(() => _user = UserModel.fromJson(data));
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
    SocketService.onBroadcastAlert((data) {
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
    if (pos != null && mounted) {
      setState(() {
        _myLocation = LatLng(pos.latitude, pos.longitude);
      });
      _animatedMapMove(_myLocation!, 14);
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
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    
    if (!mounted) return;
    try {
      if (_user?.id != null) {
        final res = await ApiService.updateProfilePicture(_user!.id.toString(), image.path);
        if (!mounted) return;
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated successfully!')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload image')),
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
        MaterialPageRoute(builder: (_) => const LoginScreen()),
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

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // My location
    if (_myLocation != null) {
      markers.add(
        Marker(
          point: _myLocation!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: const Icon(Icons.my_location_rounded,
                color: Colors.blue, size: 20),
          ),
        ),
      );
    }

    // Incident markers
    for (final incident in _incidents) {
      final lat = (incident['lat'] as num?)?.toDouble() ?? 0;
      final lng = (incident['lng'] as num?)?.toDouble() ?? 0;
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _showIncidentSheet(incident),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(Icons.warning_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ),
      );
    }

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
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : _selectedMapType == 'terrain'
                      ? 'https://tile.opentopomap.org/{z}/{x}/{y}.png'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.alertopoz.app',
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
                const Icon(Icons.near_me, color: Colors.blue),
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
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF05023), Color(0xFFEF4444)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 28),
                        const SizedBox(height: 2),
                        Text(
                          'SOS',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
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
    showDialog(
      context: context,
      barrierColor: Colors.transparent, // Like the web popup
      builder: (ctx) => Stack(
        children: [
          Positioned(
            top: 140,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Map Type',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Icon(Icons.close, size: 20, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMapTypeOption(
                          type: 'default',
                          label: 'Default',
                          imageUrl: 'https://tile.openstreetmap.org/13/6826/3673.png',
                        ),
                        _buildMapTypeOption(
                          type: 'satellite',
                          label: 'Satellite',
                          imageUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/13/3673/6826',
                        ),
                        _buildMapTypeOption(
                          type: 'terrain',
                          label: 'Terrain',
                          imageUrl: 'https://tile.opentopomap.org/13/6826/3673.png',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapTypeOption({
    required String type,
    required String label,
    required String imageUrl,
  }) {
    final isSelected = _selectedMapType == type;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedMapType = type);
        Navigator.pop(context);
      },
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.transparent,
                width: 2,
              ),
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.blue : Colors.grey[700],
            ),
          ),
        ],
      ),
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
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('Active Report', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                'You already have an ongoing emergency report. Do you want to continue with your current report or start a new one?',
                style: GoogleFonts.outfit(),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _navigateToChat(null); // Start new
                  },
                  child: const Text('Start New'),
                ),
                ElevatedButton(
                  onPressed: _user == null
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
                            onLogout: () {
                              _logout();
                              Navigator.pop(context); // back to home
                            },
                            onPickImage: _pickProfileImage,
                          ),
                        ),
                      );
                    },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5722)),
                  child: const Text('Continue Current', style: TextStyle(color: Colors.white)),
                ),
              ],
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

  void _navigateToChat(String? category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SosChatScreen(
          user: _user,
          initialCategory: category,
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
                          onLogout: () {
                            _logout();
                            Navigator.pop(context); // back to home
                          },
                          onPickImage: _pickProfileImage,
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
