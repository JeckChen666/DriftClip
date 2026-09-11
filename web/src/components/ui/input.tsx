import * as React from 'react'

import { cn } from '@/lib/utils'

export interface InputProps
  extends React.InputHTMLAttributes<HTMLInputElement> {}

const Input = React.forwardRef<HTMLInputElement, InputProps>(
  ({ className, type, ...props }, ref) => {
    return (
      <input
        type={type}
        className={cn(
          'flex h-control-lg w-full rounded-md border border-input bg-field-fill px-3 py-2 text-body text-foreground placeholder:text-muted-foreground/70',
          'transition-colors duration-150 hover:border-border-strong focus-visible:outline-none focus-visible:border-primary focus-visible:ring-2 focus-visible:ring-ring/60',
          'disabled:cursor-not-allowed disabled:opacity-55',
          'file:border-0 file:bg-transparent file:text-body-sm file:font-medium',
          className,
        )}
        ref={ref}
        {...props}
      />
    )
  },
)
Input.displayName = 'Input'

export { Input }
