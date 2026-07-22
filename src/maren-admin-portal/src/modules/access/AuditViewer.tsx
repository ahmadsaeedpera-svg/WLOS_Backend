import { useState } from 'react'
import {
  Alert, Box, Chip, IconButton, Paper, Stack, TextField, Typography,
} from '@mui/material'
import { DataGrid, type GridColDef } from '@mui/x-data-grid'
import ExpandMoreIcon from '@mui/icons-material/ExpandMore'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { accessApi, type AuditEntry } from '../../api/access'

/** Actions that describe a refusal rather than a change. */
const SECURITY_ACTIONS = new Set(['Security.EscalationRefused'])

export function AuditViewer() {
  const [action, setAction] = useState('')
  const [entityType, setEntityType] = useState('')
  const [page, setPage] = useState(0)
  const [pageSize, setPageSize] = useState(50)
  const [expanded, setExpanded] = useState<number | null>(null)

  const search = useQuery({
    queryKey: ['audit', { action, entityType, page, pageSize }],
    queryFn: () =>
      accessApi.searchAudit({
        action: action || undefined,
        entityType: entityType || undefined,
        page: page + 1,
        pageSize,
      }),
    placeholderData: keepPreviousData,
  })

  const columns: GridColDef<AuditEntry>[] = [
    {
      field: 'occurredUtc',
      headerName: 'When',
      width: 170,
      valueFormatter: (value: string) =>
        new Date(value).toLocaleString(undefined, {
          dateStyle: 'medium',
          timeStyle: 'medium',
        }),
    },
    {
      field: 'action',
      headerName: 'Action',
      width: 220,
      renderCell: (p) => (
        <Chip
          size="small"
          label={p.row.action}
          color={SECURITY_ACTIONS.has(p.row.action) ? 'error' : 'default'}
          variant={SECURITY_ACTIONS.has(p.row.action) ? 'filled' : 'outlined'}
        />
      ),
    },
    {
      field: 'actorEmail',
      headerName: 'Who',
      flex: 1,
      minWidth: 200,
      renderCell: (p) => (
        <Typography variant="body2">
          {p.row.actorEmail ?? p.row.actorKind}
        </Typography>
      ),
    },
    { field: 'entityType', headerName: 'Entity', width: 130 },
    { field: 'ipAddress', headerName: 'IP', width: 130 },
  ]

  return (
    <Stack spacing={2}>
      <Typography variant="h5" sx={{ fontWeight: 600 }}>
        Audit log
      </Typography>

      <Alert severity="info">
        Append-only. Nothing in the platform can edit or delete these entries.
        Refused escalation attempts appear here in red.
      </Alert>

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
          <TextField
            label="Action starts with"
            size="small"
            placeholder="e.g. Content. or Security."
            value={action}
            onChange={(e) => {
              setAction(e.target.value)
              setPage(0)
            }}
            sx={{ flex: 1 }}
          />
          <TextField
            label="Entity type"
            size="small"
            placeholder="e.g. User, Role, ContentItem"
            value={entityType}
            onChange={(e) => {
              setEntityType(e.target.value)
              setPage(0)
            }}
            sx={{ flex: 1 }}
          />
        </Stack>
      </Paper>

      {search.isError ? (
        <Alert severity="error">{(search.error as Error).message}</Alert>
      ) : null}

      <Paper variant="outlined">
        <DataGrid
          rows={search.data?.data.items ?? []}
          columns={columns}
          getRowId={(row) => row.auditLogId}
          loading={search.isFetching}
          rowCount={search.data?.totalCount ?? 0}
          paginationMode="server"
          paginationModel={{ page, pageSize }}
          onPaginationModelChange={(m) => {
            setPage(m.page)
            setPageSize(m.pageSize)
          }}
          pageSizeOptions={[25, 50, 100]}
          disableRowSelectionOnClick
          onRowClick={(p) =>
            setExpanded(expanded === Number(p.id) ? null : Number(p.id))
          }
          sx={{ border: 0, '& .MuiDataGrid-row': { cursor: 'pointer' } }}
          autoHeight
        />
      </Paper>

      {/* Before/after payloads are long JSON. Shown on demand rather than in a
          grid cell that would truncate them into uselessness. */}
      {expanded !== null ? (
        <Paper variant="outlined" sx={{ p: 2 }}>
          {(() => {
            const entry = search.data?.data.items.find(
              (i) => i.auditLogId === expanded,
            )
            if (!entry) return null
            return (
              <Stack spacing={1}>
                <Stack direction="row" spacing={1} sx={{ alignItems: 'center' }}>
                  <Typography variant="subtitle2" sx={{ flex: 1 }}>
                    {entry.action} · {new Date(entry.occurredUtc).toLocaleString()}
                  </Typography>
                  <IconButton size="small" onClick={() => setExpanded(null)}>
                    <ExpandMoreIcon fontSize="small" />
                  </IconButton>
                </Stack>
                {entry.beforeJson ? (
                  <JsonBlock title="Before" json={entry.beforeJson} />
                ) : null}
                {entry.afterJson ? (
                  <JsonBlock title="After" json={entry.afterJson} />
                ) : null}
              </Stack>
            )
          })()}
        </Paper>
      ) : null}
    </Stack>
  )
}

function JsonBlock({ title, json }: { title: string; json: string }) {
  let pretty = json
  try {
    pretty = JSON.stringify(JSON.parse(json), null, 2)
  } catch {
    // Not JSON — show it as it was stored rather than hiding it.
  }
  return (
    <Box>
      <Typography variant="caption" color="text.secondary">
        {title}
      </Typography>
      <Box
        component="pre"
        sx={{
          m: 0, p: 1.5, bgcolor: 'action.hover', borderRadius: 1,
          fontSize: 12, overflowX: 'auto',
        }}
      >
        {pretty}
      </Box>
    </Box>
  )
}
