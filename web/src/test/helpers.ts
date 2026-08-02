// 测试辅助：mock 全局 fetch，按 URL/方法分发响应。
import { vi } from 'vitest'

interface MockedResponse {
  status: number
  body?: unknown
}

type Handler = (url: string, init?: RequestInit) => MockedResponse

export function mockFetch(handler: Handler) {
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const { status, body } = handler(url, init)
    const headers = { 'Content-Type': 'application/json' }
    if (body === undefined) {
      return new Response(null, { status, headers })
    }
    return new Response(JSON.stringify(body), { status, headers })
  })
  vi.stubGlobal('fetch', fn)
  return fn
}

export function unstubFetch() {
  vi.unstubAllGlobals()
}
