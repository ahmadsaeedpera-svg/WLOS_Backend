import { useState } from 'react'
import {
  Alert, Box, Button, Paper, Stack, TextField, Typography,
} from '@mui/material'
import { useAuth } from '../auth/AuthContext'

export function SignIn() {
  const { signIn, loading } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function submit(event: React.FormEvent) {
    event.preventDefault()
    setError(null)
    try {
      await signIn(email, password)
    } catch (e) {
      // The API returns the same failure for an unknown account and a wrong
      // password on purpose. Repeating its message keeps the portal from
      // leaking which one it was.
      setError((e as Error).message)
    }
  }

  return (
    <Box sx={{
      minHeight: '100vh', display: 'grid', placeItems: 'center', p: 2,
    }}>
      <Paper variant="outlined" sx={{ p: 4, width: '100%', maxWidth: 380 }}>
        <form onSubmit={submit}>
          <Stack spacing={2.5}>
            <Box>
              <Typography variant="h5" sx={{ fontWeight: 600 }}>
                Maren Platform
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Sign in to manage content.
              </Typography>
            </Box>

            {error && <Alert severity="error">{error}</Alert>}

            <TextField
              label="Email" type="email" size="small" fullWidth required
              autoComplete="username"
              value={email} onChange={(e) => setEmail(e.target.value)}
            />
            <TextField
              label="Password" type="password" size="small" fullWidth required
              autoComplete="current-password"
              value={password} onChange={(e) => setPassword(e.target.value)}
            />
            <Button type="submit" variant="contained" disabled={loading}>
              {loading ? 'Signing in…' : 'Sign in'}
            </Button>
          </Stack>
        </form>
      </Paper>
    </Box>
  )
}
