import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String identifier;
  final String otp;

  const ResetPasswordScreen({
    super.key,
    required this.identifier,
    required this.otp,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (_passCtrl.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.resetPassword(
        identifier: widget.identifier,
        token: widget.otp,
        newPassword: _passCtrl.text,
      );
      if (res['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset successfully! Please sign in.',
                style: GoogleFonts.outfit()),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      } else {
        setState(() => _error = res['message'] ?? 'Reset failed');
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
              children: [
                const SizedBox(height: 60),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.lock_open_rounded,
                      color: Colors.green, size: 48),
                ),
                const SizedBox(height: 28),
                Text('New Password',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    )),
                const SizedBox(height: 8),
                Text('Create a strong new password',
                    style: GoogleFonts.outfit(
                      color: Colors.white60,
                      fontSize: 14,
                    )),
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
                        controller: _passCtrl,
                        obscureText: _obscurePass,
                        onChanged: (val) {
                          setState(() {
                            if (val.isEmpty && !_obscurePass) {
                              _obscurePass = true;
                            }
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'New Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: _passCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(_obscurePass
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined),
                                  onPressed: () => setState(
                                      () => _obscurePass = !_obscurePass),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscureConfirm,
                        onChanged: (val) {
                          setState(() {
                            if (val.isEmpty && !_obscureConfirm) {
                              _obscureConfirm = true;
                            }
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Confirm New Password',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          suffixIcon: _confirmCtrl.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(_obscureConfirm
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined),
                                  onPressed: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loading ? null : _resetPassword,
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Text('Reset Password'),
                      ),
                    ],
                  ),
                ),
              ],
            ))),
          ),
        ),
      ),
    );
  }
}
