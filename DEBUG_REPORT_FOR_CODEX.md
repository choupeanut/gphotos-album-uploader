# Google Photos Uploader (Mobile) - 深度除錯與重構報告
**致 Codex 5.3 Reviewer**

這是一份完整的 Debug 歷程報告，記錄了我們在實作「背景批量上傳至 Google Photos」時遭遇的連環陷阱，以及最終的架構決策。請協助 Review 這個歷程並給予架構上的建議。

---

## 💥 問題一：無限轉圈與假死 (The Infinite Spinner)
**現象**：
使用者點擊「開始背景備份」後，UI 按鈕陷入無限轉圈，且沒有任何相簿被建立，也沒有任何照片被上傳，`Error Log` 甚至連一行報錯都沒有。

**排查歷程**：
1. 一開始懷疑是 UI `_isUploading` 狀態卡死，或是 `getAccessToken()` 掛住。於是我們在整個啟動流程加入了極端嚴格的 `.timeout(10s)` 與微秒級別的 Trace Log。
2. 加上 Log 後，我們發現 `enqueuePendingUploads` 其實**瞬間就執行完畢並返回了**！UI 按鈕的 Spinner 也確實停止了。
3. 但使用者仍然覺得「無限轉圈」，原因是我們在 `DashboardScreen` 的「相簿列表」旁邊寫了一個小小的 `CircularProgressIndicator`（只要該相簿的狀態是 `uploading > 0` 就會轉圈）。
4. 既然 `uploading` 狀態沒有消失，代表 `_processAndEnqueue` 交付給背景引擎的任務，**永遠沒有觸發 Callback** 來更新狀態 (變成 Done 或 Failed)！

**Codex 5.3 成功抓出的 P0 致命錯誤**：
> `註冊 callback 沒指定 group（預設 default group），任務卻指定 group: 'gphotos_backup'，background_downloader 是 group-based callback，group 不同就不會進 _handleTaskStatus！`

我們修復了 `group` 參數後，確實收到了 Callback。但是，緊接著引發了下一個更嚴重的問題。

---

## 💥 問題二：網路無預警斷線 (The Doze Mode Kill)
**現象**：
當任務成功進入背景並開始上傳後，只要使用者把 App 滑到背景 (Background) 或關閉螢幕，一兩張照片上傳成功後，後續的**所有**請求瞬間全部報錯：
`ClientException with SocketException: Failed host lookup: 'photoslibrary.googleapis.com' (OS Error: No address associated with hostname, errno = 7)`

**排查歷程**：
1. 這個 `SocketException` 明確表示「沒有網路 (DNS 解析失敗)」。
2. 這是因為我們拔除了 `background_downloader`，改用自己寫的「Dart 原生非同步迴圈 (`_processAndEnqueue`)」搭配 `ResumableUploadEngine` 來切塊上傳。
3. **Android 12+ 的殘酷機制**：當一個普通的 Dart App 被退到背景超過大約 30~60 秒，系統的 Doze Mode 會**直接切斷該 App 的網路權限**。這完美解釋了為什麼前 4 張照片（前 20 秒）活得好好的，第 5 張開始網路瞬間暴斃。
4. 若要讓 Dart 引擎在背景存活，必須手寫龐大的 Java/Kotlin Foreground Service 來向系統宣告。

---

## 💥 問題三：套件失效與通知系統崩潰 (The Notification Crash)
**現象**：
既然自己寫的 Dart 引擎會在背景被斷網，我們決定**退回使用 `background_downloader`**，因為它底層實作了 WorkManager 與 Foreground Service，天生免疫斷網問題。但我們遇到了以下兩個阻礙：

1. **Android 13 通知權限崩潰**：
   為了美化通知，我們引入了 `flutter_local_notifications`，但它的初始化函數 `initialize(AndroidInitializationSettings('@mipmap/ic_launcher'))` 在某些 Android 系統（如小米/三星）上會因為找不到資源而**直接死鎖 (Deadlock)** 整個執行緒，導致連帶後面的 `registerCallbacks` 都無法執行！
2. **多執行緒的 429 轟炸 (Rate Limiting)**：
   `background_downloader` 預設是**多執行緒併發 (Concurrent)** 的。如果 5 張照片同時傳完，它會同時觸發 5 次 `batchCreateMediaItems`。Google Photos API 對於 `concurrent write request` 有極其嚴格的 Quota 限制，這導致只有 1 張照片能成功建相簿，另外 4 張全部被 `429 Too Many Requests` 踢掉。

---

## 🛠️ 最終決策與架構解決方案

為了解決這個三角習題（背景存活 vs. 併發限流 vs. 通知崩潰），我們設計了以下最終架構：

1. **捨棄複雜的背景下載器，回歸純 Dart 引擎 (`ResumableUploadEngine`)**
   既然 `background_downloader` 會帶來不受控的併發（導致 429）以及權限/群組配置的黑盒子地雷，我們決定徹底拔除它，改用我們完全掌控的純 Dart 迴圈。
   * **解決 429 問題**：純 Dart 迴圈是「循序漸進 (Sequential)」的。傳完一張 -> 睡 1 秒 -> 建立相簿 -> 再傳下一張。這完美繞過了 Google 的併發限制。

2. **拔除 `flutter_local_notifications`，改用全手動輪詢**
   避免通知系統的初始化導致主執行緒死鎖。

3. **網路中斷的優雅退避 (Graceful Degradation)**
   既然純 Dart 引擎會在螢幕關閉 1 分鐘後被 Android 斷網，我們**不再強求它能在背景無限期執行**。
   * 我們在 `_processCompletedUpload` 和 `initiateUploadSession` 中加入了針對 `SocketException` 與 `Connection closed` 的捕捉。
   * 一旦偵測到網路被系統切斷，我們**不會**將照片標記為 Failed (死件)，而是把它**優雅地退回 `Pending` (等待中)**。
   * 下次使用者打開 App 時，只要再按一次「開始備份」，它就會從斷點無縫接續上傳，不會有任何資料遺失或重複！

---
**請 Codex 5.3 針對目前的「純 Dart 循序上傳 + 斷網優雅退避」架構，給予未來演進為「真 Foreground Service」的評估與建議。**