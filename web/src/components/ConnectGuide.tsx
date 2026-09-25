// 连接原生客户端引导卡：服务地址 + 配置二维码 + 下载入口（ROADMAP P2.3）。
// 配置以 driftclip://connect?server=…&key=… 编码，客户端「从剪贴板导入」
// 与移动端扫码共用同一格式。
import { useEffect, useMemo, useState } from 'react'
import QRCode from 'qrcode'
import { ClipboardPaste, Download, QrCode } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { useToast } from '@/components/ui/toast'

const RELEASES_URL = 'https://github.com/JeckChen666/DriftClip/releases/latest'

export function ConnectGuide({ server, apiKey }: { server: string; apiKey: string }) {
  const { toast } = useToast()
  const [qrDataUrl, setQrDataUrl] = useState('')

  const connectUri = useMemo(
    () =>
      `driftclip://connect?server=${encodeURIComponent(server)}&key=${encodeURIComponent(apiKey)}`,
    [server, apiKey],
  )

  useEffect(() => {
    let alive = true
    QRCode.toDataURL(connectUri, { width: 220, margin: 1 })
      .then((url) => {
        if (alive) setQrDataUrl(url)
      })
      .catch(() => {
        if (alive) setQrDataUrl('')
      })
    return () => {
      alive = false
    }
  }, [connectUri])

  async function copy(text: string, label: string) {
    try {
      await navigator.clipboard.writeText(text)
      toast(`${label}已复制到剪贴板`)
    } catch {
      toast('复制失败，请手动选中复制', 'error')
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <span className="inline-flex size-7 items-center justify-center rounded-sm bg-primary/10 text-primary">
            <QrCode className="size-icon-md" />
          </span>
          连接原生客户端
        </CardTitle>
        <CardDescription>
          在其他设备上安装客户端，扫码或粘贴配置即可开始同步，无需手动输入。
        </CardDescription>
      </CardHeader>
      <CardContent className="grid gap-6 md:grid-cols-[1fr_auto]">
        <ol className="m-0 flex list-decimal flex-col gap-2.5 pl-5 text-body-sm text-foreground">
          <li>
            下载并安装客户端（
            <a
              className="text-primary underline underline-offset-2"
              href={RELEASES_URL}
              target="_blank"
              rel="noreferrer"
            >
              GitHub Releases
              <Download className="ml-0.5 inline size-3.5 align-[-1px]" />
            </a>
            ），支持 Windows / macOS / Linux / Android / iOS。
          </li>
          <li>
            在客户端「连接 DriftClip」页，用
            <span className="mx-1 inline-flex items-center gap-1 rounded-sm border border-border px-1.5 py-0.5 font-mono text-[11px]">
              <ClipboardPaste className="size-3" />
              从剪贴板导入
            </span>
            粘贴下方配置；手机端可直接扫描右侧二维码。
          </li>
          <li>
            在任意一台设备上复制文本，回到
            <span className="mx-1 font-medium">历史</span>
            页即可看到内容出现。
          </li>
          <li className="flex flex-wrap items-center gap-2">
            服务地址
            <code className="select-all rounded-sm border border-border bg-muted px-1.5 py-0.5 font-mono text-[12px]">
              {server}
            </code>
            <Button variant="outline" size="sm" onClick={() => void copy(connectUri, '配置')}>
              复制完整配置
            </Button>
          </li>
        </ol>
        <div className="flex flex-col items-center justify-center gap-2">
          {qrDataUrl ? (
            <img
              src={qrDataUrl}
              alt="客户端连接配置二维码"
              width={200}
              height={200}
              className="rounded-md border border-border bg-white p-1.5"
            />
          ) : (
            <div className="flex size-[200px] items-center justify-center rounded-md border border-dashed border-border text-caption text-muted-foreground">
              二维码生成失败
            </div>
          )}
          <span className="text-caption text-muted-foreground">手机客户端扫码导入</span>
        </div>
      </CardContent>
    </Card>
  )
}
