// P02 Web 核心闭环 E2E：用系统 Chrome 驱动真实浏览器，验证
// 注册/登录 → 生成 Key → 上传记录（Key 鉴权）→ Web 列表可见 → 详情 → 删除。
//
// 前置：Go 服务 127.0.0.1:8080 + Vite dev server 5173 已启动。
import { chromium } from 'playwright'
import { mkdirSync } from 'node:fs'

const BASE = 'http://localhost:5173'
const SHOT_DIR = '/Users/macos/Code/DriftClip/docs/easypower/clipboard-sync/evidence/P02-e2e'
const email = `e2e-${Date.now()}@example.com`
const password = 'pw123'
const CONTENT = `E2E 验证记录 ${Date.now()}：多设备剪贴板同步`

function assert(cond, msg) {
  if (!cond) throw new Error(`断言失败: ${msg}`)
}

const browser = await chromium.launch({ channel: 'chrome', headless: true })
try {
  const page = await browser.newPage({ viewport: { width: 1100, height: 800 } })

  // 1. 未登录访问根路径 → 跳转登录页
  await page.goto(BASE + '/', { waitUntil: 'networkidle' })
  await page.getByRole('heading', { name: '登录 DriftClip' }).waitFor({ timeout: 10000 })
  await page.screenshot({ path: `${SHOT_DIR}/1-login.png` })

  // 2. 注册 → 自动登录 → 落到 Key 管理页
  await page.getByRole('link', { name: '注册' }).click()
  await page.getByLabel('邮箱').fill(email)
  await page.getByLabel('密码').fill(password)
  await page.getByRole('button', { name: '注册' }).click()
  await page.getByRole('button', { name: '生成初始 Key' }).waitFor({ timeout: 10000 })
  await page.screenshot({ path: `${SHOT_DIR}/2-keys-before.png` })

  // 3. 生成 Key → 一次性展示完整 Key
  await page.getByRole('button', { name: '生成初始 Key' }).click()
  const keyEl = page.locator('.key-once code')
  await keyEl.waitFor({ timeout: 10000 })
  const key = (await keyEl.textContent())?.trim() ?? ''
  assert(key.startsWith('dc_'), `Key 应以 dc_ 开头，实际 ${key}`)
  await page.screenshot({ path: `${SHOT_DIR}/3-key-shown-once.png` })

  // 4. 用 Key 上传一条记录（经 Vite 代理 → Go）
  const upRes = await fetch(`${BASE}/api/v1/history`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      content: CONTENT,
      source: 'clipboard',
      platform: 'macos',
      os_version: '15',
      device_model: 'E2E-MacBook',
      app_version: '1.0.0',
      installation_id: 'e2e-install',
    }),
  })
  assert(upRes.status === 201, `上传应 201，实际 ${upRes.status}`)

  // 5. 历史列表可见该记录
  await page.goto(BASE + '/', { waitUntil: 'networkidle' })
  await page.getByText(CONTENT).waitFor({ timeout: 10000 })
  await page.screenshot({ path: `${SHOT_DIR}/4-history-listed.png` })

  // 6. 详情展开显示完整正文
  await page.getByRole('button', { name: '详情' }).click()
  await page.locator('.record-detail pre').waitFor({ timeout: 5000 })
  const detailText = await page.locator('.record-detail').textContent()
  assert(detailText?.includes(CONTENT), '详情应包含完整正文')
  await page.screenshot({ path: `${SHOT_DIR}/5-detail.png` })

  // 7. 单条删除 → 记录消失（预览与详情可能都含正文，用 first() 消歧）
  await page.getByRole('button', { name: '删除' }).click()
  await page.getByText(CONTENT).first().waitFor({ state: 'detached', timeout: 10000 })
  await page.screenshot({ path: `${SHOT_DIR}/6-after-delete.png` })

  console.log('E2E OK')
  console.log(JSON.stringify({ email, key, steps: ['login-redirect', 'register', 'key-generate', 'upload', 'list', 'detail', 'delete'] }, null, 2))
} finally {
  await browser.close()
}
