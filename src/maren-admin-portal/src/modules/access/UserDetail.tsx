import { useState } from 'react'
import {
  Alert, Autocomplete, Button, Chip, Dialog, DialogActions, DialogContent,
  DialogContentText, DialogTitle, Divider, IconButton, List, ListItem,
  ListItemText, Paper, Snackbar, Stack, TextField, Typography,
} from '@mui/material'
import DeleteIcon from '@mui/icons-material/Delete'
import LockIcon from '@mui/icons-material/Lock'
import LockOpenIcon from '@mui/icons-material/LockOpen'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useParams } from 'react-router-dom'
import type { ApiError } from '../../api/client'
import { accessApi, type Role } from '../../api/access'
import { Permissions, useAuth } from '../../auth/AuthContext'

export function UserDetail() {
  const { id } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const { can, session } = useAuth()

  const [toast, setToast] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [lockDialog, setLockDialog] = useState(false)
  const [lockReason, setLockReason] = useState('')
  const [revokeDialog, setRevokeDialog] = useState(false)
  const [revokeReason, setRevokeReason] = useState('')
  const [roleToAdd, setRoleToAdd] = useState<Role | null>(null)

  const user = useQuery({
    queryKey: ['user', id],
    queryFn: () => accessApi.getUser(id!),
    enabled: !!id,
  })

  const roles = useQuery({
    queryKey: ['roles'],
    queryFn: accessApi.listRoles,
  })

  function onDone(message: string) {
    setError(null)
    setToast(message)
    user.refetch()
    queryClient.invalidateQueries({ queryKey: ['users'] })
  }

  // Every failure here is a refusal with a reason worth reading — an
  // escalation the caller cannot make, a self-demotion, the last
  // administrator. Showing the message rather than a generic error is the
  // difference between an operator fixing it and filing a ticket.
  function onFailed(e: ApiError) {
    setError(e.message)
  }

  const lock = useMutation({
    mutationFn: (isLocked: boolean) =>
      accessApi.setLockout(id!, isLocked, isLocked ? lockReason : null),
    onSuccess: (_, isLocked) => {
      setLockDialog(false)
      setLockReason('')
      onDone(isLocked ? 'Account locked and signed out' : 'Account unlocked')
    },
    onError: onFailed,
  })

  const addRole = useMutation({
    mutationFn: (roleId: number) => accessApi.assignRole(id!, roleId),
    onSuccess: () => {
      setRoleToAdd(null)
      onDone('Role granted')
    },
    onError: onFailed,
  })

  const removeRole = useMutation({
    mutationFn: (roleId: number) => accessApi.removeRole(id!, roleId),
    onSuccess: () => onDone('Role removed'),
    onError: onFailed,
  })

  const revoke = useMutation({
    mutationFn: () => accessApi.revokeSessions(id!, revokeReason || null),
    onSuccess: () => {
      setRevokeDialog(false)
      setRevokeReason('')
      onDone('Signed out of every device')
    },
    onError: onFailed,
  })

  if (user.isLoading) return <Typography>Loading…</Typography>
  if (user.isError)
    return <Alert severity="error">{(user.error as Error).message}</Alert>

  const detail = user.data!
  const isSelf = session?.userId === detail.userId
  const held = new Set(detail.roles.map((r) => r.roleId))
  const grantable = (roles.data ?? []).filter((r) => !held.has(r.roleId))

  return (
    <Stack spacing={2} sx={{ maxWidth: 900 }}>
      <Stack direction="row" spacing={2} sx={{ alignItems: 'center' }}>
        <Typography variant="h5" sx={{ fontWeight: 600, flex: 1 }}>
          {detail.email ?? 'Account'}
        </Typography>
        {detail.isLockedOut ? (
          <Chip size="small" color="warning" label="Locked" />
        ) : (
          <Chip size="small" color="success" variant="outlined" label="Active" />
        )}
      </Stack>

      {/* An operator looking at their own account needs to understand why the
          buttons are inert before they click them. */}
      {isSelf ? (
        <Alert severity="info">
          This is your own account. You cannot change your own roles or lock
          yourself out — ask another administrator.
        </Alert>
      ) : null}

      {error ? (
        <Alert severity="warning" onClose={() => setError(null)}>
          {error}
        </Alert>
      ) : null}

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Stack spacing={1}>
          <Field label="Joined" value={new Date(detail.createdUtc).toLocaleString()} />
          <Field label="Country" value={detail.countryIso ?? '—'} />
          <Field label="Language" value={detail.languageCode} />
          <Field
            label="Email confirmed"
            value={detail.isEmailConfirmed ? 'Yes' : 'No'}
          />
          <Field label="Failed sign-ins" value={String(detail.failedLoginCount)} />
        </Stack>
      </Paper>

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Typography variant="subtitle2" sx={{ mb: 1 }}>
          Roles
        </Typography>

        {detail.roles.length === 0 ? (
          <Typography variant="body2" color="text.secondary">
            No roles. This account can sign in but reach nothing administrative.
          </Typography>
        ) : (
          <List dense>
            {detail.roles.map((role) => (
              <ListItem
                key={role.roleId}
                disableGutters
                secondaryAction={
                  can(Permissions.rolesWrite) && !isSelf ? (
                    <IconButton
                      edge="end"
                      size="small"
                      disabled={removeRole.isPending}
                      onClick={() => removeRole.mutate(role.roleId)}
                    >
                      <DeleteIcon fontSize="small" />
                    </IconButton>
                  ) : null
                }
              >
                <ListItemText
                  primary={role.name}
                  secondary={`Granted ${new Date(role.assignedUtc).toLocaleDateString()}`}
                />
              </ListItem>
            ))}
          </List>
        )}

        {can(Permissions.rolesWrite) && !isSelf ? (
          <Stack direction="row" spacing={1} sx={{ mt: 2, alignItems: 'center' }}>
            <Autocomplete
              size="small"
              sx={{ flex: 1, maxWidth: 320 }}
              options={grantable}
              value={roleToAdd}
              onChange={(_, v) => setRoleToAdd(v)}
              getOptionLabel={(o) => o.name}
              renderInput={(params) => (
                <TextField {...params} label="Grant a role" />
              )}
            />
            <Button
              variant="contained"
              disabled={!roleToAdd || addRole.isPending}
              onClick={() => roleToAdd && addRole.mutate(roleToAdd.roleId)}
            >
              Grant
            </Button>
          </Stack>
        ) : null}
      </Paper>

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Typography variant="subtitle2" sx={{ mb: 1 }}>
          Devices
        </Typography>
        {detail.devices.length === 0 ? (
          <Typography variant="body2" color="text.secondary">
            No devices registered.
          </Typography>
        ) : (
          <List dense>
            {detail.devices.map((d) => (
              <ListItem key={d.deviceId} disableGutters>
                <ListItemText
                  primary={`${d.platform} ${d.model ?? ''}`.trim()}
                  secondary={`App ${d.appVersion ?? '—'} · last seen ${new Date(
                    d.lastSeenUtc,
                  ).toLocaleString()}`}
                />
              </ListItem>
            ))}
          </List>
        )}
      </Paper>

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Typography variant="subtitle2" sx={{ mb: 1 }}>
          Recent activity
        </Typography>
        {detail.recentActivity.length === 0 ? (
          <Typography variant="body2" color="text.secondary">
            Nothing recorded.
          </Typography>
        ) : (
          <List dense>
            {detail.recentActivity.map((a) => (
              <ListItem key={a.auditLogId} disableGutters>
                <ListItemText
                  primary={a.action}
                  secondary={`${new Date(a.occurredUtc).toLocaleString()}${
                    a.ipAddress ? ` · ${a.ipAddress}` : ''
                  }`}
                />
              </ListItem>
            ))}
          </List>
        )}
      </Paper>

      <Divider />

      <Stack direction="row" spacing={1}>
        {can(Permissions.usersWrite) && !isSelf ? (
          detail.isLockedOut ? (
            <Button
              variant="outlined"
              startIcon={<LockOpenIcon />}
              disabled={lock.isPending}
              onClick={() => lock.mutate(false)}
            >
              Unlock
            </Button>
          ) : (
            <Button
              variant="outlined"
              color="warning"
              startIcon={<LockIcon />}
              onClick={() => setLockDialog(true)}
            >
              Lock account
            </Button>
          )
        ) : null}

        {can(Permissions.usersWrite) ? (
          <Button variant="outlined" onClick={() => setRevokeDialog(true)}>
            Sign out everywhere
          </Button>
        ) : null}
      </Stack>

      <Dialog open={lockDialog} onClose={() => setLockDialog(false)} fullWidth maxWidth="sm">
        <DialogTitle>Lock this account</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            The account is signed out of every device immediately and cannot
            sign in again until it is unlocked. Say why — this is recorded and
            is the first thing anybody asks afterwards.
          </DialogContentText>
          <TextField
            autoFocus fullWidth multiline minRows={2} label="Reason"
            value={lockReason}
            onChange={(e) => setLockReason(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setLockDialog(false)}>Cancel</Button>
          <Button
            color="warning"
            disabled={!lockReason.trim() || lock.isPending}
            onClick={() => lock.mutate(true)}
          >
            Lock account
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog open={revokeDialog} onClose={() => setRevokeDialog(false)} fullWidth maxWidth="sm">
        <DialogTitle>Sign out of every device</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            Ends every session within about 30 seconds. The account itself stays
            active and can sign in again straight away.
          </DialogContentText>
          <TextField
            autoFocus fullWidth label="Reason (optional)"
            value={revokeReason}
            onChange={(e) => setRevokeReason(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRevokeDialog(false)}>Cancel</Button>
          <Button disabled={revoke.isPending} onClick={() => revoke.mutate()}>
            Sign out
          </Button>
        </DialogActions>
      </Dialog>

      <Snackbar
        open={!!toast}
        autoHideDuration={3000}
        onClose={() => setToast(null)}
        message={toast}
      />
    </Stack>
  )
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <Stack direction="row" spacing={2}>
      <Typography variant="body2" color="text.secondary" sx={{ minWidth: 150 }}>
        {label}
      </Typography>
      <Typography variant="body2">{value}</Typography>
    </Stack>
  )
}
