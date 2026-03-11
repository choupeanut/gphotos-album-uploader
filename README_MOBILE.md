# GPhotos Album Uploader (Mobile)

**Primary Objective:** The official Google Photos app backs up all images into a single chronological timeline, completely ignoring the carefully organized local albums created by different Android manufacturers (Samsung, Xiaomi, Sony, etc.). This Flutter application solves this by directly reading your Android device's local albums, uploading the photos, and automatically organizing them into corresponding albums on Google Photos.

It is a robust Flutter application featuring an advanced SQLite caching engine, incremental sync logic, and a fully customized native chunked upload engine that completely bypasses background downloading issues on Android 13+.

## Features

- **Incremental Sync**: Only uploads newly added photos. Automatically groups by album.
- **Smart Cloud Matching**: Memorizes `remoteAlbumId` so photos go exactly where they belong.
- **Resumable Uploads**: Custom Dart engine safely uploads large videos in chunks without causing Out-of-Memory (OOM) crashes.
- **Robust Rate-Limiting Defense**: Built-in exponential backoff strictly prevents Google API `429 Too Many Requests` errors.
- **Persistent Notifications**: A beautifully integrated `flutter_local_notifications` foreground service to keep track of your upload progress.
- **On-Device Debugging**: View complete trace logs right inside the app via the settings drawer to diagnose network drops or OS permission bugs.

## How it works

1. **Scan**: Uses `photo_manager` to iterate through physical albums. 
2. **Hash & Queue**: Generates a fast fingerprint for each photo (preventing large file OOM during hashing) and adds them to a local SQLite database with `Pending` status.
3. **Chunk Upload**: The `ResumableUploadEngine` acquires a session URL and transmits raw binary chunks to Google.
4. **API Binding**: Triggers Google's `mediaItems.batchCreate` to append the file directly to the correct album.
5. **State Sync**: Updates the SQLite state to `Done`. If an unhandled network drop occurs, the state is rolled back to `Pending` for automatic retry on the next session.

## Configuration & Setup

1. Request an OAuth 2.0 Client ID for a **Web Application** (NOT Android) from Google Cloud Console.
2. Insert your Client ID in `google_auth_service.dart`.
3. Set your testing emails in the Google Cloud OAuth Consent Screen.
4. Build via `flutter build apk --release`.
