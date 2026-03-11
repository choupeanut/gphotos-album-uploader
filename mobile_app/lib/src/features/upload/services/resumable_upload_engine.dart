import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

class ResumableUploadEngine {
  final String accessToken;
  final String _uploadUrl = 'https://photoslibrary.googleapis.com/v1/uploads';

  ResumableUploadEngine({required this.accessToken});

  /// 1. Initiate resumable upload session
  Future<String> initiateUploadSession(File file, String fileName) async {
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final fileSize = await file.length();

    final response = await http.post(
      Uri.parse(_uploadUrl),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Length': '0',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Content-Type': mimeType,
        'X-Goog-Upload-File-Name': fileName,
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Raw-Size': fileSize.toString(),
      },
    );

    if (response.statusCode == 200) {
      final sessionUrl = response.headers['x-goog-upload-url'];
      if (sessionUrl != null) return sessionUrl;
      throw Exception('Missing x-goog-upload-url from response');
    }
    throw Exception('Failed to initiate upload: ${response.statusCode} - ${response.body}');
  }

  /// 2. Upload file in chunks (prevents OOM, supports resumable uploads)
  /// Returns the final Upload Token
  Future<String> uploadFileInChunks(String sessionUrl, File file, {void Function(double progress)? onProgress}) async {
    final int fileSize = await file.length();
    // Chunk must be a multiple of 256KB. Here we use 8MB to balance speed and memory consumption.
    final int chunkSize = 256 * 1024 * 32; 
    int offset = 0;
    String? uploadToken;

    final randomAccessFile = await file.open();

    try {
      while (offset < fileSize) {
        final int end = (offset + chunkSize < fileSize) ? offset + chunkSize : fileSize;
        final int length = end - offset;
        final bool isLastChunk = end == fileSize;

        await randomAccessFile.setPosition(offset);
        final chunk = await randomAccessFile.read(length);

        final response = await http.post(
          Uri.parse(sessionUrl),
          headers: {
            'Content-Length': chunk.length.toString(),
            'X-Goog-Upload-Command': isLastChunk ? 'upload, finalize' : 'upload',
            'X-Goog-Upload-Offset': offset.toString(),
          },
          body: chunk,
        );

        if (response.statusCode == 200) {
           if (isLastChunk) {
             uploadToken = response.body;
           } else {
             // Ensure progress is reported
             if (onProgress != null) {
               onProgress(end / fileSize);
             }
           }
        } else if (response.statusCode == 308) {
           // 308 Resume Incomplete: The server is asking to resume from a specific offset.
           // We can parse X-Goog-Upload-Size-Received to know the true offset.
           final sizeReceived = response.headers['x-goog-upload-size-received'];
           if (sizeReceived != null) {
              offset = int.parse(sizeReceived);
              continue; // Restart loop from the new offset
           } else {
              throw Exception('Upload failed: 308 but no size received.');
           }
        } else {
          // If it fails, we could query the current progress via X-Goog-Upload-Command: query before retrying
          throw Exception('Upload failed at offset $offset: ${response.statusCode} - ${response.body}');
        }
        
        offset = end;
      }
      
      if (uploadToken == null || uploadToken.isEmpty) {
         throw Exception('Upload completed but no uploadToken was received');
      }
      return uploadToken;
      
    } finally {
      await randomAccessFile.close();
    }
  }
}
