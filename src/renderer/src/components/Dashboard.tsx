import React, { useState, useEffect } from 'react'
import { AlbumData, ProgressEvent } from '../../../preload/index.d'

export default function Dashboard(): React.JSX.Element {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false)
  const [loadingAuth, setLoadingAuth] = useState(true)
  
  const [selectedDir, setSelectedDir] = useState<string | null>(null)
  const [albums, setAlbums] = useState<(AlbumData & { albumUrl?: string })[]>([])
  
  const [isUploading, setIsUploading] = useState(false)
  const [logs, setLogs] = useState<string[]>([])
  const [progress, setProgress] = useState<{
    currentAlbum?: string
    albumProgress?: string
    photoProgress?: string
    albumUrl?: string
  }>({})

  useEffect(() => {
    checkAuthStatus()
    return () => {
      window.api.removeUploadListeners()
    }
  }, [])

  const checkAuthStatus = async (): Promise<void> => {
    const status = await window.api.checkAuth()
    setIsAuthenticated(status)
    setLoadingAuth(false)
  }

  const handleLogin = async (): Promise<void> => {
    try {
      await window.api.login()
      await checkAuthStatus()
    } catch (err: any) {
      alert(`Login failed: ${err.message}`)
    }
  }

  const handleLogout = async (): Promise<void> => {
    await window.api.logout()
    setIsAuthenticated(false)
    setAlbums([])
    setSelectedDir(null)
  }

  const handleSelectDirectory = async (): Promise<void> => {
    const dir = await window.api.selectDirectory()
    if (dir) {
      setSelectedDir(dir)
      const scannedAlbums = await window.api.scanDirectory(dir)
      setAlbums(scannedAlbums)
    }
  }

  const handleStartUpload = async (): Promise<void> => {
    if (albums.length === 0) return
    setIsUploading(true)
    setLogs([])
    setProgress({})

    window.api.onUploadProgress((event: ProgressEvent) => {
      if (event.type === 'album-start') {
        setProgress(prev => ({ ...prev, currentAlbum: event.albumName, albumProgress: `${event.currentAlbumIndex} / ${event.totalAlbums}` }))
        addLog(`Started album: ${event.albumName}`)
      } else if (event.type === 'album-created') {
        addLog(`Created Google Photos album: ${event.albumName}`);
        setProgress(prev => ({ ...prev, albumUrl: event.albumUrl }));
        setAlbums(prev => prev.map(a => a.folderName === event.albumName ? { ...a, albumUrl: event.albumUrl } : a));
      } else if (event.type === 'photo-uploading') {
        setProgress(prev => ({ ...prev, photoProgress: `${event.currentPhotoIndex} / ${event.totalPhotos}` }))
      } else if (event.type === 'photo-error') {
        addLog(`Error uploading ${event.fileName}: ${event.error}`)
      } else if (event.type === 'batch-creating') {
        addLog(`Batch creating ${event.count} media items...`)
      } else if (event.type === 'album-done') {
        addLog(`Finished album: ${event.albumName}`)
      } else if (event.type === 'album-error') {
        addLog(`Error on album ${event.albumName}: ${event.error}`)
      } else if (event.type === 'all-done') {
        addLog(`All uploads completed!`)
        setIsUploading(false)
      }
    })

    await window.api.startUpload(albums)
  }

  const addLog = (msg: string): void => {
    setLogs(prev => [...prev, `${new Date().toLocaleTimeString()} - ${msg}`])
  }

  if (loadingAuth) {
    return <div className="flex items-center justify-center min-h-screen">Loading...</div>
  }

  if (!isAuthenticated) {
    return (
      <div className="flex flex-col items-center justify-center min-h-screen bg-gray-100">
        <h2 className="mb-4 text-2xl font-bold">Google Photos Uploader</h2>
        <button
          onClick={handleLogin}
          className="px-6 py-3 font-bold text-white bg-blue-600 rounded shadow hover:bg-blue-700"
        >
          Login with Google
        </button>
      </div>
    )
  }

  return (
    <div className="p-8 mx-auto max-w-5xl">
      <div className="flex items-center justify-between pb-4 mb-6 border-b">
        <h1 className="text-2xl font-bold text-gray-800">Uploader Dashboard</h1>
        <button
          onClick={handleLogout}
          className="px-4 py-2 text-sm text-red-600 bg-red-100 rounded hover:bg-red-200"
          disabled={isUploading}
        >
          Logout
        </button>
      </div>

      <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
        {/* Left Panel: Selection */}
        <div className="p-6 bg-white rounded-lg shadow">
          <h2 className="mb-4 text-xl font-semibold">1. Select Directory</h2>
          <button
            onClick={handleSelectDirectory}
            disabled={isUploading}
            className="w-full px-4 py-2 mb-4 text-white bg-gray-800 rounded hover:bg-gray-700 disabled:opacity-50"
          >
            Choose Root Folder
          </button>
          
          {selectedDir && (
            <div className="mb-4 text-sm text-gray-600 truncate">
              <strong>Selected:</strong> {selectedDir}
            </div>
          )}

          <div className="mt-4">
            <h3 className="mb-2 font-medium">Found Albums ({albums.length})</h3>
            <ul className="overflow-y-auto max-h-64">
              {albums.map((album, idx) => (
                <li key={idx} className="flex justify-between p-2 mb-1 bg-gray-50 rounded">
                  <div className="flex flex-col">
                    <span className="font-medium truncate">{album.folderName}</span>
                    {album.albumUrl && (
                      <a href={album.albumUrl} target="_blank" rel="noreferrer" className="text-xs text-blue-500 hover:underline">
                        Open in Google Photos
                      </a>
                    )}
                  </div>
                  <div className="flex gap-2 text-xs text-gray-500">
                    <span title="Photos">📷 {album.photos?.length || 0}</span>
                    <span title="Videos">🎥 {album.videos?.length || 0}</span>
                    <span title="Ignored" className="text-red-400">⚠️ {album.ignored?.length || 0}</span>
                  </div>
                </li>
              ))}
              {albums.length === 0 && selectedDir && (
                <li className="text-sm text-gray-500">No valid albums or images found.</li>
              )}
            </ul>
          </div>
        </div>

        {/* Right Panel: Progress */}
        <div className="p-6 bg-white rounded-lg shadow">
          <h2 className="mb-4 text-xl font-semibold">2. Upload Status</h2>
          
          <button
            onClick={handleStartUpload}
            disabled={albums.length === 0 || isUploading}
            className="w-full px-4 py-3 mb-6 font-bold text-white bg-green-600 rounded hover:bg-green-700 disabled:opacity-50"
          >
            {isUploading ? 'Uploading...' : 'Start Upload'}
          </button>

          {isUploading && (
            <div className="p-4 mb-4 bg-blue-50 rounded">
              <div className="mb-2"><strong>Album:</strong> {progress.currentAlbum || '-'}</div>
              <div className="mb-2"><strong>Albums Progress:</strong> {progress.albumProgress || '-'}</div>
              <div><strong>Photos in Album:</strong> {progress.photoProgress || '-'}</div>
              {progress.albumUrl && (
                <div className="mt-2">
                  <a href={progress.albumUrl} target="_blank" rel="noreferrer" className="text-sm text-blue-600 underline">
                    Open Album in Browser
                  </a>
                </div>
              )}
            </div>
          )}

          <div className="mt-4">
            <h3 className="mb-2 font-medium">Logs</h3>
            <div className="p-2 overflow-y-auto text-xs font-mono text-gray-700 bg-gray-100 rounded h-48">
              {logs.map((log, idx) => (
                <div key={idx} className="mb-1">{log}</div>
              ))}
              {logs.length === 0 && <span className="text-gray-400">Waiting to start...</span>}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
