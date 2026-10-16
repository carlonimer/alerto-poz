import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScreen extends StatefulWidget {
  final int initialMode;
  const CameraScreen({super.key, this.initialMode = 1});

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
  int _recordSeconds = 0;
  Timer? _recordTimer;

  // Loading & Error states
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPermissionDenied = false;

  // Flashlight state
  FlashMode _flashMode = FlashMode.off;

  // Zoom state
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isPermissionDenied = false;
    });

    try {
      // Check and request camera permission
      final cameraStatus = await Permission.camera.request();
      if (cameraStatus.isPermanentlyDenied || cameraStatus.isDenied || cameraStatus.isRestricted) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isPermissionDenied = true;
            _errorMessage = "Camera access is required to capture photos and report emergencies. Please enable camera permission in device settings.";
          });
        }
        return;
      }

      // Also request microphone permission for video recording mode
      try {
        await Permission.microphone.request();
      } catch (_) {
        // Microphone failure shouldn't block initialization
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "No camera was detected on this device.";
          });
        }
        return;
      }

      if (_selectedCameraIdx >= _cameras.length) {
        _selectedCameraIdx = 0;
      }

      await _setCamera(_cameras[_selectedCameraIdx]);
    } on CameraException catch (e) {
      debugPrint("CameraException in _initCamera: ${e.code} - ${e.description}");
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt' || e.code == 'CameraAccessRestricted') {
            _isPermissionDenied = true;
            _errorMessage = "Camera access was denied. Please allow camera access in device settings.";
          } else {
            _errorMessage = "Camera error (${e.code}): ${e.description ?? 'Could not initialize camera'}";
          }
        });
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not initialize camera: $e";
        });
      }
    }
  }

  Future<void> _setCamera(CameraDescription cameraDescription) async {
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }

    final controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: true,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      _maxZoom = await controller.getMaxZoomLevel();
      _minZoom = await controller.getMinZoomLevel();
      _currentZoom = _minZoom;
      _baseZoom = _minZoom;
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {}

      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      debugPrint("Error initializing camera controller: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt' || e.code == 'CameraAccessRestricted') {
            _isPermissionDenied = true;
            _errorMessage = "Camera permission was denied. Please allow camera access in device settings.";
          } else {
            _errorMessage = "Camera error: ${e.description ?? e.code}";
          }
        });
      }
    } catch (e) {
      debugPrint("Error in _setCamera: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to start camera feed: $e";
        });
      }
    }
  }

  void _switchCamera() {
    if (_cameras.length > 1 && !_isRecording) {
      _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
      _setCamera(_cameras[_selectedCameraIdx]);
    }
  }

  void _toggleFlash() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      if (_flashMode == FlashMode.off) {
        _flashMode = FlashMode.torch;
      } else {
        _flashMode = FlashMode.off;
      }
    });
    try {
      _controller!.setFlashMode(_flashMode);
    } catch (e) {
      debugPrint("Flash mode error: $e");
    }
  }

  IconData _getFlashIcon() {
    if (_flashMode == FlashMode.torch || _flashMode == FlashMode.always) return Icons.flash_on;
    return Icons.flash_off;
  }

  void _switchMode(int mode) {
    if (_isRecording) return;
    if (_currentMode == mode) return;
    setState(() {
      _currentMode = mode;
    });
  }

  void _startRecordTimer() {
    _recordSeconds = 0;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordSeconds++;
        });
        if (_recordSeconds >= 30) {
          _onShutterPressed();
        }
      }
    });
  }

  void _stopRecordTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Future<void> _onShutterPressed() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_currentMode == 1) {
      // Take Photo immediately
      try {
        final XFile file = await _controller!.takePicture();
        if (mounted) {
          Navigator.pop(context, {'type': 'image', 'path': file.path});
        }
      } catch (e) {
        debugPrint("Error taking picture: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to take photo: $e')),
          );
        }
      }
    } else if (_currentMode == 2) {
      // Record Video: Start or Stop
      if (_isRecording) {
        try {
          final XFile file = await _controller!.stopVideoRecording();
          _stopRecordTimer();
          setState(() {
            _isRecording = false;
          });
          if (mounted) {
            Navigator.pop(context, {'type': 'video', 'path': file.path});
          }
        } catch (e) {
          debugPrint("Error stopping video: $e");
          _stopRecordTimer();
          setState(() {
            _isRecording = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error saving video: $e')),
            );
          }
        }
      } else {
        try {
          await _controller!.startVideoRecording();
          _startRecordTimer();
          setState(() {
            _isRecording = true;
          });
        } catch (e) {
          debugPrint("Error starting video: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error starting recording: $e')),
            );
          }
        }
      }
    }
  }

  Widget _modeSelectorItem(String text, int index) {
    final isSelected = _currentMode == index;
    return GestureDetector(
      onTap: () => _switchMode(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? Border.all(color: Colors.amber, width: 1.5) : null,
        ),
        child: Text(
          text,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.amber : Colors.white70,
            fontSize: isSelected ? 14 : 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopRecordTimer();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Error / Permission Denied Screen
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Camera',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPermissionDenied ? Icons.no_photography_outlined : Icons.videocam_off_outlined,
                    color: Colors.amber,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isPermissionDenied ? 'Camera Permission Required' : 'Camera Unavailable',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                if (_isPermissionDenied) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      await openAppSettings();
                    },
                    icon: const Icon(Icons.settings, color: Colors.black),
                    label: Text(
                      'Open Settings',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _initCamera,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: Text(
                    'Retry',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading Screen
    if (_isLoading || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview with Pinch-to-Zoom & Horizontal Swipe gesture support
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: Center(
                child: GestureDetector(
                  onScaleStart: (details) {
                    _baseZoom = _currentZoom;
                  },
                  onScaleUpdate: (details) async {
                    if (_controller == null || !_controller!.value.isInitialized) return;
                    if (details.scale == 1.0) return;
                    double targetZoom = _baseZoom * details.scale;
                    if (targetZoom < _minZoom) targetZoom = _minZoom;
                    if (targetZoom > _maxZoom) targetZoom = _maxZoom;
                    if (targetZoom != _currentZoom) {
                      setState(() {
                        _currentZoom = targetZoom;
                      });
                      await _controller!.setZoomLevel(_currentZoom);
                    }
                  },
                  onScaleEnd: (details) {
                    if (_isRecording) return;
                    final vx = details.velocity.pixelsPerSecond.dx;
                    final vy = details.velocity.pixelsPerSecond.dy;
                    if (vx.abs() > 250 && vx.abs() > vy.abs() * 1.4) {
                      if (vx < 0) {
                        _switchMode(2); // Swipe left -> Video
                      } else {
                        _switchMode(1); // Swipe right -> Photo
                      }
                    }
                  },
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          ),

          // Zoom level display & Slider
          Positioned(
            bottom: 160,
            left: 30,
            right: 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentZoom.toStringAsFixed(1)}x',
                    style: GoogleFonts.outfit(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_maxZoom > _minZoom) ...[
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                    ),
                    child: Slider(
                      value: _currentZoom,
                      min: _minZoom,
                      max: _maxZoom,
                      activeColor: Colors.amber,
                      inactiveColor: Colors.white54,
                      onChanged: (value) async {
                        if (_controller == null || !_controller!.value.isInitialized) return;
                        setState(() {
                          _currentZoom = value;
                          _baseZoom = value;
                        });
                        await _controller!.setZoomLevel(value);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Grid overlay (simulated)
          Positioned.fill(
            child: IgnorePointer(
              child: Column(
                children: [
                  Expanded(child: Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24, width: 1))))),
                  Expanded(child: Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24, width: 1))))),
                  Expanded(child: Container()),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Row(
                children: [
                  Expanded(child: Container(decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 1))))),
                  Expanded(child: Container(decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 1))))),
                  Expanded(child: Container()),
                ],
              ),
            ),
          ),

          // Top controls
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: Icon(_getFlashIcon(), color: Colors.white),
              onPressed: _toggleFlash,
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () async {
                await openAppSettings();
              },
            ),
          ),

          // Recording Timer Indicator when recording
          if (_isRecording)
            Positioned(
              top: 44,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatDuration(_recordSeconds)} / 00:30',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom Controls Background with Mode Selector and Shutter Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.85),
              padding: const EdgeInsets.only(bottom: 40, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mode Selector with Tap and Horizontal Swipe support
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: (details) {
                      if (_isRecording) return;
                      if (details.primaryVelocity != null) {
                        if (details.primaryVelocity! < -100) {
                          _switchMode(2); // Swiped left -> Video
                        } else if (details.primaryVelocity! > 100) {
                          _switchMode(1); // Swiped right -> Photo
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _modeSelectorItem('PHOTO', 1),
                          const SizedBox(width: 16),
                          _modeSelectorItem('VIDEO', 2),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Shutter and Action Buttons
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
                            border: Border.all(
                              color: _currentMode == 2 ? Colors.redAccent : Colors.amber,
                              width: 4,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: _isRecording ? 26 : 54,
                              height: _isRecording ? 26 : 54,
                              decoration: BoxDecoration(
                                color: _currentMode == 2 ? Colors.red : Colors.white,
                                shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                                borderRadius: _isRecording ? BorderRadius.circular(6) : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.sync, color: Colors.white, size: 32),
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
