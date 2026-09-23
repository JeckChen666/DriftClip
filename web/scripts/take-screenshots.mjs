// 生成 README 截图：注册演示账户 → 生成 Key → 经 API 灌入演示数据 → 截取核心页面。
// 前置：Go 服务 127.0.0.1:8080（建议指向一次性 SQLite 库）+ Vite dev server 5173。
// 产物：docs/screenshots/*.png（2x 缩放，桌面 1440x900 / 移动 390x844）。
import { chromium } from 'playwright'
import { mkdirSync } from 'node:fs'
import { join } from 'node:path'

const BASE = 'http://localhost:5173'
const OUT_DIR = join(import.meta.dirname, '../../docs/screenshots')
const email = 'demo@driftclip.dev'
const password = 'driftclip-demo'

// 演示数据：跨平台、贴近真实剪贴板内容（命令/链接/地址/验证码/纪要）。
const DEMO_RECORDS = [
  { content: 'git rebase --onto main feature/login-redesign', platform: 'macos', device: 'MacBook Pro' },
  { content: 'https://pub.dev/packages/provider/changelog', platform: 'windows', device: 'ThinkPad X1' },
  { content: 'docker compose up -d --build && docker compose logs -f', platform: 'linux', device: 'Ubuntu 24.04' },
  { content: 'SELECT id, content, platform FROM history ORDER BY created_at DESC LIMIT 20;', platform: 'linux', device: 'Ubuntu 24.04' },
  { content: '上海市徐汇区宜州路 188 号 B 座 12 层（前台代收）', platform: 'android', device: 'Pixel 9' },
  { content: '会议要点：1) 下周五特性冻结 2) 每账户历史上限默认 100 条 3) 移动端手势进下期排期', platform: 'ios', device: 'iPhone 17' },
  { content: 'scp -r ./dist deploy@server:/srv/driftclip/web/', platform: 'macos', device: 'MacBook Pro' },
  { content: '482913', platform: 'ios', device: 'iPhone 17' },
]

mkdirSync(OUT_DIR, { recursive: true })

const browser = await chromium.launch({ channel: 'chrome', headless: true })
try {
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 2,
  })
  const page = await context.newPage()

  // 1. 注册演示账户（注册即登录，落到 Key 管理页）。
  //    Key 只在生成时展示一次，因此脚本要求服务端指向一次性 SQLite 库（见文件头注释）。
  await page.goto(BASE + '/register', { waitUntil: 'networkidle' })
  await page.locator('#register-email').fill(email)
  await page.locator('#register-password').fill(password)
  await page.getByRole('button', { name: '注册' }).click()
  await page.getByRole('button', { name: '生成初始 Key' }).waitFor({ timeout: 10000 })

  // 2. 生成 Key 并截 Key 管理页
  await page.getByRole('button', { name: '生成初始 Key' }).click()
  const key = ((await page.locator('code').first().textContent()) ?? '').trim()
  if (!key.startsWith('dc_')) throw new Error(`Key 提取失败: ${key}`)
  await page.waitForTimeout(400)
  await page.screenshot({ path: `${OUT_DIR}/web-keys.png` })

  // 3. 经 API 灌入演示数据
  for (const r of DEMO_RECORDS) {
    const res = await fetch(`${BASE}/api/v1/history`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        content: r.content,
        source: 'clipboard',
        platform: r.platform,
        os_version: 'demo',
        device_model: r.device,
        app_version: '1.0.0',
        installation_id: 'screenshots',
      }),
    })
    if (res.status !== 201) throw new Error(`灌数据失败 ${res.status}: ${await res.text()}`)
  }

  // 4. 历史列表（桌面主视图）
  await page.goto(BASE + '/', { waitUntil: 'networkidle' })
  await page.getByText('docker compose up').first().waitFor({ timeout: 10000 })
  await page.waitForTimeout(400)
  await page.screenshot({ path: `${OUT_DIR}/web-history.png` })

  // 5. 平台筛选后的列表
  await page.getByRole('combobox', { name: '平台筛选' }).click()
  await page.getByRole('option', { name: 'linux' }).click()
  await page.getByRole('button', { name: '应用' }).click()
  await page.getByText('SELECT id, content').first().waitFor({ timeout: 10000 })
  await page.waitForTimeout(400)
  await page.screenshot({ path: `${OUT_DIR}/web-filter.png` })

  // 6. 移动端历史列表（复用登录态）
  const state = await context.storageState()
  const mobile = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
    storageState: state,
  })
  const mpage = await mobile.newPage()
  await mpage.goto(BASE + '/', { waitUntil: 'networkidle' })
  await mpage.getByText('git rebase --onto').first().waitFor({ timeout: 10000 })
  await mpage.waitForTimeout(400)
  await mpage.screenshot({ path: `${OUT_DIR}/web-mobile.png` })

  console.log('Screenshots OK ->', OUT_DIR)
} finally {
  await browser.close()
}
