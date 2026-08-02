import { render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, describe, expect, it } from 'vitest'
import { AuthProvider } from '../lib/auth'
import { mockFetch, unstubFetch } from '../test/helpers'
import { LoginPage } from '../pages/LoginPage'
import { RequireAuth } from './RequireAuth'

afterEach(() => unstubFetch())

describe('RequireAuth', () => {
  it('未登录访问受保护路由跳转登录页', async () => {
    // /auth/me 返回 401 → 视为未登录
    mockFetch(() => ({ status: 401, body: { error: '未登录' } }))

    render(
      <MemoryRouter initialEntries={['/keys']}>
        <AuthProvider>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route element={<RequireAuth />}>
              <Route path="/keys" element={<div>受保护的 Key 页</div>} />
            </Route>
          </Routes>
        </AuthProvider>
      </MemoryRouter>,
    )

    // 未登录不应渲染受保护页，而是落在登录页
    expect(await screen.findByText('登录 DriftClip')).toBeInTheDocument()
    expect(screen.queryByText('受保护的 Key 页')).not.toBeInTheDocument()
  })
})
