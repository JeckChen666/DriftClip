// 轻量 Toast：基于 @radix-ui/react-toast，只暴露一个 `toast(message)`。
// 用于复制成功、删除完成等瞬时反馈，替代页面里“文字替换”式的提示。
import * as React from 'react'
import * as ToastPrimitive from '@radix-ui/react-toast'
import { CheckCircle2, AlertCircle, X } from 'lucide-react'

import { cn } from '@/lib/utils'

type ToastKind = 'success' | 'error'

interface ToastItem {
  id: number
  message: string
  kind: ToastKind
}

interface ToastContextValue {
  toast: (message: string, kind?: ToastKind) => void
}

const ToastContext = React.createContext<ToastContextValue | null>(null)

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = React.useState<ToastItem[]>([])
  const seq = React.useRef(0)

  const toast = React.useCallback((message: string, kind: ToastKind = 'success') => {
    seq.current += 1
    setItems((prev) => [...prev, { id: seq.current, message, kind }])
  }, [])

  const dismiss = (id: number) => setItems((prev) => prev.filter((t) => t.id !== id))

  return (
    <ToastContext.Provider value={{ toast }}>
      <ToastPrimitive.Provider swipeDirection="right" duration={2200}>
        {children}
        {items.map((t) => (
          <ToastPrimitive.Root
            key={t.id}
            onOpenChange={(open) => !open && dismiss(t.id)}
            className={cn(
              'group pointer-events-auto flex items-center gap-2.5 rounded-md border border-border bg-popover px-3.5 py-2.5 text-body-sm text-popover-foreground shadow-soft',
              'data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom-2 data-[state=open]:fade-in-0',
              'data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:slide-out-to-right-2',
              'data-[swipe=move]:translate-x-[var(--radix-toast-swipe-move-x)] data-[swipe=end]:animate-out',
            )}
          >
            {t.kind === 'success' ? (
              <CheckCircle2 className="size-icon-md shrink-0 text-success" />
            ) : (
              <AlertCircle className="size-icon-md shrink-0 text-destructive" />
            )}
            <ToastPrimitive.Description className="flex-1">
              {t.message}
            </ToastPrimitive.Description>
            <ToastPrimitive.Close
              aria-label="关闭"
              className="rounded-xs p-0.5 text-muted-foreground opacity-0 transition-opacity hover:text-foreground group-hover:opacity-100 focus-visible:opacity-100"
            >
              <X className="size-icon-sm" />
            </ToastPrimitive.Close>
          </ToastPrimitive.Root>
        ))}
        <ToastPrimitive.Viewport className="fixed bottom-5 right-5 z-50 flex w-[320px] max-w-[calc(100vw-40px)] flex-col gap-2 outline-none" />
      </ToastPrimitive.Provider>
    </ToastContext.Provider>
  )
}

// 无 Provider 时退化为空操作：页面在单测或独立渲染时不因缺少 Toast 而崩溃。
const noopToast: ToastContextValue = { toast: () => {} }

export function useToast(): ToastContextValue {
  return React.useContext(ToastContext) ?? noopToast
}
