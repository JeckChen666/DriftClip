// 设置页：修改密码（需当前密码，成功后所有会话失效需重新登录）、退出登录。
import { useState } from 'react'
import type { FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ApiError, auth as authApi } from '@/lib/api'
import { useAuth } from '@/lib/auth'

export function SettingsPage() {
  const { logout } = useAuth()
  const navigate = useNavigate()
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function onChangePassword(e: FormEvent) {
    e.preventDefault()
    setError('')
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
    <section className="flex flex-col gap-5">
      <h1 className="text-display font-heavy tracking-[-0.4px] text-foreground m-0">
        设置
      </h1>

      <Card className="w-full max-w-[480px]">
        <CardHeader>
          <CardTitle>修改密码</CardTitle>
          <CardDescription>
            修改成功后当前浏览器的会话也会立即失效，需要重新登录。
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form
            className="flex flex-col gap-3.5"
            onSubmit={(e) => void onChangePassword(e)}
          >
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="settings-current-password">当前密码</Label>
              <Input
                id="settings-current-password"
                type="password"
                value={currentPassword}
                onChange={(e) => setCurrentPassword(e.target.value)}
                required
                autoComplete="current-password"
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="settings-new-password">新密码</Label>
              <Input
                id="settings-new-password"
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                required
                autoComplete="new-password"
              />
            </div>
            {error && (
              <p className="text-body-sm text-destructive" role="alert">
                {error}
              </p>
            )}
            <Button type="submit" disabled={busy} className="mt-1">
              {busy ? '提交中…' : '修改密码'}
            </Button>
          </form>
        </CardContent>
      </Card>

      <Card className="w-full max-w-[480px]">
        <CardHeader>
          <CardTitle>退出登录</CardTitle>
          <CardDescription>仅退出当前浏览器会话。</CardDescription>
        </CardHeader>
        <CardContent>
          <Button variant="outline" onClick={() => void onLogout()}>
            退出登录
          </Button>
        </CardContent>
      </Card>
    </section>
  )
}
