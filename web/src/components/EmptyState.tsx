import type { LucideIcon } from 'lucide-react'

import { cn } from '@/lib/utils'

interface EmptyStateProps {
  icon: LucideIcon
  title: string
  hint?: string
  action?: React.ReactNode
  className?: string
}

// 空状态：图标块 + 标题 + 提示 + 可选操作，替代裸文字，让“没有数据”也有层级。
export function EmptyState({ icon: Icon, title, hint, action, className }: EmptyStateProps) {
  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-border px-6 py-12 text-center',
        className,
      )}
    >
      <div className="mb-1 flex size-11 items-center justify-center rounded-lg bg-secondary text-muted-foreground">
        <Icon className="size-icon-xl" />
      </div>
      <p className="m-0 text-title-md text-foreground">{title}</p>
      {hint && <p className="m-0 max-w-[360px] text-body-sm text-muted-foreground">{hint}</p>}
      {action && <div className="mt-2">{action}</div>}
    </div>
  )
}
