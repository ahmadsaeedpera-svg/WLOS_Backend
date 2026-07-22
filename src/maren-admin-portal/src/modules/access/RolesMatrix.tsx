import { useEffect, useState } from 'react'
import {
  Alert, Box, Button, Checkbox, Chip, Paper, Snackbar, Stack, Table, TableBody,
  TableCell, TableContainer, TableHead, TableRow, Tooltip, Typography,
} from '@mui/material'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ApiError } from '../../api/client'
import { accessApi } from '../../api/access'
import { Permissions, useAuth } from '../../auth/AuthContext'

export function RolesMatrix() {
  const queryClient = useQueryClient()
  const { can, session } = useAuth()

  const [toast, setToast] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [draft, setDraft] = useState<Record<number, Set<string>>>({})

  const roles = useQuery({ queryKey: ['roles'], queryFn: accessApi.listRoles })
  const permissions = useQuery({
    queryKey: ['permissions'],
    queryFn: accessApi.listPermissions,
  })

  useEffect(() => {
    if (!roles.data) return
    const next: Record<number, Set<string>> = {}
    for (const role of roles.data) next[role.roleId] = new Set(role.permissionCodes)
    setDraft(next)
  }, [roles.data])

  const save = useMutation({
    mutationFn: ({ roleId, codes }: { roleId: number; codes: string[] }) =>
      accessApi.setRolePermissions(roleId, codes),
    onSuccess: () => {
      setError(null)
      setToast('Permissions saved — affected users are signed out')
      queryClient.invalidateQueries({ queryKey: ['roles'] })
    },
    // A refusal here names exactly which permissions the caller lacks. That is
    // worth showing verbatim.
    onError: (e: ApiError) => setError(e.message),
  })

  const writable = can(Permissions.rolesWrite)
  const held = new Set(session?.permissions ?? [])

  if (roles.isLoading || permissions.isLoading)
    return <Typography>Loading…</Typography>

  const byCategory = new Map<string, typeof permissions.data>()
  for (const p of permissions.data ?? []) {
    const list = byCategory.get(p.category) ?? []
    list.push(p)
    byCategory.set(p.category, list)
  }

  function toggle(roleId: number, code: string) {
    setDraft((d) => {
      const next = { ...d }
      const set = new Set(next[roleId] ?? [])
      if (set.has(code)) set.delete(code)
      else set.add(code)
      next[roleId] = set
      return next
    })
  }

  function dirty(roleId: number) {
    const role = roles.data?.find((r) => r.roleId === roleId)
    if (!role) return false
    const current = new Set(role.permissionCodes)
    const next = draft[roleId] ?? new Set()
    if (current.size !== next.size) return true
    for (const c of next) if (!current.has(c)) return true
    return false
  }

  return (
    <Stack spacing={2}>
      <Typography variant="h5" sx={{ fontWeight: 600 }}>
        Roles &amp; permissions
      </Typography>

      {/* Both consequences an operator needs before they start ticking boxes. */}
      <Alert severity="info">
        Changing a role signs out everyone holding it, so they pick up the new
        permissions. You can only grant permissions you hold yourself.
      </Alert>

      {!writable ? (
        <Alert severity="warning">
          You can see this matrix but not change it. That needs roles.write.
        </Alert>
      ) : null}

      {error ? (
        <Alert severity="warning" onClose={() => setError(null)}>
          {error}
        </Alert>
      ) : null}

      <TableContainer component={Paper} variant="outlined" sx={{ overflowX: 'auto' }}>
        <Table size="small" stickyHeader>
          <TableHead>
            <TableRow>
              <TableCell sx={{ minWidth: 260 }}>Permission</TableCell>
              {(roles.data ?? []).map((role) => (
                <TableCell key={role.roleId} align="center" sx={{ minWidth: 120 }}>
                  <Stack spacing={0.5} sx={{ alignItems: 'center' }}>
                    <Typography variant="body2" sx={{ fontWeight: 600 }}>
                      {role.name}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {role.memberCount} member{role.memberCount === 1 ? '' : 's'}
                    </Typography>
                    {role.isSystem ? (
                      <Chip size="small" variant="outlined" label="Built-in" />
                    ) : null}
                  </Stack>
                </TableCell>
              ))}
            </TableRow>
          </TableHead>

          <TableBody>
            {[...byCategory.entries()].map(([category, perms]) => (
              <>
                <TableRow key={category}>
                  <TableCell
                    colSpan={(roles.data?.length ?? 0) + 1}
                    sx={{ bgcolor: 'action.hover' }}
                  >
                    <Typography variant="caption" sx={{ fontWeight: 700 }}>
                      {category.toUpperCase()}
                    </Typography>
                  </TableCell>
                </TableRow>

                {(perms ?? []).map((permission) => (
                  <TableRow key={permission.code} hover>
                    <TableCell>
                      <Typography variant="body2">{permission.code}</Typography>
                      {permission.description ? (
                        <Typography variant="caption" color="text.secondary">
                          {permission.description}
                        </Typography>
                      ) : null}
                    </TableCell>

                    {(roles.data ?? []).map((role) => {
                      // A permission the operator does not hold cannot be
                      // granted, so the box is disabled rather than allowed to
                      // fail on save.
                      const canGrantThis = held.has(permission.code)
                      return (
                        <TableCell key={role.roleId} align="center" padding="checkbox">
                          <Tooltip
                            title={
                              canGrantThis
                                ? ''
                                : 'You do not hold this permission, so you cannot grant it.'
                            }
                          >
                            <Box component="span">
                              <Checkbox
                                size="small"
                                checked={draft[role.roleId]?.has(permission.code) ?? false}
                                disabled={!writable || !canGrantThis || save.isPending}
                                onChange={() => toggle(role.roleId, permission.code)}
                              />
                            </Box>
                          </Tooltip>
                        </TableCell>
                      )
                    })}
                  </TableRow>
                ))}
              </>
            ))}

            {writable ? (
              <TableRow>
                <TableCell />
                {(roles.data ?? []).map((role) => (
                  <TableCell key={role.roleId} align="center">
                    <Button
                      size="small"
                      variant="contained"
                      disabled={!dirty(role.roleId) || save.isPending}
                      onClick={() =>
                        save.mutate({
                          roleId: role.roleId,
                          codes: [...(draft[role.roleId] ?? [])],
                        })
                      }
                    >
                      Save
                    </Button>
                  </TableCell>
                ))}
              </TableRow>
            ) : null}
          </TableBody>
        </Table>
      </TableContainer>

      <Snackbar
        open={!!toast}
        autoHideDuration={4000}
        onClose={() => setToast(null)}
        message={toast}
      />
    </Stack>
  )
}
