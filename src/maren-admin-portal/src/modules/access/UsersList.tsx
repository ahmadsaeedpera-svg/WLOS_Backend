import { useState } from 'react'
import {
  Alert, Box, Chip, MenuItem, Paper, Stack, TextField, Typography,
} from '@mui/material'
import { DataGrid, type GridColDef } from '@mui/x-data-grid'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { accessApi, type UserListItem } from '../../api/access'

export function UsersList() {
  const navigate = useNavigate()
  const [query, setQuery] = useState('')
  const [status, setStatus] = useState('any')
  const [page, setPage] = useState(0)
  const [pageSize, setPageSize] = useState(25)

  const search = useQuery({
    queryKey: ['users', { query, status, page, pageSize }],
    queryFn: () =>
      accessApi.searchUsers({
        query: query || undefined,
        status,
        page: page + 1,
        pageSize,
      }),
    placeholderData: keepPreviousData,
  })

  const columns: GridColDef<UserListItem>[] = [
    {
      field: 'email',
      headerName: 'Email',
      flex: 2,
      minWidth: 220,
      renderCell: (params) => (
        <Box>
          <Typography variant="body2">{params.row.email ?? '—'}</Typography>
          <Typography variant="caption" color="text.secondary">
            {params.row.countryIso ?? '—'} · {params.row.languageCode}
          </Typography>
        </Box>
      ),
    },
    {
      field: 'roleNames',
      headerName: 'Roles',
      flex: 2,
      minWidth: 200,
      renderCell: (params) =>
        params.row.roleNames ? (
          <Stack direction="row" spacing={0.5} sx={{ flexWrap: 'wrap', gap: 0.5 }}>
            {params.row.roleNames.split(', ').map((r) => (
              <Chip key={r} size="small" label={r} variant="outlined" />
            ))}
          </Stack>
        ) : (
          <Typography variant="caption" color="text.secondary">
            No roles
          </Typography>
        ),
    },
    {
      field: 'state',
      headerName: 'State',
      width: 150,
      sortable: false,
      renderCell: (params) => {
        if (params.row.isDeleted)
          return <Chip size="small" label="Deleted" color="error" variant="outlined" />
        if (params.row.isLockedOut)
          return <Chip size="small" label="Locked" color="warning" />
        if (!params.row.isEmailConfirmed)
          return <Chip size="small" label="Unconfirmed" variant="outlined" />
        return <Chip size="small" label="Active" color="success" variant="outlined" />
      },
    },
    {
      field: 'createdUtc',
      headerName: 'Joined',
      width: 160,
      valueFormatter: (value: string) =>
        new Date(value).toLocaleDateString(undefined, { dateStyle: 'medium' }),
    },
  ]

  return (
    <Stack spacing={2}>
      <Typography variant="h5" sx={{ fontWeight: 600 }}>
        Users
      </Typography>

      <Paper variant="outlined" sx={{ p: 2 }}>
        <Stack direction={{ xs: 'column', sm: 'row' }} spacing={2}>
          <TextField
            label="Search by email"
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
            label="State"
            size="small"
            value={status}
            onChange={(e) => {
              setStatus(e.target.value)
              setPage(0)
            }}
            sx={{ minWidth: 170 }}
          >
            <MenuItem value="any">Any active account</MenuItem>
            <MenuItem value="active">Active</MenuItem>
            <MenuItem value="locked">Locked</MenuItem>
            <MenuItem value="unconfirmed">Unconfirmed email</MenuItem>
            <MenuItem value="deleted">Deleted</MenuItem>
          </TextField>
        </Stack>
      </Paper>

      {search.isError ? (
        <Alert severity="error">{(search.error as Error).message}</Alert>
      ) : null}

      <Paper variant="outlined">
        <DataGrid
          rows={search.data?.data.items ?? []}
          columns={columns}
          getRowId={(row) => row.userId}
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
          onRowClick={(p) => navigate(`/users/${p.id}`)}
          sx={{ border: 0, '& .MuiDataGrid-row': { cursor: 'pointer' } }}
          autoHeight
        />
      </Paper>
    </Stack>
  )
}
