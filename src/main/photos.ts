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
  const stat = fs.statSync(filePath)
  const fileSize = stat.size

  // 1. Initiate Resumable Upload Session
  const initResponse = await fetch('https://photoslibrary.googleapis.com/v1/uploads', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Length': '0',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Content-Type': mimeType,
      'X-Goog-Upload-File-Name': fileName,
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Raw-Size': fileSize.toString()
    }
  })

  if (!initResponse.ok) {
    const errorText = await initResponse.text()
    throw new Error(`Failed to initiate resumable upload: ${initResponse.statusText} - ${errorText}`)
  }

  const sessionUrl = initResponse.headers.get('x-goog-upload-url')
  if (!sessionUrl) {
    throw new Error('Upload session URL not returned from Google Photos API')
  }

  // 2. Upload in Chunks
  // Chunk size must be a multiple of 256 KB (262144 bytes). Here we use 8 * 256 KB = 2 MB
  const chunkSize = 262144 * 8
  let offset = 0
  let uploadToken = ''

  const fd = fs.openSync(filePath, 'r')

  try {
    while (offset < fileSize) {
      const end = Math.min(offset + chunkSize, fileSize)
      const length = end - offset
      const isLastChunk = end === fileSize
      const chunkBuffer = Buffer.alloc(length)

      fs.readSync(fd, chunkBuffer, 0, length, offset)

      const uploadResponse = await fetch(sessionUrl, {
        method: 'POST',
        headers: {
          'Content-Length': length.toString(),
          'X-Goog-Upload-Command': isLastChunk ? 'upload, finalize' : 'upload',
          'X-Goog-Upload-Offset': offset.toString()
        },
        body: chunkBuffer
      })

      if (!uploadResponse.ok) {
        const errorText = await uploadResponse.text()
        throw new Error(`Failed to upload chunk at offset ${offset}: ${uploadResponse.statusText} - ${errorText}`)
      }

      if (isLastChunk) {
        uploadToken = await uploadResponse.text()
      }

      offset = end
    }
  } finally {
    fs.closeSync(fd)
  }

  return uploadToken;
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
