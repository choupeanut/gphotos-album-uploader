import { OAuth2Client } from 'google-auth-library'
import http from 'http'
import url from 'url'
import { shell } from 'electron'
import { getConfig, saveConfig } from './store'


let oAuth2Client: OAuth2Client | null = null

export function getAuthClient(): OAuth2Client {
  if (oAuth2Client) return oAuth2Client

  const config = getConfig()
  oAuth2Client = new OAuth2Client(
    config.clientId,
    config.clientSecret,
    'http://localhost:3001/oauth2callback'
  )

  if (config.tokens) {
    oAuth2Client.setCredentials(config.tokens)
  }

  return oAuth2Client
}

export function resetAuthClient(): void {
  oAuth2Client = null
}

export async function login(): Promise<any> {
  const config = getConfig()
  if (!config.clientId || !config.clientSecret) {
    throw new Error('Please save Client ID and Client Secret first.')
  }

  oAuth2Client = new OAuth2Client(
    config.clientId,
    config.clientSecret,
    'http://localhost:3001/oauth2callback'
  )

  return new Promise((resolve, reject) => {
    const server = http.createServer(async (req, res) => {
      try {
        if (req.url && req.url.startsWith('/oauth2callback')) {
          const qs = new url.URL(req.url, 'http://localhost:3001').searchParams
          const code = qs.get('code')
          res.end('Authentication successful! Please close this tab and return to the application.')
          server.closeAllConnections()
          server.close()
          
          if (code) {
            const { tokens } = await oAuth2Client!.getToken(code)
            oAuth2Client!.setCredentials(tokens)
            saveConfig({ tokens })
            resolve(tokens)
          } else {
            reject(new Error('No code found in callback'))
          }
        }
      } catch (e) {
        reject(e)
      }
    })

    server.on('error', (e) => reject(e));
    server.listen(3001, () => {
      const authorizeUrl = oAuth2Client!.generateAuthUrl({
        access_type: 'offline',
        scope: ['https://www.googleapis.com/auth/photoslibrary.appendonly', 'https://www.googleapis.com/auth/photoslibrary'],
        prompt: 'consent'
      })
      shell.openExternal(authorizeUrl)
    })
  })
}

export async function checkAuth(): Promise<boolean> {
  const config = getConfig()
  if (config.tokens) {
    try {
      const client = getAuthClient()
      const { token } = await client.getAccessToken()
      return !!token
    } catch (e) {
      return false
    }
  }
  return false
}

export function logout(): void {
  saveConfig({ tokens: null })
  resetAuthClient()
}