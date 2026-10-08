import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _selectedCameraIdx = 0;
  
  // 1: Photo, 2: Video
  int _currentMode = 1;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _setCamera(_cameras[0]);
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  Future<void> _setCamera(CameraDescription cameraDescription) async {
    if (_controller != null) {
      await _controller!.dispose();
    }
    _controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _switchCamera() {
    if (_cameras.length > 1) {
      _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
      _setCamera(_cameras[_selectedCameraIdx]);
    }
  }

  Future<void> _onShutterPressed() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_currentMode == 1) {
      // Take Photo
      try {
        final XFile file = await _controller!.takePicture();
        if (mounted) {
          Navigator.pop(context, {'type': 'image', 'path': file.path});
        }
      } catch (e) {
        debugPrint("Error taking picture: $e");
      }
    } else if (_currentMode == 2) {
      // Record Video
      if (_isRecording) {
        try {
          final XFile file = await _controller!.stopVideoRecording();
          setState(() {
            _isRecording = false;
          });
          if (mounted) {
            Navigator.pop(context, {'type': 'video', 'path': file.path});
          }
        } catch (e) {
          debugPrint("Error stopping video: $e");
        }
      } else {
        try {
          await _controller!.startVideoRecording();
          setState(() {
            _isRecording = true;
          });
        } catch (e) {
          debugPrint("Error starting video: $e");
        }
      }
    }
  }

  Widget _modeText(String text, int index) {
    final isSelected = _currentMode == index;
    return GestureDetector(
      onTap: () {
        if (_isRecording) return;
        setState(() {
          _currentMode = index;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          text,
          style: GoogleFonts.outfit(
            color: isSelected ? const Color(0xFFFFD700) : Colors.white,
            fontSize: isSelected ? 16 : 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Positioned.fill(
            child: CameraPreview(_controller!),
          ),
          
          // Grid overlay (simulated)
          Positioned.fill(
            child: Column(
              children: [
                Expanded(child: Container(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24, width: 1))))),
                Expanded(child: Container(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24, width: 1))))),
                Expanded(child: Container()),
              ],
            ),
          ),
          Positioned.fill(
            child: Row(
              children: [
                Expanded(child: Container(decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 1))))),
                Expanded(child: Container(decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 1))))),
                Expanded(child: Container()),
              ],
            ),
          ),
          
          // Top controls
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.flash_off, color: Colors.white),
              onPressed: () {},
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () {},
            ),
          ),

          // Bottom Controls Background
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.only(bottom: 40, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _modeText('Photo', 1),
                      _modeText('Video', 2),
                    ],
                  ),
                  const SizedBox(height: 30),
                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () {
                          if (!_isRecording) {
                            Navigator.pop(context);
                          }
                        },
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
                        ),
                      ),
                      GestureDetector(
                        onTap: _onShutterPressed,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _isRecording ? Colors.red : Colors.yellow, width: 4),
                          ),
                          child: Center(
                            child: Container(
                              width: _isRecording ? 24 : 56,
                              height: _isRecording ? 24 : 56,
                              decoration: BoxDecoration(
                                color: _isRecording ? Colors.red : Colors.transparent,
                                shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                                borderRadius: _isRecording ? BorderRadius.circular(4) : null,
                                border: _isRecording ? null : Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 32),
                        onPressed: _isRecording ? null : _switchCamera,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
