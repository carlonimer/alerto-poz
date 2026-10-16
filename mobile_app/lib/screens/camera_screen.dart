import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

class CameraScreen extends StatefulWidget {
  final int initialMode; // 1: Photo, 2: Video
  const CameraScreen({super.key, this.initialMode = 1});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _selectedCameraIdx = 0;

  // Capture Modes: Strictly Photo (1) and Video (2) only
  int _currentMode = 1;

  // Recording State
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  // Settings Panel state (Opened via top-right gear icon)
  bool _showSettingsPanel = false;
  String _aspectRatio = '4:3'; // '1:1', '4:3', '16:9', 'Full'
  int _timerOption = 0; // 0 (Off), 3, 5, 10
  int _countdownRemaining = 0;
  Timer? _countdownTimer;

  // Viewfinder overlay toggles
  bool _gridEnabled = true;
  bool _levelEnabled = true;
  bool _shakeReminder = false;
  bool _watermark = false;
  bool _motionAF = true;
  bool _hdrEnabled = true;
  bool _microphoneEnabled = true;

  // Flashlight state
  FlashMode _flashMode = FlashMode.off;

  // Native Zoom state & Pinch Gestures
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  bool _isPinching = false;
  double _dragStartX = 0.0;
  double _dragCurrentX = 0.0;

  // Focus indicator
  Offset? _focusPoint;
  Timer? _focusTimer;

  // Media Preview State
  bool _isPreviewing = false;
  String? _capturedPath;
  String? _capturedType; // 'image' or 'video'
  VideoPlayerController? _videoPlayerController;
  bool _isVideoPlaying = false;

