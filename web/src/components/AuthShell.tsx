import type { ReactNode } from 'react'

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'

interface AuthShellProps {
  title: string
  description?: string
  footer?: ReactNode
  children: ReactNode
}

// 登录 / 注册共用外壳：品牌标识 + 居中卡片 + 底部切换链接。
// 两页只差表单内容与文案，抽出来保证视觉一致。
export function AuthShell({ title, description, footer, children }: AuthShellProps) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-start px-5 pb-12 pt-[12vh]">
      <div className="mb-6 inline-flex items-center gap-2.5 text-title font-heavy tracking-[-0.3px] text-foreground">
        <img className="size-8 object-contain" src="/driftclip-logo.png" alt="" />
        <span>DriftClip</span>
      </div>
      <Card className="w-full max-w-[400px] shadow-soft">
        <CardHeader className="pb-4">
          <CardTitle>{title}</CardTitle>
          {description && <CardDescription>{description}</CardDescription>}
        </CardHeader>
        <CardContent>{children}</CardContent>
      </Card>
      {footer && <p className="mt-5 text-body-sm text-muted-foreground">{footer}</p>}
    </div>
  )
}
