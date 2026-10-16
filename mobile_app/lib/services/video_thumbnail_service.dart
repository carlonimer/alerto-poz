import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'api_service.dart';

/// Service responsible for extracting, caching, and persisting video thumbnails
/// so that recorded and received videos display real frame previews in chat.
class VideoThumbnailService {
  static final Map<String, Uint8List> _memoryCache = {};
  static final Map<String, Future<Uint8List?>> _inFlightFutures = {};

  /// Derives a consistent, sanitized cache key from a URL or local file path.
  static String deriveKey(String videoUrlOrPath) {
    if (videoUrlOrPath.trim().isEmpty) return 'unknown';
    final cleaned = videoUrlOrPath.trim().split('?').first;
    final seg = cleaned.split('/');
    if (seg.isNotEmpty && seg.last.isNotEmpty) {
      return seg.last.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    }
    return cleaned.split(Platform.pathSeparator).last.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
  }

  /// Manually cache thumbnail bytes (e.g., extracted immediately after recording).
  static void cacheThumbnail(String keyOrUrl, Uint8List bytes) {
    if (bytes.isEmpty) return;
    final key = deriveKey(keyOrUrl);
    _memoryCache[key] = bytes;
    _memoryCache[keyOrUrl] = bytes;

    // Persist to disk cache in background
    _saveToDisk(key, bytes);
  }

  /// Retrieves cached thumbnail synchronously if available in memory.
  static Uint8List? getCachedThumbnailSync(String videoUrlOrPath) {
    final key = deriveKey(videoUrlOrPath);
    return _memoryCache[key] ?? _memoryCache[videoUrlOrPath];
  }

  /// Asynchronously retrieves, extracts, or downloads and caches a video thumbnail.
  static Future<Uint8List?> getThumbnail(String videoUrlOrPath) async {
    final trimmed = videoUrlOrPath.trim();
    if (trimmed.isEmpty) return null;

    final key = deriveKey(trimmed);

    // 1. Check in-memory cache
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }
    if (_memoryCache.containsKey(trimmed)) {
      return _memoryCache[trimmed];
    }

    // 2. Avoid duplicate concurrent extractions
    if (_inFlightFutures.containsKey(key)) {
      return _inFlightFutures[key];
    }

    final future = _loadOrGenerate(trimmed, key);
    _inFlightFutures[key] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _inFlightFutures.remove(key);
    }
  }

  static Future<Uint8List?> _loadOrGenerate(String trimmed, String key) async {
    try {
      // 1. Check local persistent disk cache
      final tempDir = await getTemporaryDirectory();
      final thumbDir = Directory('${tempDir.path}/video_thumbs');
      if (!await thumbDir.exists()) {
        await thumbDir.create(recursive: true);
      }

      final diskFile = File('${thumbDir.path}/$key.jpg');
      if (await diskFile.exists() && await diskFile.length() > 0) {
        final bytes = await diskFile.readAsBytes();
        _memoryCache[key] = bytes;
        _memoryCache[trimmed] = bytes;
        return bytes;
      }

      // 2. Generate from physical file or download remote video
      Uint8List? generatedBytes;
      if (File(trimmed).existsSync()) {
        final thumbFile = await VideoCompress.getFileThumbnail(
          trimmed,
          quality: 75,
          position: -1,
        );
        if (await thumbFile.exists() && await thumbFile.length() > 0) {
          generatedBytes = await thumbFile.readAsBytes();
        }
      } else {
        // Remote video URL (e.g. /uploads/chat/xxx.mp4)
        final fullUrl = trimmed.startsWith('http') ? trimmed : '${ApiService.baseUrl}$trimmed';
        final uri = Uri.tryParse(fullUrl);
        if (uri != null) {
          final resp = await http.get(uri).timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            final tempVid = File('${thumbDir.path}/temp_$key.mp4');
            await tempVid.writeAsBytes(resp.bodyBytes);
            try {
              final thumbFile = await VideoCompress.getFileThumbnail(
                tempVid.path,
                quality: 75,
                position: -1,
              );
              if (await thumbFile.exists() && await thumbFile.length() > 0) {
                generatedBytes = await thumbFile.readAsBytes();
              }
            } finally {
              try {
                if (await tempVid.exists()) await tempVid.delete();
              } catch (_) {}
            }
          }
        }
      }

      if (generatedBytes != null && generatedBytes.isNotEmpty) {
        _memoryCache[key] = generatedBytes;
        _memoryCache[trimmed] = generatedBytes;
        await diskFile.writeAsBytes(generatedBytes);
        return generatedBytes;
      }
    } catch (e) {
      debugPrint("VideoThumbnailService failed for $trimmed: $e");
    }
    return null;
  }

  static Future<void> _saveToDisk(String key, Uint8List bytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbDir = Directory('${tempDir.path}/video_thumbs');
      if (!await thumbDir.exists()) {
        await thumbDir.create(recursive: true);
      }
      final file = File('${thumbDir.path}/$key.jpg');
      await file.writeAsBytes(bytes);
    } catch (e) {
      debugPrint("Failed to persist video thumbnail to disk: $e");
    }
  }
}
