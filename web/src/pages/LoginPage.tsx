// 登录页：邮箱 + 密码，成功跳转历史页。
import { useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ApiError } from '@/lib/api'
import { useAuth } from '@/lib/auth'

export function LoginPage() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setError('')
    setBusy(true)
    try {
      await login(email, password)
      navigate('/')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '登录失败，请稍后重试')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex justify-center pt-[10vh]">
      <Card className="w-full max-w-[400px]">
        <CardHeader>
          <CardTitle>登录 DriftClip</CardTitle>
        </CardHeader>
        <CardContent>
          <form className="flex flex-col gap-3.5" onSubmit={(e) => void onSubmit(e)}>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="login-email">邮箱</Label>
              <Input
                id="login-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="username"
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="login-password">密码</Label>
              <Input
                id="login-password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                autoComplete="current-password"
              />
            </div>
            {error && (
              <p className="mt-2 text-body-sm text-destructive" role="alert">
                {error}
              </p>
            )}
            <Button type="submit" disabled={busy} className="mt-1">
              {busy ? '登录中…' : '登录'}
            </Button>
            <CardDescription className="text-center">
              还没有账户？{' '}
              <Link to="/register" className="text-primary hover:underline">
                注册
              </Link>
            </CardDescription>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
