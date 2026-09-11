/** @type {import('tailwindcss').Config} */
//
// 颜色/尺寸统一从 CSS 变量（由 tokens/tokens.json 经 tool/sync_tokens.dart 产出）注入。
// 这样 Tailwind 的 utility class（bg-background / text-foreground / border-border 等）会
// 自动复用现有 token；改 tokens.json → 重跑 make tokens → 两端一致。
//
// 命名约定按 shadcn 习惯：background / foreground / primary / muted / accent / destructive /
// border / input / ring。实际值仍然来自我们的 design tokens。
// 令牌是 CSS 变量，Tailwind 无法直接给它加 /40 这类透明度修饰符（会静默忽略）。
// 用 color-mix 把 <alpha-value> 折算成百分比，让 bg-destructive/10 之类真正生效。
const alpha = (v) =>
  `color-mix(in srgb, var(${v}) calc(<alpha-value> * 100%), transparent)`

export default {
  // 实际主题切换由 tokens.generated.css 的 prefers-color-scheme 媒体查询驱动，
  // 没有手动切换开关，这里保持一致用 media，避免 dark: 前缀静默失效。
  darkMode: 'media',
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    container: {
      center: true,
      padding: '1.25rem',
      screens: { '2xl': '960px' },
    },
    extend: {
      colors: {
        border: {
          DEFAULT: 'var(--border)',
          strong: 'var(--border-strong)',
        },
        input: 'var(--border)',
        ring: alpha('--ring'),
        background: alpha('--canvas'),
        foreground: alpha('--text-primary'),
        surface: 'var(--surface)',
        'field-fill': 'var(--field-fill)',
        primary: {
          DEFAULT: alpha('--accent'),
          foreground: 'var(--on-accent)',
          hover: 'var(--accent-hover)',
          deep: 'var(--accent-deep)',
        },
        secondary: {
          DEFAULT: alpha('--surface-subtle'),
          foreground: 'var(--text-primary)',
        },
        destructive: {
          DEFAULT: alpha('--danger'),
          foreground: 'var(--on-danger)',
          hover: 'var(--danger-hover)',
          subtle: 'var(--danger-subtle)',
          'subtle-foreground': 'var(--on-danger-subtle)',
        },
        muted: {
          DEFAULT: 'var(--surface-subtle)',
          foreground: alpha('--text-muted'),
        },
        accent: {
          DEFAULT: 'var(--accent-subtle)',
          foreground: 'var(--on-accent-subtle)',
        },
        popover: {
          DEFAULT: 'var(--surface)',
          foreground: 'var(--text-primary)',
        },
        card: {
          DEFAULT: 'var(--surface)',
          foreground: 'var(--text-primary)',
        },
        success: alpha('--success'),
        warn: {
          DEFAULT: 'var(--warn-text)',
          bg: 'var(--warn-bg)',
          border: 'var(--warn-border)',
        },
        'accent-purple': {
          DEFAULT: alpha('--accent-purple-text'),
          border: alpha('--accent-purple-border'),
        },
        platform: {
          gray: 'var(--platform-gray)',
          blue: 'var(--platform-blue)',
          amber: 'var(--platform-amber)',
          green: 'var(--platform-green)',
          teal: 'var(--platform-teal)',
          purple: 'var(--platform-purple)',
          neutral: 'var(--platform-neutral)',
        },
      },
      borderRadius: {
        xl: 'var(--radius-xl)',
        lg: 'var(--radius-lg)',
        md: 'var(--radius-md)',
        sm: 'var(--radius-sm)',
        xs: 'var(--radius-xs)',
      },
      // 控件高度与图标尺寸对齐令牌刻度，用 h-control-* / size-icon-* 引用。
      height: {
        'control-sm': 'var(--control-sm)',
        'control-md': 'var(--control-md)',
        'control-lg': 'var(--control-lg)',
        'control-xl': 'var(--control-xl)',
      },
      width: {
        'control-sm': 'var(--control-sm)',
        'control-md': 'var(--control-md)',
        'control-lg': 'var(--control-lg)',
      },
      size: {
        'icon-sm': 'var(--icon-sm)',
        'icon-md': 'var(--icon-md)',
        'icon-lg': 'var(--icon-lg)',
        'icon-xl': 'var(--icon-xl)',
      },
      fontSize: {
        display: ['22px', { lineHeight: '1.3', letterSpacing: '-0.4px', fontWeight: '800' }],
        title: ['16px', { lineHeight: '1.4', letterSpacing: '-0.2px', fontWeight: '700' }],
        'title-md': ['15px', { lineHeight: '1.4', letterSpacing: '-0.15px', fontWeight: '600' }],
        body: ['14px', { lineHeight: '1.5' }],
        'body-sm': ['13px', { lineHeight: '1.5' }],
        caption: ['12px', { lineHeight: '1.4' }],
      },
      fontWeight: {
        medium: '500',
        semibold: '600',
        bold: '700',
        heavy: '800',
      },
      boxShadow: {
        soft: '0 1px 2px var(--shadow), 0 4px 12px var(--shadow)',
        pop: '0 4px 16px var(--shadow)',
      },
      keyframes: {
        'accordion-down': {
          from: { height: '0' },
          to: { height: 'var(--radix-accordion-content-height)' },
        },
        'accordion-up': {
          from: { height: 'var(--radix-accordion-content-height)' },
          to: { height: '0' },
        },
      },
      animation: {
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
}
