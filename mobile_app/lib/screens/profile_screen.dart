import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user.dart';
import 'history_screen.dart';
import '../services/api_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class ProfileScreen extends StatefulWidget {
  final UserModel? user;
  final VoidCallback onLogout;
  final VoidCallback onPickImage;
  final Function(UserModel)? onUserUpdated;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onPickImage,
    this.onUserUpdated,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  Future<void> _pickProfileImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      
      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Picture',
            toolbarColor: Colors.white,
            toolbarWidgetColor: Colors.black,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Crop Profile Picture',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
        ],
      );

      if (croppedFile == null) return;

      if (!mounted) return;
      if (_user?.id != null) {
        final res = await ApiService.updateProfilePicture(_user!.id.toString(), croppedFile.path);
        if (!mounted) return;
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated successfully!')),
          );
          
          // Get the new image path from response (or optimistic update)
          String newImageUrl = res['imageUrl'] ?? croppedFile.path; // Fallback to path if not returned
          // Ensure it starts with http or '/'
          if (!newImageUrl.startsWith('http') && !newImageUrl.startsWith('data:') && !newImageUrl.startsWith('/')) {
            newImageUrl = '/$newImageUrl';
          }
          
          final updatedUser = _user!.copyWith(profileImage: newImageUrl);
          setState(() {
            _user = updatedUser;
          });
          
          if (widget.onUserUpdated != null) {
            widget.onUserUpdated!(updatedUser);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Failed to upload image')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black54, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile',
          style: GoogleFonts.outfit(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Top Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickProfileImage,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFF5A623), width: 3),
                            image: (_user?.profileImage != null && _user!.profileImage.isNotEmpty)
                                ? DecorationImage(
                                    image: _user!.profileImage.startsWith('data:image') || _user!.profileImage.length > 500
                                        ? MemoryImage(base64Decode(_user!.profileImage.split(',').last)) as ImageProvider
                                        : NetworkImage(_user!.profileImage.startsWith('http')
                                            ? _user!.profileImage
                                            : '${ApiService.baseUrl}${_user!.profileImage.startsWith('/') ? '' : '/'}${_user!.profileImage}'),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color: const Color(0xFFF5A623).withValues(alpha: 0.1),
                          ),
                          child: (_user?.profileImage == null || _user!.profileImage.isEmpty)
                              ? Center(
                                  child: Text(
                                    _user?.name.isNotEmpty == true
                                        ? _user!.name[0].toUpperCase()
                                        : 'U',
                                    style: GoogleFonts.outfit(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFF5A623),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5A623),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    (_user?.name ?? 'USER NAME').toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _user?.email ?? 'email@example.com',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _showEditProfileDialog,
                    icon: const Icon(Icons.edit, size: 14, color: Colors.grey),
                    label: Text(
                      'Edit Profile',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // List Items
            _buildMenuItem(
              icon: Icons.history,
              label: 'Emergency History',
              onTap: () {
                if (_user != null) {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: Colors.white,
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.height * 0.8,
                        child: HistoryScreen(user: _user!),
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            _buildMenuItem(
              icon: Icons.chat_bubble_outline,
              label: 'Send Feedback',
              onTap: _showFeedbackDialog,
            ),
            const SizedBox(height: 8),
            _buildMenuItem(
              icon: Icons.lock_outline,
              label: 'Passcode Settings',
              onTap: _showPasscodeSetupDialog,
            ),
            const SizedBox(height: 8),
            _buildMenuItem(
              icon: Icons.map_outlined,
              label: 'Map Settings',
              onTap: _showMapSettingsDialog,
            ),
            
            const SizedBox(height: 32),
            
            // Log Out Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _showLogoutDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF44336), // Red
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'LOG OUT',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFF5A623), size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- DIALOG IMPLEMENTATIONS ----

  void _showEditProfileDialog() {
    try {
      final firstCtrl = TextEditingController(text: _user?.firstName ?? '');
      final middleCtrl = TextEditingController(text: _user?.middleName ?? '');
      final lastCtrl = TextEditingController(text: _user?.lastName ?? '');
      final suffixCtrl = TextEditingController(text: _user?.suffix ?? '');
      final birthdateCtrl = TextEditingController(text: _user?.birthdate ?? '');
      final addressCtrl = TextEditingController(text: _user?.address ?? '');
      final phoneCtrl = TextEditingController(text: _user?.phone ?? '');
      final emailCtrl = TextEditingController(text: _user?.email ?? '');
      String? selectedGender = ['Male', 'Female', 'Other'].contains(_user?.gender) 
          ? _user!.gender 
          : null;
      bool isLoading = false;

      showDialog(
        context: context,
      barrierDismissible: !isLoading,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Edit Profile', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Divider(color: Color(0xFFF4B400), thickness: 2, height: 2),
                      const SizedBox(height: 16),
                      _buildDialogTextField('First Name', controller: firstCtrl),
                      const SizedBox(height: 12),
                      _buildDialogTextField('Middle Initial', controller: middleCtrl),
                      const SizedBox(height: 12),
                      _buildDialogTextField('Last Name', controller: lastCtrl),
                      const SizedBox(height: 12),
                      _buildDialogTextField('Suffix (e.g. Jr, Sr)', controller: suffixCtrl),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setStateDialog(() => birthdateCtrl.text = '${date.month}/${date.day}/${date.year}');
                          }
                        },
                        child: AbsorbPointer(
                          child: _buildDialogTextField('Date of Birth', controller: birthdateCtrl, suffixIcon: Icons.calendar_today),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDialogDropdown(
                        selectedGender,
                        ['Male', 'Female', 'Other'],
                        (v) {
                          if (v != null) {
                            setStateDialog(() => selectedGender = v);
                          }
                        },
                        hint: 'Select Gender'
                      ),
                      const SizedBox(height: 12),
                      _buildDialogTextField('Barangay', controller: addressCtrl),
                      const SizedBox(height: 12),
                      _buildDialogTextField('Email Address', controller: emailCtrl),
                      const SizedBox(height: 12),
                      _buildDialogTextField('Phone Number', controller: phoneCtrl),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isLoading ? null : () => Navigator.pop(context),
                            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isLoading ? null : () async {
                              if (_user == null) return;
                              setStateDialog(() => isLoading = true);
                              try {
                                final res = await ApiService.updateProfile({
                                  'id': _user!.id.toString(),
                                  'name': '${firstCtrl.text} ${lastCtrl.text}'.trim(),
                                  'first_name': firstCtrl.text,
                                  'middle_name': middleCtrl.text,
                                  'last_name': lastCtrl.text,
                                  'suffix': suffixCtrl.text,
                                  'birthdate': birthdateCtrl.text,
                                  'gender': selectedGender ?? '',
                                  'address': addressCtrl.text,
                                  'email': emailCtrl.text,
                                  'phone': phoneCtrl.text,
                                  'profile_image': _user!.profileImage,
                                });
                                if (res['success'] == true && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully!')));
                                  final updatedUser = _user!.copyWith(
                                    firstName: firstCtrl.text,
                                    middleName: middleCtrl.text,
                                    lastName: lastCtrl.text,
                                    suffix: suffixCtrl.text,
                                    birthdate: birthdateCtrl.text,
                                    name: '${firstCtrl.text} ${lastCtrl.text}'.trim(),
                                    gender: selectedGender ?? '',
                                    address: addressCtrl.text,
                                    phone: phoneCtrl.text,
                                    email: emailCtrl.text,
                                  );
                                  setState(() {
                                    _user = updatedUser;
                                  });
                                  if (widget.onUserUpdated != null) {
                                    widget.onUserUpdated!(updatedUser);
                                  }
                                  Navigator.pop(context);
                                  // Profile doesn't auto reload in UI unless we trigger a load in home. Let's just pop. The user will see it when they reopen or if we trigger reload. 
                                  // Actually, home_screen reloads data when ProfileScreen is popped! See home_screen line 1153 ".then((_) => _loadData())".
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? res['message'] ?? 'Failed to update profile')));
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred: $e')));
                              } finally {
                                if (mounted) setStateDialog(() => isLoading = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF5A623),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: isLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening dialog: $e')),
        );
      }
    }
  }

  void _showFeedbackDialog() {
    final subjectCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    String selectedType = 'Suggestion';
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Send Feedback', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Divider(color: Color(0xFFF4B400), thickness: 2, height: 2),
                      const SizedBox(height: 16),
                      _buildDialogTextField('Subject', controller: subjectCtrl),
                      const SizedBox(height: 12),
                      _buildDialogDropdown(
                        selectedType,
                        ['Suggestion', 'Bug Report', 'Other'],
                        (v) {
                          if (v != null) {
                            setStateDialog(() => selectedType = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDialogTextField('Message (Max 1000 chars)', controller: messageCtrl, maxLines: 4),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Text('Attach Screenshot (Optional)', style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isLoading ? null : () => Navigator.pop(context),
                            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isLoading ? null : () async {
                              if (subjectCtrl.text.isEmpty || messageCtrl.text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields')));
                                return;
                              }
                              setStateDialog(() => isLoading = true);
                              try {
                                final res = await ApiService.submitFeedback({
                                  'userId': _user?.id,
                                  'subject': subjectCtrl.text,
                                  'type': selectedType,
                                  'message': messageCtrl.text,
                                });
                                if (res['success'] == true && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback submitted!')));
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Failed to submit')));
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An error occurred')));
                              } finally {
                                if (mounted) setStateDialog(() => isLoading = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF5A623),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: isLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text('Submit', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPasscodeSetupDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Passcode Settings', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Divider(color: Color(0xFFF5A623), thickness: 2, height: 2),
                      const SizedBox(height: 16),
                      Text(
                        _user!.hasPasscode ? 'Enter your current passcode to create a new one.' : 'Create a new passcode for emergency verification.', 
                        style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12)
                      ),
                      const SizedBox(height: 16),
                      if (_user!.hasPasscode) ...[
                        _buildDialogTextField('Current Passcode', controller: currentCtrl, obscureText: true),
                        const SizedBox(height: 12),
                      ],
                      _buildDialogTextField('New Passcode', controller: newCtrl, obscureText: true),
                      const SizedBox(height: 12),
                      _buildDialogTextField('Confirm New Passcode', controller: confirmCtrl, obscureText: true),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isLoading ? null : () => Navigator.pop(context),
                            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isLoading ? null : () async {
                              if (newCtrl.text.isEmpty || newCtrl.text != confirmCtrl.text) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passcodes do not match or are empty')));
                                return;
                              }
                              if (_user == null) return;
                              setStateDialog(() => isLoading = true);
                              try {
                                final res = await ApiService.savePasscode(
                                  userId: _user!.id.toString(),
                                  currentPasscode: _user!.hasPasscode ? currentCtrl.text : null,
                                  newPasscode: newCtrl.text,
                                );
                                if (res['success'] == true && mounted) {
                                  final updatedUser = _user!.copyWith(hasPasscode: true);
                                  setState(() {
                                    _user = updatedUser;
                                  });
                                  if (widget.onUserUpdated != null) {
                                    widget.onUserUpdated!(updatedUser);
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passcode updated successfully!')));
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? res['message'] ?? 'Failed to update passcode')));
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                              } finally {
                                if (mounted) setStateDialog(() => isLoading = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF5A623),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: isLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMapSettingsDialog() {
    final settings = _user?.mapSettings ?? {};
    
    // Convert 'default' to 'Default' or handle case appropriately
    String capFirst(String? s) {
      if (s == null || s.isEmpty) return 'Default';
      return s[0].toUpperCase() + s.substring(1);
    }
    
    String mapType = capFirst(settings['map_type']);
    if (mapType == 'Default') mapType = 'Standard';
    if (!['Standard', 'Satellite', 'Terrain'].contains(mapType)) {
      mapType = 'Standard';
    }

    String navPref = settings['navigation_preference'] ?? 'Fastest Route';
    double notifRadius = (settings['notification_radius'] ?? 500).toDouble();
    double alertRadius = (settings['emergency_alert_radius'] ?? 1000).toDouble();
    bool liveLoc = settings['live_location'] == 1 || settings['live_location'] == true;
    bool gpsAccess = settings['gps_enabled'] == 1 || settings['gps_enabled'] == true || settings['gps_enabled'] == null;
    bool showLabels = settings['show_labels'] == 1 || settings['show_labels'] == true || settings['show_labels'] == null;
    bool showRoutes = settings['show_routes'] == 1 || settings['show_routes'] == true || settings['show_routes'] == null;
    bool showMarkers = settings['show_markers'] == 1 || settings['show_markers'] == true || settings['show_markers'] == null;
    bool locationControls = settings['location_controls'] == 1 || settings['location_controls'] == true || settings['location_controls'] == null;
    bool autoRefresh = settings['auto_refresh'] == 1 || settings['auto_refresh'] == true || settings['auto_refresh'] == null;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: Colors.white,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Map Settings', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Divider(color: Color(0xFFF4B400), thickness: 2, height: 2),
                      const SizedBox(height: 16),
                      Text('Map Type', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      _buildDialogDropdown(
                        mapType,
                        ['Standard', 'Satellite', 'Terrain'],
                        (v) {
                          if (v != null) setStateDialog(() => mapType = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Navigation Preference', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      _buildDialogDropdown(
                        navPref,
                        ['Fastest Route', 'Shortest Route', 'Avoid Tolls'],
                        (v) {
                          if (v != null) setStateDialog(() => navPref = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Notification Radius (Meters: ${notifRadius.toInt()})', style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 13)),
                      Slider(
                        value: notifRadius,
                        min: 0,
                        max: 2000,
                        activeColor: Colors.blue,
                        onChanged: (v) => setStateDialog(() => notifRadius = v),
                      ),
                      Text('Emergency Alert Radius (Meters: ${alertRadius.toInt()})', style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 13)),
                      Slider(
                        value: alertRadius,
                        min: 0,
                        max: 5000,
                        activeColor: Colors.blue,
                        onChanged: (v) => setStateDialog(() => alertRadius = v),
                      ),
                      const SizedBox(height: 8),
                      _buildCheckbox('Show Labels', showLabels, (v) => setStateDialog(() => showLabels = v ?? false)),
                      _buildCheckbox('Show Routes', showRoutes, (v) => setStateDialog(() => showRoutes = v ?? false)),
                      _buildCheckbox('Show Markers', showMarkers, (v) => setStateDialog(() => showMarkers = v ?? false)),
                      _buildCheckbox('Location Controls', locationControls, (v) => setStateDialog(() => locationControls = v ?? false)),
                      _buildCheckbox('Enable Live Location', liveLoc, (v) => setStateDialog(() => liveLoc = v ?? false)),
                      _buildCheckbox('Allow GPS Access', gpsAccess, (v) => setStateDialog(() => gpsAccess = v ?? false)),
                      _buildCheckbox('Auto-Refresh Map', autoRefresh, (v) => setStateDialog(() => autoRefresh = v ?? false)),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isLoading ? null : () => Navigator.pop(context),
                            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isLoading ? null : () async {
                              if (_user == null) return;
                              setStateDialog(() => isLoading = true);
                              try {
                                final mapData = {
                                  'user_id': _user!.id,
                                  'map_type': mapType == 'Standard' ? 'default' : mapType.toLowerCase(),
                                  'show_labels': showLabels ? 1 : 0,
                                  'show_routes': showRoutes ? 1 : 0,
                                  'show_markers': showMarkers ? 1 : 0,
                                  'location_controls': locationControls ? 1 : 0,
                                  'live_location': liveLoc ? 1 : 0,
                                  'gps_enabled': gpsAccess ? 1 : 0,
                                  'navigation_preference': navPref,
                                  'notification_radius': notifRadius.toInt(),
                                  'emergency_alert_radius': alertRadius.toInt(),
                                  'auto_refresh': autoRefresh ? 1 : 0,
                                };
                                final res = await ApiService.saveMapSettings(mapData);
                                if (res['success'] == true && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Map settings saved!')));
                                  final updatedUser = _user!.copyWith(mapSettings: mapData);
                                  setState(() {
                                    _user = updatedUser;
                                  });
                                  if (widget.onUserUpdated != null) {
                                    widget.onUserUpdated!(updatedUser);
                                  }
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Failed to save settings')));
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                              } finally {
                                if (mounted) setStateDialog(() => isLoading = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF5A623),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: isLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Logout', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                const Divider(color: Color(0xFFF4B400), thickness: 2, height: 2),
                const SizedBox(height: 16),
                Text('Are you sure you want to logout?', style: GoogleFonts.outfit(color: Colors.black87, fontSize: 15)),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // close dialog
                        widget.onLogout(); // handle actual logout logic which also pops profile screen
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF44336), // Red
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: Text('Logout', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialogTextField(String hint, {TextEditingController? controller, bool obscureText = false, int maxLines = 1, IconData? suffixIcon}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        suffixIcon: suffixIcon != null ? Icon(suffixIcon, color: Colors.grey[600], size: 18) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF8C42)),
        ),
      ),
    );
  }

  Widget _buildDialogDropdown(String? value, List<String> items, ValueChanged<String?> onChanged, {String? hint}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), // small vertical tweak to match height
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: hint != null ? Text(hint, style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14)) : null,
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, style: GoogleFonts.outfit(color: Colors.grey[800], fontSize: 14)))).toList(),
          onChanged: onChanged,
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
        ),
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: GoogleFonts.outfit(fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }
}

