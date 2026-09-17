import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user.dart';
import 'history_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserModel? user;
  final VoidCallback onLogout;
  final VoidCallback onPickImage;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onLogout,
    required this.onPickImage,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
                    onTap: widget.onPickImage,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFF5A623), width: 3),
                            image: widget.user?.profileImage != null
                                ? DecorationImage(
                                    image: MemoryImage(base64Decode(widget.user!.profileImage.split(',').last)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color: const Color(0xFFF5A623).withValues(alpha: 0.1),
                          ),
                          child: widget.user?.profileImage == null
                              ? Center(
                                  child: Text(
                                    widget.user?.name.isNotEmpty == true
                                        ? widget.user!.name[0].toUpperCase()
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
                    (widget.user?.name ?? 'USER NAME').toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.user?.email ?? 'email@example.com',
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
                if (widget.user != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HistoryScreen(user: widget.user!),
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
    showDialog(
      context: context,
      builder: (context) {
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
                  Container(height: 2, width: double.infinity, color: const Color(0xFFF4B400)),
                  const SizedBox(height: 16),
                  _buildDialogTextField('First Name'),
                  const SizedBox(height: 12),
                  _buildDialogTextField('Middle Name'),
                  const SizedBox(height: 12),
                  _buildDialogTextField('Last Name'),
                  const SizedBox(height: 12),
                  _buildDialogTextField('Suffix (e.g. Jr, Sr)'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: Text('Select Gender', style: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14)),
                        items: const [],
                        onChanged: (v) {},
                        icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDialogTextField('Complete Address'),
                  const SizedBox(height: 12),
                  _buildDialogTextField('carlonimer36@gmail.com'),
                  const SizedBox(height: 12),
                  _buildDialogTextField('09484581731'),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5A623),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
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
  }

  void _showFeedbackDialog() {
    showDialog(
      context: context,
      builder: (context) {
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
                  Container(height: 2, width: double.infinity, color: const Color(0xFFF4B400)),
                  const SizedBox(height: 16),
                  _buildDialogTextField('Subject'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: Text('Suggestion', style: GoogleFonts.outfit(color: Colors.grey[800], fontSize: 14)),
                        items: const [],
                        onChanged: (v) {},
                        icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Message (Max 1000 chars)',
                      hintStyle: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14),
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
                        borderSide: const BorderSide(color: Color(0xFFF5A623)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
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
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5A623),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: Text('Submit', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
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
  }

  void _showPasscodeSetupDialog() {
    showDialog(
      context: context,
      builder: (context) {
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
                  Container(height: 2, width: double.infinity, color: const Color(0xFFF5A623)),
                  const SizedBox(height: 16),
                  Text('Enter your current passcode to create a new one.', style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 16),
                  _buildDialogTextField('Current Passcode (if changing)'),
                  const SizedBox(height: 12),
                  _buildDialogTextField('New Passcode'),
                  const SizedBox(height: 12),
                  _buildDialogTextField('Confirm New Passcode'),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5A623),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
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
  }

  void _showMapSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
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
                  Container(height: 2, width: double.infinity, color: const Color(0xFFF4B400)),
                  const SizedBox(height: 16),
                  Text('Map Type', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  _buildDialogDropdown('Satellite'),
                  const SizedBox(height: 16),
                  Text('Navigation Preference', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  _buildDialogDropdown('Fastest Route'),
                  const SizedBox(height: 16),
                  Text('Notification Radius (Meters: 500)', style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 13)),
                  Slider(
                    value: 500,
                    min: 0,
                    max: 2000,
                    activeColor: Colors.blue,
                    onChanged: (v) {},
                  ),
                  Text('Emergency Alert Radius (Meters: 1000)', style: GoogleFonts.outfit(fontWeight: FontWeight.w500, fontSize: 13)),
                  Slider(
                    value: 1000,
                    min: 0,
                    max: 5000,
                    activeColor: Colors.blue,
                    onChanged: (v) {},
                  ),
                  const SizedBox(height: 8),
                  _buildCheckbox('Enable Live Location', false),
                  _buildCheckbox('Allow GPS Access', false),
                  _buildCheckbox('Enable Real-Time Tracking', false),
                  _buildCheckbox('Show Traffic', false),
                  _buildCheckbox('Show Disaster Zones', false),
                  _buildCheckbox('Show Evacuation Centers', false),
                  _buildCheckbox('Show Barangay Boundaries', false),
                  _buildCheckbox('Auto-Refresh Map', true),
                  _buildCheckbox('Dark Mode Navigation', false),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF5A623),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: Text('Save', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
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
                Container(height: 2, width: double.infinity, color: const Color(0xFFF4B400)),
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

  Widget _buildDialogTextField(String hint) {
    return TextField(
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: Colors.grey[500], fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
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

  Widget _buildDialogDropdown(String value) {
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
          items: [
            DropdownMenuItem(value: value, child: Text(value, style: GoogleFonts.outfit(color: Colors.grey[800], fontSize: 14))),
          ],
          onChanged: (v) {},
          icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
        ),
      ),
    );
  }

  Widget _buildCheckbox(String label, bool value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: (v) {},
              activeColor: Colors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.outfit(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }
}
