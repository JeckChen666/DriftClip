/** @type {import('tailwindcss').Config} */
//
// 颜色/尺寸统一从 CSS 变量（由 tokens/tokens.json 经 tool/sync_tokens.dart 产出）注入。
// 这样 Tailwind 的 utility class（bg-background / text-foreground / border-border 等）会
// 自动复用现有 token；改 tokens.json → 重跑 make tokens → 两端一致。
//
// 命名约定按 shadcn 习惯：background / foreground / primary / muted / accent / destructive /
// border / input / ring。实际值仍然来自我们的 design tokens。
export default {
  darkMode: ['class'],
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    container: {
      center: true,
      padding: '1.25rem',
      screens: { '2xl': '960px' },
    },
    extend: {
      colors: {
        border: 'var(--border)',
        input: 'var(--border)',
        ring: 'var(--ring)',
        background: 'var(--canvas)',
        foreground: 'var(--text-primary)',
        'field-fill': 'var(--field-fill)',
        primary: {
          DEFAULT: 'var(--accent)',
          foreground: 'var(--on-accent)',
        },
        secondary: {
          DEFAULT: 'var(--surface-subtle)',
          foreground: 'var(--text-primary)',
        },
        destructive: {
          DEFAULT: 'var(--danger)',
          foreground: 'var(--on-accent)',
        },
        muted: {
          DEFAULT: 'var(--surface-subtle)',
          foreground: 'var(--text-muted)',
        },
        accent: {
          DEFAULT: 'var(--accent-subtle)',
          foreground: 'var(--accent-hover)',
        },
        popover: {
          DEFAULT: 'var(--surface)',
          foreground: 'var(--text-primary)',
        },
        card: {
          DEFAULT: 'var(--surface)',
          foreground: 'var(--text-primary)',
        },
        success: 'var(--success)',
        warn: {
          DEFAULT: 'var(--warn-text)',
          bg: 'var(--warn-bg)',
          border: 'var(--warn-border)',
        },
        'accent-purple': {
          DEFAULT: 'var(--accent-purple-text)',
          border: 'var(--accent-purple-border)',
        },
      },
      borderRadius: {
        xl: 'var(--radius-xl)',
        lg: 'var(--radius-lg)',
        md: 'var(--radius-md)',
        sm: 'var(--radius-sm)',
        xs: 'var(--radius-xs)',
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
