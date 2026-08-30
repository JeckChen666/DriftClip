import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'

import { cn } from '@/lib/utils'

const badgeVariants = cva(
  'inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-caption font-medium transition-colors',
  {
    variants: {
      variant: {
        default:
          'border-transparent bg-secondary text-secondary-foreground',
        primary:
          'border-transparent bg-accent text-accent-foreground',
        outline: 'border-border text-muted-foreground bg-secondary',
        success:
          'text-success',
        danger:
          'text-destructive',
        manual:
          'border-accent-purple-border/40 text-accent-purple',
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

function Badge({ className, variant, style, ...props }: BadgeProps) {
  const tint =
    variant === 'danger'
      ? {
          backgroundColor:
            'color-mix(in srgb, var(--danger) 10%, transparent)',
        }
      : variant === 'success'
        ? {
            backgroundColor:
              'color-mix(in srgb, var(--success) 10%, transparent)',
          }
        : variant === 'manual'
          ? {
              backgroundColor:
                'color-mix(in srgb, var(--accent-purple-text) 8%, transparent)',
            }
          : undefined
  return (
    <span
      className={cn(badgeVariants({ variant }), className)}
      style={{ ...tint, ...style }}
      {...props}
    />
  )
}

export { Badge, badgeVariants }
