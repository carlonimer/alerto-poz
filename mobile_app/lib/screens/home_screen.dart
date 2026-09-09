import 'dart:async';
import 'dart:convert';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  UserModel? _user;
  List<dynamic> _incidents = [];
  List<dynamic> _responders = [];
  List<dynamic> _broadcasts = [];
  LatLng? _myLocation;
  bool _loadingLocation = false;
  bool _showBroadcastBanner = false;
  Map<String, dynamic>? _latestBroadcast;
  int _selectedTab = 0; // 0=map, 1=alerts, 2=profile

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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

  Future<void> _getMyLocation() async {
    setState(() => _loadingLocation = true);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _myLocation = LatLng(pos.latitude, pos.longitude);
        _loadingLocation = false;
      });
      _mapController.move(_myLocation!, 14);
    } else {
      setState(() => _loadingLocation = false);
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

  Future<void> _checkIn() async {
    final pos = _myLocation ?? (await LocationService.getCurrentPosition().then((p) {
      if (p != null) return LatLng(p.latitude, p.longitude);
      return null;
    }));
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not get location', style: GoogleFonts.outfit()),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    SocketService.emitCheckin({
      'name': _user?.name ?? 'Citizen',
      'phone': _user?.phone ?? '',
      'lat': pos.latitude,
      'lng': pos.longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Check-in sent to Command Center!',
            style: GoogleFonts.outfit()),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _pickProfileImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    
    if (!mounted) return;
    try {
      if (_user?.id != null) {
        final res = await ApiService.updateProfilePicture(_user!.id.toString(), image.path);
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated successfully!')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload image')),
      );
    }
  }

  void _showEditProfileDialog() {
    final fnameCtrl = TextEditingController();
    final lnameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Profile', style: GoogleFonts.outfit()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: fnameCtrl, decoration: const InputDecoration(labelText: 'First Name')),
            TextField(controller: lnameCtrl, decoration: const InputDecoration(labelText: 'Last Name')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = '${fnameCtrl.text} ${lnameCtrl.text}'.trim();
              if (name.isEmpty) return;
              try {
                await ApiService.updateProfile({
                  'id': _user?.id,
                  'name': name,
                  'email': _user?.email,
                  'phone': _user?.phone,
                });
                await _loadUser();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
                }
              } catch (e) {}
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  void _showMapSettingsDialog() {
    bool dark = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Map Settings', style: GoogleFonts.outfit()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Dark Mode Map'),
                value: dark,
                onChanged: (v) async {
                  setDialogState(() => dark = v);
                  try {
                    await ApiService.saveMapSettings(_user!.id.toString(), v ? 'dark' : 'light');
                  } catch (e) {}
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  void _showPasscodeSetupDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Passcode Lock', style: GoogleFonts.outfit()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: currentCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current Passcode')),
            TextField(controller: newCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'New Passcode')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                final res = await ApiService.setupPasscode(_user!.id.toString(), newCtrl.text);
                if (res['success'] == true) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passcode saved')));
                  }
                } else {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? 'Failed')));
                }
              } catch (e) {}
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  void _showFeedbackDialog() {
    final subjCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send Feedback', style: GoogleFonts.outfit()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: subjCtrl, decoration: const InputDecoration(labelText: 'Subject')),
            TextField(controller: msgCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (subjCtrl.text.isEmpty || msgCtrl.text.isEmpty) return;
              try {
                await ApiService.submitFeedback({
                  'user_id': _user?.id,
                  'subject': subjCtrl.text,
                  'category': 'Feedback',
                  'message': msgCtrl.text,
                });
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback sent!')));
                }
              } catch (e) {}
            },
            child: const Text('Send'),
          )
        ],
      ),
    );
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
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.alertopoz.app',
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
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
        // Map controls
        Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'myLoc',
                backgroundColor: Colors.white,
                onPressed: _loadingLocation ? null : _getMyLocation,
                child: _loadingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded,
                        color: Color(0xFF1A1A2E)),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'checkin',
                backgroundColor: Colors.green,
                onPressed: () => _ensureAuthenticated(() => _checkIn()),
                child:
                    const Icon(Icons.check_circle_outline_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
        // SOS FAB
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => _ensureAuthenticated(() {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SosChatScreen(user: _user),
                  ),
                ).then((_) => _loadData());
              }),
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.5),
                            blurRadius: 20 * _pulseAnimation.value,
                            spreadRadius: 4 * _pulseAnimation.value,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'SOS',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
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

  Widget _buildAlertsTab() {
    return _broadcasts.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none_rounded,
                    size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('No active alerts',
                    style: GoogleFonts.outfit(
                        color: Colors.grey[500], fontSize: 16)),
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

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _pickProfileImage,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFFFF5722).withValues(alpha: 0.15),
                  backgroundImage: _user?.profileImage != null ? MemoryImage(base64Decode(_user!.profileImage.split(',').last)) : null,
                  child: _user?.profileImage == null
                      ? Text(
                          (_user?.name.isNotEmpty == true)
                              ? _user!.name[0].toUpperCase()
                              : 'U',
                          style: GoogleFonts.outfit(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFF5722),
                          ),
                        )
                      : null,
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF5722),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _user?.name ?? 'Citizen',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5722).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _user?.type.toUpperCase() ?? 'CITIZEN',
              style: GoogleFonts.outfit(
                color: const Color(0xFFFF5722),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _ensureAuthenticated(() => _showEditProfileDialog()),
            icon: const Icon(Icons.edit, color: Color(0xFFFF5722)),
            label: Text('Edit Profile', style: GoogleFonts.outfit(color: const Color(0xFFFF5722))),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 32),
          _profileCard(Icons.phone_outlined, 'Phone', _user?.phone ?? '-'),
          const SizedBox(height: 12),
          _profileCard(Icons.email_outlined, 'Email', _user?.email ?? '-'),
          const SizedBox(height: 12),
          _profileCard(Icons.location_city_outlined, 'Municipality',
              'Pozorrubio, Pangasinan'),
          const SizedBox(height: 32),
          // Emergency Call button
          ElevatedButton.icon(
            onPressed: () => _ensureAuthenticated(() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(user: _user, isVideo: false),
                ),
              );
            }),
            icon: const Icon(Icons.phone_rounded),
            label: const Text('Emergency Voice Call'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _ensureAuthenticated(() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(user: _user, isVideo: true),
                ),
              );
            }),
            icon: const Icon(Icons.videocam_rounded),
            label: const Text('Emergency Video Call'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0)),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _ensureAuthenticated(() {
              if (_user != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistoryScreen(user: _user!),
                  ),
                );
              }
            }),
            icon: const Icon(Icons.history_rounded, color: Colors.white),
            label: Text('Emergency History',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF16213E),
              side: const BorderSide(color: Color(0xFF16213E)),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _ensureAuthenticated(() => _showMapSettingsDialog()),
            icon: const Icon(Icons.map_rounded, color: Colors.white),
            label: Text('Map Settings',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF16213E),
              side: const BorderSide(color: Color(0xFF16213E)),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _ensureAuthenticated(() => _showPasscodeSetupDialog()),
            icon: const Icon(Icons.pin_rounded, color: Colors.white),
            label: Text('Passcode Lock',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF16213E),
              side: const BorderSide(color: Color(0xFF16213E)),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _ensureAuthenticated(() => _showFeedbackDialog()),
            icon: const Icon(Icons.feedback_rounded, color: Colors.white),
            label: Text('Feedback',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF16213E),
              side: const BorderSide(color: Color(0xFF16213E)),
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          if (_user != null)
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, color: Colors.red),
              label: Text('Sign Out',
                  style: GoogleFonts.outfit(
                      color: Colors.red, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ).then((_) => _loadUser());
              },
              icon: const Icon(Icons.login_rounded, color: Colors.white),
              label: Text('Log In',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profileCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5722).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFFFF5722), size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 12, color: Colors.grey[500])),
              Text(value,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  )),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const Text('ALERT',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5722),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.wifi_tethering_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 4),
            const Text('-POZ',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        actions: [
          if (_selectedTab == 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('LIVE',
                      style: GoogleFonts.outfit(
                        color: Colors.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: _broadcasts.isNotEmpty,
              label: Text(_broadcasts.length.toString()),
              child: const Icon(Icons.notifications_rounded),
            ),
            onPressed: () => setState(() => _selectedTab = 1),
          ),
          IconButton(
            icon: const Icon(Icons.person_rounded),
            onPressed: () => setState(() => _selectedTab = 2),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildMapTab(),
          _buildAlertsTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (i) => setState(() => _selectedTab = i),
        indicatorColor: const Color(0xFFFF5722).withValues(alpha: 0.15),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon:
                Icon(Icons.map_rounded, color: Color(0xFFFF5722)),
            label: 'Live Map',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _broadcasts.isNotEmpty,
              label: Text(_broadcasts.length.toString()),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon:
                const Icon(Icons.notifications_rounded, color: Color(0xFFFF5722)),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded,
                color: Color(0xFFFF5722)),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
