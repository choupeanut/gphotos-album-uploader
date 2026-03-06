import { app, shell, BrowserWindow, ipcMain } from 'electron'
app.commandLine.appendSwitch('no-sandbox')
app.commandLine.appendSwitch('disable-gpu-sandbox')
import { join } from 'path'
import { electronApp, optimizer, is } from '@electron-toolkit/utils'
import icon from '../../resources/icon.png?asset'
import { getConfig, saveConfig } from './store'
import { login, logout, checkAuth } from './auth'
import { selectDirectory, scanDirectory, AlbumData } from './scanner'
import { createAlbum, uploadPhotoBytes, batchCreateMediaItems } from './photos'
import path from 'path'

// Delay utility for rate limiting
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))

let mainWindow: BrowserWindow | null = null

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 670,
    show: false,
    autoHideMenuBar: true,
    ...(process.platform === 'linux' ? { icon } : {}),
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false
    }
  })

  mainWindow.on('ready-to-show', () => {
    mainWindow?.show()
  })

  mainWindow.webContents.setWindowOpenHandler((details) => {
    shell.openExternal(details.url)
    return { action: 'deny' }
  })

  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    mainWindow.loadURL(process.env['ELECTRON_RENDERER_URL'])
  } else {
    mainWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

app.commandLine.appendSwitch('no-sandbox');
app.whenReady().then(() => {
  electronApp.setAppUserModelId('com.electron')
  app.on('browser-window-created', (_, window) => {
    optimizer.watchWindowShortcuts(window)
  })

  // Register IPC Handlers
  ipcMain.handle('get-config', () => getConfig())
  ipcMain.handle('save-config', (_, config) => saveConfig(config))
  ipcMain.handle('login', async () => await login())
  ipcMain.handle('logout', () => logout())
  ipcMain.handle('check-auth', async () => await checkAuth())
  ipcMain.handle('select-directory', async () => await selectDirectory())
  ipcMain.handle('scan-directory', (_, rootDir) => scanDirectory(rootDir))

  // The main upload orchestration
  ipcMain.handle('start-upload', async (event, albums: AlbumData[]) => {
    for (let i = 0; i < albums.length; i++) {
      const album = albums[i]
      try {
        event.sender.send('upload-progress', { type: 'album-start', albumName: album.folderName, currentAlbumIndex: i + 1, totalAlbums: albums.length })
        
        // 1. Create Album
        const albumId = await createAlbum(album.folderName)
        event.sender.send('upload-progress', { type: 'album-created', albumName: album.folderName, albumId, albumUrl: `https://photos.google.com/lr/album/${albumId}` })
        
        // 2. Upload Photos sequentially to get tokens
        const uploadTokens: { token: string; fileName: string }[] = []
        for (let j = 0; j < album.photos.length; j++) {
          const photoPath = album.photos[j]
          const fileName = path.basename(photoPath)
          try {
            event.sender.send('upload-progress', { type: 'photo-uploading', fileName, currentPhotoIndex: j + 1, totalPhotos: album.photos.length })
            const token = await uploadPhotoBytes(photoPath)
            uploadTokens.push({ token, fileName })
            
            // Add a small delay to avoid hammering Google APIs
            await delay(500)
          } catch (err: any) {
            event.sender.send('upload-progress', { type: 'photo-error', fileName, error: err.message })
          }
        }

        // 3. Batch Create Media Items (Google limits to 50 items per request)
        if (uploadTokens.length > 0) {
          event.sender.send('upload-progress', { type: 'batch-creating', count: uploadTokens.length })
          
          const BATCH_SIZE = 50
          for (let k = 0; k < uploadTokens.length; k += BATCH_SIZE) {
            const batch = uploadTokens.slice(k, k + BATCH_SIZE)
            await batchCreateMediaItems(albumId, batch);
            await delay(1000) // Delay between batches
          }
        }
        
        event.sender.send('upload-progress', { type: 'album-done', albumName: album.folderName })
      } catch (err: any) {
        event.sender.send('upload-progress', { type: 'album-error', albumName: album.folderName, error: err.message })
      }
    }
    event.sender.send('upload-progress', { type: 'all-done' })
    return true
  })

  createWindow()

  app.on('activate', function () {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit()
  }
})
