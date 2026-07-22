import {
  AppBar, Box, Button, Drawer, List, ListItemButton, ListItemIcon,
  ListItemText, Toolbar, Typography, Divider, Chip,
} from '@mui/material'
import ArticleIcon from '@mui/icons-material/Article'
import PeopleIcon from '@mui/icons-material/People'
import SecurityIcon from '@mui/icons-material/Security'
import HistoryIcon from '@mui/icons-material/History'
import FlagIcon from '@mui/icons-material/Flag'
import LogoutIcon from '@mui/icons-material/Logout'
import { NavLink, useLocation } from 'react-router-dom'
import { Permissions, useAuth } from '../auth/AuthContext'

const DRAWER_WIDTH = 232

interface NavItem {
  label: string
  to: string
  icon: React.ReactNode
  permission: string
}

const NAV: NavItem[] = [
  {
    label: 'Content',
    to: '/content',
    icon: <ArticleIcon fontSize="small" />,
    permission: Permissions.contentRead,
  },
  {
    label: 'Feature flags',
    to: '/flags',
    icon: <FlagIcon fontSize="small" />,
    permission: Permissions.flagsRead,
  },
  {
    label: 'Users',
    to: '/users',
    icon: <PeopleIcon fontSize="small" />,
    permission: Permissions.usersRead,
  },
  {
    label: 'Roles',
    to: '/roles',
    icon: <SecurityIcon fontSize="small" />,
    permission: Permissions.rolesRead,
  },
  {
    label: 'Audit log',
    to: '/audit',
    icon: <HistoryIcon fontSize="small" />,
    permission: Permissions.auditRead,
  },
]

export function Shell({ children }: { children: React.ReactNode }) {
  const { session, signOut, can } = useAuth()
  const location = useLocation()

  // Only what this operator can actually reach. A menu item that always
  // returns 403 teaches people to ignore errors.
  const visible = NAV.filter((item) => can(item.permission))

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      <AppBar
        position="fixed"
        color="inherit"
        elevation={0}
        sx={{
          zIndex: (t) => t.zIndex.drawer + 1,
          borderBottom: 1,
          borderColor: 'divider',
        }}
      >
        <Toolbar sx={{ gap: 2 }}>
          <Typography variant="h6" sx={{ fontWeight: 600, letterSpacing: '-0.01em' }}>
            Maren
          </Typography>
          <Chip label="Platform" size="small" variant="outlined" />
          <Box sx={{ flex: 1 }} />
          <Typography variant="body2" color="text.secondary">
            {session?.displayName ?? session?.email}
          </Typography>
          <Button
            size="small"
            startIcon={<LogoutIcon fontSize="small" />}
            onClick={signOut}
          >
            Sign out
          </Button>
        </Toolbar>
      </AppBar>

      <Drawer
        variant="permanent"
        sx={{
          width: DRAWER_WIDTH,
          flexShrink: 0,
          '& .MuiDrawer-paper': {
            width: DRAWER_WIDTH,
            boxSizing: 'border-box',
            borderRight: 1,
            borderColor: 'divider',
          },
        }}
      >
        <Toolbar />
        <Divider />
        <List sx={{ py: 1 }}>
          {visible.map((item) => (
            <ListItemButton
              key={item.to}
              component={NavLink}
              to={item.to}
              selected={location.pathname.startsWith(item.to)}
              sx={{ mx: 1, borderRadius: 1 }}
            >
              <ListItemIcon sx={{ minWidth: 36 }}>{item.icon}</ListItemIcon>
              <ListItemText
                primary={item.label}
                slotProps={{ primary: { variant: 'body2' } }}
              />
            </ListItemButton>
          ))}
        </List>
      </Drawer>

      <Box component="main" sx={{ flexGrow: 1, p: 3, minWidth: 0 }}>
        <Toolbar />
        {children}
      </Box>
    </Box>
  )
}
