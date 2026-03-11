# 如何開放 GPhotos Uploader 給朋友或大眾使用

因為我們的 App 使用了 **Google Photos Library API**，這在 Google 的定義中屬於「敏感權限 (Sensitive Scopes)」。
因此，您可以根據需求，選擇以下兩種方式來開放權限給其他人：

---

## 方式一：新增朋友為「測試使用者」(免審核，最快，適合親友)

如果您只是想讓幾個朋友（上限 100 人）安裝這個 APK 幫忙測試或自用，**完全不需要經過 Google 審核**。

**操作步驟：**
1. 進入 [Google Cloud Console](https://console.cloud.google.com/)。
2. 確保您選對了您的專案（例如：GPhotos Uploader）。
3. 點擊左側選單的 **「API 和服務」 > 「OAuth 同意畫面 (OAuth consent screen)」**。
4. 確認您的「發布狀態 (Publishing status)」是維持在 **「測試中 (Testing)」**。
   *(如果您之前不小心按到了 In production，請點擊 "返回測試階段 (Back to testing)")*
5. 往下捲動找到 **「測試使用者 (Test users)」** 區塊。
6. 點擊 **「+ 新增使用者 (ADD USERS)」**。
7. 輸入您朋友的 Google 帳號 (Gmail)，點擊儲存。
8. 把您編譯好的 `.apk` 檔案傳給朋友安裝。

**朋友的使用體驗：**
朋友安裝後點擊「使用 Google 帳號登入」時，Google 為了保護他們，畫面會跳出一個警告：*「此應用程式尚未通過 Google 驗證 (Google hasn't verified this app)」*。
您只要請朋友點擊左下角的 **「進階 (Advanced)」** -> **「繼續前往 (Go to xxx (unsafe))」**，就可以順利授權並開始備份了！

---

## 方式二：將 App 發布為公開可用 (需經過 Google 嚴格人工審核)

如果您希望把這個 App 放到網路上、論壇上給大家自由下載，且不希望他們登入時看到「未經驗證」的紅色警告，您就必須將狀態改為「發布」，並通過 Google 官方的 Trust & Safety 團隊審核。

**這是一條非常漫長且嚴格的路：**

1. **申請發布**：在「OAuth 同意畫面」點擊 **「發布應用程式 (Publish App)」**。
2. **準備隱私權政策 (Privacy Policy)**：您必須架設一個網站（或用 GitHub Pages），放上符合法規的隱私權政策，清楚說明您的 App 為什麼需要相簿權限、會如何使用、且承諾不會將資料傳送到其他第三方伺服器。
3. **準備示範影片 (Demo Video)**：您必須錄製一段 YouTube 影片（畫面要清晰）。影片內容要包含從「點擊登入按鈕」、「同意授權畫面」一路操作到「照片成功上傳顯示在 App 內」，以證明您的 App 真的有在做它宣稱的事情。
4. **提交審核 (Verification)**：送出後，Google 團隊通常會花 3~7 個工作天進行人工審核。由於 Photos API 是敏感權限，他們甚至會發 Email 問您為什麼不用官方 App 等等問題。

**💡 給您的強烈建議：**
除非您打算將此 App 正式上架到 Google Play 商店營利，或是打算開源並宣傳給上萬人使用，否則**請直接使用「方式一」**。
只要把親朋好友的 Gmail 信箱手動加進後台，並請他們在跳出警告時點擊「進階 -> 繼續」，他們就能立刻享受這套超強的備份系統，完全省去跟 Google 官方來回審核文件的麻煩！