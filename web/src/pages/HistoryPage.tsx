// 历史页：组合筛选（平台/正文/时间）、多选删除、清空全部（5s 确认）、
// 单条删除、复制、详情展开、手动刷新、自动刷新（localStorage）、分页。
import { useCallback, useEffect, useRef, useState } from 'react'
import { ChevronDown, ChevronUp, Loader2, RefreshCw, Trash2 } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Checkbox } from '@/components/ui/checkbox'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  ApiError,
  getAutoRefreshSeconds,
  history as historyApi,
  setAutoRefreshSeconds,
} from '@/lib/api'
import type { HistoryDetail, HistoryFilter, HistoryListItem } from '@/lib/api'
import { cn } from '@/lib/utils'

const PAGE_SIZE = 20
const PLATFORMS = ['windows', 'macos', 'linux', 'android', 'ios'] as const
const AUTO_REFRESH_OPTIONS = [
  { value: 0, label: '自动刷新：关闭' },
  { value: 5, label: '自动刷新：5 秒' },
  { value: 30, label: '自动刷新：30 秒' },
  { value: 60, label: '自动刷新：1 分钟' },
  { value: 300, label: '自动刷新：5 分钟' },
]

export function HistoryPage() {
  const [items, setItems] = useState<HistoryListItem[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [details, setDetails] = useState<Record<number, HistoryDetail>>({})
  const [expandedId, setExpandedId] = useState<number | null>(null)

  // 筛选条件
  const [platform, setPlatform] = useState('all')
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
    platform: platform === 'all' ? undefined : platform,
    q: q || undefined,
    from: from ? `${from}:00` : undefined, // datetime-local 为分钟精度，补秒（对齐 P01 时间解析）
    to: to ? `${to}:00` : undefined,
  })

  function applyFilter() {
    void load(1, buildFilter())
  }

  function resetFilter() {
    setPlatform('all')
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

  const allSelected = selected.size > 0 && selected.size === items.length

  return (
    <section className="flex flex-col gap-5">
      <div className="flex items-center justify-between gap-4">
        <h1 className="text-display font-heavy tracking-[-0.4px] text-foreground m-0">
          历史
        </h1>
        <div className="flex items-center gap-2.5">
          <span className="text-body-sm text-muted-foreground">
            共 {total} 条 · 第 {page}/{totalPages} 页
          </span>
          <Select
            value={String(autoRefresh)}
            onValueChange={(v) => {
              const n = Number(v)
              setAutoRefreshSeconds(n)
              setAutoRefresh(n)
            }}
          >
            <SelectTrigger className="h-9 w-[150px]" aria-label="自动刷新间隔">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {AUTO_REFRESH_OPTIONS.map((opt) => (
                <SelectItem key={opt.value} value={String(opt.value)}>
                  {opt.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button
            size="sm"
            onClick={() => void load(page, appliedFilter.current)}
            disabled={loading}
          >
            <RefreshCw className={cn('h-3.5 w-3.5', loading && 'animate-spin')} />
            刷新
          </Button>
        </div>
      </div>

      {/* 筛选栏（Spec §6.2：组合筛选 AND 关系，正文匹配忽略英文字母大小写） */}
      <Card>
        <CardContent className="pt-5">
          <div className="flex flex-wrap items-center gap-2">
            <Select value={platform} onValueChange={setPlatform}>
              <SelectTrigger className="w-[140px]" aria-label="平台筛选">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">全部平台</SelectItem>
                {PLATFORMS.map((p) => (
                  <SelectItem key={p} value={p}>
                    {p}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              aria-label="正文筛选"
              type="text"
              placeholder="正文包含…"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              className="flex-1 min-w-[160px]"
            />
            <Input
              aria-label="起始时间"
              type="datetime-local"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
              className="w-[200px]"
            />
            <Input
              aria-label="结束时间"
              type="datetime-local"
              value={to}
              onChange={(e) => setTo(e.target.value)}
              className="w-[200px]"
            />
            <Button onClick={applyFilter} size="sm">
              应用
            </Button>
            <Button variant="ghost" size="sm" onClick={resetFilter}>
              重置
            </Button>
          </div>
        </CardContent>
      </Card>

      {error && (
        <p className="text-body-sm text-destructive" role="alert">
          {error}
        </p>
      )}

      <div className="flex items-center gap-2.5">
        <label className="inline-flex cursor-pointer items-center gap-1.5 text-body-sm text-muted-foreground">
          <Checkbox
            aria-label="全选"
            checked={allSelected}
            onCheckedChange={toggleSelectAll}
          />
          全选
        </label>
        {selected.size > 0 && (
          <Button
            variant="outline"
            size="sm"
            onClick={() => void deleteSelected()}
          >
            删除所选（{selected.size}）
          </Button>
        )}
        {clearConfirming ? (
          clearCountdown > 0 ? (
            <Button variant="danger" size="sm" disabled>
              清空全部（{clearCountdown}s）
            </Button>
          ) : (
            <Button variant="danger" size="sm" onClick={() => void clearAll()}>
              确认清空全部
            </Button>
          )
        ) : (
          <Button
            variant="danger"
            size="sm"
            onClick={() => setClearConfirming(true)}
          >
            <Trash2 className="h-3.5 w-3.5" />
            清空全部
          </Button>
        )}
      </div>

      {loading && items.length === 0 ? (
        <p className="text-body-sm text-muted-foreground inline-flex items-center gap-2">
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
          加载中…
        </p>
      ) : items.length === 0 ? (
        <p className="py-10 text-center text-body-sm text-muted-foreground">
          暂无历史记录。
        </p>
      ) : (
        <ul className="flex flex-col gap-3 list-none m-0 p-0">
          {items.map((it) => (
            <li key={it.id}>
              <Card className="transition-colors hover:border-border-strong">
                <CardContent className="flex flex-col gap-2 p-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <Checkbox
                      aria-label={`选择记录 ${it.id}`}
                      checked={selected.has(it.id)}
                      onCheckedChange={() => toggleSelect(it.id)}
                    />
                    <Badge variant="outline">{it.platform}</Badge>
                    <Badge variant={it.source === 'manual' ? 'manual' : 'primary'}>
                      {it.source === 'manual' ? '手动' : '剪贴板'}
                    </Badge>
                    <span className="text-body-sm text-muted-foreground">
                      {it.received_at}
                    </span>
                    <span className="text-body-sm text-muted-foreground">
                      {it.device_model || it.os_version || ''}
                    </span>
                  </div>
                  <div className="text-body whitespace-pre-wrap break-words text-foreground">
                    {it.content_preview}
                  </div>
                  <div className="flex gap-2.5">
                    <Button
                      variant="link"
                      size="sm"
                      onClick={() => void toggleDetail(it.id)}
                      className="h-7 px-2"
                    >
                      {expandedId === it.id ? (
                        <ChevronUp className="h-3.5 w-3.5" />
                      ) : (
                        <ChevronDown className="h-3.5 w-3.5" />
                      )}
                      {expandedId === it.id ? '收起' : '详情'}
                    </Button>
                    <Button
                      variant="link"
                      size="sm"
                      onClick={() => void copyFull(it.id)}
                      className="h-7 px-2"
                    >
                      复制
                    </Button>
                    <Button
                      variant="link"
                      size="sm"
                      className="h-7 px-2 text-destructive hover:text-destructive"
                      onClick={() => void removeOne(it.id)}
                    >
                      删除
                    </Button>
                  </div>
                  {expandedId === it.id && details[it.id] && (
                    <div className="mt-1 border-t border-dashed border-border pt-3">
                      <pre className="m-0 mb-2 whitespace-pre-wrap break-words rounded-md border border-border bg-secondary p-3 text-body-sm">
                        {details[it.id].content}
                      </pre>
                      <p className="text-body-sm text-muted-foreground">
                        来源：{details[it.id].source} · 接收时间：
                        {details[it.id].received_at} · IP：
                        {details[it.id].public_ip} · 平台：
                        {details[it.id].platform}
                        {details[it.id].device_model &&
                          ` · 型号：${details[it.id].device_model}`}
                        {details[it.id].os_version &&
                          ` · 系统：${details[it.id].os_version}`}
                        {details[it.id].app_version &&
                          ` · 版本：${details[it.id].app_version}`}
                      </p>
                    </div>
                  )}
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}

      {totalPages > 1 && (
        <div className="mt-6 flex justify-center gap-2.5">
          <Button
            variant="outline"
            size="sm"
            disabled={page <= 1}
            onClick={() => void load(page - 1, appliedFilter.current)}
          >
            上一页
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={page >= totalPages}
            onClick={() => void load(page + 1, appliedFilter.current)}
          >
            下一页
          </Button>
        </div>
      )}
    </section>
  )
}
