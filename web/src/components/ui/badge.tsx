import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'

import { cn } from '@/lib/utils'

// 色彩全部走令牌 utility，不再用内联 color-mix；
// 淡底用 /10 透明度叠加，亮暗色下都能自洽。
const badgeVariants = cva(
  'inline-flex items-center gap-1 rounded-full border px-2 py-px text-caption font-medium leading-[1.5] transition-colors',
  {
    variants: {
      variant: {
        default: 'border-transparent bg-secondary text-secondary-foreground',
        primary: 'border-transparent bg-accent text-accent-foreground',
        outline: 'border-border bg-transparent text-muted-foreground',
        success: 'border-success/25 bg-success/10 text-success',
        danger:
          'border-destructive/25 bg-destructive-subtle text-destructive-subtle-foreground',
        manual:
          'border-accent-purple-border/50 bg-accent-purple/10 text-accent-purple',
      },
    },
    defaultVariants: {
      variant: 'outline',
    },
  },
)

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />
}

export { Badge, badgeVariants }