  // Loading & Error states
  bool _isLoading = true;
  String? _errorMessage;
  bool _isPermissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentMode = widget.initialMode == 2 ? 2 : 1;
    _aspectRatio = _currentMode == 2 ? '16:9' : '4:3';
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRecordTimer();
    _countdownTimer?.cancel();
    _focusTimer?.cancel();
    _controller?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_isRecording) {
        _onShutterPressed();
      }
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_cameras.isNotEmpty && !_isPreviewing) {
        _setCamera(_cameras[_selectedCameraIdx]);
      }
    }
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isPermissionDenied = false;
    });

    try {
      final cameraStatus = await Permission.camera.request();
      if (cameraStatus.isPermanentlyDenied || cameraStatus.isDenied || cameraStatus.isRestricted) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isPermissionDenied = true;
            _errorMessage = "Camera access is required to capture emergency evidence. Please allow camera permissions in settings.";
          });
        }
        return;
      }

      try {
        await Permission.microphone.request();
      } catch (_) {}

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "No camera found on this device.";
          });
        }
        return;
      }

      if (_selectedCameraIdx >= _cameras.length) {
        _selectedCameraIdx = 0;
      }

      await _setCamera(_cameras[_selectedCameraIdx]);
    } catch (e) {
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
      enableAudio: _microphoneEnabled,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;

      _maxZoom = await controller.getMaxZoomLevel();
      _minZoom = await controller.getMinZoomLevel();
      _currentZoom = 1.0.clamp(_minZoom, _maxZoom);
      _baseZoom = _currentZoom;

      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {}

      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to start camera: $e";
        });
      }
    }
  }

  void _switchCamera() {
    if (_cameras.length > 1 && !_isRecording && !_isPreviewing) {
      HapticFeedback.lightImpact();
      _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
      _setCamera(_cameras[_selectedCameraIdx]);
    }
  }

  void _toggleFlash() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_flashMode == FlashMode.off) {
        _flashMode = FlashMode.torch;
      } else {
        _flashMode = FlashMode.off;
      }
    });
    try {
      _controller!.setFlashMode(_flashMode);
    } catch (_) {}
  }

  void _switchMode(int mode, [String? label]) {
    if (_isRecording || _isPreviewing) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentMode = mode;
      _aspectRatio = mode == 2 ? '16:9' : '4:3';
    });
  }

  Future<void> _setZoom(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    if ((clamped - _currentZoom).abs() < 0.005) return;
    setState(() {
      _currentZoom = clamped;
    });
    try {
      await _controller!.setZoomLevel(clamped);
    } catch (e) {
      debugPrint("Zoom error: $e");
    }
  }

  void _onTapToFocus(Offset localPosition, BoxConstraints constraints) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final offset = Offset(
      (localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
      (localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0),
    );
    setState(() {
      _focusPoint = localPosition;
    });
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    try {
      _controller!.setFocusPoint(offset);
      _controller!.setExposurePoint(offset);
    } catch (_) {}
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
    HapticFeedback.heavyImpact();

    if (_currentMode == 1) {
      // Photo Mode
      if (_timerOption > 0) {
        _startPhotoCountdown();
      } else {
        await _executeCapturePhoto();
      }
    } else if (_currentMode == 2) {
      // Video Mode
      if (_isRecording) {
        // Stop recording
        try {
          final XFile file = await _controller!.stopVideoRecording();
          _stopRecordTimer();
          setState(() {
            _isRecording = false;
          });
          final recordedFile = File(file.path);
          if (await recordedFile.exists() && await recordedFile.length() > 0) {
            _showPreview(file.path, 'video');
          } else {
            throw Exception("Recorded video file is empty or corrupted.");
          }
        } catch (e) {
          _stopRecordTimer();
          setState(() {
            _isRecording = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to save video: $e')),
            );
          }
        }
      } else {
        // Start recording
        try {
          await _controller!.startVideoRecording();
          _startRecordTimer();
          setState(() {
            _isRecording = true;
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to start recording: $e')),
            );
          }
        }
      }
    }
  }

  void _startPhotoCountdown() {
    setState(() => _countdownRemaining = _timerOption);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      if (_countdownRemaining <= 1) {
        timer.cancel();
        setState(() => _countdownRemaining = 0);
        await _executeCapturePhoto();
      } else {
        setState(() => _countdownRemaining--);
      }
    });
  }

  Future<void> _executeCapturePhoto() async {
    try {
      final XFile file = await _controller!.takePicture();
      final photoFile = File(file.path);
      if (await photoFile.exists() && await photoFile.length() > 0) {
        _showPreview(file.path, 'image');
      } else {
        throw Exception("Captured photo file is empty.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture photo: $e')),
        );
      }
    }
  }

  Future<void> _showPreview(String path, String type) async {
    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    if (type == 'video') {
      final vCtrl = VideoPlayerController.file(File(path));
      try {
        await vCtrl.initialize();
        await vCtrl.setLooping(true);
        await vCtrl.play();
        _isVideoPlaying = true;
      } catch (e) {
        debugPrint("Video preview init error: $e");
      }
      _videoPlayerController = vCtrl;
    }

    if (mounted) {
      setState(() {
        _isPreviewing = true;
        _capturedPath = path;
        _capturedType = type;
      });
    }
  }

  void _retakeMedia() {
    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    if (_capturedPath != null) {
      try {
        final f = File(_capturedPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }

    setState(() {
      _isPreviewing = false;
      _capturedPath = null;
      _capturedType = null;
      _isVideoPlaying = false;
    });
  }

  void _confirmSendMedia() {
    if (_capturedPath == null || _capturedType == null) return;
    _videoPlayerController?.pause();
    _videoPlayerController?.dispose();
    _videoPlayerController = null;

    Navigator.pop(context, {
      'type': _capturedType,
      'path': _capturedPath,
    });
  }

  /// Calculates proper portrait aspect ratio to prevent stretching or distortion
  double get _portraitAspectRatio {
    if (_controller == null || !_controller!.value.isInitialized) return 3 / 4;
    final ratio = _controller!.value.aspectRatio;
    return ratio > 1.0 ? (1.0 / ratio) : ratio;
  }

  // ───────────────────────── Main Scaffold & Navigation ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isPermissionDenied || _errorMessage != null) {
      return _buildErrorScaffold();
    }

    if (_isLoading || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFFCC00))),
      );
    }

    return PopScope(
      canPop: !_isRecording && !_showSettingsPanel,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showSettingsPanel) {
          setState(() => _showSettingsPanel = false);
          return;
        }
        if (!_isRecording) {
          Navigator.pop(context);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.black,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: _isPreviewing ? _buildPreviewScreen() : _buildCameraViewfinder(),
        ),
      ),
    );
  }

  Widget _buildErrorScaffold() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPermissionDenied ? Icons.no_photography_rounded : Icons.videocam_off_rounded,
                  color: const Color(0xFFFFCC00),
                  size: 54,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isPermissionDenied ? 'Camera Access Required' : 'Camera Unavailable',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Please enable camera permissions in device settings.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 28),
              if (_isPermissionDenied) ...[
                ElevatedButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings, color: Colors.black, size: 20),
                  label: Text('Open Settings', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFCC00),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _initCamera,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                label: Text('Retry', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
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

  // ───────────────────────── Viewfinder Layout (Structured Sizing) ─────────────────────────

  Widget _buildCameraViewfinder() {
    return Stack(
      children: [
        // Structured Layout: Top Bar -> Expanded Viewfinder -> Bottom Controls Area
        Column(
          children: [
            // Top Control Bar (Clean: Flash on Left, Settings on Right; Circled elements removed)
            _buildTopControlBar(),

            // Camera Viewfinder Preview Area (Scaled accurately without distortion or covering controls)
            Expanded(
              child: ClipRect(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _portraitAspectRatio,
                    child: _buildViewfinderStack(),
                  ),
                ),
              ),
            ),

            // Bottom Controls Area (Zoom pill, PHOTO/VIDEO modes, Centered Shutter, Camera Switch)
            _buildBottomControlsArea(),
          ],
        ),

        // Pull-Down Settings Menu (Opened via Settings Gear icon)
        if (_showSettingsPanel)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildSettingsDropdownPanel(),
          ),
      ],
    );
  }

  // ───────────────────────── Interactive Viewfinder Stack ─────────────────────────

  Widget _buildViewfinderStack() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            _baseZoom = _currentZoom;
            _dragStartX = details.focalPoint.dx;
            _isPinching = details.pointerCount >= 2;
          },
          onScaleUpdate: (details) {
            if (details.pointerCount >= 2) {
              _isPinching = true;
              // Smooth, continuous two-finger pinch-to-zoom
              final targetZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
              if ((targetZoom - _currentZoom).abs() > 0.01) {
                _setZoom(targetZoom);
              }
            } else if (!_isPinching && details.pointerCount == 1) {
              _dragCurrentX = details.focalPoint.dx;
            }
          },
          onScaleEnd: (details) {
            if (_isPinching) {
              _isPinching = false;
              return;
            }
            // Horizontal swipe to switch modes cleanly without conflict
            if (!_isRecording) {
              final dx = _dragCurrentX - _dragStartX;
              if (dx < -50 && _currentMode == 1) {
                _switchMode(2, 'Video'); // Swipe left -> Video
              } else if (dx > 50 && _currentMode == 2) {
                _switchMode(1, 'Photo'); // Swipe right -> Photo
              }
            }
          },
          onTapUp: (details) {
            if (!_isPinching) {
              _onTapToFocus(details.localPosition, constraints);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Native Camera Preview
              CameraPreview(_controller!),

              // 3x3 Grid Lines Overlay (Matches reference layout)
              if (_gridEnabled)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GridLinesPainter(),
                    ),
                  ),
                ),

              // Center Horizon Level & Alignment Notch (Matches reference layout)
              if (_levelEnabled)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: SizedBox(
                        width: 140,
                        height: 30,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Container(height: 1.2, color: Colors.white.withValues(alpha: 0.65))),
                                const SizedBox(width: 24),
                                Expanded(child: Container(height: 1.2, color: Colors.white.withValues(alpha: 0.65))),
                              ],
                            ),
                            Container(
                              width: 2,
                              height: 8,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Tap-to-Focus Indicator
              if (_focusPoint != null)
                Positioned(
                  left: _focusPoint!.dx - 30,
                  top: _focusPoint!.dy - 30,
                  child: IgnorePointer(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFFFCC00), width: 1.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),

              // Photo Timer Countdown Overlay
              if (_countdownRemaining > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$_countdownRemaining',
                          style: GoogleFonts.outfit(color: const Color(0xFFFFCC00), fontSize: 72, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────── Top Control Bar ─────────────────────────
  // Note: All circled elements (< back arrow, rainbow cinema icon, and ( 00 . 00 )) removed!

  Widget _buildTopControlBar() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 8,
        left: 16,
        right: 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Flash toggle
          IconButton(
            icon: Icon(
              _flashMode == FlashMode.off ? Icons.flash_off_rounded : Icons.flash_on_rounded,
              color: _flashMode == FlashMode.off ? Colors.white : const Color(0xFFFFCC00),
              size: 24,
            ),
            tooltip: 'Flash mode',
            onPressed: _toggleFlash,
          ),

          // Center: Empty (Circled rainbow icon removed)
          const Spacer(),

          // Right: Settings Hexagon Gear Icon (Kept clean and accessible)
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 24),
            tooltip: 'Camera settings',
            onPressed: () {
              setState(() => _showSettingsPanel = !_showSettingsPanel);
            },
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Zoom Selector Pill ─────────────────────────

  Widget _buildZoomSelectorPill() {
    final is1x = (_currentZoom - 1.0).abs() < 0.15;
    final is06 = _currentZoom <= 0.7;
    final is2x = (_currentZoom - 2.0).abs() < 0.2;
    final isCustom = !is1x && !is06 && !is2x;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _setZoom(0.6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '0.6',
                  style: GoogleFonts.outfit(
                    color: is06 ? const Color(0xFFFFCC00) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('···', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _setZoom(1.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (is1x || isCustom) ? const Color(0xFF2C2C2C) : Colors.transparent,
                  shape: isCustom ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isCustom ? BorderRadius.circular(12) : null,
                  border: (is1x || isCustom) ? Border.all(color: const Color(0xFFFFCC00).withValues(alpha: 0.8), width: 1.2) : null,
                ),
                child: Text(
                  isCustom ? '${_currentZoom.toStringAsFixed(1)}x' : '1x',
                  style: GoogleFonts.outfit(
                    color: (is1x || isCustom) ? const Color(0xFFFFCC00) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('···', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _setZoom(2.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '2',
                  style: GoogleFonts.outfit(
                    color: is2x ? const Color(0xFFFFCC00) : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Mode Selector (PHOTO / VIDEO ONLY) ─────────────────────────

  Widget _buildModeSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => _switchMode(1, 'Photo'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            color: Colors.transparent,
            child: Text(
              'PHOTO',
              style: GoogleFonts.outfit(
                color: _currentMode == 1 ? const Color(0xFFFFCC00) : Colors.white70,
                fontSize: 15,
                fontWeight: _currentMode == 1 ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: () => _switchMode(2, 'Video'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            color: Colors.transparent,
            child: Text(
              'VIDEO',
              style: GoogleFonts.outfit(
                color: _currentMode == 2 ? const Color(0xFFFFCC00) : Colors.white70,
                fontSize: 15,
                fontWeight: _currentMode == 2 ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── Bottom Controls Area ─────────────────────────

  Widget _buildBottomControlsArea() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zoom Selector Pill with real-time pinch zoom display
          _buildZoomSelectorPill(),
          const SizedBox(height: 12),

          // Active Recording Time Pill (Only shown during video recording)
          if (_isRecording) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(
                    'REC ${_formatDuration(_recordSeconds)} / 00:30',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Strictly PHOTO and VIDEO capture mode options
          _buildModeSelector(),
          const SizedBox(height: 18),

          // Bottom Shutter Controls Bar (Centered Shutter Button + Switch Camera)
          // Note: Left gallery button removed as circled; balanced with empty spacer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Empty spacer to balance the switch camera button on the right
                const SizedBox(width: 48, height: 48),

                // Center: Big Camera Shutter Button (Photo vs Video)
                GestureDetector(
                  onTap: _onShutterPressed,
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3.5),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Center(
                      child: _buildShutterCore(),
                    ),
                  ),
                ),

                // Right: Switch Camera Icon
                GestureDetector(
                  onTap: _switchCamera,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFF222222),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.sync_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShutterCore() {
    if (_currentMode == 2) {
      // Video Mode: Solid Red Circle, morphs into rounded red square during recording
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _isRecording ? 28 : 58,
        height: _isRecording ? 28 : 58,
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30),
          shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: _isRecording ? BorderRadius.circular(6) : null,
        ),
      );
    } else {
      // Photo Mode: Dark center with gold/yellow ring
      return Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFCC00), width: 3),
        ),
      );
    }
  }

  // ───────────────────────── Settings Dropdown (Screenshots 3 & 4) ─────────────────────────

  Widget _buildSettingsDropdownPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF2151515),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 1)),
      ),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drawer Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                onPressed: () => setState(() => _showSettingsPanel = false),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('More settings', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 12),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Aspect Ratio Selector
          _buildSegmentedSettingRow(
            options: ['1:1', '4:3', '16:9', 'Full'],
            selected: _aspectRatio,
            onSelect: (val) {
              setState(() => _aspectRatio = val);
            },
          ),
          const SizedBox(height: 12),

          // Countdown Timer Selector (Only active in Photo mode)
          if (_currentMode == 1) ...[
            _buildSegmentedSettingRow(
              options: ['Off', '3s', '5s', '10s'],
              selected: _timerOption == 0 ? 'Off' : '${_timerOption}s',
              onSelect: (val) {
                setState(() {
                  if (val == '3s') {
                    _timerOption = 3;
                  } else if (val == '5s') {
                    _timerOption = 5;
                  } else if (val == '10s') {
                    _timerOption = 10;
                  } else {
                    _timerOption = 0;
                  }
                });
              },
            ),
            const SizedBox(height: 14),
          ],

          // Quick-Toggles Grid (Grid lines, Level, Shake, Watermark, HDR, etc.)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildSettingPillButton(
                label: 'Grid lines',
                icon: Icons.grid_3x3_rounded,
                active: _gridEnabled,
                onTap: () => setState(() => _gridEnabled = !_gridEnabled),
              ),
              _buildSettingPillButton(
                label: 'Level',
                icon: Icons.remove_circle_outline_rounded,
                active: _levelEnabled,
                onTap: () => setState(() => _levelEnabled = !_levelEnabled),
              ),
              _buildSettingPillButton(
                label: 'Shake reminder',
                icon: Icons.camera_alt_outlined,
                active: _shakeReminder,
                onTap: () => setState(() => _shakeReminder = !_shakeReminder),
              ),
              _buildSettingPillButton(
                label: 'Watermark',
                icon: Icons.branding_watermark_outlined,
                active: _watermark,
                onTap: () => setState(() => _watermark = !_watermark),
              ),
              _buildSettingPillButton(
                label: 'Motion AF',
                icon: Icons.filter_center_focus_rounded,
                active: _motionAF,
                onTap: () => setState(() => _motionAF = !_motionAF),
              ),
              if (_currentMode == 1)
                _buildSettingPillButton(
                  label: 'HDR',
                  icon: Icons.hdr_on_rounded,
                  active: _hdrEnabled,
                  onTap: () => setState(() => _hdrEnabled = !_hdrEnabled),
                )
              else
                _buildSettingPillButton(
                  label: 'Microphone',
                  icon: Icons.mic_rounded,
                  active: _microphoneEnabled,
                  onTap: () => setState(() => _microphoneEnabled = !_microphoneEnabled),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedSettingRow({required List<String> options, required String selected, required ValueChanged<String> onSelect}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFCC00) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  opt,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: isSelected ? Colors.black : Colors.white,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSettingPillButton({required String label, required IconData icon, required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 52) / 3,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFCC00) : Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(icon, color: Colors.black87, size: 16),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Preview Screen (Photo & Video) ─────────────────────────

  Widget _buildPreviewScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Media Preview View
        Positioned.fill(
          child: Container(
            color: Colors.black,
            child: Center(
              child: _capturedType == 'video' && _videoPlayerController != null && _videoPlayerController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoPlayerController!.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_videoPlayerController!),
                          // Play / Pause Overlay Button
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_videoPlayerController!.value.isPlaying) {
                                  _videoPlayerController!.pause();
                                  _isVideoPlaying = false;
                                } else {
                                  _videoPlayerController!.play();
                                  _isVideoPlaying = true;
                                }
                              });
                            },
                            child: AnimatedOpacity(
                              opacity: _isVideoPlaying ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white70, width: 2),
                                ),
                                child: Icon(
                                  _isVideoPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : (_capturedPath != null
                      ? Image.file(
                          File(_capturedPath!),
                          fit: BoxFit.contain,
                        )
                      : const SizedBox()),
            ),
          ),
        ),

        // Top Preview Header (Close/Cancel)
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: _retakeMedia,
          ),
        ),

        // Bottom Action Bar: Retake & Confirm Send
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black.withValues(alpha: 0.85),
            padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _retakeMedia,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    label: Text('Retake', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white54, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _confirmSendMedia,
                    icon: const Icon(Icons.send_rounded, color: Colors.black),
                    label: Text('Send to Chat', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCC00),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Custom Grid Painter ─────────────────────────

class _GridLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Horizontal lines
    final h1 = size.height / 3;
    final h2 = size.height * 2 / 3;
    canvas.drawLine(Offset(0, h1), Offset(size.width, h1), paint);
    canvas.drawLine(Offset(0, h2), Offset(size.width, h2), paint);

    // Vertical lines
    final w1 = size.width / 3;
    final w2 = size.width * 2 / 3;
    canvas.drawLine(Offset(w1, 0), Offset(w1, size.height), paint);
    canvas.drawLine(Offset(w2, 0), Offset(w2, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
