/**
 * Users, roles, permissions and audit.
 *
 * Typed to match Maren.Contracts/AccessContracts.cs. Nothing here carries
 * password material — the procedures behind these endpoints name their result
 * columns precisely so it cannot reach a browser.
 */
import { request, requestPaged } from './client'

export interface UserListItem {
  userId: string
  email: string | null
  languageCode: string
  isEmailConfirmed: boolean
  isLockedOut: boolean
  lockoutEndUtc: string | null
  failedLoginCount: number
  isDeleted: boolean
  createdUtc: string
  countryIso: string | null
  roleNames: string
}

export interface UserRole {
  roleId: number
  name: string
  description: string | null
  isSystem: boolean
  assignedUtc: string
  assignedBy: string | null
}

export interface UserDevice {
  deviceId: string
  platform: string
  osVersion: string | null
  appVersion: string | null
  model: string | null
  isActive: boolean
  lastSeenUtc: string
}

export interface UserActivity {
  auditLogId: number
  occurredUtc: string
  action: string
  entityType: string | null
  entityId: string | null
  ipAddress: string | null
}

export interface UserDetail {
  userId: string
  email: string | null
  languageCode: string
  isEmailConfirmed: boolean
  isLockedOut: boolean
  lockoutEndUtc: string | null
  failedLoginCount: number
  isDeleted: boolean
  deletedUtc: string | null
  createdUtc: string
  modifiedUtc: string
  countryIso: string | null
  roles: UserRole[]
  devices: UserDevice[]
  recentActivity: UserActivity[]
}

export interface Role {
  roleId: number
  name: string
  description: string | null
  isSystem: boolean
  permissionCount: number
  memberCount: number
  permissionCodes: string[]
}

export interface Permission {
  permissionId: number
  code: string
  description: string | null
  category: string
}

export interface AuditEntry {
  auditLogId: number
  occurredUtc: string
  actorUserId: string | null
  actorEmail: string | null
  actorKind: string
  action: string
  entityType: string | null
  entityId: string | null
  beforeJson: string | null
  afterJson: string | null
  ipAddress: string | null
  correlationId: string | null
}

export interface Paged<T> {
  items: T[]
  page: number
  pageSize: number
  totalCount: number
  totalPages: number
}

function queryString(params: Record<string, unknown>) {
  const search = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === '') continue
    search.set(key, String(value))
  }
  const s = search.toString()
  return s ? `?${s}` : ''
}

export const accessApi = {
  searchUsers: (params: {
    query?: string
    roleId?: number
    status?: string
    page?: number
    pageSize?: number
  }) =>
    requestPaged<Paged<UserListItem>>(
      `/api/v1/admin/users${queryString(params)}`,
    ),

  getUser: (id: string) => request<UserDetail>(`/api/v1/admin/users/${id}`),

  setLockout: (
    id: string,
    isLocked: boolean,
    reason: string | null,
    lockoutEndUtc: string | null = null,
  ) =>
    request<unknown>(`/api/v1/admin/users/${id}/lock`, {
      method: 'POST',
      body: { isLocked, reason, lockoutEndUtc },
    }),

  assignRole: (id: string, roleId: number) =>
    request<unknown>(`/api/v1/admin/users/${id}/roles`, {
      method: 'POST',
      body: { roleId },
    }),

  removeRole: (id: string, roleId: number) =>
    request<unknown>(`/api/v1/admin/users/${id}/roles/${roleId}`, {
      method: 'DELETE',
    }),

  revokeSessions: (id: string, reason: string | null) =>
    request<unknown>(`/api/v1/admin/users/${id}/revoke-sessions`, {
      method: 'POST',
      body: { reason },
    }),

  listRoles: () => request<Role[]>('/api/v1/admin/roles'),

  listPermissions: () =>
    request<Permission[]>('/api/v1/admin/roles/permissions'),

  saveRole: (roleId: number | null, name: string, description: string | null) =>
    request<number>('/api/v1/admin/roles', {
      method: 'PUT',
      body: { roleId, name, description },
    }),

  deleteRole: (roleId: number) =>
    request<unknown>(`/api/v1/admin/roles/${roleId}`, { method: 'DELETE' }),

  setRolePermissions: (roleId: number, permissionCodes: string[]) =>
    request<unknown>(`/api/v1/admin/roles/${roleId}/permissions`, {
      method: 'PUT',
      body: { permissionCodes },
    }),

  searchAudit: (params: {
    actorUserId?: string
    entityType?: string
    entityId?: string
    action?: string
    fromUtc?: string
    toUtc?: string
    page?: number
    pageSize?: number
  }) =>
    requestPaged<Paged<AuditEntry>>(
      `/api/v1/admin/audit${queryString(params)}`,
    ),
}
