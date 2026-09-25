import { act, fireEvent, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { mockFetch, unstubFetch } from '../test/helpers'
import { KeysPage } from './KeysPage'

afterEach(() => {
  vi.useRealTimers()
  unstubFetch()
})

describe('KeysPage', () => {
  it('无 Key 时生成并一次性展示完整 Key', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetch((url, init) => {
      if (url === '/api/v1/keys' && init?.method === 'POST') {
        return { status: 201, body: { key: 'dc_test_secret_key_123' } }
      }
      if (url === '/api/v1/keys') return { status: 200, body: { has_key: false } }
      return { status: 404, body: { error: 'x' } }
    })

    render(<KeysPage />)

    // 等 status() 解析后显示「生成初始 Key」
    const genBtn = await screen.findByRole('button', { name: '生成初始 Key' })
    await user.click(genBtn)

    // 完整 Key 只展示一次
    expect(await screen.findByText('dc_test_secret_key_123')).toBeInTheDocument()
    const postCall = fetchMock.mock.calls.find(
      ([u, init]) => u === '/api/v1/keys' && init?.method === 'POST',
    )
    expect(postCall).toBeDefined()
    const init = postCall![1] as RequestInit
    expect((init.headers as Record<string, string>)['X-Requested-With']).toBe('XMLHttpRequest')
  })

  it('重置需 5 秒倒计时，期间按钮不可点击（Spec §2.2）', async () => {
    vi.useFakeTimers()
    mockFetch((url, init) => {
      if (url === '/api/v1/keys/reset' && init?.method === 'POST') return { status: 200, body: { key: 'new_key' } }
      if (url === '/api/v1/keys') return { status: 200, body: { has_key: true } }
      return { status: 404, body: { error: 'x' } }
    })

    render(<KeysPage />)
    // 冲刷 status() 的异步解析（act 环境）
    await act(async () => {})

    const resetBtn = screen.getByRole('button', { name: '重置 Key' })
    fireEvent.click(resetBtn)

    // 倒计时期间按钮禁用并显示剩余秒数
    expect(screen.getByRole('button', { name: '重置 Key（5s）' })).toBeDisabled()

    // 走完 5 秒后出现可点击的「确认重置 Key」
    await act(async () => {
      await vi.advanceTimersByTimeAsync(6000)
    })
    const confirmBtn = screen.getByRole('button', { name: '确认重置 Key' })
    expect(confirmBtn).toBeEnabled()
    fireEvent.click(confirmBtn)
    await act(async () => {})
    expect(screen.getByText('new_key')).toBeInTheDocument()
  })

  it('已配置 Key 时可随时查看当前完整 Key 并展示复制按钮', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetch((url) => {
      if (url === '/api/v1/keys/secret') return { status: 200, body: { key: 'dc_current_key_456' } }
      if (url === '/api/v1/keys') return { status: 200, body: { has_key: true } }
      return { status: 404, body: { error: 'x' } }
    })

    render(<KeysPage />)
    const revealBtn = await screen.findByRole('button', { name: '查看 Key' })
    await user.click(revealBtn)

    expect(await screen.findByText('dc_current_key_456')).toBeInTheDocument()
    expect(screen.getByText('当前 Key')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '复制 Key' })).toBeInTheDocument()
    const revealCall = fetchMock.mock.calls.find(([u]) => u === '/api/v1/keys/secret')
    expect(revealCall).toBeDefined()
  })

  it('旧版本 Key（无加密副本）查看时展示服务端 409 提示', async () => {
    const user = userEvent.setup()
    mockFetch((url) => {
      if (url === '/api/v1/keys/secret')
        return { status: 409, body: { error: '该 Key 生成于旧版本，无法回显；重置后即可随时查看' } }
      if (url === '/api/v1/keys') return { status: 200, body: { has_key: true } }
      return { status: 404, body: { error: 'x' } }
    })

    render(<KeysPage />)
    const revealBtn = await screen.findByRole('button', { name: '查看 Key' })
    await user.click(revealBtn)

    expect(await screen.findByText(/生成于旧版本/)).toBeInTheDocument()
    expect(screen.queryByText('dc_current_key_456')).not.toBeInTheDocument()
  })
})
