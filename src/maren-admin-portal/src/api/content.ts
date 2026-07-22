/**
 * Content endpoints, typed to match Maren.Contracts.
 *
 * Kept as plain functions rather than hooks so they can be composed into
 * TanStack queries and mutations without one deciding the other's caching.
 */
import { request, requestPaged } from './client'

export interface ContentLocalization {
  languageCode: string
  title: string | null
  body: string | null
  summary: string | null
  metadataJson: string | null
  isMachineTranslated?: boolean
}

export interface ContentItem {
  contentItemId: string
  contentType: string
  key: string | null
  categoryKey: string | null
  status: string
  versionNumber: number
  publishedVersionId: string | null
  weight: number
  sourceCitation: string | null
  countryFilter: string | null
  minAppVersion: string | null
  fromWeek: number | null
  toWeek: number | null
  season: string | null
  modifiedUtc: string
  localizations: ContentLocalization[]
  tags: { key: string; label: string }[]
}

export interface ContentListItem {
  contentItemId: string
  contentType: string
  key: string | null
  title: string | null
  status: string
  versionNumber: number
  categoryKey: string | null
  modifiedUtc: string
  isDeleted: boolean
}

export interface ContentVersion {
  contentVersionId: string
  versionNumber: number
  changeSummary: string | null
  createdUtc: string
  createdByName: string | null
}

export interface PagedResult<T> {
  items: T[]
  totalCount: number
  page: number
  pageSize: number
  totalPages: number
}

export interface ContentCategory {
  categoryId: string
  key: string
  label: string
}

export interface SearchParams {
  query?: string
  contentType?: string
  categoryKey?: string
  status?: string
  includeDeleted?: boolean
  page?: number
  pageSize?: number
  sortBy?: string
  sortDescending?: boolean
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

export const contentApi = {
  search: (params: SearchParams) =>
    requestPaged<PagedResult<ContentListItem>>(
      `/api/v1/content${queryString(params as Record<string, unknown>)}`,
    ),

  get: (id: string) => request<ContentItem>(`/api/v1/content/${id}`),

  categories: () =>
    request<ContentCategory[]>('/api/v1/content/categories'),

  versions: (id: string) =>
    request<ContentVersion[]>(`/api/v1/content/${id}/versions`),

  /**
   * Saves, sending the version the editor started from as If-Match.
   *
   * Omitting it means last-write-wins, which in a CMS is how an afternoon of
   * somebody else's work disappears with nobody told.
   */
  save: (payload: Record<string, unknown>, expectedVersionNumber: number | null) =>
    request<{
      contentItemId: string
      contentVersionId: string
      versionNumber: number
    }>('/api/v1/content', {
      method: 'PUT',
      body: { ...payload, expectedVersionNumber },
      ifMatch: expectedVersionNumber,
    }),

  approve: (id: string, contentVersionId: string, isApproved: boolean, reason?: string) =>
    request<unknown>(`/api/v1/content/${id}/approve`, {
      method: 'POST',
      body: { contentVersionId, isApproved, reason: reason ?? null },
    }),

  publish: (id: string) =>
    request<unknown>(`/api/v1/content/${id}/publish`, {
      method: 'POST',
      body: {},
    }),

  unpublish: (id: string) =>
    request<unknown>(`/api/v1/content/${id}/unpublish`, { method: 'POST' }),

  remove: (id: string) =>
    request<unknown>(`/api/v1/content/${id}`, { method: 'DELETE' }),

  restore: (id: string, contentVersionId: string) =>
    request<unknown>(`/api/v1/content/${id}/restore`, {
      method: 'POST',
      body: { contentVersionId },
    }),
}
