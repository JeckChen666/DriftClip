// Key 管理页：
//   - 无 Key 时提供「生成初始 Key」；
//   - 有 Key 时提供「重置 Key」，点击后 5 秒倒计时确认（Spec §2.2）；
//   - 完整 Key 只在生成/重置完成时展示一次，不缓存到本地存储。
import { useEffect, useState } from 'react'
import { AlertCircle, Copy, KeyRound, ShieldCheck } from 'lucide-react'

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'
import { useToast } from '@/components/ui/toast'
import { ApiError, keys as keysApi } from '@/lib/api'

export function KeysPage() {
  const { toast } = useToast()
  const [hasKey, setHasKey] = useState<boolean | null>(null)
  const [shownKey, setShownKey] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [countdown, setCountdown] = useState(0)

  useEffect(() => {
    keysApi
      .status()
      .then((s) => setHasKey(s.has_key))
      .catch(() => setError('加载 Key 状态失败'))
  }, [])

  // 倒计时：确认开始时从 5 倒数到 0（下限 0）。归零后保持确认态，
  // 显示「确认重置 Key」按钮（Spec §2.2：重置按钮在 5 秒倒计时结束前不可点击）。
  useEffect(() => {
    if (!confirming) return
    setCountdown(5)
    const t = setInterval(() => setCountdown((c) => (c > 0 ? c - 1 : c)), 1000)
    return () => clearInterval(t)
  }, [confirming])

  async function generate() {
    setBusy(true)
    setError('')
    setShownKey('')
    try {
      const r = await keysApi.generate()
      setShownKey(r.key)
      setHasKey(true)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '生成 Key 失败')
    } finally {
      setBusy(false)
    }
  }

  async function doReset() {
    setBusy(true)
    setError('')
    setShownKey('')
    try {
      const r = await keysApi.reset()
      setShownKey(r.key)
      setHasKey(true)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '重置 Key 失败')
    } finally {
      setBusy(false)
    }
  }

  async function copyShown() {
    try {
      await navigator.clipboard.writeText(shownKey)
      toast('Key 已复制到剪贴板')
    } catch {
      toast('复制失败，请手动选中复制', 'error')
    }
  }

  if (hasKey === null) {
    return (
      <section className="flex flex-col gap-5" aria-busy="true">
        <div className="flex flex-col gap-2">
          <Skeleton className="h-7 w-28" />
          <Skeleton className="h-4 w-3/4" />
        </div>
        <Card>
          <CardHeader>
            <Skeleton className="h-5 w-40" />
            <Skeleton className="h-4 w-64" />
          </CardHeader>
          <CardContent>
            <Skeleton className="h-control-lg w-28 rounded-md" />
          </CardContent>
        </Card>
      </section>
    )
  }

  return (
    <section className="flex flex-col gap-5">
      <div>
        <h1 className="text-display font-heavy tracking-[-0.4px] text-foreground m-0">
          Key 管理
        </h1>
        <p className="mt-1.5 text-body-sm text-muted-foreground">
          原生客户端使用 Key 同步历史。完整 Key 只在生成或重置时展示一次，请立即保存；服务端不保存完整
          Key，遗失后只能重置。
        </p>
      </div>

      {error && (
        <Alert variant="destructive">
          <AlertCircle className="size-icon-md" />
          <AlertTitle>出错了</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <span
              className={
                hasKey
                  ? 'inline-flex size-7 items-center justify-center rounded-sm bg-success/10 text-success'
                  : 'inline-flex size-7 items-center justify-center rounded-sm bg-secondary text-muted-foreground'
              }
            >
              {hasKey ? <ShieldCheck className="size-icon-md" /> : <KeyRound className="size-icon-md" />}
            </span>
            {hasKey ? 'Key 状态：已启用' : '尚未生成 Key'}
          </CardTitle>
          {hasKey && (
            <CardDescription>
              现有 Key 仍可同步客户端；重置会立即作废旧 Key。
            </CardDescription>
          )}
        </CardHeader>
        <CardContent>
          {hasKey ? (
            <div className="flex items-center gap-2">
              {confirming ? (
                countdown > 0 ? (
                  <Button disabled variant="danger">
                    重置 Key（{countdown}s）
                  </Button>
                ) : (
                  <Button onClick={() => void doReset()} disabled={busy} variant="danger">
                    {busy ? '重置中…' : '确认重置 Key'}
                  </Button>
                )
              ) : (
                <Button onClick={() => setConfirming(true)} variant="outline">
                  重置 Key
                </Button>
              )}
            </div>
          ) : (
            <Button onClick={() => void generate()} disabled={busy}>
              {busy ? '生成中…' : '生成初始 Key'}
            </Button>
          )}
        </CardContent>
      </Card>

      {shownKey && (
        <Card>
          <CardHeader>
            <CardTitle>新的 Key</CardTitle>
            <CardDescription>
              请立即复制并妥善保存以下完整 Key（只展示这一次）。服务端不保存完整 Key，遗失只能重置。
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            <code className="block select-all break-all rounded-md border border-warn-border bg-warn-bg px-3 py-3 font-mono text-body-sm text-warn">
              {shownKey}
            </code>
            <div>
              <Button onClick={() => void copyShown()} size="sm">
                <Copy className="size-icon-sm" />
                复制 Key
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </section>
  )
}
