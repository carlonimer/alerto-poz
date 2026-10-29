import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsAndConditionsModal extends StatefulWidget {
  final String termsVersion;
  final String effectiveDate;
  final bool isSubmitting;
  final String? errorMessage;
  final Future<void> Function() onAccept;
  final Future<void> Function() onSignOut;
  final Future<void> Function()? onRetryStatus;

  const TermsAndConditionsModal({
    super.key,
    this.termsVersion = 'ALERTO_POZ_TERMS_V1',
    this.effectiveDate = 'October 29, 2026',
    required this.isSubmitting,
    this.errorMessage,
    required this.onAccept,
    required this.onSignOut,
    this.onRetryStatus,
  });

  @override
  State<TermsAndConditionsModal> createState() =>
      _TermsAndConditionsModalState();
}

class _TermsAndConditionsModalState extends State<TermsAndConditionsModal> {
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToBottom = false;
  bool _isChecked = false;
  bool _hasDeclined = false;

  static const List<Map<String, String>> _sections = [
    {
      'title': '1. Acceptance of Terms',
      'body':
          'By using the ALERTO-POZ application, you acknowledge that you have read and understood these Terms and Conditions. You must explicitly agree before continuing to use the application.',
    },
    {
      'title': '2. Accurate Account Information',
      'body':
          'You agree to provide accurate and up-to-date personal information during registration and account verification. You must not impersonate another person or submit false information or fraudulent identification documents.',
    },
    {
      'title': '3. ID Verification and Personal Information',
      'body':
          'ALERTO-POZ may collect and process identification information and ID images for identity verification, account security, and fraud prevention. Your personal information must be handled securely and processed only for legitimate, disclosed purposes in accordance with applicable Philippine data protection laws.',
    },
    {
      'title': '4. Emergency Reporting',
      'body':
          'You agree to use the emergency reporting and SOS features responsibly and provide accurate information, descriptions, and location details to the best of your ability.\n\nFalse, malicious, intentionally misleading, or abusive emergency reports are prohibited and may result in appropriate account restrictions or further action in accordance with applicable laws.',
    },
    {
      'title': '5. Location Services',
      'body':
          'ALERTO-POZ may request permission to access your device location to help identify your reported emergency location and assist authorized responders. Location accuracy may vary depending on your device, network, GPS signal, and permission settings.',
    },
    {
      'title': '6. Photos, Videos, and Evidence',
      'body':
          'When submitting photos, videos, or other evidence, you agree to provide relevant and truthful information. Do not submit fabricated evidence, manipulated media intended to deceive responders, or content that unlawfully violates another person\'s privacy.',
    },
    {
      'title': '7. Notifications and Emergency Updates',
      'body':
          'You may receive emergency-related notifications, incident updates, and authorized public safety alerts through the application. Notification delivery may depend on device permissions, connectivity, and service availability.',
    },
    {
      'title': '8. Responsible Use',
      'body':
          'You agree not to misuse, disrupt, exploit, or attempt to gain unauthorized access to the application, its APIs, user accounts, emergency records, or administrative functions.',
    },
    {
      'title': '9. Privacy and Data Protection',
      'body':
          'Your personal information will be collected, used, stored, retained, and disclosed only as permitted by applicable law and the published ALERTO-POZ Privacy Notice. Access to sensitive information must be restricted to authorized personnel with legitimate purposes.',
    },
    {
      'title': '10. Service Availability and Limitations',
      'body':
          'ALERTO-POZ is intended to support emergency communication and coordination. The application does not guarantee immediate responder dispatch, successful message delivery, uninterrupted service, or a particular emergency response time. In an urgent or life-threatening situation, contact the appropriate emergency services directly if possible.',
    },
    {
      'title': '11. Account Security and Restrictions',
      'body':
          'You are responsible for protecting your account credentials and notifying the appropriate administrator if you suspect unauthorized access. Accounts may be restricted for serious misuse, fraudulent activity, or violations of these terms, subject to applicable laws and appropriate procedures.',
    },
    {
      'title': '12. Updates to These Terms',
      'body':
          'ALERTO-POZ may update these Terms and Conditions when necessary. When a new version requires renewed acceptance, the application will display the updated agreement and request the user\'s consent before allowing continued access to protected app features.',
    },
    {
      'title': '13. Contact and Support',
      'body':
          'For questions about these terms, account verification, or privacy concerns, contact the authorized ALERTO-POZ administrator through the official support channels provided by the application.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant TermsAndConditionsModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.termsVersion != widget.termsVersion) {
      setState(() {
        _hasScrolledToBottom = false;
        _isChecked = false;
        _hasDeclined = false;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _hasScrolledToBottom) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 24) {
      setState(() {
        _hasScrolledToBottom = true;
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_hasScrolledToBottom && notification.metrics.maxScrollExtent > 0) {
      if (notification.metrics.pixels >=
          notification.metrics.maxScrollExtent - 24) {
        setState(() {
          _hasScrolledToBottom = true;
        });
      }
    }
    return false;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleDecline() {
    if (widget.isSubmitting) return;
    setState(() {
      _hasDeclined = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canAgree = _hasScrolledToBottom && _isChecked && !widget.isSubmitting;

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 480,
                  maxHeight: 740,
                ),
                child: Container(
                  key: const Key('terms_and_conditions_modal'),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF5722),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFF5722)
                                            .withValues(alpha: 0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.gavel_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Terms and Conditions',
                                        style: GoogleFonts.outfit(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Version: ${widget.termsVersion}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFFFF5722),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Please read and agree to the following terms before using the ALERTO-POZ Emergency Network.',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: const Color(0xFF64748B),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Scrollable Content Area
                      Expanded(
                        child: Container(
                          color: const Color(0xFFF8FAFC),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _handleScrollNotification,
                            child: Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                key: const Key('terms_scroll_view'),
                                controller: _scrollController,
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ALERTO-POZ Terms and Conditions',
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    ..._sections.map(
                                      (sec) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 14),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sec['title']!,
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF1E293B),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              sec['body']!,
                                              style: GoogleFonts.outfit(
                                                fontSize: 13,
                                                color: const Color(0xFF475569),
                                                height: 1.45,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const Divider(color: Color(0xFFE2E8F0)),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Last Updated: ${widget.effectiveDate}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF334155),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Implementation note: These terms are a draft and should be reviewed by the responsible LGU or legal/privacy officer before official deployment.',
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Footer Controls
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                          border: Border(
                            top: BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_hasScrolledToBottom)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () async {
                                    if (_scrollController.hasClients) {
                                      await _scrollController.animateTo(
                                        _scrollController.position.maxScrollExtent,
                                        duration: const Duration(milliseconds: 350),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                    if (mounted) {
                                      setState(() {
                                        _hasScrolledToBottom = true;
                                      });
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.arrow_downward_rounded,
                                          size: 15,
                                          color: Color(0xFFFF5722),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Please scroll to the bottom of the agreement to enable the checkbox.',
                                            key: const Key('scroll_prompt_text'),
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFFFF5722),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            // Error message banner (offline / failed API request)
                            if (widget.errorMessage != null &&
                                widget.errorMessage!.isNotEmpty)
                              Container(
                                key: const Key('terms_error_banner'),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFF87171),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: Color(0xFFDC2626),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.errorMessage!,
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          color: const Color(0xFFB91C1C),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (widget.onRetryStatus != null)
                                      TextButton(
                                        key: const Key('terms_retry_button'),
                                        onPressed: widget.isSubmitting
                                            ? null
                                            : () {
                                                setState(() {
                                                  _hasDeclined = false;
                                                });
                                                widget.onRetryStatus!();
                                              },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'Retry',
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFFDC2626),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                            // Decline warning banner
                            if (_hasDeclined)
                              Container(
                                key: const Key('terms_decline_banner'),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFB923C),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: Color(0xFFEA580C),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Agreement is required to continue using the ALERTO-POZ application.',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF9A3412),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          key: const Key('terms_sign_out_button'),
                                          onPressed: widget.isSubmitting
                                              ? null
                                              : widget.onSignOut,
                                          icon: const Icon(
                                            Icons.logout_rounded,
                                            size: 14,
                                          ),
                                          label: Text(
                                            'Sign Out',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFF9A3412),
                                            side: const BorderSide(
                                              color: Color(0xFFFB923C),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          key: const Key('terms_exit_app_button'),
                                          onPressed: widget.isSubmitting
                                              ? null
                                              : () => SystemNavigator.pop(),
                                          icon: const Icon(
                                            Icons.exit_to_app_rounded,
                                            size: 14,
                                          ),
                                          label: Text(
                                            'Exit App',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFFDC2626),
                                            side: const BorderSide(
                                              color: Color(0xFFF87171),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                            // Required Checkbox
                            InkWell(
                              key: const Key('terms_checkbox_row'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: (_hasScrolledToBottom &&
                                      !widget.isSubmitting)
                                  ? () {
                                      setState(() {
                                        _isChecked = !_isChecked;
                                        if (_isChecked) _hasDeclined = false;
                                      });
                                    }
                                  : null,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        key: const Key('terms_checkbox'),
                                        value: _isChecked,
                                        onChanged: (_hasScrolledToBottom &&
                                                !widget.isSubmitting)
                                            ? (val) {
                                                setState(() {
                                                  _isChecked = val ?? false;
                                                  if (_isChecked) {
                                                    _hasDeclined = false;
                                                  }
                                                });
                                              }
                                            : null,
                                        activeColor: const Color(0xFFFF5722),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'I have read and agree to the Terms and Conditions and acknowledge the Privacy Notice.',
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _hasScrolledToBottom
                                              ? const Color(0xFF1E293B)
                                              : const Color(0xFF94A3B8),
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Primary Action Button: I Agree and Continue
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                key: const Key('terms_agree_button'),
                                onPressed: canAgree ? widget.onAccept : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF5722),
                                  disabledBackgroundColor:
                                      const Color(0xFFE2E8F0),
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor:
                                      const Color(0xFF94A3B8),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: widget.isSubmitting
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'I Agree and Continue',
                                        style: GoogleFonts.outfit(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Secondary Action: Decline
                            SizedBox(
                              height: 40,
                              child: TextButton(
                                key: const Key('terms_decline_button'),
                                onPressed:
                                    widget.isSubmitting ? null : _handleDecline,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF64748B),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'Decline',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
      ),
    );
  }
}

