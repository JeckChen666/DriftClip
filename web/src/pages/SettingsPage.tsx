// 设置页：修改密码（需当前密码，成功后所有会话失效需重新登录）、退出登录。
import { useState } from 'react'
import type { FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { ApiError, auth as authApi } from '../lib/api'
import { useAuth } from '../lib/auth'

export function SettingsPage() {
  const { logout } = useAuth()
  const navigate = useNavigate()
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [error, setError] = useState('')
  const [ok, setOk] = useState('')
  const [busy, setBusy] = useState(false)

  async function onChangePassword(e: FormEvent) {
    e.preventDefault()
    setError('')
    setOk('')
    setBusy(true)
    try {
      await authApi.changePassword(currentPassword, newPassword)
      // 改密后所有 Web 会话立即失效（Spec §2.3），跳转登录
      navigate('/login')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '修改密码失败')
    } finally {
      setBusy(false)
    }
  }

  async function onLogout() {
    await logout()
    navigate('/login')
  }

  return (
    <section>
      <h1>设置</h1>

      <form className="card auth-card" onSubmit={(e) => void onChangePassword(e)}>
        <h2>修改密码</h2>
        <p className="muted">修改成功后当前浏览器的会话也会立即失效，需要重新登录。</p>
        <label>
          当前密码
          <input
            type="password"
            value={currentPassword}
            onChange={(e) => setCurrentPassword(e.target.value)}
            required
            autoComplete="current-password"
          />
        </label>
        <label>
          新密码
          <input
            type="password"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            required
            autoComplete="new-password"
          />
        </label>
        {error && <p className="error">{error}</p>}
        {ok && <p className="ok">{ok}</p>}
        <button type="submit" disabled={busy}>
          {busy ? '提交中…' : '修改密码'}
        </button>
      </form>

      <div className="card auth-card">
        <h2>退出登录</h2>
        <p className="muted">仅退出当前浏览器会话。</p>
        <button onClick={() => void onLogout()}>退出登录</button>
      </div>
    </section>
  )
}
