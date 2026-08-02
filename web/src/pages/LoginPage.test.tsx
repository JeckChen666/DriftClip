import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it } from 'vitest'
import { AuthProvider } from '../lib/auth'
import { mockFetch, unstubFetch } from '../test/helpers'
import { LoginPage } from './LoginPage'

afterEach(() => unstubFetch())

describe('LoginPage', () => {
  it('提交登录时调用 API 并携带 CSRF 头与正确载荷', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetch((url) => {
      if (url === '/api/v1/auth/me') return { status: 401, body: { error: '未登录' } }
      if (url === '/api/v1/auth/login') return { status: 200, body: { email: 'a@b.com' } }
      return { status: 404, body: { error: 'not found' } }
    })

    render(
      <MemoryRouter>
        <AuthProvider>
          <LoginPage />
        </AuthProvider>
      </MemoryRouter>,
    )

    await user.type(screen.getByLabelText('邮箱'), 'a@b.com')
    await user.type(screen.getByLabelText('密码'), 'pw123')
    await user.click(screen.getByRole('button', { name: '登录' }))

    const loginCall = fetchMock.mock.calls.find(([u]) => u === '/api/v1/auth/login')
    expect(loginCall).toBeDefined()
    const init = loginCall![1] as RequestInit
    expect((init.headers as Record<string, string>)['X-Requested-With']).toBe('XMLHttpRequest')
    expect(JSON.parse(init.body as string)).toEqual({ email: 'a@b.com', password: 'pw123' })
  })

  it('登录失败展示服务端错误', async () => {
    const user = userEvent.setup()
    mockFetch((url) => {
      if (url === '/api/v1/auth/me') return { status: 401, body: { error: '未登录' } }
      return { status: 401, body: { error: '邮箱或密码错误' } }
    })
    render(
      <MemoryRouter>
        <AuthProvider>
          <LoginPage />
        </AuthProvider>
      </MemoryRouter>,
    )
    await user.type(screen.getByLabelText('邮箱'), 'a@b.com')
    await user.type(screen.getByLabelText('密码'), 'wrong')
    await user.click(screen.getByRole('button', { name: '登录' }))
    expect(await screen.findByText('邮箱或密码错误')).toBeInTheDocument()
  })
})
