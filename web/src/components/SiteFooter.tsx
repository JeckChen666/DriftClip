import { ExternalLink } from 'lucide-react'

import { cn } from '@/lib/utils'

// GitHub 开源仓库地址：页脚（登录页与主布局）共用。
export const REPO_URL = 'https://github.com/JeckChen666/DriftClip'

// 全站页脚：开源仓库入口，登录/注册页与主布局共用。
export function SiteFooter({ className }: { className?: string }) {
  return (
    <footer className={cn('w-full border-t border-border', className)}>
      <div className="mx-auto flex w-full max-w-[960px] flex-wrap items-center justify-between gap-x-4 gap-y-1 px-5 py-4 text-caption text-muted-foreground">
        <span>DriftClip · 跨设备剪贴板同步</span>
        <a
          className="inline-flex items-center gap-1 no-underline transition-colors duration-150 hover:text-foreground"
          href={REPO_URL}
          target="_blank"
          rel="noreferrer"
        >
          GitHub 开源仓库
          <ExternalLink className="size-3.5" />
        </a>
      </div>
    </footer>
  )
}
