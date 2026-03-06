import { app } from 'electron'
import path from 'path'
import fs from 'fs'

const storePath = path.join(app.getPath('userData'), 'config.json')

export function getConfig(): any {
  try {
    if (fs.existsSync(storePath)) {
      const data = fs.readFileSync(storePath, 'utf8')
      return JSON.parse(data)
    }
  } catch (error) {
    console.error('Error reading config:', error)
  }
  return {}
}

export function saveConfig(newConfig: any): void {
  try {
    const currentConfig = getConfig()
    const updatedConfig = { ...currentConfig, ...newConfig }
    fs.writeFileSync(storePath, JSON.stringify(updatedConfig, null, 2))
  } catch (error) {
    console.error('Error saving config:', error)
  }
}
