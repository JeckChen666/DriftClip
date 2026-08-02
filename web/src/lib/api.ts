// API 客户端：对齐 P01 服务端 API 契约。
//
// 约定：
//   - 同源请求，浏览器自动携带会话 Cookie；
//   - 所有状态修改请求带 X-Requested-With 头（P01 CSRF 契约）；
//   - 错误统一抛 ApiError，携带状态码与服务端错误信息。

export class ApiError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (init.method && init.method !== 'GET') {
    headers['X-Requested-With'] = 'XMLHttpRequest'
  }
  const res = await fetch(path, {
    ...init,
    credentials: 'same-origin',
    headers: { ...headers, ...(init.headers as Record<string, string> | undefined) },
  })
  if (res.status === 204) {
    return undefined as T
  }
  const data = (await res.json().catch(() => null)) as { error?: string } | null
  if (!res.ok) {
    throw new ApiError(res.status, data?.error ?? `请求失败（${res.status}）`)
  }
  return data as T
}

// ---- 类型（与 P01 API 契约对齐） ----

export interface HistoryListItem {
  id: number
  content_preview: string
  source: 'clipboard' | 'manual'
  received_at: string
  platform: string
  os_version: string
  device_model: string
  app_version: string
  installation_id: string
}

export interface HistoryDetail extends HistoryListItem {
  content: string
  public_ip: string
}

export interface HistoryListResponse {
  items: HistoryListItem[]
  total: number
  page: number
  page_size: number
}

// ---- 认证 ----

export const auth = {
  register: (email: string, password: string) =>
    request<{ email: string }>('/api/v1/auth/register', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }),
  login: (email: string, password: string) =>
    request<{ email: string }>('/api/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }),
  logout: () => request<void>('/api/v1/auth/logout', { method: 'POST' }),
  changePassword: (currentPassword: string, newPassword: string) =>
    request<void>('/api/v1/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }),
    }),
  me: () => request<{ email: string }>('/api/v1/auth/me'),
}

// ---- Key ----

export const keys = {
  status: () => request<{ has_key: boolean }>('/api/v1/keys'),
  generate: () => request<{ key: string }>('/api/v1/keys', { method: 'POST' }),
  reset: () => request<{ key: string }>('/api/v1/keys/reset', { method: 'POST' }),
}

// ---- 历史 ----

export interface HistoryFilter {
  platform?: string
  q?: string
  from?: string
  to?: string
}

export const history = {
  list: (page = 1, pageSize = 20, filter?: HistoryFilter) => {
    const params = new URLSearchParams({
      page: String(page),
      page_size: String(pageSize),
    })
    if (filter?.platform) params.set('platform', filter.platform)
    if (filter?.q) params.set('q', filter.q)
    if (filter?.from) params.set('from', filter.from)
    if (filter?.to) params.set('to', filter.to)
    return request<HistoryListResponse>(`/api/v1/history?${params.toString()}`)
  },
  get: (id: number) => request<HistoryDetail>(`/api/v1/history/${id}`),
  remove: (id: number) => request<void>(`/api/v1/history/${id}`, { method: 'DELETE' }),
  batchDelete: (ids: number[]) =>
    request<{ deleted: number }>('/api/v1/history/batch-delete', {
      method: 'POST',
      body: JSON.stringify({ ids }),
    }),
  clear: () =>
    request<{ deleted: number }>('/api/v1/history/clear', { method: 'POST' }),
}

// 自动刷新间隔：仅保存在当前浏览器 localStorage（Spec §6.3），0 表示关闭。
const REFRESH_KEY = 'dc_auto_refresh_seconds'

export function getAutoRefreshSeconds(): number {
  const v = Number(localStorage.getItem(REFRESH_KEY) ?? '0')
  return Number.isFinite(v) && v >= 0 ? v : 0
}

export function setAutoRefreshSeconds(seconds: number) {
  localStorage.setItem(REFRESH_KEY, String(Math.max(0, seconds)))
}
