import React, { useState } from 'react'

interface SetupProps {
  onComplete: () => void
}

export default function Setup({ onComplete }: SetupProps): React.JSX.Element {
  const [clientId, setClientId] = useState('')
  const [clientSecret, setClientSecret] = useState('')
  const [saving, setSaving] = useState(false)

  const handleSave = async (): Promise<void> => {
    if (!clientId || !clientSecret) {
      alert('Please fill in both fields')
      return
    }
    setSaving(true)
    await window.api.saveConfig({ clientId, clientSecret })
    setSaving(false)
    onComplete()
  }

  return (
    <div className="flex items-center justify-center min-h-screen bg-gray-100">
      <div className="w-full max-w-md p-8 bg-white rounded-lg shadow-md">
        <h2 className="mb-6 text-2xl font-bold text-center text-gray-800">API Configuration</h2>
        <p className="mb-4 text-sm text-gray-600">
          To use this application, you need to provide your Google OAuth Client ID and Secret configured for Desktop Apps.
        </p>
        
        <div className="mb-4">
          <label className="block mb-2 text-sm font-medium text-gray-700" htmlFor="clientId">
            Client ID
          </label>
          <input
            className="w-full px-3 py-2 leading-tight text-gray-700 border rounded shadow appearance-none focus:outline-none focus:shadow-outline"
            id="clientId"
            type="text"
            placeholder="Enter Client ID"
            value={clientId}
            onChange={(e) => setClientId(e.target.value)}
          />
        </div>
        
        <div className="mb-6">
          <label className="block mb-2 text-sm font-medium text-gray-700" htmlFor="clientSecret">
            Client Secret
          </label>
          <input
            className="w-full px-3 py-2 mb-3 leading-tight text-gray-700 border rounded shadow appearance-none focus:outline-none focus:shadow-outline"
            id="clientSecret"
            type="password"
            placeholder="Enter Client Secret"
            value={clientSecret}
            onChange={(e) => setClientSecret(e.target.value)}
          />
        </div>
        
        <div className="flex items-center justify-between">
          <button
            className="w-full px-4 py-2 font-bold text-white bg-blue-500 rounded hover:bg-blue-700 focus:outline-none focus:shadow-outline disabled:opacity-50"
            type="button"
            onClick={handleSave}
            disabled={saving}
          >
            {saving ? 'Saving...' : 'Save Configuration'}
          </button>
        </div>
      </div>
    </div>
  )
}
