import {
  Alert, Button, Dialog, DialogActions, DialogContent, DialogTitle,
  List, ListItem, ListItemText, Stack, Typography,
} from '@mui/material'
import { useMutation, useQuery } from '@tanstack/react-query'
import { contentApi } from '../../api/content'
import { Permissions, useAuth } from '../../auth/AuthContext'

interface Props {
  contentItemId: string
  open: boolean
  onClose: () => void
  onRestored: () => void
}

export function VersionHistory({ contentItemId, open, onClose, onRestored }: Props) {
  const { can } = useAuth()

  const versions = useQuery({
    queryKey: ['versions', contentItemId],
    queryFn: () => contentApi.versions(contentItemId),
    enabled: open,
  })

  const restore = useMutation({
    mutationFn: (versionId: string) => contentApi.restore(contentItemId, versionId),
    onSuccess: () => {
      versions.refetch()
      onRestored()
      onClose()
    },
  })

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>Version history</DialogTitle>
      <DialogContent dividers>
        {/* Restoring is safe, and saying so stops people treating history as
            read-only. Nothing is lost because a restore appends. */}
        <Alert severity="info" sx={{ mb: 2 }}>
          Restoring copies an old version forward as a new one. Nothing is
          overwritten, so you can always restore back.
        </Alert>

        {versions.isLoading && <Typography>Loading…</Typography>}

        <List dense>
          {(versions.data ?? []).map((version, index) => (
            <ListItem
              key={version.contentVersionId}
              secondaryAction={
                index > 0 && can(Permissions.contentRestore) ? (
                  <Button
                    size="small"
                    disabled={restore.isPending}
                    onClick={() => restore.mutate(version.contentVersionId)}
                  >
                    Restore
                  </Button>
                ) : null
              }
            >
              <ListItemText
                primary={
                  <Stack direction="row" spacing={1} sx={{ alignItems: 'baseline' }}>
                    <Typography variant="body2" sx={{ fontWeight: 600 }}>
                      v{version.versionNumber}
                    </Typography>
                    {index === 0 ? (
                      <Typography variant="caption" color="text.secondary">
                        current
                      </Typography>
                    ) : null}
                  </Stack>
                }
                secondary={
                  <>
                    {version.changeSummary || 'No summary'}
                    {' — '}
                    {new Date(version.createdUtc).toLocaleString(undefined, {
                      dateStyle: 'medium',
                      timeStyle: 'short',
                    })}
                    {version.createdByName ? ` by ${version.createdByName}` : ''}
                  </>
                }
              />
            </ListItem>
          ))}
        </List>

        {restore.isError && (
          <Alert severity="error">{(restore.error as Error).message}</Alert>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Close</Button>
      </DialogActions>
    </Dialog>
  )
}
