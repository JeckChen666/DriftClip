import { Link, NavLink, Outlet } from 'react-router-dom'
import { LogOut } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { useAuth } from '@/lib/auth'
import { cn } from '@/lib/utils'

// 受保护页面的顶部导航布局（shadcn + Tailwind）。
export function Layout() {
  const { email, logout } = useAuth()
  return (
    <div className="mx-auto w-full max-w-[960px] px-5 pb-14">
      <header className="flex items-center gap-7 border-b border-border py-4 mb-7">
        <Link
          to="/"
          className="inline-flex items-center gap-2 text-[18px] font-heavy tracking-[-0.3px] text-primary no-underline"
        >
          <img className="h-7 w-7 object-contain" src="/driftclip-logo.png" alt="" />
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
                  'rounded-md px-3 py-1.5 text-body-sm font-medium no-underline transition-colors',
                  isActive
                    ? 'bg-secondary text-foreground font-semibold'
                    : 'text-muted-foreground hover:bg-secondary hover:text-foreground',
                )
              }
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
        <div className="flex items-center gap-3">
          <span className="text-body-sm text-muted-foreground">{email}</span>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => void logout()}
            className="gap-1.5"
          >
            <LogOut className="h-3.5 w-3.5" />
            退出
          </Button>
        </div>
      </header>
      <main>
        <Outlet />
      </main>
    </div>
  )
}
