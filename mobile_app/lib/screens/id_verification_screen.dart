import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SelectedIdFile {
  final Uint8List bytes;
  final String fileName;
  final int sizeBytes;

  const SelectedIdFile({
    required this.bytes,
    required this.fileName,
    required this.sizeBytes,
  });
}

typedef IdFilePickerCallback = Future<SelectedIdFile?> Function(bool isFront);

class IdVerificationScreen extends StatefulWidget {
  final IdFilePickerCallback? customFilePicker;

  const IdVerificationScreen({
    super.key,
    this.customFilePicker,
  });

  @override
  State<IdVerificationScreen> createState() => _IdVerificationScreenState();
}

class _IdVerificationScreenState extends State<IdVerificationScreen> {
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const List<String> _idTypes = ApiService.validIdTypes;

  UserModel? _user;
  bool _loadingStatus = true;
  bool _submitting = false;
  bool _pickingFront = false;
  bool _pickingBack = false;

  String _verificationStatus = 'Unsubmitted'; // 'Unsubmitted' | 'Pending' | 'Approved' | 'Rejected'
  String? _selectedIdType;
  String? _submittedIdType;
  String? _rejectionReason;
  int? _submittedAt;

  SelectedIdFile? _frontFile;
  SelectedIdFile? _backFile;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  @override
  void dispose() {
    SocketService.off('id-verification-updated');
    super.dispose();
  }

  Future<void> _initScreen() async {
    await _loadLocalUser();
    _initRealtimeUpdates();
    await _refreshVerificationStatus();
  }

  void _initRealtimeUpdates() {
    try {
      SocketService.init();
      SocketService.onIdVerificationUpdated((data) async {
        if (!mounted) return;
        if (data is Map) {
          final targetUserId = data['userId']?.toString();
          if (_user != null && targetUserId != null && targetUserId != _user!.id.toString()) {
            return;
          }
          await _refreshVerificationStatus();
        }
      });
    } catch (_) {}
  }

  Future<void> _loadLocalUser() async {
    final userData = await ApiService.getUser();
    if (!mounted) return;
    if (userData != null) {
      final user = UserModel.fromJson(userData);
      final normalizedStatus = _normalizeStatus(user.verificationStatus, user.idVerified);
      setState(() {
        _user = user;
        _verificationStatus = normalizedStatus;
        _submittedIdType = user.idType;
        if (user.idType != null && _idTypes.contains(user.idType)) {
          _selectedIdType ??= user.idType;
        }
        _rejectionReason = user.rejectionReason;
        _submittedAt = user.idSubmittedAt;
      });
      if (normalizedStatus == 'Approved') {
        _navigateToDashboard();
      }
    }
  }

  String _normalizeStatus(String rawStatus, bool idVerified) {
    final lower = rawStatus.trim().toLowerCase();
    if (idVerified || lower == 'approved') return 'Approved';
    if (lower == 'pending') return 'Pending';
    if (lower == 'rejected') return 'Rejected';
    return 'Unsubmitted';
  }

  Future<void> _refreshVerificationStatus({bool showFeedback = false}) async {
    if (!mounted) return;
    setState(() {
      _loadingStatus = true;
      if (showFeedback) {
        _errorMessage = null;
      }
    });

    try {
      final res = await ApiService.getIdVerificationStatus();
      if (!mounted) return;

      final statusCode = res['_statusCode'] as int? ?? 200;
      if (statusCode == 200 && res['success'] == true) {
        if (res['user'] is Map<String, dynamic>) {
          final userMap = res['user'] as Map<String, dynamic>;
          await ApiService.updateUserLocal(userMap);
          if (!mounted) return;
          _user = UserModel.fromJson(userMap);
        }
        final statusStr = res['status']?.toString() ??
            _user?.verificationStatus ??
            'Unsubmitted';
        final isVerified = res['id_verified'] == true ||
            res['idVerified'] == true ||
            statusStr.toLowerCase() == 'approved';
        final normalized = _normalizeStatus(statusStr, isVerified);

        final idTypeFromServer =
            (res['id_type'] ?? res['idType'])?.toString() ?? _user?.idType;
        final reasonFromServer =
            (res['rejection_reason'] ?? res['rejectionReason'])?.toString() ??
                _user?.rejectionReason;
        final rawSubmittedAt = res['submitted_at'] ?? res['submittedAt'];
        final submittedAtFromServer = rawSubmittedAt is int
            ? rawSubmittedAt
            : int.tryParse(rawSubmittedAt?.toString() ?? '');

        setState(() {
          _verificationStatus = normalized;
          _submittedIdType = idTypeFromServer;
          if (idTypeFromServer != null && _idTypes.contains(idTypeFromServer)) {
            _selectedIdType ??= idTypeFromServer;
          }
          _rejectionReason = reasonFromServer;
          _submittedAt = submittedAtFromServer ?? _submittedAt;
          _loadingStatus = false;
        });

        if (normalized == 'Approved') {
          _navigateToDashboard();
          return;
        }
      } else if (statusCode == 401) {
        await _signOut();
        return;
      } else {
        setState(() {
          _loadingStatus = false;
          if (showFeedback) {
            _errorMessage = res['error']?.toString() ??
                'Unable to check verification status. Please try again.';
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingStatus = false;
        if (showFeedback) {
          _errorMessage =
              'Network error while checking status. Please check your connection.';
        }
      });
    }
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    });
  }

