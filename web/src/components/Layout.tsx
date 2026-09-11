import { Link, NavLink, Outlet } from 'react-router-dom'
import { LogOut } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { useAuth } from '@/lib/auth'
import { cn } from '@/lib/utils'

// 受保护页面的顶部导航布局（shadcn + Tailwind）。
// 顶栏 sticky + 半透明磨砂，滚动时内容从下方穿过仍保持可读。
export function Layout() {
  const { email, logout } = useAuth()
  return (
    <div className="min-h-screen">
      <header className="sticky top-0 z-40 border-b border-border bg-background/85 backdrop-blur supports-[backdrop-filter]:bg-background/70">
        <div className="mx-auto flex h-14 w-full max-w-[960px] items-center gap-6 px-5">
          <Link
            to="/"
            className="inline-flex items-center gap-2 text-title font-heavy tracking-[-0.3px] text-foreground no-underline"
          >
            <img className="size-7 object-contain" src="/driftclip-logo.png" alt="" />
            <span>DriftClip</span>
          </Link>
          <nav className="flex flex-1 gap-1">
            {[
              { to: '/', label: '历史', end: true },
              { to: '/keys', label: 'Key 管理' },
              { to: '/settings', label: '设置' },
            ].map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) =>
                  cn(
                    'rounded-sm px-3 py-1.5 text-body-sm font-medium no-underline transition-colors duration-150',
                    isActive
                      ? 'bg-accent text-accent-foreground'
                      : 'text-muted-foreground hover:bg-secondary hover:text-foreground',
                  )
                }
              >
                {item.label}
              </NavLink>
            ))}
          </nav>
          <div className="flex items-center gap-2">
            <span className="hidden text-body-sm text-muted-foreground sm:inline">{email}</span>
            <Button variant="ghost" size="sm" onClick={() => void logout()}>
              <LogOut className="size-icon-sm" />
              退出
            </Button>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-[960px] px-5 pb-14 pt-7">
        <Outlet />
      </main>
    </div>
  )
}
