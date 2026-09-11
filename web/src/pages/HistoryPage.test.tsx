import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { mockFetch, unstubFetch } from '../test/helpers'
import { HistoryPage } from './HistoryPage'

const item = {
  id: 1,
  content_preview: '剪贴板预览内容',
  source: 'clipboard',
  received_at: '2026-08-02T19:00:00+08:00',
  platform: 'macos',
  os_version: '15',
  device_model: 'MacBook',
  app_version: '1.0.0',
  installation_id: 'i-1',
}

const listBody = { items: [item], total: 1, page: 1, page_size: 20 }

afterEach(() => {
  vi.useRealTimers()
  localStorage.clear()
  unstubFetch()
})

describe('HistoryPage', () => {
  it('渲染历史列表并可单条删除', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetch((url, init) => {
      if (init?.method === 'DELETE') return { status: 204 }
      if (url.startsWith('/api/v1/history?')) return { status: 200, body: listBody }
      return { status: 404, body: { error: 'x' } }
    })

    render(<HistoryPage />)

    expect(await screen.findByText('剪贴板预览内容')).toBeInTheDocument()
    // 平台徽标（筛选下拉里也有 macos，用 getAllBy 断言存在）
    expect(screen.getAllByText('macos').length).toBeGreaterThan(0)

    await user.click(screen.getByRole('button', { name: '删除' }))
    const delCall = fetchMock.mock.calls.find(
      ([u, init]) => u === '/api/v1/history/1' && init?.method === 'DELETE',
    )
    expect(delCall).toBeDefined()
  })

  it('组合筛选应用到请求参数', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetch((url, init) => {
      if (init?.method === 'DELETE') return { status: 204 }
      if (url.startsWith('/api/v1/history?')) return { status: 200, body: listBody }
      return { status: 404, body: { error: 'x' } }
    })

    render(<HistoryPage />)
    await screen.findByText('剪贴板预览内容')

    // Radix Select 改为 combobox：点击 trigger，弹出后点击选项
    await user.click(screen.getByRole('combobox', { name: '平台筛选' }))
    await user.click(screen.getByRole('option', { name: 'macos' }))
    await user.type(screen.getByLabelText('正文筛选'), 'hello')
    await user.click(screen.getByRole('button', { name: '应用' }))

    const filterCall = fetchMock.mock.calls.find(([u]) => u.includes('q=hello'))
    expect(filterCall).toBeDefined()
    expect(filterCall![0]).toContain('platform=macos')
  })

  it('多选删除调用 batch-delete', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetch((url, init) => {
      if (url === '/api/v1/history/batch-delete' && init?.method === 'POST') {
        return { status: 200, body: { deleted: 1 } }
      }
      if (url.startsWith('/api/v1/history?')) return { status: 200, body: listBody }
      return { status: 404, body: { error: 'x' } }
    })

    render(<HistoryPage />)
    await screen.findByText('剪贴板预览内容')

    await user.click(screen.getByRole('checkbox', { name: '选择记录 1' }))
    await user.click(screen.getByRole('button', { name: /删除所选/ }))

    const call = fetchMock.mock.calls.find(
      ([u, init]) => u === '/api/v1/history/batch-delete' && init?.method === 'POST',
    )
    expect(call).toBeDefined()
    expect(JSON.parse((call![1]!.body as string) ?? '{}')).toEqual({ ids: [1] })
  })

  it('清空全部需 5 秒倒计时确认（Spec §6.2）', async () => {
    vi.useFakeTimers()
    const fetchMock = mockFetch((url, init) => {
      if (url === '/api/v1/history/clear' && init?.method === 'POST') {
        return { status: 200, body: { deleted: 1 } }
      }
      if (url.startsWith('/api/v1/history?')) return { status: 200, body: listBody }
      return { status: 404, body: { error: 'x' } }
    })

    render(<HistoryPage />)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })

    // 倒计时期间按钮不可点击
    fireEvent.click(screen.getByRole('button', { name: '清空全部' }))
    expect(screen.getByRole('button', { name: '清空全部（5s）' })).toBeDisabled()

    // 5 秒后出现「确认清空全部」
    await act(async () => {
      await vi.advanceTimersByTimeAsync(6000)
    })
    fireEvent.click(screen.getByRole('button', { name: '确认清空全部' }))
    await act(async () => {})

    const call = fetchMock.mock.calls.find(
      ([u, init]) => u === '/api/v1/history/clear' && init?.method === 'POST',
    )
    expect(call).toBeDefined()
  })

  it('自动刷新按间隔重新加载（localStorage）', async () => {
    vi.useFakeTimers()
    localStorage.setItem('dc_auto_refresh_seconds', '5')
    let listCalls = 0
    mockFetch((url) => {
      if (url.startsWith('/api/v1/history?')) {
        listCalls++
        return { status: 200, body: listBody }
      }
      return { status: 404, body: { error: 'x' } }
    })

    render(<HistoryPage />)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })
    expect(listCalls).toBe(1)

    // 5 秒后自动重新加载
    await act(async () => {
      await vi.advanceTimersByTimeAsync(5000)
    })
    expect(listCalls).toBe(2)
  })

  it('列表为空时显示空态', async () => {
    mockFetch((url) => {
      if (url.startsWith('/api/v1/history?')) {
        return { status: 200, body: { items: [], total: 0, page: 1, page_size: 20 } }
      }
      return { status: 404, body: { error: 'x' } }
    })
    render(<HistoryPage />)
    expect(await screen.findByText('暂无历史记录')).toBeInTheDocument()
  })
})
