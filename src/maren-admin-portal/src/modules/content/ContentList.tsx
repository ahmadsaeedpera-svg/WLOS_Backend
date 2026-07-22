import { useMemo, useState } from 'react'
import {
  Box, Button, Chip, MenuItem, Paper, Stack, TextField, Typography, Alert,
} from '@mui/material'
import { DataGrid, type GridColDef } from '@mui/x-data-grid'
import AddIcon from '@mui/icons-material/Add'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { contentApi, type ContentListItem } from '../../api/content'
import { Permissions, useAuth } from '../../auth/AuthContext'

const STATUS_COLOR: Record<string, 'default' | 'success' | 'warning' | 'info'> = {
  draft: 'default',
  in_review: 'warning',
  approved: 'info',
  published: 'success',
}

export function ContentList() {
  const navigate = useNavigate()
  const { can } = useAuth()

  const [query, setQuery] = useState('')
  const [status, setStatus] = useState('')
  const [contentType, setContentType] = useState('')
  const [page, setPage] = useState(0)
  const [pageSize, setPageSize] = useState(25)

  const search = useQuery({
    queryKey: ['content', { query, status, contentType, page, pageSize }],
    queryFn: () =>
      contentApi.search({
        query: query || undefined,
        status: status || undefined,
        contentType: contentType || undefined,
        page: page + 1, // the grid is zero-based, the API is one-based
        pageSize,
      }),
    // Keeps the previous page on screen while the next loads, so the grid does
    // not collapse to empty and jump the scroll position on every keystroke.
    placeholderData: keepPreviousData,
  })

  const columns = useMemo<GridColDef<ContentListItem>[]>(
    () => [
      {
        field: 'title',
        headerName: 'Title',
        flex: 2,
        minWidth: 220,
        renderCell: (params) => (
          <Box>
            <Typography variant="body2">
              {params.row.title ?? <em>Untitled</em>}
            </Typography>
            {params.row.key && (
              <Typography variant="caption" color="text.secondary">
                {params.row.key}
              </Typography>
            )}
          </Box>
        ),
      },
      { field: 'contentType', headerName: 'Type', width: 120 },
      { field: 'categoryKey', headerName: 'Category', width: 130 },
      {
        field: 'status',
        headerName: 'Status',
        width: 130,
        renderCell: (params) => (
          <Chip
            size="small"
            label={String(params.value).replace('_', ' ')}
            color={STATUS_COLOR[String(params.value)] ?? 'default'}
            variant={params.value === 'published' ? 'filled' : 'outlined'}
          />
        ),
      },
      {
        field: 'versionNumber',
        headerName: 'Ver.',
        width: 70,
        align: 'right',
        headerAlign: 'right',
      },
      {
        field: 'modifiedUtc',
        headerName: 'Modified',
        width: 170,
        valueFormatter: (value: string) =>
          new Date(value).toLocaleString(undefined, {
            dateStyle: 'medium',
            timeStyle: 'short',
          }),
      },
    ],
    [],
  )

  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={2} sx={{ alignItems: 'center' }}>
        <Typography variant="h5" sx={{ fontWeight: 600, flex: 1 }}>
          Content
        </Typography>
        {can(Permissions.contentWrite) && (
          <Button
            variant="contained"
            startIcon={<AddIcon />}
            onClick={() => navigate('/content/new')}
          >
            New item
          </Button>
        )}
      </Stack>

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
          <TextField
            label="Search titles and bodies"
            size="small"
            value={query}
            onChange={(e) => {
              setQuery(e.target.value)
              setPage(0)
            }}
            sx={{ flex: 1 }}
          />
          <TextField
            select
            label="Status"
            size="small"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value)
              setPage(0)
            }}
            sx={{ minWidth: 150 }}
          >
            <MenuItem value="">Any</MenuItem>
            <MenuItem value="draft">Draft</MenuItem>
            <MenuItem value="in_review">In review</MenuItem>
            <MenuItem value="approved">Approved</MenuItem>
            <MenuItem value="published">Published</MenuItem>
          </TextField>
          <TextField
            select
            label="Type"
            size="small"
            value={contentType}
            onChange={(e) => {
              setContentType(e.target.value)
              setPage(0)
            }}
            sx={{ minWidth: 150 }}
          >
            <MenuItem value="">Any</MenuItem>
            <MenuItem value="article">Article</MenuItem>
            <MenuItem value="tip">Tip</MenuItem>
            <MenuItem value="snippet">Snippet</MenuItem>
            <MenuItem value="checklist">Checklist</MenuItem>
          </TextField>
        </Stack>
      </Paper>

      {search.isError && (
        <Alert severity="error">
          {(search.error as Error).message}
        </Alert>
      )}

      <Paper variant="outlined">
        <DataGrid
          rows={search.data?.data.items ?? []}
          columns={columns}
          getRowId={(row) => row.contentItemId}
          loading={search.isFetching}
          rowCount={search.data?.totalCount ?? 0}
          paginationMode="server"
          paginationModel={{ page, pageSize }}
          onPaginationModelChange={(model) => {
            setPage(model.page)
            setPageSize(model.pageSize)
          }}
          pageSizeOptions={[25, 50, 100]}
          disableRowSelectionOnClick
          onRowClick={(params) => navigate(`/content/${params.id}`)}
          sx={{
            border: 0,
            '& .MuiDataGrid-row': { cursor: 'pointer' },
          }}
          autoHeight
        />
      </Paper>
    </Stack>
  )
}
