import { CssBaseline, ThemeProvider, createTheme } from '@mui/material'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, useAuth } from './auth/AuthContext'
import { Shell } from './components/Shell'
import { SignIn } from './modules/SignIn'
import { ContentList } from './modules/content/ContentList'
import { ContentEditor } from './modules/content/ContentEditor'
import { FeatureFlags } from './modules/flags/FeatureFlags'

const theme = createTheme({
  palette: {
    primary: { main: '#8E2C55' },
    background: { default: '#FAFAFB' },
  },
  shape: { borderRadius: 8 },
  typography: {
    fontFamily: '"Inter", system-ui, -apple-system, "Segoe UI", sans-serif',
  },
})

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // A 401 or 403 will not become a 200 on the third attempt, and retrying
      // a denial three times triples the noise in the audit log.
      retry: (failureCount, error) => {
        const status = (error as { status?: number }).status
        if (status === 401 || status === 403 || status === 400) return false
        return failureCount < 2
      },
      staleTime: 30_000,
    },
  },
})

function Routed() {
  const { session } = useAuth()

  if (!session) return <SignIn />

  return (
    <Shell>
      <Routes>
        <Route path="/content" element={<ContentList />} />
        <Route path="/content/:id" element={<ContentEditor />} />
        <Route path="/flags" element={<FeatureFlags />} />
        <Route path="*" element={<Navigate to="/content" replace />} />
      </Routes>
    </Shell>
  )
}

export default function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <BrowserRouter>
            <Routed />
          </BrowserRouter>
        </AuthProvider>
      </QueryClientProvider>
    </ThemeProvider>
  )
}
