// 注册页：注册成功即登录（P01 注册即建立会话）。
import { useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { ApiError } from '@/lib/api'
import { useAuth } from '@/lib/auth'

export function RegisterPage() {
  const { register } = useAuth()
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
      await register(email, password)
      navigate('/keys')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '注册失败，请稍后重试')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex justify-center pt-[10vh]">
      <Card className="w-full max-w-[400px]">
        <CardHeader>
          <CardTitle>注册 DriftClip</CardTitle>
          <CardDescription>
            注册后可登录 Web 生成访问 Key；设备客户端用 Key 同步历史。
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form className="flex flex-col gap-3.5" onSubmit={(e) => void onSubmit(e)}>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="register-email">邮箱</Label>
              <Input
                id="register-email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="username"
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="register-password">密码</Label>
              <Input
                id="register-password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                autoComplete="new-password"
              />
            </div>
            {error && (
              <p className="mt-2 text-body-sm text-destructive" role="alert">
                {error}
              </p>
            )}
            <Button type="submit" disabled={busy} className="mt-1">
              {busy ? '注册中…' : '注册'}
            </Button>
            <CardDescription className="text-center">
              已有账户？{' '}
              <Link to="/login" className="text-primary hover:underline">
                登录
              </Link>
            </CardDescription>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
