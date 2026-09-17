import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../models/user.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';

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

  String? _incidentId;
  String? _selectedCategory;
  String? _ticketCode;
  bool _sent = false;
  bool _cancelled = false; // New cancelled state
  final List<Map<String, dynamic>> _chatFeed = [];
  final List<String> _attachedImages = []; // base64 strings

  bool _isMapExpanded = true;
  String _mapLayer = 'Standard'; // Standard, Satellite, Terrain
  Position? _currentPos;
  String _currentAddress = 'Locating...';

  static const List<Map<String, dynamic>> _categories = [
    {'key': 'medical', 'label': 'Medical', 'icon': Icons.local_hospital_rounded, 'color': Colors.red},
    {'key': 'fire', 'label': 'Fire', 'icon': Icons.local_fire_department_rounded, 'color': Colors.orange},
    {'key': 'crime', 'label': 'Crime', 'icon': Icons.local_police_rounded, 'color': Colors.blue},
    {'key': 'natural', 'label': 'Natural', 'icon': Icons.storm_rounded, 'color': Colors.teal},
    {'key': 'utility', 'label': 'Utility', 'icon': Icons.power_off_rounded, 'color': Colors.purple},
    {'key': 'other', 'label': 'Other', 'icon': Icons.warning_rounded, 'color': Color(0xFF424242)},
  ];

  @override
  void initState() {
    super.initState();
    _initLocation();

    if (widget.activeIncident != null) {
      _incidentId = widget.activeIncident!['_id']?.toString() ?? widget.activeIncident!['id']?.toString();
      _selectedCategory = widget.activeIncident!['category'];
      _ticketCode = widget.activeIncident!['ticketCode'] ?? 'ALERTOPOZ-26-854911';
      _sent = true;
      if (widget.activeIncident!['status'] == 'cancelled') {
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

    SocketService.on('chat-message', (data) {
      if (data['incident_id'] == _incidentId) {
        if (!mounted) return;
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
    });

    SocketService.on('incident-cancelled', (data) {
      if (data['id'] == _incidentId && mounted) {
        setState(() {
          _cancelled = true;
        });
        // We do not pop the context here to match web app behavior where user sees the cancelled message
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incident has been cancelled.')));
      }
    });
  }

  Future<void> _initLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (mounted && pos != null) {
      setState(() {
        _currentPos = pos;
        _currentAddress = 'Buneg, Pozorrubio, Pangasinan'; // Mocked address based on screenshot
      });
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
    }
  }

  Future<void> _fetchHistory() async {
    if (_incidentId == null) return;
    try {
      final res = await ApiService.fetchMessages(_incidentId!);
      if (res['success'] == true) {
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
    } catch (e) {}
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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

  void _selectCategory(String key, String label) async {
    if (_sent) return;
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
          { 'senderId': widget.user?.id, 'content': 'Image Attachment' },
          mediaPath: path
        );
      } catch(e) {}
    }
  }

  void _showCameraDialog() {
    String? tempImagePath;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF232736), // Dark theme color
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Capture Photo', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            Container(
                              height: 2, 
                              width: 80, 
                              color: const Color(0xFFF5A623), 
                              margin: const EdgeInsets.only(top: 4),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(6)), // Purple color
                          child: Row(
                            children: [
                              const Icon(Icons.flip_camera_ios, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text('Switch', style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Preview Area
                    Container(
                      height: 300,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[800]!),
                      ),
                      child: tempImagePath != null 
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.file(File(tempImagePath!), fit: BoxFit.cover),
                          )
                        : const Center(child: Icon(Icons.camera_alt, color: Colors.grey, size: 50)),
                    ),
                    const SizedBox(height: 20),
                    // Action Buttons
                    if (tempImagePath == null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
                              if (file != null) {
                                setDialogState(() {
                                  tempImagePath = file.path;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2196F3), // Blue Capture button
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text('Capture', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF44336), // Red Cancel button
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              setDialogState(() {
                                tempImagePath = null;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF5A623), // Orange Retake button
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text('Retake', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context); // Close dialog
                              _handleImageTaken(tempImagePath!); // Send image
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981), // Green Confirm button
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text('Confirm', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF44336), // Red Cancel button
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _sendSos() async {
    if (_selectedCategory == null) return;
    final pos = await LocationService.getCurrentPosition();
    _doTransmit(pos);
  }

  Future<void> _doTransmit(dynamic pos) async {
    final payload = {
      'id': _incidentId,
      'reporterId': widget.user?.id ?? 0,
      'reporterName': widget.user?.name ?? 'Citizen',
      'reporterPhone': widget.user?.phone ?? '',
      'category': _selectedCategory,
      'lat': pos?.latitude ?? 16.1086,
      'lng': pos?.longitude ?? 120.5424,
      'notes': _commentCtrl.text.trim(),
      'attachments': _attachedImages,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    };

    SocketService.emitSosReport(payload);

    if (!mounted) return;
    setState(() {
      _sent = true;
      _ticketCode = 'ALERTOPOZ-26-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
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
      } catch(e) {}
    }
  }

  Future<void> _cancelIncident() async {
    if (_incidentId == null) return;
    try {
      await ApiService.cancelIncident(_incidentId!);
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
    } catch(e) {}
  }

  void _showCloseIncidentDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Close Incident', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                Container(height: 2, width: double.infinity, color: const Color(0xFFF5A623)),
                const SizedBox(height: 16),
                Text('Are you sure you want to cancel this incident?\nThis will notify the Command Center that you have cancelled the emergency.', 
                  style: GoogleFonts.outfit(color: Colors.black87, fontSize: 14)),
                const SizedBox(height: 16),
                Text('Enter Passcode:', style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 8),
                TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFF5A623)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _cancelIncident();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF44336),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: Text('Confirm Close Incident', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
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

  void _showLayersMenu(BuildContext context, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy + 30, position.dx, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        _buildLayerMenuItem('Standard', Icons.map_outlined),
        _buildLayerMenuItem('Satellite', Icons.satellite_outlined),
        _buildLayerMenuItem('Terrain', Icons.terrain_outlined),
      ],
    ).then((value) {
      if (value != null) {
        setState(() => _mapLayer = value);
      }
    });
  }

  PopupMenuItem<String> _buildLayerMenuItem(String title, IconData icon) {
    final isSelected = _mapLayer == title;
    return PopupMenuItem<String>(
      value: title,
      child: Container(
        decoration: isSelected ? BoxDecoration(
          color: Colors.blue[600],
          borderRadius: BorderRadius.circular(6)
        ) : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.black87, size: 20),
            const SizedBox(width: 12),
            Text(title, style: GoogleFonts.outfit(color: isSelected ? Colors.white : Colors.black87, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    final d = DateTime.tryParse(isoDate)?.toLocal() ?? DateTime.now();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final hr = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final min = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year} ${hr.toString().padLeft(2, '0')}:$min $ampm';
  }

  Widget _buildChatBubble(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final type = msg['type'] as String;
    final timeStr = _formatDate(msg['timestamp'] as String?);

    if (type == 'image') {
      final isUrl = msg['content'].toString().startsWith('http') || msg['content'].toString().startsWith('/uploads');
      final imgUrl = msg['content'].toString().startsWith('http') ? msg['content'] : '${ApiService.baseUrl}${msg['content']}';
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 60, bottom: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: isUrl 
              ? Image.network(imgUrl, width: 200, height: 200, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50))
              : Image.memory(base64Decode(msg['content'] as String), width: 200, height: 200, fit: BoxFit.cover),
          ),
        ),
      );
    }

    if (type == 'system') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isUser ? const SizedBox(width: 32) : const CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.support_agent, color: Color(0xFFD32F2F), size: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isUser) Text('alertopoz', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black)),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF01579B) : const Color(0xFF9BAFB9).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(msg['content'] as String, style: GoogleFonts.outfit(color: isUser ? Colors.white : Colors.black87, fontSize: 14)),
                        if (msg['timestamp'] != null) ...[
                          const SizedBox(height: 6),
                          Text(timeStr, style: GoogleFonts.outfit(color: isUser ? Colors.white70 : Colors.black54, fontSize: 10)),
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isUser) const SizedBox(width: 8),
          ],
        ),
      );
    }

    if (type == 'activated') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.support_agent, color: Color(0xFFD32F2F), size: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('alertopoz', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black)),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFB0C4DE),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🚨 INCIDENT ACTIVATED', style: GoogleFonts.outfit(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Ticket Code: $_ticketCode', style: GoogleFonts.outfit(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Your emergency request has been received.\nKeep this ticket number for reference.\n\nYour emergency location and details have been sent to the Command Center.\nFor emergency validation, please provide:\n📸 Validation picture of the incident\n🎥 Validation video, if available\nStay calm and provide clear updates.', 
                          style: GoogleFonts.outfit(color: Colors.black87, fontSize: 13)),
                        const SizedBox(height: 6),
                        Text(timeStr, style: GoogleFonts.outfit(color: Colors.black54, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) const CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Icon(Icons.support_agent, color: Color(0xFFD32F2F), size: 20)),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF0066CC) : const Color(0xFFB0C4DE),
                borderRadius: BorderRadius.only(
                  topLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
                  topRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
                  bottomLeft: const Radius.circular(18),
                  bottomRight: const Radius.circular(18),
                ),
              ),
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(msg['content'] as String, style: GoogleFonts.outfit(color: isUser ? Colors.white : const Color(0xFF0B1E36), fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(timeStr, style: GoogleFonts.outfit(color: isUser ? Colors.white70 : Colors.black54, fontSize: 10)),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.home_outlined, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text('Alerto-poz ', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black)),
            if (_cancelled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)),
                child: Text('cancelled', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFFD32F2F))),
              )
            else
              Text(_sent ? 'Pending' : 'draft', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: _sent ? Colors.red : Colors.grey[700])),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(16),
          child: Padding(
            padding: const EdgeInsets.only(left: 56, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('No active responder', style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.phone, color: Colors.grey), onPressed: () {}),
          IconButton(icon: const Icon(Icons.videocam, color: Colors.grey), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert, color: Colors.grey), onPressed: () {}),
        ],
      ),
      body: Column(
        children: [
          // Orange Location Strip
          Container(
            color: const Color(0xFFF5A623),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_currentAddress, style: GoogleFonts.outfit(color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (_sent && !_cancelled)
                  GestureDetector(
                    onTap: _showCloseIncidentDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFF44336), borderRadius: BorderRadius.circular(16)),
                      child: Text('Close Incident', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTapDown: (details) => _showLayersMenu(context, details.globalPosition),
                  child: const Icon(Icons.layers, color: Colors.black87, size: 22),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(() => _isMapExpanded = !_isMapExpanded),
                  child: Icon(_isMapExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.black87, size: 24),
                ),
              ],
            ),
          ),
          
          // Map View
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: _isMapExpanded ? 200 : 0,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPos != null ? LatLng(_currentPos!.latitude, _currentPos!.longitude) : const LatLng(16.1086, 120.5424),
                initialZoom: 15.0,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.app',
                ),
                if (_currentPos != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(_currentPos!.latitude, _currentPos!.longitude),
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 12, height: 12,
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            ),
                          ),
                        ),
                      )
                    ],
                  )
              ],
            ),
          ),

          // Chat Header Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDate(DateTime.now().toIso8601String()), style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w600)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    children: [
                      Text(_sent ? (_ticketCode ?? 'PENDING') : 'DRAFT-5', style: GoogleFonts.outfit(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy, size: 12, color: Colors.black54),
                    ],
                  ),
                )
              ],
            ),
          ),

          // Chat feed
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                ..._chatFeed.map((msg) => _buildChatBubble(msg)),
                // if (!_sent && !_cancelled) _buildCategoryGrid(),
                const SizedBox(height: 20),
              ],
            ),
          ),
          
          // Bottom Input Bar
          if (!_cancelled)
            Container(
              color: const Color(0xFFF5F5F7),
              padding: EdgeInsets.only(left: 12, right: 12, top: 12, bottom: MediaQuery.of(context).padding.bottom + 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _attachGalleryImage,
                    child: Icon(Icons.image, color: Colors.grey[500], size: 26),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _showCameraDialog,
                    child: Icon(Icons.camera_alt, color: Colors.grey[500], size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        hintText: 'Type here...',
                        hintStyle: GoogleFonts.outfit(color: Colors.grey[500]),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendChatMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendChatMessage,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
