/**
 * The single place the portal talks to the API.
 *
 * Everything goes through `request` so that token refresh, the response
 * envelope and error shaping exist once. A component that calls `fetch`
 * directly bypasses all three, and the failure shows up as an unexplained
 * logout for whoever is using it.
 */

const BASE = import.meta.env.VITE_API_BASE ?? ''

/** The envelope every endpoint returns, success or failure. */
export interface ApiResponse<T> {
  succeeded: boolean
  data: T | null
  failureCode: string | null
  message: string | null
  validationErrors: Record<string, string[]> | null
}

/**
 * A failed request, carrying enough for a form to highlight its own fields.
 */
export class ApiError extends Error {
  // Declared and assigned rather than using constructor parameter properties:
  // the project builds with erasableSyntaxOnly, which forbids syntax that
  // emits runtime code from a type-position annotation.
  readonly status: number
  readonly failureCode: string | null
  readonly validationErrors: Record<string, string[]> | null

  constructor(
    status: number,
    failureCode: string | null,
    message: string,
    validationErrors: Record<string, string[]> | null = null,
  ) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.failureCode = failureCode
    this.validationErrors = validationErrors
  }

  /** True when somebody else saved first and the caller's copy is stale. */
  get isConflict() {
    return this.failureCode === 'VERSION_CONFLICT'
  }

  get isForbidden() {
    return this.status === 403
  }
}

// ---------------------------------------------------------------------------
// Tokens
// ---------------------------------------------------------------------------

/*  In memory, not localStorage.
 *
 *  A token in localStorage is readable by any script that manages to run on
 *  the page, and this portal can publish content to every user of the app. The
 *  cost is that a refresh signs the operator out; the refresh token in a
 *  sameSite cookie is the proper fix and needs an API change, so for now the
 *  session lives as long as the tab.
 */
let accessToken: string | null = null
let onUnauthenticated: (() => void) | null = null

export const tokens = {
  set(token: string | null) {
    accessToken = token
  },
  get() {
    return accessToken
  },
  onLost(handler: () => void) {
    onUnauthenticated = handler
  },
}

// ---------------------------------------------------------------------------

interface RequestOptions {
  method?: string
  body?: unknown
  /** Sent as If-Match for optimistic concurrency on a save. */
  ifMatch?: number | null
  signal?: AbortSignal
}

export async function request<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  }

  if (accessToken) headers.Authorization = `Bearer ${accessToken}`
  if (options.ifMatch != null) headers['If-Match'] = `"${options.ifMatch}"`

  const response = await fetch(`${BASE}${path}`, {
    method: options.method ?? 'GET',
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
    signal: options.signal,
  })

  if (response.status === 401) {
    // The session is gone. Surface it once rather than letting every pending
    // query render its own error.
    tokens.set(null)
    onUnauthenticated?.()
    throw new ApiError(401, 'UNAUTHENTICATED', 'Your session has ended. Sign in again.')
  }

  if (response.status === 304) {
    throw new ApiError(304, 'NOT_MODIFIED', 'Not modified.')
  }

  let envelope: ApiResponse<T> | null = null
  try {
    envelope = (await response.json()) as ApiResponse<T>
  } catch {
    // A body that is not JSON means something upstream failed — a proxy, a
    // gateway timeout. Report the status rather than a parse error.
    throw new ApiError(
      response.status,
      null,
      `The server returned an unexpected response (${response.status}).`,
    )
  }

  if (!response.ok || !envelope.succeeded) {
    throw new ApiError(
      response.status,
      envelope.failureCode,
      envelope.message ?? 'The request could not be completed.',
      envelope.validationErrors,
    )
  }

  return envelope.data as T
}

/**
 * A search that also needs the paging headers.
 *
 * The body carries the same totals, but reading them from headers means a
 * caller can show "page 3 of 12" without depending on the payload shape.
 */
export async function requestPaged<T>(path: string): Promise<{
  data: T
  totalCount: number
  totalPages: number
}> {
  const headers: Record<string, string> = {}
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`

  const response = await fetch(`${BASE}${path}`, { headers })

  if (response.status === 401) {
    tokens.set(null)
    onUnauthenticated?.()
    throw new ApiError(401, 'UNAUTHENTICATED', 'Your session has ended. Sign in again.')
  }

  const envelope = (await response.json()) as ApiResponse<T>

  if (!response.ok || !envelope.succeeded) {
    throw new ApiError(
      response.status,
      envelope.failureCode,
      envelope.message ?? 'The request could not be completed.',
      envelope.validationErrors,
    )
  }

  return {
    data: envelope.data as T,
    totalCount: Number(response.headers.get('X-Total-Count') ?? 0),
    totalPages: Number(response.headers.get('X-Total-Pages') ?? 0),
  }
}
