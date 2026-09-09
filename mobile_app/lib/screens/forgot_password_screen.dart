import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'otp_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiService.forgotPassword(
        identifier: _identifierCtrl.text.trim(),
      );

      if (res['success'] == true) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              identifier: _identifierCtrl.text.trim(),
              otpType: 'password_reset',
            ),
          ),
        );
      } else {
        setState(() => _error = res['message'] ?? 'Failed to request reset');
      }
    } catch (e) {
      setState(() => _error = 'Network error. Try again later.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Lock Icon
                    const Icon(
                      Icons.lock_outline,
                      color: Color(0xFF1D1D1F),
                      size: 24,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Account Recovery',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1D1D1F),
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF87171)),
                        ),
                        child: Text(
                          _error!,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFB91C1C),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Input
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF1F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextFormField(
                        controller: _identifierCtrl,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: 'name@gmail.com or 09xxxxxxxxx',
                          hintStyle: GoogleFonts.outfit(
                            color: const Color(0xFF86868B),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 16, horizontal: 16),
                        ),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _sendCode,
                        icon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          _loading ? 'Sending...' : 'Send Verification Code',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5722),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Back Link
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.arrow_back,
                              size: 16, color: Color(0xFFFF5722)),
                          const SizedBox(width: 4),
                          Text(
                            'Back to Login',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFFF5722),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
