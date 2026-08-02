// 历史页：组合筛选（平台/正文/时间）、多选删除、清空全部（5s 确认）、
// 单条删除、复制、详情展开、手动刷新、自动刷新（localStorage）、分页。
import { useCallback, useEffect, useRef, useState } from 'react'
import { ApiError, getAutoRefreshSeconds, history as historyApi, setAutoRefreshSeconds } from '../lib/api'
import type { HistoryDetail, HistoryFilter, HistoryListItem } from '../lib/api'

const PAGE_SIZE = 20
const PLATFORMS = ['windows', 'macos', 'linux', 'android', 'ios'] as const

export function HistoryPage() {
  const [items, setItems] = useState<HistoryListItem[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [details, setDetails] = useState<Record<number, HistoryDetail>>({})
  const [expandedId, setExpandedId] = useState<number | null>(null)

  // 筛选条件
  const [platform, setPlatform] = useState('')
  const [q, setQ] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')

  // 多选
  const [selected, setSelected] = useState<Set<number>>(new Set())

  // 清空 5s 确认
  const [clearConfirming, setClearConfirming] = useState(false)
  const [clearCountdown, setClearCountdown] = useState(0)

  // 自动刷新间隔（秒），0 关闭
  const [autoRefresh, setAutoRefresh] = useState(getAutoRefreshSeconds)
  const appliedFilter = useRef<HistoryFilter>({})

  const load = useCallback(async (p: number, filter: HistoryFilter) => {
    setLoading(true)
    setError('')
    try {
      const res = await historyApi.list(p, PAGE_SIZE, filter)
      appliedFilter.current = filter
      setItems(res.items)
      setTotal(res.total)
      setPage(p)
      setExpandedId(null)
      setSelected(new Set())
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '加载失败')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load(1, {})
  }, [load])

  // 清空倒计时：确认开始从 5 倒数到 0，归零后保持确认态显示「确认清空全部」
  useEffect(() => {
    if (!clearConfirming) return
    setClearCountdown(5)
    const t = setInterval(() => setClearCountdown((c) => (c > 0 ? c - 1 : c)), 1000)
    return () => clearInterval(t)
  }, [clearConfirming])

  // 自动刷新：仅当间隔 > 0 时启动定时重载（Spec §6.3）
  useEffect(() => {
    if (autoRefresh <= 0) return
    const t = setInterval(() => {
      void load(page, appliedFilter.current)
    }, autoRefresh * 1000)
    return () => clearInterval(t)
  }, [autoRefresh, load, page])

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const buildFilter = (): HistoryFilter => ({
    platform: platform || undefined,
    q: q || undefined,
    from: from ? `${from}:00` : undefined, // datetime-local 为分钟精度，补秒（对齐 P01 时间解析）
    to: to ? `${to}:00` : undefined,
  })

  function applyFilter() {
    void load(1, buildFilter())
  }

  function resetFilter() {
    setPlatform('')
    setQ('')
    setFrom('')
    setTo('')
    void load(1, {})
  }

  function toggleSelect(id: number) {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }

  function toggleSelectAll() {
    setSelected((prev) => {
      if (prev.size === items.length) return new Set()
      return new Set(items.map((i) => i.id))
    })
  }

  async function deleteSelected() {
    setError('')
    try {
      await historyApi.batchDelete([...selected])
      await load(page, appliedFilter.current)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '批量删除失败')
    }
  }

  async function clearAll() {
    setError('')
    try {
      await historyApi.clear()
      setClearConfirming(false)
      setClearCountdown(0)
      await load(1, appliedFilter.current)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '清空失败')
    }
  }

  async function toggleDetail(id: number) {
    if (expandedId === id) {
      setExpandedId(null)
      return
    }
    if (!details[id]) {
      try {
        const d = await historyApi.get(id)
        setDetails((m) => ({ ...m, [id]: d }))
      } catch {
        // 详情加载失败仅不展开
      }
    }
    setExpandedId(id)
  }

  async function copyFull(id: number) {
    try {
      const d = details[id] ?? (await historyApi.get(id))
      await navigator.clipboard.writeText(d.content)
    } catch {
      // 剪贴板不可用时静默
    }
  }

  async function removeOne(id: number) {
    setError('')
    try {
      await historyApi.remove(id)
      await load(page, appliedFilter.current)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '删除失败')
    }
  }

  return (
    <section>
      <div className="page-head">
        <h1>历史</h1>
        <div className="actions">
          <span className="muted">共 {total} 条 · 第 {page}/{totalPages} 页</span>
          <select
            aria-label="自动刷新间隔"
            value={autoRefresh}
            onChange={(e) => {
              const v = Number(e.target.value)
              setAutoRefreshSeconds(v)
              setAutoRefresh(v)
            }}
          >
            <option value={0}>自动刷新：关闭</option>
            <option value={5}>自动刷新：5 秒</option>
            <option value={30}>自动刷新：30 秒</option>
            <option value={60}>自动刷新：1 分钟</option>
            <option value={300}>自动刷新：5 分钟</option>
          </select>
          <button onClick={() => void load(page, appliedFilter.current)} disabled={loading}>
            刷新
          </button>
        </div>
      </div>

      {/* 筛选栏（Spec §6.2：组合筛选 AND 关系，正文匹配忽略英文字母大小写） */}
      <div className="card filter-bar">
        <select
          aria-label="平台筛选"
          value={platform}
          onChange={(e) => setPlatform(e.target.value)}
        >
          <option value="">全部平台</option>
          {PLATFORMS.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
        <input
          aria-label="正文筛选"
          type="text"
          placeholder="正文包含…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <input
          aria-label="起始时间"
          type="datetime-local"
          value={from}
          onChange={(e) => setFrom(e.target.value)}
        />
        <input
          aria-label="结束时间"
          type="datetime-local"
          value={to}
          onChange={(e) => setTo(e.target.value)}
        />
        <button onClick={applyFilter}>应用</button>
        <button className="btn-link" onClick={resetFilter}>
          重置
        </button>
      </div>

      {error && <p className="error">{error}</p>}

      <div className="actions bulk-actions">
        <label className="muted select-all">
          <input
            type="checkbox"
            aria-label="全选"
            checked={selected.size > 0 && selected.size === items.length}
            onChange={toggleSelectAll}
          />
          全选
        </label>
        {selected.size > 0 && (
          <button onClick={() => void deleteSelected()}>
            删除所选（{selected.size}）
          </button>
        )}
        {clearConfirming ? (
          clearCountdown > 0 ? (
            <button disabled>清空全部（{clearCountdown}s）</button>
          ) : (
            <button className="danger-btn" onClick={() => void clearAll()}>
              确认清空全部
            </button>
          )
        ) : (
          <button className="danger-btn" onClick={() => setClearConfirming(true)}>
            清空全部
          </button>
        )}
      </div>

      {loading && items.length === 0 ? (
        <p className="muted">加载中…</p>
      ) : items.length === 0 ? (
        <p className="muted empty">暂无历史记录。</p>
      ) : (
        <ul className="history-list">
          {items.map((it) => (
            <li key={it.id} className="card record">
              <div className="record-head">
                <input
                  type="checkbox"
                  aria-label={`选择记录 ${it.id}`}
                  checked={selected.has(it.id)}
                  onChange={() => toggleSelect(it.id)}
                />
                <span className={`badge badge-${it.platform}`}>{it.platform}</span>
                <span className={`badge ${it.source === 'manual' ? 'badge-manual' : 'badge-clip'}`}>
                  {it.source === 'manual' ? '手动' : '剪贴板'}
                </span>
                <span className="muted">{it.received_at}</span>
                <span className="muted">{it.device_model || it.os_version || ''}</span>
              </div>
              <div className="record-preview">{it.content_preview}</div>
              <div className="record-actions">
                <button className="btn-link" onClick={() => void toggleDetail(it.id)}>
                  {expandedId === it.id ? '收起' : '详情'}
                </button>
                <button className="btn-link" onClick={() => void copyFull(it.id)}>
                  复制
                </button>
                <button className="btn-link danger" onClick={() => void removeOne(it.id)}>
                  删除
                </button>
              </div>
              {expandedId === it.id && details[it.id] && (
                <div className="record-detail">
                  <pre>{details[it.id].content}</pre>
                  <p className="muted">
                    来源：{details[it.id].source} · 接收时间：{details[it.id].received_at} · IP：
                    {details[it.id].public_ip} · 平台：{details[it.id].platform}
                    {details[it.id].device_model && ` · 型号：${details[it.id].device_model}`}
                    {details[it.id].os_version && ` · 系统：${details[it.id].os_version}`}
                    {details[it.id].app_version && ` · 版本：${details[it.id].app_version}`}
                  </p>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}

      {totalPages > 1 && (
        <div className="pager">
          <button disabled={page <= 1} onClick={() => void load(page - 1, appliedFilter.current)}>
            上一页
          </button>
          <button disabled={page >= totalPages} onClick={() => void load(page + 1, appliedFilter.current)}>
            下一页
          </button>
        </div>
      )}
    </section>
  )
}
