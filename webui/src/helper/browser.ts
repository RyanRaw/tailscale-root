import { exec } from '@/composables/useKsu'

// 常见浏览器包名 -> 显示名：shell 拿不到应用标签，至少让常见的那几个能认出来
const KNOWN: Record<string, string> = {
  'com.android.chrome': 'Chrome',
  'com.android.browser': '系统浏览器',
  'com.hyperosfix.browser': '系统浏览器',
  'com.mi.globalbrowser': '小米浏览器',
  'com.xbrowser.play': 'X 浏览器',
  'com.tencent.mtt': 'QQ 浏览器',
  'com.UCMobile': 'UC 浏览器',
  'com.quark.browser': '夸克',
  'org.mozilla.firefox': 'Firefox',
  'com.microsoft.emmx': 'Edge',
  'com.brave.browser': 'Brave',
  'com.opera.browser': 'Opera',
  'com.opera.mini.native': 'Opera Mini',
  'com.sec.android.app.sbrowser': 'Samsung Internet',
  'com.kiwibrowser.browser': 'Kiwi',
  'com.vivaldi.browser': 'Vivaldi',
  'com.duckduckgo.mobile.android': 'DuckDuckGo',
}

// 包名兜底匹配：很多浏览器没在 query-activities 里回报（部分 ROM 只给默认那个）
const HINT = /browser|chrome|chromium|firefox|opera|brave|vivaldi|quark|ucmobile|mtt|sbrowser|duckduckgo|yandex|alook|emmx|kiwi/i

export interface BrowserApp {
  pkg: string
  label: string
  // 图标：WebView 里拿不到 PackageManager，壳层也只有 ksu.exec，
  // 取不到系统图标，所以用"包名色相 + 首字"生成一个稳定的徽标。
  initial: string
  color: string
}

export function browserLabel(pkg: string) {
  return KNOWN[pkg] || pkg
}

// 常见浏览器的品牌色，让徽标一眼能认出来；没有的按包名取稳定色相
const BRAND: Record<string, string> = {
  'com.android.chrome': '#4285F4',
  'com.android.browser': '#FF6900',
  'com.hyperosfix.browser': '#FF6900',
  'com.mi.globalbrowser': '#FF6900',
  'com.xbrowser.play': '#2F7ED8',
  'com.tencent.mtt': '#12B7F5',
  'com.UCMobile': '#FF6A00',
  'com.quark.browser': '#1E88E5',
  'org.mozilla.firefox': '#FF7139',
  'com.microsoft.emmx': '#0F6CBD',
  'com.brave.browser': '#FB542B',
  'com.opera.browser': '#FF1B2D',
  'com.opera.mini.native': '#FF1B2D',
  'com.sec.android.app.sbrowser': '#1428A0',
  'com.kiwibrowser.browser': '#5CB85C',
  'com.vivaldi.browser': '#EF3939',
  'com.duckduckgo.mobile.android': '#DE5833',
}

function hashHue(s: string) {
  let h = 5381
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) & 0xffffffff
  return Math.abs(h) % 360
}

function badge(pkg: string, label: string) {
  const initial = label !== pkg ? label.slice(0, 1) : pkg.split('.').pop()!.slice(0, 2).toUpperCase()
  return { initial, color: BRAND[pkg] || `hsl(${hashHue(pkg)} 62% 46%)` }
}

// 列能打开 https 的浏览器。两条来源取并集：
//   1. 系统查询（声明了 VIEW + BROWSABLE 的 activity）
//   2. 包名兜底（query-activities 在部分 ROM 上只回报默认应用）
export async function listBrowsers(): Promise<BrowserApp[]> {
  const found = new Set<string>()

  const q = await exec(
    "cmd package query-activities --brief -a android.intent.action.VIEW " +
      "-c android.intent.category.BROWSABLE -d 'https://example.com' 2>/dev/null",
  )
  q.stdout.split('\n').forEach((l) => {
    const m = l.match(/^\s*([a-zA-Z][\w.]*)\//)
    if (m) found.add(m[1])
  })

  const pm = await exec("pm list packages 2>/dev/null | sed 's/^package://'")
  pm.stdout
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean)
    .forEach((p) => {
      // WebAPK 的包名里也带 chromium，但它不是浏览器
      if (HINT.test(p) && !/webapk/i.test(p)) found.add(p)
    })

  return [...found]
    .sort((a, b) => browserLabel(a).localeCompare(browserLabel(b)))
    .map((pkg) => {
      const label = browserLabel(pkg)
      return { pkg, label, ...badge(pkg, label) }
    })
}

// root 下 am start 可用；cmd activity 作为老 ROM 的兜底。pkg 为空 = 交给系统默认。
export async function openUrl(url: string, pkg?: string) {
  if (!url) return
  const u = url.replace(/'/g, '')
  const cu = await exec('am get-current-user 2>/dev/null')
  const user = cu.stdout.trim() || '0'
  const sel = pkg ? ` -p ${pkg}` : ''
  await exec(
    `am start --user ${user} -a android.intent.action.VIEW -d '${u}'${sel} >/dev/null 2>&1 ` +
      `|| cmd activity start --user ${user} -a android.intent.action.VIEW -d '${u}'${sel} >/dev/null 2>&1`,
  )
}
