/**
 * Who is signed in and what they may do.
 *
 * Permissions are read from the access token's claims and used only to decide
 * what the UI offers. They are NOT the access control: the API re-checks every
 * permission in the MediatR pipeline, and a portal that hid a button would
 * still be defeated by anyone opening the network tab. Hiding a control the
 * caller cannot use is a courtesy, not a boundary.
 */
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import { request, tokens } from '../api/client'

interface Session {
  userId: string
  email: string
  displayName: string
  permissions: string[]
}

interface AuthState {
  session: Session | null
  signIn: (email: string, password: string) => Promise<void>
  signOut: () => void
  can: (permission: string) => boolean
  loading: boolean
}

const AuthContext = createContext<AuthState | null>(null)

interface AuthResponse {
  accessToken: string
  refreshToken: string
  userId: string
  email: string
  displayName: string
}

/**
 * Reads the claims out of a JWT payload without verifying it.
 *
 * Verification is the API's job and happens on every request. Decoding here
 * only decides which menu items to draw, so a forged token buys nothing —
 * the buttons it reveals all fail server-side.
 */
function claimsFrom(token: string): string[] {
  try {
    const payload = token.split('.')[1]
    if (!payload) return []

    const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'))
    const parsed = JSON.parse(json) as Record<string, unknown>
    const perm = parsed.perm

    if (Array.isArray(perm)) return perm.map(String)
    if (typeof perm === 'string') return [perm]
    return []
  } catch {
    return []
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(false)

  const signOut = useCallback(() => {
    tokens.set(null)
    setSession(null)
  }, [])

  useEffect(() => {
    // The client calls this when a request comes back 401, so an expired
    // session lands on the sign-in screen rather than an empty grid.
    tokens.onLost(() => setSession(null))
  }, [])

  const signIn = useCallback(async (email: string, password: string) => {
    setLoading(true)
    try {
      const result = await request<AuthResponse>('/api/v1/auth/login', {
        method: 'POST',
        body: { email, password },
      })

      tokens.set(result.accessToken)

      setSession({
        userId: result.userId,
        email: result.email,
        displayName: result.displayName,
        permissions: claimsFrom(result.accessToken),
      })
    } finally {
      setLoading(false)
    }
  }, [])

  const can = useCallback(
    (permission: string) => session?.permissions.includes(permission) ?? false,
    [session],
  )

  const value = useMemo(
    () => ({ session, signIn, signOut, can, loading }),
    [session, signIn, signOut, can, loading],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside an AuthProvider')
  return context
}

/** The permission codes the portal references. Mirrors PlatformPermissions. */
export const Permissions = {
  contentRead: 'content.read',
  contentWrite: 'content.write',
  contentPublish: 'content.publish',
  contentReview: 'content.review',
  contentDelete: 'content.delete',
  contentRestore: 'content.restore',
  flagsRead: 'flags.read',
  flagsWrite: 'flags.write',
  usersRead: 'users.read',
  usersWrite: 'users.write',
  rolesRead: 'roles.read',
  rolesWrite: 'roles.write',
  auditRead: 'audit.read',
} as const
