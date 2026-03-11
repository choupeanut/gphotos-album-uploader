# GPhotos Album Uploader - Android (Flutter) 版本架構設計

參考 **Immich** 的架構，為了在 Android 裝置上實現「掃描本地相簿」、「背景斷點續傳」、「防重複上傳 (Hash 比對)」以及「上傳後驗證」等進階功能，推薦使用 **Flutter** 作為行動端的開發框架，並搭配強大的本地端資料庫與背景任務機制。

以下是完整的架構設計與核心程式碼範例：

---

## 1. 核心技術選型 (Tech Stack)

*   **框架**: Flutter (Dart)
*   **本地資料庫**: [Isar](https://isar.dev/) (高效能 NoSQL，Immich 也使用此資料庫管理幾十萬張照片的 Metadata 與 Hash)。
*   **本地相簿存取**: [photo_manager](https://pub.dev/packages/photo_manager) (直接讀取 iOS/Android 底層 MediaStore 結構，支援分頁讀取與緩存)。
*   **狀態管理**: [Riverpod](https://riverpod.dev/)。
*   **背景任務**: [workmanager](https://pub.dev/packages/workmanager) (利用 Android WorkManager 執行背景掃描與斷點續傳)。

---

## 2. 核心流程設計

### A. 本地相簿掃描與 Hash 計算 (避免重複上傳)
與桌面版不同，手機端照片數量龐大，直接掃描 File System 會很慢且拿不到系統相簿分類。
1. 使用 `photo_manager` 取得手機上的 Album 與 Asset (照片/影片) 列表。
2. 將 Asset 的 `id`, `modifiedTime`, `size` 組合計算出 **SHA-256 Hash** 作為唯一指紋 (Fingerprint)。
3. 將這些資訊寫入本地 Isar 資料庫，標記 `syncStatus` 為 `PENDING`。
4. 如果資料庫中已存在相同 Hash 且 `syncStatus` 為 `DONE`，則跳過該檔案，達到**防重複上傳**的目的。

### B. 大檔案斷點續傳 (Resumable Chunked Upload)
原本 Node.js 版本使用的是 `X-Goog-Upload-Protocol: raw`，這會把檔案一次讀進記憶體，在手機上傳送大型影片 (例如 1GB) 時會直接觸發 **OOM (Out of Memory) 閃退**。
必須改用 Google Photos API 的 `resumable` 協定，並透過 `File.openRead` 進行**串流分塊讀取**。

### C. 上傳後比對與驗證 (Verification)
Google Photos API `batchCreate` 成功後，有時照片不會立刻出現。
1. 取得上傳後的 `mediaItem.id`，存入 Isar 資料庫。
2. 啟動背景驗證任務，呼叫 `mediaItems:search` 查詢該相簿。
3. 比對相簿內的 ID 與本地記錄，若確認存在，才將狀態改為 `VERIFIED`，徹底完成該照片的同步。

---

## 3. 核心程式碼實作參考

### 實作：斷點續傳與串流讀取 (Dart)
此程式碼解決了大檔案佔用記憶體的問題，支援中斷後接續上傳。

```dart
import 'dart:io';
import 'package:http/http.dart' as http;

class GooglePhotosUploader {
  final String accessToken;
  GooglePhotosUploader(this.accessToken);

  /// 1. 取得斷點續傳的 Session URL
  Future<String?> initiateUploadSession(int fileSize, String mimeType, String fileName) async {
    final response = await http.post(
      Uri.parse('https://photoslibrary.googleapis.com/v1/uploads'),
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
      return response.headers['x-goog-upload-url'];
    }
    throw Exception('Failed to initiate upload: ${response.body}');
  }

  /// 2. 分塊上傳 (防 OOM 記憶體溢出)
  Future<String> uploadFileInChunks(String sessionUrl, File file) async {
    final int fileSize = await file.length();
    // Chunk 必須是 256KB 的倍數，這裡設定為 2MB
    final int chunkSize = 256 * 1024 * 8; 
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

        if (response.statusCode != 200) {
          // 若失敗，可透過 X-Goog-Upload-Command: query 查詢當前進度再重試
          throw Exception('Upload failed at offset $offset: ${response.body}');
        }

        if (isLastChunk) {
          uploadToken = response.body;
        }
        
        offset = end;
      }
      return uploadToken!;
    } finally {
      await randomAccessFile.close();
    }
  }
}
```

### 實作：檔案 Hash 計算 (防重複)
利用 `crypto` 套件計算檔案指紋。為避免大檔案讀取過久，Immich 的策略是結合「檔案大小 + 修改時間 + 檔名前 100KB 的 Hash」。

```dart
import 'dart:io';
import 'package:crypto/crypto.dart';

Future<String> calculateAssetFingerprint(File file, DateTime modified) async {
  final size = await file.length();
  
  // 為了效能，如果是大於 5MB 的影片，只取前 512KB 計算 Hash
  final randomAccessFile = await file.open();
  final chunkToHash = await randomAccessFile.read(size > 512 * 1024 ? 512 * 1024 : size);
  await randomAccessFile.close();

  final hash = sha256.convert(chunkToHash).toString();
  
  // 組合成為唯一指紋
  return "\${hash}_\${size}_\${modified.millisecondsSinceEpoch}";
}
```

### 實作：上傳後相簿比對與驗證
```dart
Future<bool> verifyAlbumContents(String albumId, String targetMediaItemId) async {
  final response = await http.post(
    Uri.parse('https://photoslibrary.googleapis.com/v1/mediaItems:search'),
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: '{"albumId": "$albumId", "pageSize": 100}',
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final items = data['mediaItems'] as List<dynamic>? ?? [];
    
    // 檢查我們上傳的 ID 是否真的存在於 Google Photos 該相簿中
    return items.any((item) => item['id'] == targetMediaItemId);
  }
  return false;
}
```

---

## 4. 下一步開發建議

1. **建立 Flutter 專案**：在您的環境中安裝 Flutter SDK，並執行 `flutter create mobile_app`。
2. **共用 TypeScript 邏輯？**：如果您希望目前的 Electron (桌面版) 也能享有**「斷點續傳」與「防記憶體溢出」**的好處，我們可以先將 `src/main/photos.ts` 裡的 `raw` 上傳機制，重構成 Node.js 版本的 Resumable Stream 寫法！
