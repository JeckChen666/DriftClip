// 时间展示：近期记录用相对时间（与原生客户端一致），久远记录退回日期。
// 服务端返回带时区的 ISO 串，Date 解析后按浏览器本地时区展示。

export function formatRelative(iso: string, now: Date = new Date()): string {
  const t = new Date(iso)
  if (Number.isNaN(t.getTime())) return iso
  const seconds = Math.max(0, Math.floor((now.getTime() - t.getTime()) / 1000))
  if (seconds < 60) return '刚刚'
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟前`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} 小时前`
  if (seconds < 7 * 86400) return `${Math.floor(seconds / 86400)} 天前`
  const y = t.getFullYear() === now.getFullYear()
  const pad = (n: number) => String(n).padStart(2, '0')
  const date = `${y ? '' : t.getFullYear() + '/'}${pad(t.getMonth() + 1)}-${pad(t.getDate())}`
  return `${date} ${pad(t.getHours())}:${pad(t.getMinutes())}`
}

// 详情等精确场景：本地时区的完整时间戳（到秒）。
export function formatAbsolute(iso: string): string {
  const t = new Date(iso)
  if (Number.isNaN(t.getTime())) return iso
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())} ${pad(t.getHours())}:${pad(t.getMinutes())}:${pad(t.getSeconds())}`
}
