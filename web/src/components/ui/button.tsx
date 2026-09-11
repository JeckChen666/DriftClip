import * as React from 'react'
import { Slot } from '@radix-ui/react-slot'
import { cva, type VariantProps } from 'class-variance-authority'

import { cn } from '@/lib/utils'

const buttonVariants = cva(
  'inline-flex items-center justify-center gap-1.5 whitespace-nowrap rounded-md text-body font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 focus-visible:ring-offset-background disabled:pointer-events-none disabled:opacity-55 [&_svg]:shrink-0',
  {
    variants: {
      variant: {
        default:
          'bg-primary text-primary-foreground hover:bg-primary-hover active:bg-primary-deep',
        destructive:
          'bg-destructive text-destructive-foreground hover:bg-destructive-hover',
        outline:
          'border border-input bg-background text-foreground hover:border-border-strong hover:bg-secondary',
        secondary:
          'bg-secondary text-secondary-foreground hover:bg-secondary/80',
        ghost: 'text-muted-foreground hover:bg-secondary hover:text-foreground',
        link: 'text-primary hover:text-primary-hover underline-offset-2 hover:underline',
        danger:
          'border border-destructive/50 bg-background text-destructive hover:border-destructive hover:bg-destructive-subtle',
      },
      // 高度对齐 control 令牌刻度（32 / 36 / 40 / 44）。
      size: {
        xs: 'h-control-sm px-2.5 text-body-sm',
        sm: 'h-control-md px-3 text-body-sm',
        md: 'h-control-lg px-4 text-body',
        lg: 'h-control-xl px-5 text-body font-semibold',
        icon: 'h-control-md w-control-md',
        'icon-sm': 'h-control-sm w-control-sm',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'md',
    },
  },
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : 'button'
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    )
  },
)
Button.displayName = 'Button'

export { Button, buttonVariants }
