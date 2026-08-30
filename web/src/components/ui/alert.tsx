import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'

import { cn } from '@/lib/utils'

const alertVariants = cva(
  'relative w-full rounded-md border px-3.5 py-2.5 text-body-sm [&>svg+div]:translate-y-[-3px] [&>svg]:absolute [&>svg]:left-3.5 [&>svg]:top-3 [&>svg]:text-foreground [&>svg~*]:pl-6',
  {
    variants: {
      variant: {
        default: 'bg-background text-foreground',
        warn: 'border-warn-border bg-warn-bg text-warn',
        destructive:
          'text-destructive [&>svg]:text-destructive',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  },
)

const Alert = React.forwardRef<
  HTMLDivElement,
  React.HTMLAttributes<HTMLDivElement> & VariantProps<typeof alertVariants>
>(({ className, variant, style, ...props }, ref) => {
  const isDestructive = variant === 'destructive'
  const destructiveStyle: React.CSSProperties | undefined = isDestructive
    ? {
        backgroundColor:
          'color-mix(in srgb, var(--danger) 10%, transparent)',
        borderColor:
          'color-mix(in srgb, var(--danger) 40%, transparent)',
        ...style,
      }
    : style
  return (
    <div
      ref={ref}
      role="alert"
      style={destructiveStyle}
      className={cn(
        alertVariants({ variant }),
        isDestructive && 'border',
        className,
      )}
      {...props}
    />
  )
})
Alert.displayName = 'Alert'

const AlertTitle = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLHeadingElement>
>(({ className, ...props }, ref) => (
  <h5
    ref={ref}
    className={cn('mb-0.5 font-semibold leading-none tracking-[-0.1px]', className)}
    {...props}
  />
))
AlertTitle.displayName = 'AlertTitle'

const AlertDescription = React.forwardRef<
  HTMLParagraphElement,
  React.HTMLAttributes<HTMLParagraphElement>
>(({ className, ...props }, ref) => (
  <div
    ref={ref}
    className={cn('text-body-sm [&_p]:leading-relaxed', className)}
    {...props}
  />
))
AlertDescription.displayName = 'AlertDescription'

export { Alert, AlertTitle, AlertDescription }
