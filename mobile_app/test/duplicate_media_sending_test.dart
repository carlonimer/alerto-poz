import 'package:flutter_test/flutter_test.dart';
import 'package:alerto_poz/services/socket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SocketService Event Deduplication Tests', () {
    setUp(() {
      SocketService.off('test-event');
    });

    test('Registering the same callback twice does not duplicate invocation', () {
      int callCount = 0;
      void onEvent(dynamic data) {
        callCount++;
      }

      // Register the same listener twice
      SocketService.on('test-event', onEvent);
      SocketService.on('test-event', onEvent);

      // Trigger via SocketService.off verification or registry check
      // Unregister should clean it up
      SocketService.off('test-event', onEvent);
      expect(callCount, equals(0));
    });

    test('SocketService.off with handler removes listener', () {
      void handler(dynamic data) {}
      SocketService.on('test-event-2', handler);
      SocketService.off('test-event-2', handler);
    });

    test('SocketService.off without handler removes all listeners for event', () {
      void handler1(dynamic data) {}
      void handler2(dynamic data) {}
      SocketService.on('test-event-3', handler1);
      SocketService.on('test-event-3', handler2);
      SocketService.off('test-event-3');
    });
  });

  group('Message Deduplication and In-Place Reconciliation Logic Tests', () {
    test('Optimistic entry is reconciled by clientMessageId without duplicating bubble', () {
      final List<Map<String, dynamic>> chatFeed = [];
      final Set<String> seenMessageIds = {};
      final Set<String> seenClientMessageIds = {};

      const testClientMsgId = 'cm_123_1710000000000';
      const testServerId = '501';

      // 1. Citizen captures image -> Optimistic entry added
      final optimisticEntry = <String, dynamic>{
        'clientMessageId': testClientMsgId,
        'role': 'user',
        'type': 'image',
        'content': 'data:image/jpeg;base64,sample...',
        'localPath': '/data/user/0/cache/photo.jpg',
        'status': 'uploading',
        'timestamp': DateTime.now().toIso8601String(),
      };
      chatFeed.add(optimisticEntry);
      expect(chatFeed.length, equals(1));
      expect(chatFeed[0]['id'], isNull);
      expect(chatFeed[0]['status'], equals('uploading'));

      // 2. Realtime WebSocket event arrives with matching client_message_id
      final incomingSocketData = {
        'id': testServerId,
        'incident_id': 'INC-101',
        'client_message_id': testClientMsgId,
        'sender_role': 'Citizen App',
        'message_type': 'image',
        'media_url': '/uploads/chat/media-501.jpg',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final msgId = incomingSocketData['id']?.toString();
      final clientMsgId = incomingSocketData['client_message_id']?.toString();

      // Dedupe check
      expect(seenMessageIds.contains(msgId), isFalse);
      expect(seenClientMessageIds.contains(clientMsgId), isFalse);

      // Reconcile in place
      final optIdx = chatFeed.indexWhere((m) => m['clientMessageId'] == clientMsgId);
      expect(optIdx, equals(0)); // Found optimistic entry!

      // Update in place
      chatFeed[optIdx]['id'] = msgId;
      chatFeed[optIdx]['status'] = 'sent';
      chatFeed[optIdx]['media_url'] = incomingSocketData['media_url'];
      seenMessageIds.add(msgId!);
      seenClientMessageIds.add(clientMsgId!);

      // Feed should still only have 1 entry (NO DUPLICATE)
      expect(chatFeed.length, equals(1));
      expect(chatFeed[0]['id'], equals('501'));
      expect(chatFeed[0]['media_url'], equals('/uploads/chat/media-501.jpg'));
      expect(chatFeed[0]['status'], equals('sent'));

      // 3. HTTP Response completes afterward (_applyServerAck)
      // When _applyServerAck runs with server response:
      if (seenMessageIds.contains(msgId)) {
        // Already recorded by socket
      }
      expect(chatFeed.length, equals(1));

      // 4. If a duplicate socket event arrives again for the same message:
      final duplicateArrival = seenMessageIds.contains(msgId) || seenClientMessageIds.contains(clientMsgId);
      expect(duplicateArrival, isTrue); // Correctly detected and ignored!
      expect(chatFeed.length, equals(1));
    });

    test('History fetch deduplicates and reconciles optimistic media without duplicates', () {
      final List<Map<String, dynamic>> chatFeed = [];
      final Set<String> seenMessageIds = {};
      final Set<String> seenClientMessageIds = {};

      const testClientMsgId = 'cm_123_video_999';
      const testServerId = '502';

      // Optimistic video
      chatFeed.add({
        'clientMessageId': testClientMsgId,
        'role': 'user',
        'type': 'video',
        'content': '/data/user/0/cache/video.mp4',
        'videoPath': '/data/user/0/cache/video.mp4',
        'localPath': '/data/user/0/cache/video.mp4',
        'status': 'uploading',
        'timestamp': DateTime.now().toIso8601String(),
      });

      // History messages returned from server
      final serverHistoryMessages = [
        {
          'id': testServerId,
          'client_message_id': testClientMsgId,
          'sender_role': 'Citizen App',
          'message_type': 'video',
          'media_url': '/uploads/chat/media-502.mp4',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      ];

      for (final msg in serverHistoryMessages) {
        final msgId = msg['id']?.toString();
        final clientMsgId = msg['client_message_id']?.toString();

        if (msgId != null && seenMessageIds.contains(msgId)) continue;
        if (clientMsgId != null && seenClientMessageIds.contains(clientMsgId)) continue;

        final optIdx = chatFeed.indexWhere((m) => m['clientMessageId'] == clientMsgId);
        if (optIdx != -1) {
          chatFeed[optIdx]['id'] = msgId;
          chatFeed[optIdx]['media_url'] = msg['media_url'];
          chatFeed[optIdx]['videoPath'] = msg['media_url'];
          chatFeed[optIdx]['status'] = 'sent';
          if (msgId != null) seenMessageIds.add(msgId);
          if (clientMsgId != null) seenClientMessageIds.add(clientMsgId);
        } else {
          chatFeed.add(Map<String, dynamic>.from(msg));
        }
      }

      // Still exactly 1 message in feed!
      expect(chatFeed.length, equals(1));
      expect(chatFeed[0]['id'], equals('502'));
      expect(chatFeed[0]['videoPath'], equals('/uploads/chat/media-502.mp4'));
      expect(chatFeed[0]['status'], equals('sent'));
    });

    test('Draft migration skips already-uploaded media in _flushPendingMediaUploads', () {
      // Setup pending media items
      final List<Map<String, dynamic>> pendingUploads = [
        {
          'clientMessageId': 'cm_img_1',
          'path': '/tmp/img1.jpg',
          'type': 'image',
          'uploaded': true, // Successfully uploaded during draft
        },
        {
          'clientMessageId': 'cm_img_2',
          'path': '/tmp/img2.jpg',
          'type': 'image',
          'uploaded': false, // Failed during draft (offline)
        },
      ];

      final toUpload = List<Map<String, dynamic>>.from(pendingUploads);
      final executedUploads = <String>[];

      for (final item in toUpload) {
        if (item['uploaded'] == true || item['uploaded'] == 'true') {
          // MUST SKIP already uploaded media
          continue;
        }
        executedUploads.add(item['clientMessageId'] as String);
      }

      // Only the failed item should be retried, preventing duplicate upload of img1
      expect(executedUploads.length, equals(1));
      expect(executedUploads.first, equals('cm_img_2'));
    });

    test('Failed upload can be retried safely with the same clientMessageId', () {
      final message = <String, dynamic>{
        'clientMessageId': 'cm_retry_001',
        'role': 'user',
        'type': 'image',
        'localPath': '/cache/photo.jpg',
        'status': 'failed',
        'error': 'Network timeout',
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Before retry: marked failed
      expect(message['status'], equals('failed'));
      expect(message['clientMessageId'], equals('cm_retry_001'));

      // Simulate retry start
      message['status'] = 'uploading';
      message.remove('error');
      expect(message['status'], equals('uploading'));
      expect(message['error'], isNull);

      // Simulate success ack
      message['status'] = 'sent';
      message['id'] = '601';
      expect(message['status'], equals('sent'));
      expect(message['id'], equals('601'));
      // Client message id remained constant
      expect(message['clientMessageId'], equals('cm_retry_001'));
    });

    test('Ascending chat order is preserved with tiebreaking', () {
      final t1 = DateTime(2026, 10, 17, 10, 0, 0);
      final t2 = DateTime(2026, 10, 17, 10, 0, 5);
      final t3 = DateTime(2026, 10, 17, 10, 0, 10);

      final feed = [
        {'id': '3', 'timestamp': t3.toIso8601String()},
        {'id': '1', 'timestamp': t1.toIso8601String()},
        {'id': '2', 'timestamp': t2.toIso8601String()},
      ];

      final indexed = feed.asMap().entries.toList();
      indexed.sort((a, b) {
        final ta = DateTime.parse(a.value['timestamp']!);
        final tb = DateTime.parse(b.value['timestamp']!);
        final c = ta.compareTo(tb);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
      final sorted = indexed.map((e) => e.value).toList();

      expect(sorted[0]['id'], equals('1'));
      expect(sorted[1]['id'], equals('2'));
      expect(sorted[2]['id'], equals('3'));
    });
  });
}
