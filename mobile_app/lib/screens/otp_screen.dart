import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class OtpScreen extends StatefulWidget {
  final String identifier;
  final String otpType; // 'registration' | 'login' | 'password_reset'

  const OtpScreen({
    super.key,
    required this.identifier,
    required this.otpType,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _ctrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  bool _resending = false;
  String? _error;
  int _countdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _ctrls) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 0) {
        t.cancel();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  String get _otp => _ctrls.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 6) {
      setState(() => _error = 'Enter all 6 digits');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      String apiType = widget.otpType == 'registration' ? 'register' : (widget.otpType == 'password_reset' ? 'forgot' : 'login');
      final res = await ApiService.verifyOtp(
        identifier: widget.identifier,
        otp: _otp,
        type: apiType,
      );
      if (res['success'] == true) {
        if (res['token'] != null) {
          await ApiService.saveSession(
            token: res['token'],
            user: res['user'] ?? {},
          );
        }
        if (!mounted) return;
        if (widget.otpType == 'password_reset') {
          Navigator.pop(context, res['reset_token'] ?? _otp); // Return token for reset password screen
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
          );
        }
      } else {
        setState(() => _error = res['message'] ?? 'Invalid OTP');
      }
    } catch (e) {
      setState(() => _error = 'Cannot connect to server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      String apiType = widget.otpType == 'registration' ? 'register' : (widget.otpType == 'password_reset' ? 'forgot' : 'login');
      await ApiService.resendOtp(
        identifier: widget.identifier,
        type: apiType,
      );
      _startTimer();
    } catch (_) {
      setState(() => _error = 'Failed to resend OTP');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 48,
      height: 58,
      child: TextField(
        controller: _ctrls[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: const Color(0xFFF0F2F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFFF5722), width: 2.5),
          ),
        ),
        onChanged: (v) {
          if (v.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (v.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(child: Container(constraints: const BoxConstraints(maxWidth: 450), child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5722).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.shield_outlined,
                      color: Color(0xFFFF5722), size: 48),
                ),
                const SizedBox(height: 28),
                Text('Verify OTP',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    )),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code sent to\n${widget.identifier}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white60,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 40),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: const Color(0xFFEF9A9A)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Color(0xFFE53935), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFFE53935),
                                      fontSize: 13,
                                    )),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children:
                            List.generate(6, (i) => _buildOtpBox(i)),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton(
                        onPressed: _loading ? null : _verify,
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text('Verify & Continue'),
                      ),
                      const SizedBox(height: 16),
                      _countdown > 0
                          ? Text(
                              'Resend in $_countdown seconds',
                              style: GoogleFonts.outfit(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                            )
                          : TextButton(
                              onPressed: _resending ? null : _resend,
                              child: _resending
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text('Resend OTP',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFFFF5722),
                                        fontWeight: FontWeight.w600,
                                      )),
                            ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                TextButton.icon(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white54, size: 18),
                  label: Text('Back to Login',
                      style: GoogleFonts.outfit(color: Colors.white54)),
                ),
              ],
            ))),
          ),
        ),
      ),
    );
  }
}
