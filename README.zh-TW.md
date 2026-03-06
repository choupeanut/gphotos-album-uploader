# GPhotos Album Uploader (Google Photos 本地相簿上傳工具)

這是一個基於 Electron、React 與 TypeScript 開發的跨平台桌面應用程式。它可以幫助您將電腦本機的照片資料夾自動上傳至 Google Photos，並在雲端自動建立與本機同名的相簿，完美保留您的資料夾分類結構。

## 功能特色

- **OAuth 2.0 授權登入**：透過您個人的 Google Cloud Console 憑證安全登入，不需將相片庫存取權交給第三方伺服器。
- **自動掃描目錄**：選擇一個根目錄 (Root Folder)，程式會自動掃描其第一層的子目錄，找出所有支援的媒體檔案。
- **支援多種媒體格式**：
  - 相片：`.jpg`, `.jpeg`, `.png`, `.heic`
  - 影片：`.mp4`, `.mov`, `.mkv`, `.avi`, `.3gp`, `.m4v`, `.mts`, `.webm`
- **自動過濾與紀錄**：遇到不支援的檔案格式會自動跳過，並將被忽略的檔案路徑記錄在您選擇的根目錄下的 `ignored_files.log` 檔案中。
- **智慧檔名修正**：自動將備份軟體產生的 HTML 實體編碼（例如 `&amp;`）還原為正常字元，確保雲端相簿名稱正確無誤。
- **分批上傳機制**：針對 Google Photos API 的限制，自動將照片分批 (Batch) 處理上傳，避免觸發 Rate Limit 錯誤。
- **即時進度與導覽**：介面即時顯示上傳進度，當雲端相簿建立完成後，在左側相簿列表會直接提供「在 Google Photos 開啟」的超連結。

## 事前準備與設定 (非常重要)

由於 Google 對於存取 Photos API 的應用程式有嚴格的額度與審查限制，您必須使用自己申請的 OAuth 憑證來執行此程式。

1. 前往 [Google Cloud Console](https://console.cloud.google.com/)。
2. 建立一個新的專案 (Project)。
3. 在左側選單進入 **[API 和服務] > [程式庫]**，搜尋 **Photos Library API** 並點擊「啟用」。
4. 進入 **[API 和服務] > [OAuth 同意畫面]**。User Type 請選擇 **外部 (External)**。**最重要的一步：請務必將您要登入上傳照片的 Google 帳號加入「Test users (測試使用者)」清單中。**
5. 進入 **[憑證] > [建立憑證] > [OAuth 用戶端 ID]**。
6. **重要：** 應用程式類型請務必選擇 **「桌面應用程式 (Desktop app)」**。
7. 建立完成後，將畫面上的 `Client ID` 與 `Client Secret` 記下來。

## 使用方式

1. 開啟 GPhotos Album Uploader。
2. 在初始設定畫面，填入您剛才取得的 `Client ID` 與 `Client Secret`。
3. 點擊 **Login with Google**，系統會開啟瀏覽器讓您授權。請使用您加入測試清單的帳號登入並同意權限。
4. 登入成功後，點擊 **Choose Root Folder** 選擇包含您多個相簿資料夾的總目錄。
5. 點擊 **Start Upload** 開始上傳。您可以在左側列表點擊超連結直接前往 Google Photos 查看成果。

## 開發與編譯指南

### 安裝依賴套件
```bash
npm install
```

### 開發模式啟動 (Linux 環境)
*註：由於 Linux 環境下的 Electron 沙盒權限限制，請使用此指令啟動以自動帶入 `--no-sandbox` 參數：*
```bash
npm run dev
```

### 打包 Linux 版本 (AppImage)
```bash
npm run build:linux
```

### 打包 Windows 版本 (.exe)
*註：若在 Linux 系統上編譯 Windows 執行檔，系統必須先安裝 `wine64`。*
```bash
npm run build:win
```