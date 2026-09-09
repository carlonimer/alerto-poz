import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'otp_screen.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifierCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final id = _identifierCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Please enter your phone or email');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.forgotPassword(identifier: id);
      if (res['success'] == true) {
        if (!mounted) return;
        // Navigate to OTP then password reset
        final otp = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              identifier: id,
              otpType: 'password_reset',
            ),
          ),
        );
        if (!mounted) return;
        if (otp != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ResetPasswordScreen(identifier: id, otp: otp),
            ),
          );
        }
      } else {
        setState(() => _error = res['message'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      setState(() => _error = 'Cannot connect to server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Center(child: Container(constraints: const BoxConstraints(maxWidth: 450), child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.lock_reset_rounded,
                      color: Color(0xFFFF9800), size: 48),
                ),
                const SizedBox(height: 28),
                Text('Forgot Password',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    )),
                const SizedBox(height: 8),
                Text(
                  'Enter your phone number or email\nto receive a reset OTP',
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
                          child: Text(_error!,
                              style: GoogleFonts.outfit(
                                color: const Color(0xFFE53935),
                                fontSize: 13,
                              )),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _identifierCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Phone or Email',
                          prefixIcon: Icon(Icons.person_search_rounded),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loading ? null : _sendOtp,
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text('Send Reset OTP'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
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
