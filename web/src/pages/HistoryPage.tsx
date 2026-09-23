// 历史页：组合筛选（平台/正文/时间）、多选删除、清空全部（5s 确认）、
// 单条删除、复制、详情展开、手动刷新、自动刷新（localStorage）、分页。
import { useCallback, useEffect, useRef, useState } from 'react'
import {
  AlertCircle,
  ChevronDown,
  ChevronUp,
  ClipboardList,
  Copy,
  RefreshCw,
  Trash2,
} from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
import { Alert, AlertDescription } from '@/components/ui/alert'
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
import { Skeleton } from '@/components/ui/skeleton'
import { useToast } from '@/components/ui/toast'
import {
  ApiError,
  getAutoRefreshSeconds,
  history as historyApi,
  setAutoRefreshSeconds,
} from '@/lib/api'
import type { HistoryDetail, HistoryFilter, HistoryListItem } from '@/lib/api'
import { formatAbsolute, formatRelative } from '@/lib/time'
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
  const { toast } = useToast()
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
    const count = selected.size
    try {
      await historyApi.batchDelete([...selected])
      await load(page, appliedFilter.current)
      toast(`已删除 ${count} 条记录`)
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
      toast('已复制到剪贴板')
    } catch {
      toast('复制失败，浏览器未授予剪贴板权限', 'error')
    }
  }

  async function removeOne(id: number) {
    setError('')
    try {
      await historyApi.remove(id)
      await load(page, appliedFilter.current)
      toast('已删除 1 条记录')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : '删除失败')
    }
  }

  const allSelected = selected.size > 0 && selected.size === items.length

  return (
    <section className="flex flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2.5">
        <h1 className="text-display font-heavy tracking-[-0.4px] text-foreground m-0">
          历史
        </h1>
        <div className="flex flex-wrap items-center gap-2.5">
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
            <SelectTrigger
              className="h-control-md w-[136px] sm:w-[150px]"
              aria-label="自动刷新间隔"
            >
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
            <RefreshCw className={cn('size-icon-sm', loading && 'animate-spin')} />
            刷新
          </Button>
        </div>
      </div>

      {/* 筛选栏（Spec §6.2：组合筛选 AND 关系，正文匹配忽略英文字母大小写） */}
      <Card>
        <CardContent className="p-4">
          {/* 移动端：选择/搜索一行、两个时间一行、按钮一行自然换行；桌面保持单行。 */}
          <div className="flex flex-wrap items-center gap-2">
            <Select value={platform} onValueChange={setPlatform}>
              <SelectTrigger className="w-[132px] sm:w-[140px]" aria-label="平台筛选">
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
              className="min-w-0 flex-1"
            />
            <Input
              aria-label="起始时间"
              type="datetime-local"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
              className="min-w-0 flex-1 sm:w-[200px] sm:flex-none"
            />
            <Input
              aria-label="结束时间"
              type="datetime-local"
              value={to}
              onChange={(e) => setTo(e.target.value)}
              className="min-w-0 flex-1 sm:w-[200px] sm:flex-none"
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
        <Alert variant="destructive">
          <AlertCircle className="size-icon-md" />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
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
            <Trash2 className="size-icon-sm" />
            清空全部
          </Button>
        )}
      </div>

      {loading && items.length === 0 ? (
        // 首屏加载用骨架占位，内容到达后布局不跳动。
        <ul className="m-0 flex list-none flex-col gap-3 p-0" aria-busy="true">
          {Array.from({ length: 4 }).map((_, i) => (
            <li key={i}>
              <Card>
                <CardContent className="flex flex-col gap-3 p-4">
                  <div className="flex items-center gap-2">
                    <Skeleton className="size-4 rounded-xs" />
                    <Skeleton className="h-5 w-14 rounded-full" />
                    <Skeleton className="h-5 w-12 rounded-full" />
                    <Skeleton className="h-3.5 w-32" />
                  </div>
                  <Skeleton className="h-4 w-4/5" />
                  <Skeleton className="h-4 w-3/5" />
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      ) : items.length === 0 ? (
        <EmptyState
          icon={ClipboardList}
          title="暂无历史记录"
          hint="在任意已连接设备上复制内容，或调整上方筛选条件后再试。"
        />
      ) : (
        <ul className="m-0 flex list-none flex-col gap-3 p-0">
          {items.map((it) => {
            const expanded = expandedId === it.id
            const isSelected = selected.has(it.id)
            return (
              <li key={it.id}>
                <Card
                  className={cn(
                    'group transition-colors duration-150 hover:border-border-strong',
                    isSelected && 'border-primary/50 bg-accent/40',
                  )}
                >
                  <CardContent className="flex flex-col gap-2 p-4">
                    <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                      <Checkbox
                        aria-label={`选择记录 ${it.id}`}
                        checked={isSelected}
                        onCheckedChange={() => toggleSelect(it.id)}
                      />
                      <Badge variant="outline">{it.platform}</Badge>
                      <Badge variant={it.source === 'manual' ? 'manual' : 'primary'}>
                        {it.source === 'manual' ? '手动' : '剪贴板'}
                      </Badge>
                      {/* 时间与设备合并为一个可截断的整体，窄屏下省略而不是拆成两行。 */}
                      <span className="min-w-0 truncate text-caption text-muted-foreground tabular-nums">
                        {formatRelative(it.received_at)}
                        {(it.device_model || it.os_version) &&
                          ` · ${it.device_model || it.os_version}`}
                      </span>
                      {/* 操作区常驻在右上角，hover 时才浮现，保持列表安静。 */}
                      <div className="ml-auto flex items-center gap-0.5 opacity-60 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label="复制全文"
                          title="复制全文"
                          onClick={() => void copyFull(it.id)}
                        >
                          <Copy className="size-icon-sm" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="icon-sm"
                          aria-label="删除"
                          title="删除"
                          className="hover:bg-destructive-subtle hover:text-destructive"
                          onClick={() => void removeOne(it.id)}
                        >
                          <Trash2 className="size-icon-sm" />
                        </Button>
                      </div>
                    </div>
                    <div className="line-clamp-2 whitespace-pre-wrap break-words text-body text-foreground">
                      {it.content_preview}
                    </div>
                    <div>
                      <Button
                        variant="ghost"
                        size="xs"
                        className="-ml-2 text-muted-foreground"
                        onClick={() => void toggleDetail(it.id)}
                        aria-expanded={expanded}
                      >
                        {expanded ? (
                          <ChevronUp className="size-icon-sm" />
                        ) : (
                          <ChevronDown className="size-icon-sm" />
                        )}
                        {expanded ? '收起' : '详情'}
                      </Button>
                    </div>
                    {expanded && details[it.id] && (
                      <div className="mt-1 border-t border-dashed border-border pt-3">
                        <pre className="m-0 mb-2 whitespace-pre-wrap break-words rounded-md border border-border bg-secondary p-3 font-mono text-body-sm leading-relaxed">
                          {details[it.id].content}
                        </pre>
                        <dl className="m-0 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-caption text-muted-foreground">
                          <dt>来源</dt>
                          <dd className="m-0 text-foreground">{details[it.id].source}</dd>
                          <dt>接收时间</dt>
                          <dd className="m-0 text-foreground tabular-nums">
                            {formatAbsolute(details[it.id].received_at)}
                          </dd>
                          <dt>IP</dt>
                          <dd className="m-0 font-mono text-foreground">
                            {details[it.id].public_ip}
                          </dd>
                          <dt>平台</dt>
                          <dd className="m-0 text-foreground">{details[it.id].platform}</dd>
                          {details[it.id].device_model && (
                            <>
                              <dt>型号</dt>
                              <dd className="m-0 text-foreground">
                                {details[it.id].device_model}
                              </dd>
                            </>
                          )}
                          {details[it.id].os_version && (
                            <>
                              <dt>系统</dt>
                              <dd className="m-0 text-foreground">
                                {details[it.id].os_version}
                              </dd>
                            </>
                          )}
                          {details[it.id].app_version && (
                            <>
                              <dt>版本</dt>
                              <dd className="m-0 text-foreground">
                                {details[it.id].app_version}
                              </dd>
                            </>
                          )}
                        </dl>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </li>
            )
          })}
        </ul>
      )}

      {totalPages > 1 && (
        <nav
          className="mt-4 flex items-center justify-center gap-3"
          aria-label="分页"
        >
          <Button
            variant="outline"
            size="sm"
            disabled={page <= 1}
            onClick={() => void load(page - 1, appliedFilter.current)}
          >
            上一页
          </Button>
          <span className="text-body-sm text-muted-foreground tabular-nums">
            第 <span className="font-semibold text-foreground">{page}</span> / {totalPages} 页
          </span>
          <Button
            variant="outline"
            size="sm"
            disabled={page >= totalPages}
            onClick={() => void load(page + 1, appliedFilter.current)}
          >
            下一页
          </Button>
        </nav>
      )}
    </section>
  )
}
