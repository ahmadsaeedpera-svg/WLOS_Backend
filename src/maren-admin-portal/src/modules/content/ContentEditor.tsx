import { useEffect, useState } from 'react'
import {
  Alert, Box, Button, Chip, Dialog, DialogActions, DialogContent,
  DialogContentText, DialogTitle, Divider, IconButton, MenuItem, Paper,
  Stack, Tab, Tabs, TextField, Typography, Snackbar,
} from '@mui/material'
import DeleteIcon from '@mui/icons-material/Delete'
import HistoryIcon from '@mui/icons-material/History'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate, useParams } from 'react-router-dom'
import { ApiError } from '../../api/client'
import { contentApi, type ContentLocalization } from '../../api/content'
import { Permissions, useAuth } from '../../auth/AuthContext'
import { VersionHistory } from './VersionHistory'

const LANGUAGES = ['en-GB', 'es-ES', 'fr-FR', 'de-DE']

interface Draft {
  contentType: string
  key: string
  categoryKey: string
  weight: number
  sourceCitation: string
  countryFilter: string
  minAppVersion: string
  fromWeek: string
  toWeek: string
  localizations: ContentLocalization[]
}

const EMPTY: Draft = {
  contentType: 'article',
  key: '',
  categoryKey: '',
  weight: 100,
  sourceCitation: '',
  countryFilter: '',
  minAppVersion: '',
  fromWeek: '',
  toWeek: '',
  localizations: [
    { languageCode: 'en-GB', title: '', body: '', summary: '', metadataJson: null },
  ],
}

