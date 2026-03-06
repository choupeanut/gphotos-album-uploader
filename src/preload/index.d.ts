import { ElectronAPI } from '@electron-toolkit/preload'

export interface AlbumData {
  folderName: string
  folderPath: string
  photos: string[]
  videos: string[]
  ignored: string[]
}

export interface ProgressEvent {
  type: 'album-start' | 'album-created' | 'photo-uploading' | 'photo-error' | 'batch-creating' | 'album-done' | 'album-error' | 'all-done'
  albumName?: string
  albumId?: string
  albumUrl?: string
  fileName?: string
  currentAlbumIndex?: number
  totalAlbums?: number
  currentPhotoIndex?: number
  totalPhotos?: number
  count?: number
  error?: string
}

declare global {
  interface Window {
    electron: ElectronAPI
    api: {
      getConfig: () => Promise<any>
      saveConfig: (config: any) => Promise<void>
      login: () => Promise<any>
      logout: () => Promise<void>
      checkAuth: () => Promise<boolean>
      selectDirectory: () => Promise<string | null>
      scanDirectory: (rootDir: string) => Promise<AlbumData[]>
      startUpload: (albums: AlbumData[]) => Promise<boolean>
      onUploadProgress: (callback: (value: ProgressEvent) => void) => void
      removeUploadListeners: () => void
    }
  }
}
