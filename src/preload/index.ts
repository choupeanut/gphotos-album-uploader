import { contextBridge, ipcRenderer } from 'electron'
import { electronAPI } from '@electron-toolkit/preload'

// Custom APIs for renderer
const api = {
  // Config & Auth
  getConfig: () => ipcRenderer.invoke('get-config'),
  saveConfig: (config) => ipcRenderer.invoke('save-config', config),
  login: () => ipcRenderer.invoke('login'),
  logout: () => ipcRenderer.invoke('logout'),
  checkAuth: () => ipcRenderer.invoke('check-auth'),
  
  // File System
  selectDirectory: () => ipcRenderer.invoke('select-directory'),
  scanDirectory: (rootDir) => ipcRenderer.invoke('scan-directory', rootDir),
  
  // Upload Process
  startUpload: (albums) => ipcRenderer.invoke('start-upload', albums),
  
  // Event Listeners
  onUploadProgress: (callback) => ipcRenderer.on('upload-progress', (_event, value) => callback(value)),
  removeUploadListeners: () => ipcRenderer.removeAllListeners('upload-progress')
}

// Use `contextBridge` APIs to expose Electron APIs to
// renderer only if context isolation is enabled, otherwise
// just add to the DOM global.
if (process.contextIsolated) {
  try {
    contextBridge.exposeInMainWorld('electron', electronAPI)
    contextBridge.exposeInMainWorld('api', api)
  } catch (error) {
    console.error(error)
  }
} else {
  // @ts-ignore (define in dts)
  window.electron = electronAPI
  // @ts-ignore (define in dts)
  window.api = api
}
