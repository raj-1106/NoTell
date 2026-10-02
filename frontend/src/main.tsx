import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { ErrorToastProvider } from './context/ErrorToastContext'
import { ErrorToastStack } from './components/ErrorToastStack'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ErrorToastProvider>
      <App />
      <ErrorToastStack />
    </ErrorToastProvider>
  </StrictMode>,
)
