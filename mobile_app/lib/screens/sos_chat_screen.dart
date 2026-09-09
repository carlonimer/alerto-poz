import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/user.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';

class SosChatScreen extends StatefulWidget {
  final UserModel? user;
  final Map<String, dynamic>? activeIncident;

  const SosChatScreen({super.key, required this.user, this.activeIncident});

  @override
  State<SosChatScreen> createState() => _SosChatScreenState();
}

class _SosChatScreenState extends State<SosChatScreen>
    with TickerProviderStateMixin {
  final _commentCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String? _incidentId;
  String? _selectedCategory;
  bool _sent = false;
  bool _sending = false;
  int _countdown = 5;
  Timer? _countdownTimer;
  final List<Map<String, dynamic>> _chatFeed = [];
  final List<String> _attachedImages = []; // base64 strings

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const List<Map<String, dynamic>> _categories = [
    {'key': 'medical', 'label': 'Medical', 'icon': Icons.medical_services_rounded, 'color': 0xFFE53935},
    {'key': 'fire', 'label': 'Fire', 'icon': Icons.local_fire_department_rounded, 'color': 0xFFFF6D00},
    {'key': 'crime', 'label': 'Police', 'icon': Icons.local_police_rounded, 'color': 0xFF1565C0},
    {'key': 'barangay', 'label': 'Barangay', 'icon': Icons.account_balance_rounded, 'color': 0xFF6A1B9A},
    {'key': 'accident', 'label': 'Accident', 'icon': Icons.car_crash_rounded, 'color': 0xFFE65100},
    {'key': 'roadside', 'label': 'Roadside', 'icon': Icons.construction_rounded, 'color': 0xFF827717},
    {'key': 'women', 'label': 'Women & Children', 'icon': Icons.family_restroom_rounded, 'color': 0xFFAD1457},
    {'key': 'disaster', 'label': 'Disaster', 'icon': Icons.thunderstorm_rounded, 'color': 0xFF00838F},
    {'key': 'earthquake', 'label': 'Earthquake', 'icon': Icons.vibration_rounded, 'color': 0xFF558B2F},
    {'key': 'inquiry', 'label': 'Inquiry', 'icon': Icons.help_rounded, 'color': 0xFF00695C},
    {'key': 'report', 'label': 'Report', 'icon': Icons.report_rounded, 'color': 0xFF4527A0},
    {'key': 'sos', 'label': 'SOS', 'icon': Icons.sos_rounded, 'color': 0xFFB71C1C},
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    if (widget.activeIncident != null) {
      _incidentId = widget.activeIncident!['_id']?.toString() ?? widget.activeIncident!['id']?.toString();
      _selectedCategory = widget.activeIncident!['category'];
      _sent = true;
      _chatFeed.add({
        'role': 'bot',
        'type': 'success',
        'content': '✅ Connected to active emergency session.',
      });
      _fetchHistory();
    } else {
      _chatFeed.add({
        'role': 'bot',
        'type': 'text',
        'content': 'What is your emergency? Select a category or describe your situation.',
      });
    }

    SocketService.on('chat-message', (data) {
      if (data['incident_id'] == _incidentId) {
        if (!mounted) return;
        setState(() {
          _chatFeed.add({
            'role': data['sender_id'] == widget.user?.id.toString() ? 'user' : 'bot',
            'type': data['is_media'] == true ? 'image' : 'text',
            'content': data['message'],
          });
        });
        _scrollToBottom();
      }
    });

    SocketService.on('incident-cancelled', (data) {
      if (data['id'] == _incidentId && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incident was cancelled.')));
      }
    });
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
    _countdownTimer?.cancel();
    _pulseCtrl.dispose();
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
      _chatFeed.add({'role': 'user', 'type': 'text', 'content': 'Category: $label'});
      _chatFeed.add({
        'role': 'bot',
        'type': 'text',
        'content': 'Understood. You can add comments or photos, then tap SEND SOS ALERT.',
      });
    });
    _scrollToBottom();
    
    try {
      final pos = await LocationService.getCurrentPosition();
      final res = await ApiService.createDraftIncident({
        'reporterId': widget.user?.id,
        'category': key,
        'lat': pos?.latitude ?? 16.1086,
        'lng': pos?.longitude ?? 120.5424,
      });
      if (res['success'] == true && res['incident'] != null) {
        _incidentId = res['incident']['id'];
      }
    } catch (e) {}
  }

  Future<void> _attachImage() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
    );
    if (file == null) return;
    
    if (_sent && _incidentId != null) {
      // Send directly via chat API
      try {
        final res = await ApiService.sendMessage(
          _incidentId!, 
          { 'senderId': widget.user?.id, 'content': 'Image Attachment' },
          mediaPath: file.path
        );
        // message will come via socket
      } catch(e) {}
    } else {
      // Draft phase
      final bytes = await File(file.path).readAsBytes();
      final b64 = base64Encode(bytes);
      setState(() {
        _attachedImages.add(b64);
        _chatFeed.add({
          'role': 'user',
          'type': 'image',
          'content': b64,
        });
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendSos() async {
    if (_sent || _selectedCategory == null) {
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please select an emergency category first',
                style: GoogleFonts.outfit()),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final pos = await LocationService.getCurrentPosition();
    final comments = _commentCtrl.text.trim();

    if (comments.isNotEmpty) {
      setState(() {
        _chatFeed.add({'role': 'user', 'type': 'text', 'content': comments});
        _commentCtrl.clear();
      });
    }

    setState(() => _sending = true);
    _countdown = 5;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _doTransmit(pos);
      }
    });
  }

  void _cancelSend() {
    _countdownTimer?.cancel();
    setState(() {
      _sending = false;
      _countdown = 5;
    });
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
      'status': 'pending', // Web socket logic turns it into pending
    };

    SocketService.emitSosReport(payload);

    if (!mounted) return;
    setState(() {
      _sent = true;
      _sending = false;
      _chatFeed.add({
        'role': 'bot',
        'type': 'success',
        'content':
            '✅ SOS Alert transmitted to Pozorrubio Command Center. Help is on the way. Stay calm and stay put.',
      });
      _commentCtrl.clear();
    });
    _scrollToBottom();
  }

  Future<void> _sendChatMessage() async {
    final txt = _commentCtrl.text.trim();
    if (txt.isEmpty || _incidentId == null) return;
    _commentCtrl.clear();
    
    try {
      await ApiService.sendMessage(_incidentId!, {
        'senderId': widget.user?.id,
        'content': txt,
      });
    } catch(e) {}
  }

  Future<void> _cancelIncident() async {
    if (_incidentId == null) return;
    try {
      await ApiService.cancelIncident(_incidentId!);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Emergency Cancelled')));
      }
    } catch(e) {}
  }

  Widget _buildCategoryGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _categories.length,
      itemBuilder: (_, i) {
        final cat = _categories[i];
        final isSelected = _selectedCategory == cat['key'];
        final color = Color(cat['color'] as int);
        return GestureDetector(
          onTap: () => _selectCategory(
              cat['key'] as String, cat['label'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? color : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? color : color.withValues(alpha: 0.3),
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  cat['icon'] as IconData,
                  color: isSelected ? Colors.white : color,
                  size: 28,
                ),
                const SizedBox(height: 6),
                Text(
                  cat['label'] as String,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: isSelected ? Colors.white : color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final type = msg['type'] as String;

    if (type == 'image') {
      final isUrl = msg['content'].toString().startsWith('http') || msg['content'].toString().startsWith('/uploads');
      final imgUrl = msg['content'].toString().startsWith('http') ? msg['content'] : '${ApiService.baseUrl}${msg['content']}';
      
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 60, bottom: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: isUrl 
              ? Image.network(
                  imgUrl,
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
                )
              : Image.memory(
                  base64Decode(msg['content'] as String),
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                ),
          ),
        ),
      );
    }

    final isSuccess = type == 'success';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isUser ? 60 : 0,
          right: isUser ? 0 : 60,
          bottom: 8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSuccess
              ? Colors.green.shade50
              : isUser
                  ? const Color(0xFFFF5722)
                  : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(16),
          ),
          border: isSuccess
              ? Border.all(color: Colors.green.shade200)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          msg['content'] as String,
          style: GoogleFonts.outfit(
            color: isSuccess
                ? Colors.green.shade800
                : isUser
                    ? Colors.white
                    : const Color(0xFF1A1A2E),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SOS Emergency',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                )),
            Text(
              _sent
                  ? '✅ Alert Sent'
                  : _selectedCategory == null
                      ? 'Select emergency type'
                      : 'Ready to transmit',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: _sent
                    ? Colors.green
                    : _selectedCategory == null
                        ? Colors.grey[500]
                        : const Color(0xFFFF5722),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Chat feed
          Expanded(
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                // Chat messages
                ..._chatFeed.map((msg) => _buildChatBubble(msg)),
                const SizedBox(height: 8),
                // Category grid
                if (!_sent) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Emergency Category',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: const Color(0xFF1A1A2E),
                            )),
                        const SizedBox(height: 12),
                        _buildCategoryGrid(),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
          // Sending countdown overlay
          if (_sending)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$_countdown',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Transmitting in $_countdown seconds...',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _cancelSend,
                    child: Text('CANCEL',
                        style: GoogleFonts.outfit(
                            color: Colors.orange,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          // Bottom input bar
          if (!_sending)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _attachImage,
                        icon: const Icon(Icons.add_photo_alternate_rounded,
                            color: Color(0xFFFF5722)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _commentCtrl,
                          decoration: InputDecoration(
                            hintText: 'Add details, location description...',
                            hintStyle: GoogleFonts.outfit(
                                fontSize: 14, color: Colors.grey[400]),
                            filled: true,
                            fillColor: const Color(0xFFF0F2F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!_sent)
                    GestureDetector(
                      onTap: _sendSos,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.sos_rounded,
                                color: Colors.white, size: 24),
                            const SizedBox(width: 10),
                            Text('SEND SOS ALERT',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  letterSpacing: 1,
                                )),
                          ],
                        ),
                      ),
                    ),
                  if (_sent)
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _cancelIncident,
                            icon: const Icon(Icons.cancel_rounded, color: Colors.grey),
                            label: const Text('Cancel Emergency', style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _sendChatMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5722),
                            minimumSize: const Size(60, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                ],
              ),
            ),

        ],
      ),
    );
  }
}
