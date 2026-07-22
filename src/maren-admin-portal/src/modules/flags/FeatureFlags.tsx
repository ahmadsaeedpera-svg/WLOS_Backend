import { useState } from 'react'
import {
  Alert, Chip, Paper, Slider, Snackbar, Stack, Switch, Typography,
} from '@mui/material'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ApiError, request } from '../../api/client'
import { Permissions, useAuth } from '../../auth/AuthContext'

interface FeatureFlag {
  featureFlagId: number
  key: string
  name: string
  description: string | null
  isEnabled: boolean
  rolloutPercent: number
  minAppVersion: string | null
  countryFilter: string | null
  requiresPremium: boolean
  betaOnly: boolean
  defaultValue: boolean
  modifiedUtc: string
}

export function FeatureFlags() {
  const { can } = useAuth()
  const queryClient = useQueryClient()
  const [toast, setToast] = useState<string | null>(null)

  const flags = useQuery({
    queryKey: ['flags'],
    queryFn: () => request<FeatureFlag[]>('/api/v1/admin/flags'),
  })

  const save = useMutation({
    // The endpoint is a full upsert, so a partial body would blank every field
    // it omits. Spread the flag as it stands and change only what was touched.
    mutationFn: (flag: FeatureFlag) =>
      request<FeatureFlag>('/api/v1/admin/flags', {
        method: 'PUT',
        body: {
          key: flag.key,
          name: flag.name,
          description: flag.description,
          isEnabled: flag.isEnabled,
          rolloutPercent: flag.rolloutPercent,
          minAppVersion: flag.minAppVersion,
          countryFilter: flag.countryFilter,
          requiresPremium: flag.requiresPremium,
          betaOnly: flag.betaOnly,
          defaultValue: flag.defaultValue,
        },
      }),
    onSuccess: (_, flag) => {
      queryClient.invalidateQueries({ queryKey: ['flags'] })
      setToast(`${flag.name} is now ${flag.isEnabled ? 'on' : 'off'}`)
    },
    onError: (error: ApiError) => setToast(error.message),
  })

  const writable = can(Permissions.flagsWrite)

  return (
    <Stack spacing={2} sx={{ maxWidth: 820 }}>
      <Typography variant="h5" sx={{ fontWeight: 600 }}>
        Feature flags
      </Typography>

      {/* The evaluator caches for 30 seconds, so a switch flipped here is not
          instantaneous. Saying so stops an operator flipping it repeatedly
          during an incident because "nothing happened". */}
      <Alert severity="info">
        Changes reach the API within about 30 seconds. Turning a flag off
        overrides its rollout percentage for everyone.
      </Alert>

      {!writable ? (
        <Alert severity="warning">
          You can see these but not change them. That needs the flags.write
          permission.
        </Alert>
      ) : null}

      {flags.isError ? (
        <Alert severity="error">{(flags.error as Error).message}</Alert>
      ) : null}

      <Stack spacing={1}>
        {(flags.data ?? []).map((flag) => (
          <Paper key={flag.key} variant="outlined" sx={{ p: 2 }}>
            <Stack direction="row" spacing={2} sx={{ alignItems: 'flex-start' }}>
              <Stack sx={{ flex: 1, minWidth: 0 }}>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {flag.name}
                </Typography>
                <Typography variant="caption" color="text.secondary">
                  {flag.key}
                </Typography>
                {flag.description ? (
                  <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                    {flag.description}
                  </Typography>
                ) : null}

                {flag.isEnabled && flag.rolloutPercent < 100 ? (
                  <Stack sx={{ mt: 1.5, maxWidth: 320 }}>
                    <Typography variant="caption" color="text.secondary">
                      Rollout: {flag.rolloutPercent}% of users
                    </Typography>
                    <Slider
                      size="small"
                      value={flag.rolloutPercent}
                      disabled={!writable || save.isPending}
                      valueLabelDisplay="auto"
                      onChangeCommitted={(_, value) =>
                        save.mutate({ ...flag, rolloutPercent: value as number })
                      }
                    />
                  </Stack>
                ) : null}

                <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
                  {flag.betaOnly ? (
                    <Chip size="small" variant="outlined" label="Beta only" />
                  ) : null}
                  {flag.requiresPremium ? (
                    <Chip size="small" variant="outlined" label="Premium" />
                  ) : null}
                  {flag.countryFilter ? (
                    <Chip size="small" variant="outlined" label={flag.countryFilter} />
                  ) : null}
                  {flag.minAppVersion ? (
                    <Chip size="small" variant="outlined" label={`>= ${flag.minAppVersion}`} />
                  ) : null}
                </Stack>
              </Stack>

              <Switch
                checked={flag.isEnabled}
                disabled={!writable || save.isPending}
                onChange={(e) =>
                  save.mutate({ ...flag, isEnabled: e.target.checked })
                }
              />
            </Stack>
          </Paper>
        ))}
      </Stack>

      <Snackbar
        open={!!toast}
        autoHideDuration={3000}
        onClose={() => setToast(null)}
        message={toast}
      />
    </Stack>
  )
}
