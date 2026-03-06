import React, { useState, useEffect } from 'react'
import Setup from './components/Setup'
import Dashboard from './components/Dashboard'

function App(): React.JSX.Element {
  const [configChecked, setConfigChecked] = useState(false)
  const [hasConfig, setHasConfig] = useState(false)

  useEffect(() => {
    checkConfig()
  }, [])

  const checkConfig = async (): Promise<void> => {
    const config = await window.api.getConfig()
    setHasConfig(!!(config && config.clientId && config.clientSecret))
    setConfigChecked(true)
  }

  if (!configChecked) {
    return <div className="flex items-center justify-center min-h-screen">Loading...</div>
  }

  if (!hasConfig) {
    return <Setup onComplete={checkConfig} />
  }

  return <Dashboard />
}

export default App
