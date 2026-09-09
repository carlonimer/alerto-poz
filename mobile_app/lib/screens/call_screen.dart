import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user.dart';
import '../services/socket_service.dart';

class CallScreen extends StatefulWidget {
  final UserModel? user;
  final bool isVideo;

  const CallScreen({super.key, required this.user, required this.isVideo});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with TickerProviderStateMixin {
  String _callStatus = 'ringing'; // ringing | connected | ended
  int _seconds = 0;
  Timer? _callTimer;
  late AnimationController _ringCtrl;
  late Animation<double> _ringAnim;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _ringAnim = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOut),
    );

    SocketService.init();
    _emitRinging();

    // Listen for acceptance from dispatcher
    SocketService.on('call-status-change', (data) {
      if (!mounted) return;
      final d = data as Map<String, dynamic>;
      if (d['status'] == 'accepted') {
        _onCallConnected();
      } else if (d['status'] == 'declined' || d['status'] == 'ended') {
        _onCallEnded();
      }
    });
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    _callTimer?.cancel();
    SocketService.off('call-status-change');
    super.dispose();
  }

  void _emitRinging() {
    SocketService.emitCallStatus({
      'status': 'ringing',
      'type': widget.isVideo ? 'video' : 'voice',
      'callerName': widget.user?.name ?? 'Citizen',
      'callerPhone': widget.user?.phone ?? '',
      'callerId': widget.user?.id ?? 0,
    });
  }

  void _onCallConnected() {
    _ringCtrl.stop();
    setState(() => _callStatus = 'connected');
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _onCallEnded() {
    _callTimer?.cancel();
    setState(() => _callStatus = 'ended');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _hangUp() {
    _callTimer?.cancel();
    SocketService.emitCallStatus({
      'status': 'ended',
      'callerName': widget.user?.name ?? 'Citizen',
      'callerPhone': widget.user?.phone ?? '',
      'callerId': widget.user?.id ?? 0,
    });
    Navigator.pop(context);
  }

  String get _durationStr {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _callStatus == 'connected'
                ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                : _callStatus == 'ended'
                    ? [Colors.grey.shade900, Colors.grey.shade700]
                    : [const Color(0xFF1A1A2E), const Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Call type badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isVideo ? 'Video Call' : 'Voice Call',
                      style: GoogleFonts.outfit(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Avatar
              ScaleTransition(
                scale: _callStatus == 'ringing' ? _ringAnim : const AlwaysStoppedAnimation(1.0),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38, width: 2),
                    boxShadow: _callStatus == 'ringing'
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.2),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.local_police_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Pozorrubio Command Center',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _callStatus == 'ringing'
                    ? 'Calling...'
                    : _callStatus == 'connected'
                        ? _durationStr
                        : 'Call Ended',
                style: GoogleFonts.outfit(
                  color: Colors.white60,
                  fontSize: 16,
                ),
              ),
              if (_callStatus == 'connected') ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                      const SizedBox(width: 6),
                      Text('Connected',
                          style: GoogleFonts.outfit(
                              color: Colors.greenAccent, fontSize: 13)),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              // Caller info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_rounded,
                          color: Colors.white60, size: 20),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.user?.name ?? 'Citizen',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              )),
                          Text(widget.user?.phone ?? '',
                              style: GoogleFonts.outfit(
                                  color: Colors.white60, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_callStatus == 'connected') ...[
                    _controlBtn(
                      icon: Icons.mic_off_rounded,
                      label: 'Mute',
                      color: Colors.white24,
                      onTap: () {}, // Simulated
                    ),
                    const SizedBox(width: 20),
                  ],
                  // Hang up
                  GestureDetector(
                    onTap: _hangUp,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.call_end_rounded,
                          color: Colors.white, size: 32),
                    ),
                  ),
                  if (_callStatus == 'connected') ...[
                    const SizedBox(width: 20),
                    _controlBtn(
                      icon: Icons.volume_up_rounded,
                      label: 'Speaker',
                      color: Colors.white24,
                      onTap: () {},
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }
}
