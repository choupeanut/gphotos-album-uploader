# 在 Linux 安裝 Android Studio 並設定 Flutter 開發環境

為了能夠成功編譯 Flutter Android 應用程式 (APK)，您需要安裝 Android SDK。最簡單且官方最推薦的方式是直接安裝 Android Studio。

請依照以下步驟在您的電腦上進行安裝與設定：

### 1. 下載 Android Studio
請開啟您的網頁瀏覽器，前往 Android Studio 官方下載頁面：
👉 [https://developer.android.com/studio](https://developer.android.com/studio)
下載 Linux 版本的 `.tar.gz` 壓縮檔 (例如 `android-studio-202X.X.X.X-linux.tar.gz`)。

### 2. 解壓縮並安裝
下載完成後，您可以將其解壓縮到 `/opt` 或您的家目錄下。例如，打開終端機並輸入：
```bash
# 假設您下載到 ~/Downloads 目錄下
tar -xzf ~/Downloads/android-studio-*.tar.gz -C ~/
```

### 3. 啟動 Android Studio 進行初次設定
解壓縮後，執行 `studio.sh` 來啟動 Android Studio 的設定精靈：
```bash
~/android-studio/bin/studio.sh
```

**【重要步驟】設定精靈 (Setup Wizard)：**
1. 當精靈詢問是否匯入設定時，選擇 **Do not import settings**。
2. 在安裝類型 (Install Type) 選擇 **Standard**。
3. 一路點擊 **Next**。精靈會自動幫您下載並安裝最新的 **Android SDK**、**Android SDK Platform-Tools** 以及 **Android Emulator**。
4. 點擊 **Finish** 開始下載 (這可能需要幾分鐘的時間，視網路速度而定)。

### 4. 設定環境變數
安裝完成後，為了讓 Flutter 能夠找到 Android SDK，您需要將 SDK 路徑加入您的環境變數中。
請打開終端機，編輯您的 `~/.bashrc` (如果您使用 bash) 或 `~/.zshrc` (如果您使用 zsh)：

```bash
echo 'export ANDROID_HOME=$HOME/Android/Sdk' >> ~/.bashrc
echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools' >> ~/.bashrc
source ~/.bashrc
```

### 5. 接受 Android 授權協議
Flutter 需要您同意 Android SDK 的授權協議才能進行編譯。請在終端機執行以下指令：
```bash
flutter doctor --android-licenses
```
*(當提示出現時，請一路輸入 `y` 並按下 Enter 同意所有條款)*

### 6. 檢查環境設定
最後，執行 `flutter doctor` 來確認一切是否就緒：
```bash
flutter doctor
```
如果看到 **[✓] Android toolchain - develop for Android devices**，就代表您已經成功設定好 Android 開發環境了！

---
完成上述步驟後，您就可以回到專案目錄下執行編譯指令：
```bash
cd /home/peanutchou/pricer/gphotos-album-uploader/mobile_app
flutter build apk --debug
```