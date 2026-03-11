# GPhotos Uploader Mobile

**Primary Objective:** Google Photos currently lacks the ability to backup photos while preserving the local album structure created by various Android device manufacturers. This Flutter app directly reads the Android media store's album configurations and syncs them directly into matching Google Photos albums.

Flutter Android App for scanning local albums and uploading photos/videos to Google Photos.

## Current Architecture

- **UI / State**: Flutter + Riverpod
- **Auth**: `google_sign_in`
- **Media Access**: `photo_manager`
- **Local DB**: `sqflite`
- **Upload Session**: `ResumableUploadEngine` (create Google upload session URL)
- **Background Transfer**: `background_downloader` (WorkManager/Foreground Service)
- **Post Upload Binding**: Serialized queue to call Google Photos `batchCreate` safely
- **Notifications**: `background_downloader` task notifications + Android permission flow

## Core Flow

1. User signs in with Google account.
2. App scans selected albums and writes metadata into SQLite.
3. Pending items create resumable upload sessions and are enqueued into Android background transfer.
4. Background callback receives upload token and enters serialized post-upload queue.
5. App calls Google Photos `batchCreate` into album with retry/limit protection.
6. Progress and completion notifications are shown on Android.

## Important Notes

- Background upload supports screen-off and app background scenarios through system-managed tasks.
- Post-upload album binding is serialized to reduce Google Photos write-rate failures (429).
- Retryable network failures are moved back to `pending` for next run.

## Development

### Prerequisites

To build and run this application yourself, you will need to set up your own Google Cloud project and OAuth credentials, as Google strictly limits API usage for unverified apps.

1.  **Create a Google Cloud Project:**
    *   Go to the [Google Cloud Console](https://console.cloud.google.com/).
    *   Create a new project.
    *   Navigate to **APIs & Services > Library**, search for **Photos Library API**, and enable it.
2.  **Configure OAuth Consent Screen:**
    *   Go to **APIs & Services > OAuth consent screen**.
    *   Select **External** user type.
    *   Fill in the required app information.
    *   **Crucial Step for Testing:** Under the **Test users** section, click **+ ADD USERS** and add the Google account email address(es) you intend to use for testing the app. *Only these specific accounts will be able to log in while the app is unverified.*
3.  **Create OAuth Credentials:**
    *   Go to **APIs & Services > Credentials**.
    *   Click **Create Credentials > OAuth client ID**.
    *   Select **Web application** (NOT Android) as the Application type. *Note: Using Web Application type is required for the specific OAuth flow used in this app.*
    *   Note down your `Client ID`.
4.  **Configure the App:**
    *   Open `lib/services/google_auth_service.dart` (or the relevant configuration file).
    *   Replace the placeholder Client ID with your newly created `Client ID`.

### Building and Running

Ensure you have Flutter installed and configured for Android development.

```bash
# Get dependencies
flutter pub get

# Run the app on a connected device or emulator
flutter run

# Build a release APK
flutter build apk --release
```

**Note on First Login:** When you first log in with your configured test account, Google will display a warning screen stating "Google hasn't verified this app". Click **Advanced**, and then click **Go to [Your App Name] (unsafe)** to proceed with the authorization.

