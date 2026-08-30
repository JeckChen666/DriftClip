import { clsx, type ClassValue } from 'clsx'
import { extendTailwindMerge } from 'tailwind-merge'

// 把 tokens 里定义的 font-size 名称（text-body / text-body-sm / text-caption /
// text-display / text-title / text-title-md）告诉 tailwind-merge，
// 否则 cn() 会把 text-body 当作 text-color 的"重置"，把后续的 text-primary-foreground
// 这类真正表达颜色的类误判为冲突并丢掉。
const twMerge = extendTailwindMerge({
  extend: {
    classGroups: {
      'font-size': [
        {
          text: [
            'display',
            'title',
            'title-md',
            'body',
            'body-sm',
            'caption',
          ],
        },
      ],
    },
  },
})

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
