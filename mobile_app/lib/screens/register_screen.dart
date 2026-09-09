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
  final _confirmPassCtrl = TextEditingController();

  String _regMethod = 'phone'; // 'phone' or 'email'
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  // Password checklist state
  bool _hasLength = false;
  bool _hasUpper = false;
  bool _hasLower = false;
  bool _hasNum = false;
  bool _hasSpecial = false;

  @override
  void initState() {
    super.initState();
    _passCtrl.addListener(() {
      final p = _passCtrl.text;
      setState(() {
        _hasLength = p.length >= 8;
        _hasUpper = p.contains(RegExp(r'[A-Z]'));
        _hasLower = p.contains(RegExp(r'[a-z]'));
        _hasNum = p.contains(RegExp(r'[0-9]'));
        _hasSpecial = p.contains(RegExp(r'[!@#\$&*~]'));
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    
    bool validPass = _hasLength && _hasUpper && _hasLower && _hasNum && _hasSpecial;
    if (!validPass) {
      setState(() => _error = 'Please meet all password requirements');
      return;
    }

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
              identifier: _regMethod == 'phone'
                  ? _phoneCtrl.text.trim()
                  : _emailCtrl.text.trim(),
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

  Widget _buildChecklistItem(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
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
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    bool? obscureValue,
    VoidCallback? toggleObscure,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureValue ?? false,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: GoogleFonts.outfit(
            color: const Color(0xFF86868B),
            fontSize: 14,
          ),
          prefixIcon: Icon(icon, color: const Color(0xFF86868B), size: 20),
          suffixIcon: isPassword && toggleObscure != null
              ? IconButton(
                  icon: Icon(
                    obscureValue! ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xFF86868B),
                    size: 20,
                  ),
                  onPressed: toggleObscure,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        validator: validator ?? (v) => v!.isEmpty ? 'Required' : null,
      ),
    );
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
                    // Logo
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5722),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF5722).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.podcasts_rounded,
                          color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Create Account',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1D1D1F),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Join Pozorrubio Emergency Network',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: const Color(0xFF86868B),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Choose Registration Method',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1D1D1F),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Toggle Button
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF1F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _regMethod = 'phone';
                                _error = null;
                                _emailCtrl.clear();
                              }),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _regMethod == 'phone'
                                      ? const Color(0xFFFF5722)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.phone_android,
                                          size: 16,
                                          color: _regMethod == 'phone'
                                              ? Colors.white
                                              : const Color(0xFF86868B)),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Phone',
                                        style: GoogleFonts.outfit(
                                          color: _regMethod == 'phone'
                                              ? Colors.white
                                              : const Color(0xFF86868B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _regMethod = 'email';
                                _error = null;
                                _phoneCtrl.clear();
                              }),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _regMethod == 'email'
                                      ? const Color(0xFFFF5722)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.email_outlined,
                                          size: 16,
                                          color: _regMethod == 'email'
                                              ? Colors.white
                                              : const Color(0xFF86868B)),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Email',
                                        style: GoogleFonts.outfit(
                                          color: _regMethod == 'email'
                                              ? Colors.white
                                              : const Color(0xFF86868B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
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
                        ),
                      ),
                    ],

                    _buildInput(
                      controller: _nameCtrl,
                      hintText: 'Full Name',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 16),

                    if (_regMethod == 'phone')
                      _buildInput(
                        controller: _phoneCtrl,
                        hintText: 'Phone Number',
                        icon: Icons.phone_android,
                        keyboardType: TextInputType.phone,
                      )
                    else
                      _buildInput(
                        controller: _emailCtrl,
                        hintText: 'Email Address',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    const SizedBox(height: 16),

                    _buildInput(
                      controller: _passCtrl,
                      hintText: 'Password',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      obscureValue: _obscurePass,
                      toggleObscure: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    const SizedBox(height: 8),

                    // Password requirements checklist
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildChecklistItem('8+ Characters', _hasLength),
                          _buildChecklistItem('1 Uppercase', _hasUpper),
                          _buildChecklistItem('1 Lowercase', _hasLower),
                          _buildChecklistItem('1 Number', _hasNum),
                          _buildChecklistItem('1 Special Char', _hasSpecial),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildInput(
                      controller: _confirmPassCtrl,
                      hintText: 'Confirm Password',
                      icon: Icons.settings_backup_restore_rounded,
                      isPassword: true,
                      obscureValue: _obscureConfirm,
                      toggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      validator: (v) {
                        if (v!.isEmpty) return 'Required';
                        if (v != _passCtrl.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5722),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'Create Account',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Login Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Already have an account? ",
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: const Color(0xFF86868B),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            );
                          },
                          child: Text(
                            'Sign In',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFF5722),
                            ),
                          ),
                        ),
                      ],
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
