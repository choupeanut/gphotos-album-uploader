# GPhotos Album Uploader - Android Version (Flutter) Tasks Plan

這份計畫書是針對行動版 (Android/Flutter) 從零到一的建置清單，參考 Immich 處理大量媒體素材的最佳實務。

## Phase 1: 專案初始化與基礎建設 (Project Setup & Infrastructure)
- [x] **Task 1.1**: 安裝 Flutter SDK 並建立專案 (`flutter create gphotos_uploader_mobile`)。
- [x] **Task 1.2**: 設定 `pubspec.yaml`，引入核心套件：
  - `photo_manager` (相簿存取)
  - `isar` & `isar_flutter_libs` (高效能本地資料庫)
  - `flutter_riverpod` (狀態管理)
  - `http` & `google_sign_in` (API & 驗證)
  - `crypto` (Hash 計算)
  - `workmanager` (背景任務)
- [x] **Task 1.3**: 設定 Android `AndroidManifest.xml` 權限：
  - `READ_EXTERNAL_STORAGE` / `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO`
  - `INTERNET`
  - `WAKE_LOCK` (背景執行需要)
- [x] **Task 1.4**: 建立專案基本目錄結構：`lib/src/features/` (依功能切分模組，如 auth, albums, upload, database)。

## Phase 2: 驗證與 Google API 串接 (Auth & Google API)
 - [x] **Task 2.1**: 設定 Firebase 專案與 OAuth 2.0 客戶端 ID (為 Android 應用程式設定 SHA-1 憑證)。
 - [x] **Task 2.2**: 實作 `GoogleSignInService`，取得具備 `https://www.googleapis.com/auth/photoslibrary.appendonly` 權限的 Access Token。
 - [x] **Task 2.3**: 實作 `GooglePhotosApiClient` 基礎類別，用於處理授權 Header 與錯誤重試邏輯。

## Phase 3: 本地資料庫與 Hash 防重複機制 (Local Database & Deduplication)
 - [x] **Task 3.1**: 定義 Isar Collection (`AssetMetadata`)，包含欄位：
  - `localId` (String, 主鍵或唯一索引)
  - `albumName` (String)
  - `hashFingerprint` (String)
  - `size` (int)
  - `syncStatus` (Enum: PENDING, UPLOADING, DONE, VERIFIED, FAILED)
  - `remoteMediaItemId` (String, Google API 回傳的 ID)
 - [x] **Task 3.2**: 實作 `HashService`：
  - 利用檔案大小 + 修改時間 + 取檔案前段 512KB (避免大影片 OOM) 進行 `sha256` 計算。
 - [x] **Task 3.3**: 實作本地 DB CRUD Repository 介面，供後續掃描與上傳更新狀態使用。

## Phase 4: 本地相簿掃描器 (Local Media Scanner)
 - [x] **Task 4.1**: 實作 `MediaScannerService`：
  - 呼叫 `photo_manager` 獲取裝置上所有相簿 (Album/Folder)。
  - 取得相簿內所有的照片/影片 (AssetEntity)。
 - [x] **Task 4.2**: 實作掃描過濾機制：
  - 略過已存在 DB 且狀態為 `DONE` / `VERIFIED` 的項目。
  - 將新發現的項目計算 Hash 並寫入 Isar DB，標記為 `PENDING`。

## Phase 5: 上傳引擎與斷點續傳 (Upload Engine & Resumable Tasks)
 - [x] **Task 5.1**: 實作 `UploadEngine` 的 Chunked Resumable Upload 邏輯 (使用 `File.openRead` 與 `dart:io` 的 RandomAccessFile 進行串流分段讀取，固定 2MB 或 5MB chunk)。
 - [x] **Task 5.2**: 實作 `AlbumManager`，若 Google Photos 上尚未建立該名稱的相簿，則發送 `POST /v1/albums` 建立相簿並快取其 `albumId`。
 - [x] **Task 5.3**: 實作 `batchCreateMediaItems` 邏輯，將上傳取得的 `uploadToken` 綁定進指定的相簿中。
 - [x] **Task 5.4**: 將 Upload 邏輯包裝至 **background_downloader** 任務：
  - 允許使用者在背景 (即使 App 被滑掉或在背景中) 執行上傳任務。
  - 每上傳完一個 chunk 或一張圖片，即時更新 Isar DB 的進度與狀態。

## Phase 6: 上傳後驗證機制 (Verification Mechanism)
 - [x] **Task 6.1**: 實作 `VerificationWorker` (可設定為定時背景任務)：
  - 查詢 Isar DB 狀態為 `DONE` (已完成 BatchCreate) 的照片。
  - 呼叫 Google Photos API `mediaItems:search` (或 `mediaItems:get`) 檢查該 `remoteMediaItemId` 是否生效。
  - 若 API 回應確認，將狀態更新為 `VERIFIED`；若失敗超過一定次數，退回 `PENDING` 重新上傳。

## Phase 7: UI 畫面與狀態管理 (UI & State Management)
 - [x] **Task 7.1**: 實作 **登入畫面 (Login Screen)**。
 - [x] **Task 7.2**: 實作 **Dashboard (主畫面)**：
  - 顯示本機偵測到的相簿列表。
  - 顯示各相簿的照片數量與尚未備份的數量。
 - [x] **Task 7.3**: 實作 **上傳狀態監控面板 (Progress Dashboard)**：
  - 綁定 Riverpod 讀取 Isar 的 Stream (即時更新數量)。
  - 顯示進度條 (例如：正在上傳 XX/YY，已完成 ZZ)。
  - 顯示目前的背景任務狀態 (Running/Idle)。
 - [x] **Task 7.4**: 實作 **日誌/錯誤畫面 (Logs/Errors)**，以便排除錯誤 (如被忽略的不支援格式)。

## Phase 8: 測試與優化 (Testing & Polish)
- [ ] **Task 8.1**: 真機測試 (大影片上傳測試，觀察記憶體與耗電)。
 - [x] **Task 8.2**: 處理不同網路環境 (如：僅限 Wi-Fi 時上傳的設定)。
- [ ] **Task 8.3**: 加入錯誤重試策略與 Exponential Backoff。
