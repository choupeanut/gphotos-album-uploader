# 解決 serverClientId must be provided on Android 錯誤

在最新的 `google_sign_in` 7.0.0 版本中，Google 改變了安全架構：Android 端如果需要向 Google 的伺服器 (如 Google Photos API) 請求存取權限 (Scopes)，**必須同時提供 Web 應用程式 (Web Application) 的 Client ID 作為 `serverClientId`**。

請您依照以下步驟，在 Google Cloud Console 中「加開一個 Web 版的憑證」並將其填入我們的 App 中：

### 步驟 1：建立 Web 應用程式的 OAuth 用戶端 ID
1. 回到 [Google Cloud Console](https://console.cloud.google.com/)。
2. 進入「API 和服務」 > 「憑證 (Credentials)」。
3. 點擊上方的 **「+ 建立憑證」** > **「OAuth 用戶端 ID」**。
4. **應用程式類型 (Application type)** 請選擇：**`網頁應用程式 (Web application)`** (不要選 Android)。
5. 名稱可以隨便填 (例如 `GPhotos Uploader Web Client`)。
6. 底下的「已授權的 JavaScript 來源」與「已授權的重新導向 URI」都**留空即可**。
7. 點擊 **「建立 (Create)」**。
8. 畫面上會跳出一個視窗，顯示您的 **用戶端 ID (Client ID)** (通常長得像 `1234567890-abcdefg...apps.googleusercontent.com`)。
9. 請將這串 **用戶端 ID (Client ID)** 複製下來。

### 步驟 2：將這串 ID 告訴我
請您將剛剛複製的這串 `Web Client ID` 貼在對話框回覆給我。
我會把它編譯進我們 App 的程式碼 (`serverClientId` 參數) 中，這樣就可以順利登入了！