export function ContentEditor() {
  const { id } = useParams<{ id: string }>()
  const isNew = id === 'new' || !id
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { can } = useAuth()

  const [draft, setDraft] = useState<Draft>(EMPTY)
  const [language, setLanguage] = useState('en-GB')
  const [historyOpen, setHistoryOpen] = useState(false)
  const [conflict, setConflict] = useState(false)
  const [toast, setToast] = useState<string | null>(null)
  const [fieldErrors, setFieldErrors] = useState<Record<string, string[]>>({})
  const [rejecting, setRejecting] = useState(false)
  const [rejectReason, setRejectReason] = useState('')

  const item = useQuery({
    queryKey: ['content', id],
    queryFn: () => contentApi.get(id!),
    enabled: !isNew,
  })

  const categories = useQuery({
    queryKey: ['categories'],
    queryFn: contentApi.categories,
  })

  useEffect(() => {
    if (!item.data) return
    setDraft({
      contentType: item.data.contentType,
      key: item.data.key ?? '',
      categoryKey: item.data.categoryKey ?? '',
      weight: item.data.weight,
      sourceCitation: item.data.sourceCitation ?? '',
      countryFilter: item.data.countryFilter ?? '',
      minAppVersion: item.data.minAppVersion ?? '',
      fromWeek: item.data.fromWeek?.toString() ?? '',
      toWeek: item.data.toWeek?.toString() ?? '',
      localizations: item.data.localizations.length
        ? item.data.localizations
        : EMPTY.localizations,
    })
  }, [item.data])

  const current =
    draft.localizations.find((l) => l.languageCode === language) ??
    { languageCode: language, title: '', body: '', summary: '', metadataJson: null }

  function updateLocalization(patch: Partial<ContentLocalization>) {
    setDraft((d) => {
      const existing = d.localizations.find((l) => l.languageCode === language)
      const next = existing
        ? d.localizations.map((l) =>
            l.languageCode === language ? { ...l, ...patch } : l,
          )
        : [...d.localizations, { ...current, ...patch }]
      return { ...d, localizations: next }
    })
  }

  const save = useMutation({
    mutationFn: () => {
      // Only send translations somebody actually filled in. An empty row would
      // be rejected by the validator, and an editor who opened the French tab
      // by accident should not be blocked by it.
      const localizations = draft.localizations.filter(
        (l) => (l.title ?? '').trim() || (l.body ?? '').trim(),
      )

      return contentApi.save(
        {
          contentItemId: isNew ? null : id,
          contentType: draft.contentType,
          key: draft.key || null,
          categoryKey: draft.categoryKey || null,
          weight: draft.weight,
          sourceCitation: draft.sourceCitation || null,
          countryFilter: draft.countryFilter || null,
          minAppVersion: draft.minAppVersion || null,
          fromWeek: draft.fromWeek ? Number(draft.fromWeek) : null,
          toWeek: draft.toWeek ? Number(draft.toWeek) : null,
          localizations,
        },
        isNew ? null : (item.data?.versionNumber ?? null),
      )
    },
    onSuccess: (result) => {
      setFieldErrors({})
      queryClient.invalidateQueries({ queryKey: ['content'] })
      setToast('Saved')
      if (isNew) navigate(`/content/${result.contentItemId}`, { replace: true })
    },
    onError: (error: ApiError) => {
      if (error.isConflict) {
        setConflict(true)
        return
      }
      setFieldErrors(error.validationErrors ?? {})
    },
  })

  const workflow = useMutation({
    mutationFn: async (
      action: 'approve' | 'reject' | 'publish' | 'unpublish' | 'delete',
    ) => {
      if (!id || isNew) return

      switch (action) {
        case 'approve':
        case 'reject': {
          // Approval names an exact version, never "the item". Approving an
          // item would let a later edit inherit the approval, which is the
          // hole the whole workflow exists to close — so read the newest
          // version now and approve that specific one.
          const versions = await contentApi.versions(id)
          const newest = versions[0]
          if (!newest) {
            throw new ApiError(400, 'NO_VERSION', 'There is nothing to review yet.')
          }
          return contentApi.approve(
            id,
            newest.contentVersionId,
            action === 'approve',
            action === 'reject' ? rejectReason : undefined,
          )
        }
        case 'publish':
          return contentApi.publish(id)
        case 'unpublish':
          return contentApi.unpublish(id)
        case 'delete':
          return contentApi.remove(id)
      }
    },
    onSuccess: (_, action) => {
      queryClient.invalidateQueries({ queryKey: ['content'] })
      item.refetch()
      setRejecting(false)
      setRejectReason('')
      setToast(
        action === 'delete' ? 'Deleted'
        : action === 'approve' ? 'Approved — it can now be published'
        : action === 'reject' ? 'Sent back to the author'
        : action === 'publish' ? 'Published'
        : 'Unpublished',
      )
      if (action === 'delete') navigate('/content')
    },
    onError: (error: ApiError) => setToast(error.message),
  })

  const errorFor = (field: string) =>
    Object.entries(fieldErrors)
      .filter(([k]) => k.toLowerCase().includes(field.toLowerCase()))
      .flatMap(([, v]) => v)
      .join(' ')

  if (item.isLoading) return <Typography>Loading…</Typography>

  const status = item.data?.status ?? 'draft'
  const readOnly = !can(Permissions.contentWrite)

  return (
    <Stack spacing={2} sx={{ maxWidth: 960 }}>
      <Stack direction="row" spacing={2} sx={{ alignItems: 'center' }}>
        <Typography variant="h5" sx={{ fontWeight: 600, flex: 1 }}>
          {isNew ? 'New content' : draft.key || 'Content'}
        </Typography>

        {!isNew && (
          <>
            <Chip
              size="small"
              label={status.replace('_', ' ')}
              color={status === 'published' ? 'success' : 'default'}
              variant={status === 'published' ? 'filled' : 'outlined'}
            />
            <Chip size="small" variant="outlined" label={`v${item.data?.versionNumber}`} />
            <IconButton onClick={() => setHistoryOpen(true)} title="Version history">
              <HistoryIcon />
            </IconButton>
          </>
        )}
      </Stack>

      {!isNew && status !== 'published' && (
        <Alert severity="info">
          This item is not live. Readers see nothing until it has been approved
          and published.
        </Alert>
      )}

      {!isNew && status === 'published' && (
        <Alert severity="success">
          Live. Editing here creates a new draft — readers keep seeing the
          approved version until you publish again.
        </Alert>
      )}

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Stack spacing={2}>
          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
            <TextField
              select label="Type" size="small" sx={{ minWidth: 150 }}
              value={draft.contentType} disabled={readOnly}
              onChange={(e) => setDraft({ ...draft, contentType: e.target.value })}
            >
              {['article', 'tip', 'snippet', 'checklist', 'faq'].map((t) => (
                <MenuItem key={t} value={t}>{t}</MenuItem>
              ))}
            </TextField>

            <TextField
              label="Key" size="small" sx={{ flex: 1 }}
              value={draft.key} disabled={readOnly}
              onChange={(e) => setDraft({ ...draft, key: e.target.value })}
              error={!!errorFor('key')}
              helperText={errorFor('key') || 'Stable identifier the app refers to. Letters, digits, dot, dash, underscore.'}
            />

            <TextField
              select label="Category" size="small" sx={{ minWidth: 170 }}
              value={draft.categoryKey} disabled={readOnly}
              onChange={(e) => setDraft({ ...draft, categoryKey: e.target.value })}
            >
              <MenuItem value="">None</MenuItem>
              {(categories.data ?? []).map((c) => (
                <MenuItem key={c.key} value={c.key}>{c.label}</MenuItem>
              ))}
            </TextField>
          </Stack>

          <Divider />

          <Typography variant="subtitle2" color="text.secondary">
            Targeting
          </Typography>

          <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
            <TextField
              label="Countries" size="small" sx={{ flex: 1 }}
              value={draft.countryFilter} disabled={readOnly}
              onChange={(e) => setDraft({ ...draft, countryFilter: e.target.value })}
              error={!!errorFor('countryFilter')}
              helperText={errorFor('countryFilter') || 'JSON array, e.g. ["GB","IE"]. Empty means everywhere.'}
            />
            <TextField
              label="From week" size="small" type="number" sx={{ width: 120 }}
              value={draft.fromWeek} disabled={readOnly}
              onChange={(e) => setDraft({ ...draft, fromWeek: e.target.value })}
            />
            <TextField
              label="To week" size="small" type="number" sx={{ width: 120 }}
              value={draft.toWeek} disabled={readOnly}
              onChange={(e) => setDraft({ ...draft, toWeek: e.target.value })}
            />
            <TextField
              label="Min app version" size="small" sx={{ width: 160 }}
              value={draft.minAppVersion} disabled={readOnly}
              onChange={(e) => setDraft({ ...draft, minAppVersion: e.target.value })}
              error={!!errorFor('minAppVersion')}
              helperText={errorFor('minAppVersion') || 'e.g. 2.1.0'}
            />
          </Stack>

          <TextField
            label="Source citation" size="small" fullWidth
            value={draft.sourceCitation} disabled={readOnly}
            onChange={(e) => setDraft({ ...draft, sourceCitation: e.target.value })}
            helperText="Where this guidance comes from. Health content without a source cannot be reviewed."
          />
        </Stack>
      </Paper>

      <Paper variant="outlined">
        <Tabs
          value={language}
          onChange={(_, v) => setLanguage(v)}
          sx={{ borderBottom: 1, borderColor: 'divider', px: 1 }}
        >
          {LANGUAGES.map((code) => {
            const filled = draft.localizations.some(
              (l) => l.languageCode === code && ((l.title ?? '') || (l.body ?? '')),
            )
            return (
              <Tab
                key={code}
                value={code}
                label={
                  <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                    <span>{code}</span>
                    {filled && <Box sx={{
                      width: 6, height: 6, borderRadius: '50%',
                      bgcolor: 'success.main',
                    }} />}
                  </Stack>
                }
              />
            )
          })}
        </Tabs>

        <Stack spacing={2} sx={{ p: 2 }}>
          {language !== 'en-GB' && (
            <Alert severity="info" variant="outlined">
              Leave this blank and readers in this language see the en-GB text.
            </Alert>
          )}
          <TextField
            label="Title" fullWidth size="small"
            value={current.title ?? ''} disabled={readOnly}
            onChange={(e) => updateLocalization({ title: e.target.value })}
            error={!!errorFor('localizations')}
          />
          <TextField
            label="Summary" fullWidth size="small"
            value={current.summary ?? ''} disabled={readOnly}
            onChange={(e) => updateLocalization({ summary: e.target.value })}
          />
          <TextField
            label="Body" fullWidth multiline minRows={10}
            value={current.body ?? ''} disabled={readOnly}
            onChange={(e) => updateLocalization({ body: e.target.value })}
          />
        </Stack>
      </Paper>

      {!!Object.keys(fieldErrors).length && (
        <Alert severity="error">
          {Object.entries(fieldErrors).map(([field, messages]) => (
            <div key={field}>{messages.join(' ')}</div>
          ))}
        </Alert>
      )}

      <Stack direction="row" spacing={1}>
        <Button
          variant="contained"
          disabled={readOnly || save.isPending}
          onClick={() => save.mutate()}
        >
          {save.isPending ? 'Saving…' : 'Save draft'}
        </Button>

        {!isNew && can(Permissions.contentReview) && status !== 'published' && (
          <>
            <Button
              variant="outlined"
              color="success"
              disabled={workflow.isPending}
              onClick={() => workflow.mutate('approve')}
            >
              Approve
            </Button>
            <Button
              variant="outlined"
              color="warning"
              disabled={workflow.isPending}
              onClick={() => setRejecting(true)}
            >
              Send back
            </Button>
          </>
        )}

        {!isNew && can(Permissions.contentPublish) && status !== 'published' && (
          <Button
            variant="outlined"
            disabled={workflow.isPending}
            onClick={() => workflow.mutate('publish')}
          >
            Publish
          </Button>
        )}

        {!isNew && can(Permissions.contentPublish) && status === 'published' && (
          <Button variant="outlined" onClick={() => workflow.mutate('unpublish')}>
            Unpublish
          </Button>
        )}

        <Box sx={{ flex: 1 }} />

        {!isNew && can(Permissions.contentDelete) && (
          <Button
            color="error"
            startIcon={<DeleteIcon />}
            onClick={() => workflow.mutate('delete')}
          >
            Delete
          </Button>
        )}
      </Stack>

      {!isNew && (
        <VersionHistory
          contentItemId={id!}
          open={historyOpen}
          onClose={() => setHistoryOpen(false)}
          onRestored={() => {
            item.refetch()
            setToast('Restored as a new version')
          }}
        />
      )}

      {/* A rejection without a reason is useless to the author, and the reason
          is what the audit trail records — so the API requires one and the
          dialog cannot be submitted without it. */}
      <Dialog open={rejecting} onClose={() => setRejecting(false)} fullWidth maxWidth="sm">
        <DialogTitle>Send back to the author</DialogTitle>
        <DialogContent>
          <DialogContentText sx={{ mb: 2 }}>
            Say what needs to change. This is recorded against the version and
            is what the author will see.
          </DialogContentText>
          <TextField
            autoFocus fullWidth multiline minRows={3}
            label="Reason"
            value={rejectReason}
            onChange={(e) => setRejectReason(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRejecting(false)}>Cancel</Button>
          <Button
            color="warning"
            disabled={!rejectReason.trim() || workflow.isPending}
            onClick={() => workflow.mutate('reject')}
          >
            Send back
          </Button>
        </DialogActions>
      </Dialog>

      {/* A conflict is not a validation error — the editor's text is fine, it
          is simply no longer based on the newest version. Reloading would
          discard their typing, so the choice is theirs. */}
      <Dialog open={conflict} onClose={() => setConflict(false)}>
        <DialogTitle>Somebody else saved first</DialogTitle>
        <DialogContent>
          <DialogContentText>
            This item changed while you were editing. Your text has not been
            saved and is still on screen. Open the current version in a new tab
            to compare before deciding what to keep.
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setConflict(false)}>Keep editing</Button>
          <Button
            onClick={() => {
              setConflict(false)
              item.refetch()
            }}
            color="error"
          >
            Discard mine and reload
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
