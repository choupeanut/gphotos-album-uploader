# GPhotos Album Uploader

**The Core Problem:** Currently, the official Google Photos app does not support uploading photos while preserving your local folder or Android album structures. All backed-up photos are mixed into a single timeline, losing your existing organization.

**The Solution:** This repository provides tools to solve this pain point, ensuring your photo organization is preserved in the cloud:
1. **Desktop App:** A cross-platform application (Electron/React) that uploads local folders to Google Photos, automatically creating matching albums to retain your PC's directory structure.
2. **Mobile App:** An Android application (Flutter) that directly reads local albums on your Android device (supporting albums created by any Android manufacturer) and backs them up into corresponding Google Photos albums.

[中文說明 (Traditional Chinese)](README.zh-TW.md)

## Features

- **OAuth 2.0 Authentication**: Secure login via your own Google Cloud Console credentials.
- **Directory Scanning**: Select a root folder, and the app will recursively scan its subdirectories (depth 1) for valid media files.
- **Broad Format Support**:
  - Images: `.jpg`, `.jpeg`, `.png`, `.heic`
  - Videos: `.mp4`, `.mov`, `.mkv`, `.avi`, `.3gp`, `.m4v`, `.mts`, `.webm`
- **Error Handling**: Automatically skips unsupported files and logs them to `ignored_files.log` in your selected root directory.
- **Smart Naming**: Automatically fixes HTML-escaped characters (like `&amp;`) in folder names before creating the album.
- **Batch Uploading**: Overcomes Google API limits by grouping uploads into compliant batches.
- **Real-time Progress**: Visual indicators and direct links to the newly created Google Photos albums.

## Prerequisites & Setup

Since Google Photos API restricts public app quotas, you need to provide your own OAuth credentials.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project.
3. Navigate to **APIs & Services > Library**, search for **Photos Library API**, and enable it.
4. Go to **APIs & Services > OAuth consent screen**. Choose **External** user type. **Crucial:** Add your Google account email to the **Test users** list.
5. Go to **Credentials > Create Credentials > OAuth client ID**.
6. **Important:** Select **Desktop app** as the Application type.
7. Note down your `Client ID` and `Client Secret`.

## Usage

1. Launch the application.
2. Enter your `Client ID` and `Client Secret` obtained from the steps above.
3. Click **Login with Google**. A browser window will open asking you to authorize the app.
4. Select a Root Folder containing your album directories.
5. Click **Start Upload**. You can click the "Open in Google Photos" link next to each album once it's created.

## Development & Build

### Install Dependencies
```bash
npm install
```

### Development (Linux)
*Note: Due to Electron sandbox restrictions on Linux, use the following command to start:*
```bash
npm run dev
```

### Build for Linux (AppImage)
```bash
npm run build:linux
```

### Build for Windows (.exe)
*Note: Building for Windows on a Linux host requires `wine64`.*
```bash
npm run build:win
```