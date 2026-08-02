// Key 管理页：
//   - 无 Key 时提供「生成初始 Key」；
//   - 有 Key 时提供「重置 Key」，点击后 5 秒倒计时确认（Spec §2.2）；
//   - 完整 Key 只在生成/重置完成时展示一次，不缓存到本地存储。
import { useEffect, useState } from 'react'
import { ApiError, keys as keysApi } from '../lib/api'

export function KeysPage() {
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

  if (hasKey === null) {
    return <p className="muted">加载中…</p>
  }

  return (
    <section>
      <h1>Key 管理</h1>
      <p className="muted">
        原生客户端使用 Key 同步历史。完整 Key 只在生成或重置时展示一次，请立即保存；服务端不保存完整
        Key，遗失后只能重置。
      </p>

      {error && <p className="error">{error}</p>}

      <div className="card key-card">
        {hasKey ? (
          <>
            <p>
              Key 状态：<strong>已启用</strong>
            </p>
            <div className="actions">
              {confirming ? (
                countdown > 0 ? (
                  <button disabled>重置 Key（{countdown}s）</button>
                ) : (
                  <button onClick={() => void doReset()} disabled={busy}>
                    {busy ? '重置中…' : '确认重置 Key'}
                  </button>
                )
              ) : (
                <button onClick={() => setConfirming(true)}>重置 Key</button>
              )}
            </div>
          </>
        ) : (
          <div className="actions">
            <button onClick={() => void generate()} disabled={busy}>
              {busy ? '生成中…' : '生成初始 Key'}
            </button>
          </div>
        )}
      </div>

      {shownKey && (
        <div className="card key-once">
          <p className="warn">
            请立即复制并妥善保存以下完整 Key（只展示这一次）。服务端不保存完整 Key，遗失只能重置。
          </p>
          <code>{shownKey}</code>
          <div className="actions">
            <button onClick={() => void navigator.clipboard.writeText(shownKey)}>复制 Key</button>
          </div>
        </div>
      )}
    </section>
  )
}
