import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'otp_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  String? _regMethod; // 'phone' or 'email'

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_regMethod == null) {
      setState(() => _error = 'Please select a registration method.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.register(
        name: _nameCtrl.text.trim(),
        phone: _regMethod == 'phone' ? _phoneCtrl.text.trim() : '',
        email: _regMethod == 'email' ? _emailCtrl.text.trim() : '',
        password: _passCtrl.text,
      );
      if (res['success'] == true) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              identifier: _regMethod == 'phone' ? _phoneCtrl.text.trim() : _emailCtrl.text.trim(),
              otpType: 'registration',
            ),
          ),
        );
      } else {
        setState(() => _error = res['message'] ?? 'Registration failed');
      }
    } catch (e) {
      setState(() => _error = 'Cannot connect to server. Is it running?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildField({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    bool? obscureValue,
    VoidCallback? toggleObscure,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      onChanged: onChanged,
      obscureText: obscureValue ?? false,
      keyboardType: keyboardType,
      style: GoogleFonts.outfit(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
        prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFFF2F3F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF5722)),
        ),
        suffixIcon: toggleObscure != null && ctrl.text.isNotEmpty
            ? IconButton(
                icon: Icon(
                  (obscureValue ?? false)
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF64748B),
                ),
                onPressed: toggleObscure,
              )
            : null,
      ),
      validator: validator,
    );
  }

  Widget _buildChecklistItem(String text, bool isValid) {
    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF161E38), Color(0xFF0A1F33)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.chevron_left_rounded,
                            color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create Account',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                        const SizedBox(height: 2),
                        Text('Join Pozorrubio Emergency Network',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF94A3B8),
                              fontSize: 12,
                            )),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFF87171)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Color(0xFFEF4444), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_error!,
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFFEF4444),
                                        fontSize: 13,
                                      )),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildField(
                          ctrl: _nameCtrl,
                          hint: 'Full Name',
                          icon: Icons.badge_outlined,
                          validator: (v) =>
                              (v == null || v.length < 2) ? 'Enter your full name' : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _regMethod = 'phone'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _regMethod == 'phone' ? const Color(0xFFFF5722) : const Color(0xFFF2F3F5),
                                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                                  ),
                                  child: Center(
                                    child: Text('📱 Phone', style: GoogleFonts.outfit(
                                      color: _regMethod == 'phone' ? Colors.white : const Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    )),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _regMethod = 'email'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _regMethod == 'email' ? const Color(0xFFFF5722) : const Color(0xFFF2F3F5),
                                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                                  ),
                                  child: Center(
                                    child: Text('📧 Email', style: GoogleFonts.outfit(
                                      color: _regMethod == 'email' ? Colors.white : const Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    )),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_regMethod == 'phone')
                          _buildField(
                            ctrl: _phoneCtrl,
                            hint: 'Phone Number (09XXXXXXXXX)',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              if (_regMethod != 'phone') return null;
                              if (v == null || v.isEmpty) return 'Required';
                              if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(v)) {
                                return 'Enter valid PH number (09XXXXXXXXX)';
                              }
                              return null;
                            },
                          ),
                        if (_regMethod == 'email')
                          _buildField(
                            ctrl: _emailCtrl,
                            hint: 'Email Address',
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (_regMethod != 'email') return null;
                              if (v == null || v.isEmpty) return 'Required';
                              if (!v.contains('@')) return 'Enter valid email';
                              return null;
                            },
                          ),
                        if (_regMethod != null)
                          const SizedBox(height: 14),
                        _buildField(
                          ctrl: _passCtrl,
                          hint: 'Password',
                          icon: Icons.lock_outline_rounded,
                          obscureValue: _obscurePass,
                          toggleObscure: () =>
                              setState(() => _obscurePass = !_obscurePass),
                          onChanged: (val) {
                            setState(() {
                              if (val.isEmpty && !_obscurePass) {
                                _obscurePass = true;
                              }
                            });
                          },
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (v.length < 8) return 'Minimum 8 characters';
                            if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Requires uppercase letter';
                            if (!RegExp(r'[a-z]').hasMatch(v)) return 'Requires lowercase letter';
                            if (!RegExp(r'[0-9]').hasMatch(v)) return 'Requires number';
                            if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v)) return 'Requires special character';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        // Password Checklist
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildChecklistItem('8+ Characters', _passCtrl.text.length >= 8),
                              const SizedBox(height: 4),
                              _buildChecklistItem('1 Uppercase', RegExp(r'[A-Z]').hasMatch(_passCtrl.text)),
                              const SizedBox(height: 4),
                              _buildChecklistItem('1 Lowercase', RegExp(r'[a-z]').hasMatch(_passCtrl.text)),
                              const SizedBox(height: 4),
                              _buildChecklistItem('1 Number', RegExp(r'[0-9]').hasMatch(_passCtrl.text)),
                              const SizedBox(height: 4),
                              _buildChecklistItem('1 Special Char', RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(_passCtrl.text)),
                            ],
                          ),
                        ),
                        _buildField(
                          ctrl: _confirmCtrl,
                          hint: 'Confirm Password',
                          icon: Icons.lock_reset_rounded,
                          obscureValue: _obscureConfirm,
                          toggleObscure: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                          onChanged: (val) {
                            setState(() {
                              if (val.isEmpty && !_obscureConfirm) {
                                _obscureConfirm = true;
                              }
                            });
                          },
                          validator: (v) {
                            if (v != _passCtrl.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF5722),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Create Account',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account? ',
                        style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: Text('Sign In',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFFF5722),
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
