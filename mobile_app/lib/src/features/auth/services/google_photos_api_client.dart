import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synchronized/synchronized.dart';
import 'google_auth_service.dart';

final googlePhotosApiProvider = Provider<GooglePhotosApiClient>((ref) {
  final authService = ref.read(authServiceProvider);
  return GooglePhotosApiClient(authService: authService);
});

class GooglePhotosApiClient {
  final GoogleAuthService _authService;
  final String _baseUrl = 'https://photoslibrary.googleapis.com/v1';
  final Lock _albumLock = Lock();
  final Lock _batchLock = Lock();
  bool _albumCacheLoaded = false;

  GooglePhotosApiClient({required GoogleAuthService authService})
      : _authService = authService;

  Future<Map<String, String>> _getHeaders() async {
    final authHeaders = await _authService.getAuthHeaders();
    if (authHeaders == null) {
      throw Exception('使用者未登入，無法發送請求');
    }
    return {
      ...authHeaders,
      'Content-Type': 'application/json',
    };
  }

  final Map<String, String> _albumIdCache = {};

  /// Fetch and cache existing albums (only once per session)
  Future<void> _fetchAndCacheAlbums({bool force = false}) async {
    if (_albumCacheLoaded && !force) return;

    final headers = await _getHeaders();
    String? nextPageToken;
    int pageCount = 0;
    const maxPages = 100; // Safety limit to prevent infinite loops

    do {
      final url = nextPageToken == null 
          ? '$_baseUrl/albums?pageSize=50'
          : '$_baseUrl/albums?pageSize=50&pageToken=$nextPageToken';
          
      final response = await http.get(Uri.parse(url), headers: headers);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final albums = data['albums'] as List<dynamic>? ?? [];
        
        for (var album in albums) {
          final title = album['title'] as String?;
          final id = album['id'] as String?;
          if (title != null && id != null) {
            // Keep the FIRST album with a given name (don't overwrite)
            _albumIdCache.putIfAbsent(title, () => id);
          }
        }
        nextPageToken = data['nextPageToken'];
      } else {
        print('_fetchAndCacheAlbums failed page $pageCount: ${response.statusCode}');
        break;
      }
      pageCount++;
    } while (nextPageToken != null && pageCount < maxPages);

    _albumCacheLoaded = true;
  }

  /// Get or create a Google Photos album ID.
  /// Uses lock to prevent concurrent creation of duplicate albums.
  Future<String> getOrCreateAlbum(String title) async {
    return await _albumLock.synchronized(() async {
      // 1. Check cache first
      if (_albumIdCache.containsKey(title)) {
        return _albumIdCache[title]!;
      }
      
      // 2. If cache hasn't been loaded yet, do a full fetch
      if (!_albumCacheLoaded) {
        try {
          await _fetchAndCacheAlbums();
        } catch (e) {
          print('_fetchAndCacheAlbums error: $e');
        }
      }
      
      if (_albumIdCache.containsKey(title)) {
        return _albumIdCache[title]!;
      }

      // 3. Cache was loaded but title not found — do a forced refresh
      //    in case album was created externally or in a previous session
      if (_albumCacheLoaded) {
        try {
          await _fetchAndCacheAlbums(force: true);
        } catch (e) {
          print('_fetchAndCacheAlbums refresh error: $e');
        }
        if (_albumIdCache.containsKey(title)) {
          return _albumIdCache[title]!;
        }
      }

      // 4. Create a new album via API (with retry logic for 429 rate limits)
      final headers = await _getHeaders();
      
      for (int i = 0; i < 3; i++) {
        try {
          final response = await http.post(
            Uri.parse('$_baseUrl/albums'),
            headers: headers,
            body: jsonEncode({
              'album': {'title': title}
            }),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final newId = data['id'] as String;
            _albumIdCache[title] = newId; // Update cache
            print('Created new album "$title" with id: $newId');
            return newId;
          } else if (response.statusCode == 429) {
            await Future.delayed(Duration(seconds: 2 * (i + 1)));
            continue;
          } else {
            throw Exception('Failed to create album: ${response.statusCode} - ${response.body}');
          }
        } catch (e) {
          if (i == 2) rethrow;
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
        }
      }
      throw Exception('Failed to create album: retries exhausted');
    });
  }

  /// Batch create media items in a specific album using their uploadTokens
  Future<dynamic> batchCreateMediaItems(String albumId, List<Map<String, String>> items) async {
    return await _batchLock.synchronized(() async {
      // Force a minimum delay of 1.5 seconds between batchCreate calls to avoid Google's strict 'concurrent write request' quota
      await Future.delayed(const Duration(milliseconds: 1500));
      
      final headers = await _getHeaders();
      
      final newMediaItems = items.map((item) {
        return {
          'description': item['fileName'],
          'simpleMediaItem': {
            'uploadToken': item['uploadToken'],
          }
        };
      }).toList();

      for (int i = 0; i < 3; i++) {
        try {
          final response = await http.post(
            Uri.parse('$_baseUrl/mediaItems:batchCreate'),
            headers: headers,
            body: jsonEncode({
              'albumId': albumId,
              'newMediaItems': newMediaItems,
            }),
          );

          if (response.statusCode == 200) {
            return jsonDecode(response.body); // Return mediaItems array containing status for each
          } else if (response.statusCode == 429) {
            await Future.delayed(Duration(seconds: 3 * (i + 1)));
            continue;
          } else {
            throw Exception('Failed to batch create media: ${response.statusCode} - ${response.body}');
          }
        } catch (e) {
          if (i == 2) rethrow;
          await Future.delayed(Duration(seconds: 3 * (i + 1)));
        }
      }
      throw Exception('Failed to batch create media: retries exhausted');
    });
  }

  /// Verify if a photo exists in an album after uploading
  Future<bool> checkMediaItemExistsInAlbum(String albumId, String mediaItemId) async {
    final headers = await _getHeaders();
    
    final response = await http.post(
      Uri.parse('$_baseUrl/mediaItems:search'),
      headers: headers,
      body: jsonEncode({
        'albumId': albumId,
        'pageSize': 100, // 批次檢查
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final mediaItems = data['mediaItems'] as List<dynamic>? ?? [];
      
      // 搜尋是否包含目標 ID
      return mediaItems.any((item) => item['id'] == mediaItemId);
    }
    return false;
  }
}
