import * as React from 'react'

import { cn } from '@/lib/utils'

// 骨架屏：加载时先占住布局，避免内容到达后整页跳动。
function Skeleton({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn('animate-pulse rounded-sm bg-secondary', className)}
      {...props}
    />
  )
}

export { Skeleton }
