import 'dart:io';
import 'package:crypto/crypto.dart';

class HashService {
  /// Calculate a unique fingerprint for large files 
  /// (To prevent OOM, we only hash the first 512KB, then append file size and modified time)
  static Future<String> calculateFingerprint(File file, DateTime modified) async {
    final size = await file.length();
    
    final randomAccessFile = await file.open();
    // Limit max read to 512KB
    final bytesToRead = size > 512 * 1024 ? 512 * 1024 : size;
    final chunkToHash = await randomAccessFile.read(bytesToRead);
    await randomAccessFile.close();

    final hash = sha256.convert(chunkToHash).toString();
    
    // Combine to form a unique fingerprint
    return '${hash}_${size}_${modified.millisecondsSinceEpoch}';
  }
}
