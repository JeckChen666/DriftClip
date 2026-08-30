// 受保护页面的顶部导航布局。
import { Link, NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../lib/auth'

export function Layout() {
  const { email, logout } = useAuth()
  return (
    <div className="app">
      <header className="topbar">
        <Link to="/" className="brand">
          <img className="brand-mark" src="/driftclip-logo.png" alt="" />
          <span>DriftClip</span>
        </Link>
        <nav>
          <NavLink to="/" end>
            历史
          </NavLink>
          <NavLink to="/keys">Key 管理</NavLink>
          <NavLink to="/settings">设置</NavLink>
        </nav>
        <div className="topbar-right">
          <span className="muted">{email}</span>
          <button className="btn-link" onClick={() => void logout()}>
            退出
          </button>
        </div>
      </header>
      <main className="content">
        <Outlet />
      </main>
    </div>
  )
}
