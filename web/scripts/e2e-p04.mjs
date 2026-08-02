// P04 Web 增强 E2E：组合筛选、多选删除、清空全部（5s 确认）。
// 前置：Go 服务 8080 + Vite 5173。
import { chromium } from 'playwright'
import { mkdirSync } from 'node:fs'

const BASE = 'http://localhost:5173'
const SHOT_DIR = '/Users/macos/Code/DriftClip/docs/easypower/clipboard-sync/evidence/P04-e2e'
const email = `e2e-p04-${Date.now()}@example.com`
const records = [
  { content: 'alpha 内容', platform: 'macos' },
  { content: 'beta 内容', platform: 'windows' },
  { content: 'gamma 内容', platform: 'linux' },
]

function assert(cond, msg) {
  if (!cond) throw new Error(`断言失败: ${msg}`)
}

const browser = await chromium.launch({ channel: 'chrome', headless: true })
try {
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } })

  // 注册并生成 Key
  await page.goto(BASE + '/register', { waitUntil: 'networkidle' })
  await page.getByLabel('邮箱').fill(email)
  await page.getByLabel('密码').fill('pw123')
  await page.getByRole('button', { name: '注册' }).click()
  await page.getByRole('button', { name: '生成初始 Key' }).waitFor({ timeout: 10000 })
  await page.getByRole('button', { name: '生成初始 Key' }).click()
  const key = ((await page.locator('.key-once code').textContent()) ?? '').trim()

  // 上传 3 条不同平台记录
  for (const r of records) {
    const res = await fetch(`${BASE}/api/v1/history`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({ content: r.content, source: 'clipboard', platform: r.platform, installation_id: 'p04' }),
    })
    assert(res.status === 201, `上传 ${r.content} 应 201，实际 ${res.status}`)
  }

  // 1. 组合筛选：platform=macos → 只显示 alpha
  await page.goto(BASE + '/', { waitUntil: 'networkidle' })
  await page.getByText('alpha 内容').waitFor({ timeout: 10000 })
  await page.getByLabel('平台筛选').selectOption('macos')
  await page.getByRole('button', { name: '应用' }).click()
  await page.getByText('beta 内容').waitFor({ state: 'detached', timeout: 5000 })
  const alphaVisible = await page.getByText('alpha 内容').isVisible()
  assert(alphaVisible, 'alpha 应在 macos 筛选中可见')
  await page.screenshot({ path: `${SHOT_DIR}/1-filter-platform.png` })

  // 2. 正文子串筛选：q=beta（忽略大小写）→ 只显示 beta
  await page.getByRole('button', { name: '重置' }).click()
  await page.getByText('gamma 内容').waitFor({ state: 'attached', timeout: 5000 })
  await page.getByLabel('正文筛选').fill('BETA')
  await page.getByRole('button', { name: '应用' }).click()
  await page.getByText('gamma 内容').waitFor({ state: 'detached', timeout: 5000 })
  assert(await page.getByText('beta 内容').isVisible(), 'beta 应在 q=BETA 筛选中可见')
  await page.screenshot({ path: `${SHOT_DIR}/2-filter-q.png` })

  // 3. 重置后多选删除
  await page.getByRole('button', { name: '重置' }).click()
  await page.getByText('gamma 内容').waitFor({ timeout: 5000 })
  await page.getByLabel('全选').check()
  await page.getByRole('button', { name: /删除所选/ }).click()
  await page.getByText('暂无历史记录。').waitFor({ timeout: 10000 })
  await page.screenshot({ path: `${SHOT_DIR}/3-after-batch-delete.png` })

  // 4. 清空全部：5s 倒计时确认
  const res2 = await fetch(`${BASE}/api/v1/history`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
    body: JSON.stringify({ content: '清空测试', source: 'manual', platform: 'ios', installation_id: 'p04' }),
  })
  assert(res2.status === 201, '上传清空测试记录失败')
  await page.getByRole('button', { name: '刷新' }).click()
  await page.getByText('清空测试').waitFor({ timeout: 10000 })

  await page.getByRole('button', { name: '清空全部' }).click()
  const countdownBtn = page.getByRole('button', { name: /清空全部（[0-9]s）/ })
  assert(await countdownBtn.isDisabled(), '倒计时期间清空按钮应不可点击')
  await page.screenshot({ path: `${SHOT_DIR}/4-clear-countdown.png` })
  await page.getByRole('button', { name: '确认清空全部' }).waitFor({ timeout: 10000 })
  await page.getByRole('button', { name: '确认清空全部' }).click()
  await page.getByText('暂无历史记录。').waitFor({ timeout: 10000 })
  await page.screenshot({ path: `${SHOT_DIR}/5-after-clear.png` })

  console.log('E2E P04 OK')
  console.log(JSON.stringify({ email, steps: ['filter-platform', 'filter-q', 'batch-delete', 'clear-countdown', 'clear'] }, null, 2))
} finally {
  await browser.close()
}
