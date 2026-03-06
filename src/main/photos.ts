import fs from 'fs'
import path from 'path'
import { getAuthClient } from './auth'
import mime from 'mime-types'

const API_BASE_URL = 'https://photoslibrary.googleapis.com/v1'

export async function createAlbum(title: string): Promise<string> {
  const client = getAuthClient()
  const res = await client.request({
    url: `${API_BASE_URL}/albums`,
    method: 'POST',
    data: {
      album: {
        title: title
      }
    }
  })
  
  if (res.status !== 200) {
    throw new Error(`Failed to create album: ${res.statusText}`)
  }
  
  return (res.data as any).id
}

export async function uploadPhotoBytes(filePath: string): Promise<string> {
  const client = getAuthClient()
  const tokenRes = await client.getAccessToken()
  const token = tokenRes.token

  const fileName = path.basename(filePath)
  const mimeType = mime.lookup(filePath) || 'application/octet-stream'

  // Read the whole file into buffer, this avoids stream compatibility issues with different fetch implementations
  const fileBuffer = fs.readFileSync(filePath)

  const response = await fetch('https://photoslibrary.googleapis.com/v1/uploads', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/octet-stream',
      'X-Goog-Upload-Content-Type': mimeType,
      'X-Goog-Upload-Protocol': 'raw',
      'X-Goog-Upload-File-Name': fileName
    },
    body: fileBuffer
  })

  if (!response.ok) {
    throw new Error(`Failed to upload photo bytes: ${response.statusText}`)
  }
  
  return await response.text();
}

export async function batchCreateMediaItems(albumId: string, uploadTokens: { token: string; fileName: string }[]): Promise<any> {
  const client = getAuthClient()
  
  // Create max 50 items per request as per API limits
  const newMediaItems = uploadTokens.map(t => ({
    description: t.fileName,
    simpleMediaItem: {
      uploadToken: t.token
    }
  }))

  const res = await client.request({
    url: `${API_BASE_URL}/mediaItems:batchCreate`,
    method: 'POST',
    data: {
      albumId: albumId,
      newMediaItems: newMediaItems
    }
  })

  if (res.status !== 200) {
    throw new Error(`Failed to batch create media items: ${res.statusText}`)
  }

  return res.data
}
