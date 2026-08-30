// Vitest 测试环境：注入 jest-dom 匹配器（toBeInTheDocument 等）。
import '@testing-library/jest-dom/vitest'

// jsdom 不支持 Radix UI 使用的 Pointer / scrollIntoView 方法，
// 给 HTMLElement 原型补桩避免运行时报错。
if (typeof Element !== 'undefined') {
  if (!Element.prototype.hasPointerCapture) {
    Element.prototype.hasPointerCapture = () => false
  }
  if (!Element.prototype.releasePointerCapture) {
    Element.prototype.releasePointerCapture = () => {}
  }
  if (!Element.prototype.scrollIntoView) {
    Element.prototype.scrollIntoView = () => {}
  }
}