  bool _isAllowedImageFormat(String fileName, Uint8List bytes) {
    final lower = fileName.trim().toLowerCase();
    final hasValidExt = lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
    if (!hasValidExt) return false;

    if (bytes.length < 4) return false;
    final isPng = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final isJpg = bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;

    return isPng || isJpg;
  }

  String? _validateSelectedFile(SelectedIdFile file, String sideLabel) {
    if (file.sizeBytes <= 0 || file.bytes.isEmpty) {
      return '$sideLabel image file is empty or unreadable.';
    }
    if (file.sizeBytes > _maxFileSizeBytes || file.bytes.length > _maxFileSizeBytes) {
      return '$sideLabel image exceeds the 5MB maximum file size limit.';
    }
    if (!_isAllowedImageFormat(file.fileName, file.bytes)) {
      return 'Invalid file type for $sideLabel. Only PNG and JPG/JPEG images are accepted.';
    }
    return null;
  }

  Future<void> _pickImage({required bool isFront}) async {
    if (_submitting || _pickingFront || _pickingBack) return;

    setState(() {
      if (isFront) {
        _pickingFront = true;
      } else {
        _pickingBack = true;
      }
      _errorMessage = null;
    });

    try {
      SelectedIdFile? picked;
      if (widget.customFilePicker != null) {
        picked = await widget.customFilePicker!(isFront);
      } else {
        final picker = ImagePicker();
        final XFile? xfile = await picker.pickImage(source: ImageSource.gallery);
        if (xfile != null) {
          final bytes = await xfile.readAsBytes();
          picked = SelectedIdFile(
            bytes: bytes,
            fileName: xfile.name.isNotEmpty ? xfile.name : xfile.path.split(RegExp(r'[/\\]')).last,
            sizeBytes: bytes.length,
          );
        }
      }

      if (!mounted) return;

      // Graceful handling when user cancels file selection
      if (picked == null) {
        return;
      }

      final sideLabel = isFront ? 'ID Front Side' : 'ID Back Side';
      final validationError = _validateSelectedFile(picked, sideLabel);
      if (validationError != null) {
        setState(() {
          _errorMessage = validationError;
        });
        return;
      }

      setState(() {
        if (isFront) {
          _frontFile = picked;
        } else {
          _backFile = picked;
        }
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not access the selected image. Please grant photo/storage permission and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          if (isFront) {
            _pickingFront = false;
          } else {
            _pickingBack = false;
          }
        });
      }
    }
  }

  void _removeImage({required bool isFront}) {
    if (_submitting) return;
    setState(() {
      if (isFront) {
        _frontFile = null;
      } else {
        _backFile = null;
      }
      _errorMessage = null;
    });
  }

  Future<void> _submitVerification() async {
    // Prevent duplicate submissions while a request is processing
    if (_submitting) return;

    setState(() {
      _errorMessage = null;
    });

    if (_selectedIdType == null || !_idTypes.contains(_selectedIdType)) {
      setState(() {
        _errorMessage = 'Please select a valid ID Type before submitting.';
      });
      return;
    }

    if (_frontFile == null) {
      setState(() {
        _errorMessage = 'Please upload your ID Front Side image.';
      });
      return;
    }

    if (_backFile == null) {
      setState(() {
        _errorMessage = 'Please upload your ID Back Side image.';
      });
      return;
    }

    final frontErr = _validateSelectedFile(_frontFile!, 'ID Front Side');
    if (frontErr != null) {
      setState(() => _errorMessage = frontErr);
      return;
    }

    final backErr = _validateSelectedFile(_backFile!, 'ID Back Side');
    if (backErr != null) {
      setState(() => _errorMessage = backErr);
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final res = await ApiService.submitIdVerification(
        idType: _selectedIdType!,
        frontFileBytes: _frontFile!.bytes,
        frontFileName: _frontFile!.fileName,
        backFileBytes: _backFile!.bytes,
        backFileName: _backFile!.fileName,
      );

      if (!mounted) return;

      final statusCode = res['_statusCode'] as int? ?? 200;
      if (statusCode == 200 && res['success'] == true) {
        if (res['user'] is Map<String, dynamic>) {
          final userMap = res['user'] as Map<String, dynamic>;
          await ApiService.updateUserLocal(userMap);
          if (!mounted) return;
          _user = UserModel.fromJson(userMap);
        } else if (_user != null) {
          final updatedUser = _user!.copyWith(
            idVerified: false,
            verificationStatus: 'Pending',
            idType: _selectedIdType,
            clearRejectionReason: true,
            idSubmittedAt: res['submitted_at'] is int
                ? res['submitted_at'] as int
                : DateTime.now().millisecondsSinceEpoch,
          );
          _user = updatedUser;
          await ApiService.updateUserLocal(updatedUser.toJson());
        }

        if (!mounted) return;
        setState(() {
          _verificationStatus = 'Pending';
          _submittedIdType = _selectedIdType;
          _rejectionReason = null;
          _submittedAt = res['submitted_at'] is int
              ? res['submitted_at'] as int
              : DateTime.now().millisecondsSinceEpoch;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = res['error']?.toString() ??
              res['message']?.toString() ??
              'Failed to submit ID verification. Please try again.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Network error: Could not upload ID images. Please check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    await ApiService.clearSession();
    SocketService.disconnect();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  Widget _buildUploadSection({
    required String label,
    required bool isFront,
    required SelectedIdFile? selectedFile,
    required bool isPicking,
  }) {
    final boxKey = Key(isFront ? 'upload_front_id_box' : 'upload_back_id_box');
    final replaceKey = Key(isFront ? 'replace_front_id_button' : 'replace_back_id_button');
    final removeKey = Key(isFront ? 'remove_front_id_button' : 'remove_back_id_button');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '*',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          key: boxKey,
          onTap: selectedFile == null && !_submitting && !isPicking
              ? () => _pickImage(isFront: isFront)
              : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selectedFile != null
                    ? const Color(0xFFFF5722)
                    : const Color(0xFFCBD5E1),
                width: 1.5,
              ),
            ),
            child: selectedFile == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5722).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: isPicking
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFF5722),
                                ),
                              )
                            : const Icon(
                                Icons.cloud_upload_outlined,
                                color: Color(0xFFFF5722),
                                size: 24,
                              ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Click to upload or drag and drop',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PNG, JPG up to 5MB',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          height: 150,
                          color: const Color(0xFFE2E8F0),
                          child: Image.memory(
                            selectedFile.bytes,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.image_outlined,
                                      color: Color(0xFF475569),
                                      size: 36,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      selectedFile.fileName,
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF10B981),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${selectedFile.fileName} (${_formatFileSize(selectedFile.sizeBytes)})',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              key: replaceKey,
                              onPressed: _submitting
                                  ? null
                                  : () => _pickImage(isFront: isFront),
                              icon: const Icon(Icons.sync_rounded, size: 16),
                              label: Text(
                                'Replace',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFF5722),
                                side: const BorderSide(color: Color(0xFFFF5722)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: removeKey,
                              onPressed: _submitting
                                  ? null
                                  : () => _removeImage(isFront: isFront),
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: Text(
                                'Remove',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFEF4444),
                                side: const BorderSide(color: Color(0xFFF87171)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuidelinesCard() {
    return Container(
      key: const Key('id_verification_guidelines_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFEA580C),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '② ID Verification Guidelines',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9A3412),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure the ID is not fake or generated by AI and the image is clear and all details are visible.',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF7C2D12),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          _buildGuidelineBullet('The entire ID is visible in both images.'),
          _buildGuidelineBullet('The images are clear and readable.'),
          _buildGuidelineBullet('The ID type matches the submitted document.'),
          _buildGuidelineBullet('Submit genuine, unaltered ID images.'),
        ],
      ),
    );
  }

  Widget _buildGuidelineBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 14,
              color: Color(0xFFEA580C),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                color: const Color(0xFF7C2D12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingConfirmationView() {
    return Column(
      key: const Key('id_verification_pending_view'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFF5722).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.verified_user_outlined,
            color: Color(0xFFFF5722),
            size: 36,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'ID Verification Submitted',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your ID has been submitted successfully and is awaiting verification. You will be notified when your verification status changes.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 14,
            color: const Color(0xFF64748B),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Current Status',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    key: const Key('verification_status_badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Text(
                      'Pending',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
              if (_submittedIdType != null && _submittedIdType!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Submitted ID Type',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _submittedIdType!,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF87171)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.outfit(
                      color: const Color(0xFFEF4444),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            key: const Key('refresh_verification_status_button'),
            onPressed: _loadingStatus
                ? null
                : () => _refreshVerificationStatus(showFeedback: true),
            icon: _loadingStatus
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              _loadingStatus ? 'Checking Status...' : 'Check Verification Status',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5722),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          key: const Key('id_verification_logout_button'),
          onPressed: _signOut,
          icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFF64748B)),
          label: Text(
            'Sign Out',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmissionFormView() {
    final isRejected = _verificationStatus == 'Rejected';

    return Column(
      key: const Key('id_verification_form_view'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Center(
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5722),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF5722).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'ID Verification',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Verify your identity to help keep the Pozorrubio Emergency Network safe and trusted.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  color: const Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Rejected status banner (if previously rejected by admin)
        if (isRejected) ...[
          Container(
            key: const Key('id_verification_rejected_banner'),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF87171)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verification Status: Rejected',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF991B1B),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_rejectionReason != null && _rejectionReason!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Reason: ${_rejectionReason!}',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFB91C1C),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Please upload corrected, clear front and back ID images below to resubmit.',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    color: const Color(0xFF7F1D1D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Error message banner
        if (_errorMessage != null) ...[
          Container(
            key: const Key('id_verification_error_banner'),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF87171)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.outfit(
                      color: const Color(0xFFEF4444),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // A. ID Type Selection
        Row(
          children: [
            Text(
              'ID Type',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '*',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonFormField<String>(
            key: const Key('id_type_dropdown'),
            initialValue: _selectedIdType,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
            decoration: InputDecoration(
              hintText: 'Select your ID Type',
              hintStyle: GoogleFonts.outfit(
                color: const Color(0xFF86868B),
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: const Color(0xFF1D1D1F),
              fontWeight: FontWeight.w500,
            ),
            items: _idTypes
                .map(
                  (idType) => DropdownMenuItem<String>(
                    value: idType,
                    child: Text(
                      idType,
                      style: GoogleFonts.outfit(
                        fontSize: 14.5,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: _submitting
                ? null
                : (val) {
                    setState(() {
                      _selectedIdType = val;
                      _errorMessage = null;
                    });
                  },
          ),
        ),
        const SizedBox(height: 20),

        // B. Upload ID Front Side
        _buildUploadSection(
          label: 'ID Front Side',
          isFront: true,
          selectedFile: _frontFile,
          isPicking: _pickingFront,
        ),
        const SizedBox(height: 20),

        // C. Upload ID Back Side
        _buildUploadSection(
          label: 'ID Back Side',
          isFront: false,
          selectedFile: _backFile,
          isPicking: _pickingBack,
        ),
        const SizedBox(height: 20),

        // D. ID Verification Guidelines
        _buildGuidelinesCard(),
        const SizedBox(height: 24),

        // 3. Submit Verification Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            key: const Key('submit_id_verification_button'),
            onPressed: _submitting ? null : _submitVerification,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5722),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _submitting
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Submitting...',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Submit for Verification',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            key: const Key('id_verification_logout_button'),
            onPressed: _submitting ? null : _signOut,
            icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFF64748B)),
            label: Text(
              'Sign Out',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPending = _verificationStatus == 'Pending';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 440),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(28),
                child: isPending
                    ? _buildPendingConfirmationView()
                    : _buildSubmissionFormView(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
