// 登录态上下文：启动时用 /auth/me 判定登录态，提供 login/register/logout。
import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import type { ReactNode } from 'react'
import { auth as authApi } from './api'

interface AuthState {
  email: string | null
  loading: boolean
  login: (email: string, password: string) => Promise<void>
  register: (email: string, password: string) => Promise<void>
  logout: () => Promise<void>
}

const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [email, setEmail] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    authApi
      .me()
      .then((m) => setEmail(m.email))
      .catch(() => setEmail(null))
      .finally(() => setLoading(false))
  }, [])

  const login = useCallback(async (em: string, pw: string) => {
    const m = await authApi.login(em, pw)
    setEmail(m.email)
  }, [])

  const register = useCallback(async (em: string, pw: string) => {
    const m = await authApi.register(em, pw)
    setEmail(m.email)
  }, [])

  const logout = useCallback(async () => {
    await authApi.logout()
    setEmail(null)
  }, [])

  return (
    <AuthContext.Provider value={{ email, loading, login, register, logout }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth 必须在 AuthProvider 内使用')
  return ctx
}
