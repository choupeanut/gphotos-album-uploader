import fs from 'fs'
import path from 'path'
import { dialog } from 'electron'

const imageExtensions = new Set(['.jpg', '.jpeg', '.png', '.heic'])
const videoExtensions = new Set(['.mp4', '.mov', '.mkv', '.avi', '.3gp', '.m4v', '.mts', '.webm'])

export interface AlbumData {
  folderName: string
  folderPath: string
  photos: string[]
  videos: string[]
  ignored: string[]
}

export async function selectDirectory(): Promise<string | null> {
  const result = await dialog.showOpenDialog({
    properties: ['openDirectory']
  })
  
  if (result.canceled || result.filePaths.length === 0) {
    return null
  }
  return result.filePaths[0]
}

export function scanDirectory(rootDir: string): AlbumData[] {
  const albums: AlbumData[] = []
  
  if (!fs.existsSync(rootDir)) {
    throw new Error(`Directory not found: ${rootDir}`)
  }

  const items = fs.readdirSync(rootDir, { withFileTypes: true })
  
  for (const item of items) {
    if (item.isDirectory()) {
      const folderPath = path.join(rootDir, item.name)
      const folderName = unescapeHtml(item.name)
      const photos: string[] = []
      const videos: string[] = []
      const ignored: string[] = []
      
      try {
        const subItems = fs.readdirSync(folderPath, { withFileTypes: true })
        for (const subItem of subItems) {
          if (subItem.isFile()) {
            const ext = path.extname(subItem.name).toLowerCase()
            if (imageExtensions.has(ext)) {
              photos.push(path.join(folderPath, subItem.name))
            } else if (videoExtensions.has(ext)) {
              videos.push(path.join(folderPath, subItem.name))
            } else {
              ignored.push(path.join(folderPath, subItem.name))
              const logMsg = `Ignored unsupported file: ${path.join(folderPath, subItem.name)}\n`;
              fs.appendFileSync(path.join(rootDir, 'ignored_files.log'), logMsg);
            }
          }
        }
        
        if (photos.length > 0 || videos.length > 0) {
          albums.push({
            folderName,
            folderPath,
            photos,
            videos,
            ignored
          })
        }
      } catch (err) {
        console.error(`Error reading directory ${folderPath}:`, err)
      }
    }
  }
  
  return albums
}


function unescapeHtml(safe: string): string {
  return safe
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'");
}
