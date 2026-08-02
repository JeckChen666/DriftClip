// 路由守卫：未登录跳转登录页。
import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '../lib/auth'

export function RequireAuth() {
  const { email, loading } = useAuth()
  if (loading) {
    return <div className="center muted">加载中…</div>
  }
  if (!email) {
    return <Navigate to="/login" replace />
  }
  return <Outlet />
}
