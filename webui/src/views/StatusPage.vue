<template>
  <div
    class="h-full overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
    <CtrlsBar>
      <div class="flex h-12 flex-row items-center gap-2 p-2 text-sm">
        <span>Tailscale</span>
        <span class="text-base-content/40">|</span>
        <span class="text-base-content/60 tabular-nums">{{ state.binVersion || '—' }}</span>
        <div class="flex-1" />
        <button class="btn btn-ghost btn-sm btn-circle" @click="showPrivacy = !showPrivacy">
          <EyeIcon v-if="showPrivacy" class="h-4 w-4" />
          <EyeSlashIcon v-else class="h-4 w-4" />
        </button>
      </div>
    </CtrlsBar>

    <div v-if="!state.loaded" class="flex h-full items-center justify-center">
      <span class="loading loading-spinner loading-lg text-base-content/30"></span>
    </div>
    <div v-else class="mx-auto w-full max-w-3xl space-y-1 p-3 md:px-8 md:py-6">
      <!-- Hero Status -->
      <div class="base-container">
        <div class="bg-base-200/30 flex items-center gap-4 rounded-xl p-4">
          <div
            class="h-4 w-4 shrink-0 rounded-full"
            :class="isOnline ? 'bg-success animate-pulse' : state.daemonRunning ? 'bg-warning' : 'bg-error'"
          />
          <div class="flex flex-col">
            <span class="text-base font-bold">
              {{ heroLabel }}
            </span>
            <span
              v-if="tailscaleIP"
              class="text-base-content/50 text-sm tabular-nums cursor-pointer"
              @click="copyText(tailscaleIP)"
            >
              {{ showPrivacy ? tailscaleIP : '***.***.***.***' }}
            </span>
            <span
              v-else
              class="text-base-content/40 text-sm"
            >
              {{ heroSub }}
            </span>
          </div>
          <div class="ml-auto flex gap-2">
            <template v-if="state.daemonRunning">
              <button
                v-if="!isOnline"
                class="btn btn-primary btn-sm"
                :disabled="busy"
                @click="tsUp"
              >
                {{ hasAuthKey ? '密钥登录' : '获取登录链接' }}
              </button>
              <button class="btn btn-sm" :disabled="busy" @click="restartDaemon">重启</button>
              <button class="btn btn-error btn-sm" :disabled="busy" @click="stopDaemon">停止</button>
            </template>
            <button
              v-else
              class="btn btn-success btn-sm"
              :disabled="busy || !state.binInstalled"
              @click="startDaemon"
            >
              启动
            </button>
          </div>
        </div>
      </div>

      <!-- Auth URL -->
      <div v-if="state.authURL && needsLogin" class="base-container">
        <div class="bg-base-200/30 flex flex-col rounded-xl p-4 gap-2">
          <div class="text-base-content/60 text-xs font-semibold tracking-wider uppercase">在浏览器中打开以下链接完成登录</div>
          <div
            class="text-primary cursor-pointer break-all text-sm"
            @click="copyText(state.authURL)"
          >{{ state.authURL }}</div>
          <div class="flex items-center gap-2">
            <span class="text-base-content/40 text-xs">点击链接可复制</span>
            <button class="btn btn-primary btn-sm ml-auto" @click="openAuthUrl(state.authURL)">
              选择浏览器打开
            </button>
          </div>
        </div>
      </div>

      <!-- Browser picker：安卓的默认浏览器是全局偏好，这里给一次选择机会 -->
      <DialogWrapper v-model="browserOpen" title="选择浏览器打开">
        <div class="flex flex-col gap-1">
          <button
            v-for="b in browserList"
            :key="b.pkg"
            class="btn btn-ghost btn-sm justify-start normal-case"
            @click="openWith(b.pkg)"
          >
            <span class="text-sm">{{ b.label }}</span>
            <span v-if="b.label !== b.pkg" class="text-base-content/40 ml-2 text-xs">{{ b.pkg }}</span>
          </button>
          <button class="btn btn-ghost btn-sm justify-start normal-case" @click="openWith()">
            系统默认（不指定应用）
          </button>
        </div>
      </DialogWrapper>

      <!-- Up / login failure -->
      <div v-if="upError" class="base-container">
        <div class="bg-error/10 flex flex-col gap-1 rounded-xl p-4">
          <div class="text-error text-xs font-semibold tracking-wider uppercase">登录失败</div>
          <pre class="text-base-content/60 text-xs whitespace-pre-wrap break-all">{{ upError }}</pre>
          <div class="text-base-content/40 text-xs">
            切换控制服务器后需在设置页把 TS_UP_ARGS 设为 --reset 重新注册；自签证书需先让系统信任其 CA。
          </div>
        </div>
      </div>

      <!-- Account -->
      <div v-if="state.status && isOnline">
        <div class="settings-section-label">账号</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">用户</div>
            <span class="text-sm">{{ showPrivacy ? userName : '****@***' }}</span>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">Tailnet</div>
            <span class="text-sm">{{ showPrivacy ? tailnetName : '****' }}</span>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">节点</div>
            <span class="text-sm tabular-nums"><span class="text-success">{{ onlineCount }}</span> / {{ peerCount }}</span>
          </div>
          <div class="setting-item justify-end gap-2">
            <button class="btn btn-ghost btn-xs" @click="tsDown">断开</button>
            <button class="btn btn-ghost btn-error btn-xs" @click="tsLogout">登出</button>
          </div>
        </div>
      </div>

      <!-- Daemon -->
      <div>
        <div class="settings-section-label">守护进程</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">tailscaled</div>
            <div class="flex items-center gap-2">
              <div class="h-2 w-2 rounded-full" :class="state.daemonRunning ? 'bg-success' : 'bg-error'" />
              <span class="text-sm">{{ state.daemonRunning ? '运行中' : '已停止' }}</span>
            </div>
          </div>
          <div v-if="state.pid" class="setting-item">
            <div class="setting-item-label">PID</div>
            <span class="text-sm tabular-nums">{{ state.pid }}</span>
          </div>
          <div v-if="state.daemonRunning" class="setting-item">
            <div class="setting-item-label">运行时间</div>
            <span class="text-sm tabular-nums">{{ uptimeDisplay }}</span>
          </div>
          <div v-if="state.binVersion" class="setting-item">
            <div class="setting-item-label">版本</div>
            <span class="text-sm">{{ state.binVersion }}</span>
          </div>
          <div v-if="state.exePath" class="setting-item">
            <div class="setting-item-label">二进制路径</div>
            <span class="text-xs text-base-content/50 break-all">{{ state.exePath }}</span>
          </div>
        </div>
      </div>

      <!-- Network diagnostics -->
      <div>
        <div class="settings-section-label flex items-center">
          <span class="flex-1">网络诊断</span>
          <button class="btn btn-ghost btn-xs" :disabled="diagBusy" @click="runDiag">
            {{ diagBusy ? '抓取中…' : '抓取' }}
          </button>
        </div>
        <div class="settings-grid">
          <div v-if="!diag" class="setting-item justify-center">
            <span class="text-base-content/40 text-sm py-2">
              点「抓取」立即采集一份到 log/net_probe.log（设置页日志级别为调试时每 60 秒自动采集）
            </span>
          </div>
          <pre
            v-else
            class="text-[11px] leading-4 whitespace-pre-wrap break-all max-h-72 overflow-auto px-3 py-2"
          >{{ diag }}</pre>
        </div>
      </div>

      <!-- Box Guard -->
      <div v-if="state.box">
        <div class="settings-section-label">Box Guard</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">src_valid_mark</div>
            <span class="text-sm tabular-nums" :class="svmBad ? 'text-error' : 'text-success'">{{ state.svm }}</span>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">守护</div>
            <div class="flex items-center gap-2">
              <div class="h-2 w-2 rounded-full" :class="state.guardOn ? 'bg-success' : state.daemonRunning ? 'bg-warning' : 'bg-base-300'" />
              <span class="text-sm">{{ state.guardOn ? '活跃' : state.daemonRunning ? '未运行' : '空闲' }}</span>
            </div>
          </div>
          <div v-if="state.daemonRunning && !state.guardOn" class="setting-item justify-end">
            <button class="btn btn-ghost btn-xs" @click="startGuard">启动</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import DialogWrapper from '@/components/common/DialogWrapper.vue'
import { useKsu, BIN, SOCK, PIDFILE, UP_LOG, MODDIR, TS_DIR, AUTH_URL_RE } from '@/composables/useKsu'
import { usePaddingForViews } from '@/composables/paddingViews'
import { useAutoRefresh } from '@/composables/useAutoRefresh'
import { listBrowsers, openUrl } from '@/helper/browser'
import { EyeIcon, EyeSlashIcon } from '@heroicons/vue/24/outline'
import { computed, onActivated, onDeactivated, onMounted, onUnmounted, ref, watch } from 'vue'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const { state, busy, refreshing, refresh, act, exec } = useKsu()

const showPrivacy = ref(false)
const upError = ref('')
const hasAuthKey = ref(false)

const loadAuthKey = async () => {
  const r = await exec("sed -n 's/^TS_AUTHKEY=//p' /data/adb/tailscale/env 2>/dev/null | head -1")
  hasAuthKey.value = r.stdout.trim().replace(/^["']|["']$/g, '').length > 0
}
const uptimeSeconds = ref(0)
let uptimeTimer: number | undefined

function parseEtime(s: string): number {
  if (!s) return 0
  const parts = s.split(/[-:]/).reverse().map(Number)
  return (parts[0] || 0) + (parts[1] || 0) * 60 + (parts[2] || 0) * 3600 + (parts[3] || 0) * 86400
}
function fmtUptime(s: number): string {
  const d = Math.floor(s / 86400)
  const h = Math.floor((s % 86400) / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  if (d > 0) return `${d}天 ${h}时${m}分`
  if (h > 0) return `${h}时${m}分${sec}秒`
  return `${m}分${sec}秒`
}
const uptimeDisplay = computed(() => fmtUptime(uptimeSeconds.value))

const isOnline = computed(() => state.value.status?.BackendState === 'Running')
const needsLogin = computed(() => state.value.status?.BackendState === 'NeedsLogin')
const svmBad = computed(() => state.value.svm === '1')

const heroLabel = computed(() => {
  if (!state.value.loaded) return '加载中…'
  if (!state.value.binInstalled) return '未安装'
  if (!state.value.daemonRunning) return '已离线'
  if (isOnline.value) return '已连接'
  if (state.value.status?.BackendState === 'NeedsLogin') return '需要登录'
  const be = state.value.status?.BackendState || ''
  const map: Record<string, string> = { Starting: '启动中', Stopped: '已停止', NoState: '未初始化' }
  return map[be] || be || '启动中'
})
const heroSub = computed(() => {
  if (!state.value.loaded) return '正在读取状态…'
  if (!state.value.binInstalled) return '请在安装页安装 Tailscale'
  if (!state.value.daemonRunning) return '守护进程未运行'
  return ''
})

const tailscaleIP = computed(() => {
  const ips = state.value.status?.Self?.TailscaleIPs || []
  return ips.find((i: string) => !i.includes(':')) || ''
})
const userName = computed(() => {
  try {
    const uid = String(state.value.status?.Self?.UserID)
    return state.value.status?.User?.[uid]?.LoginName || '—'
  } catch { return '—' }
})
const tailnetName = computed(() => {
  return state.value.status?.MagicDNSSuffix?.replace(/\.ts\.net$/, '') || '—'
})
const allNodes = computed(() => {
  const self = state.value.status?.Self
  const peers = Object.values(state.value.status?.Peer || {}) as any[]
  return self ? [self, ...peers] : peers
})
const peerCount = computed(() => allNodes.value.length)
const onlineCount = computed(() => allNodes.value.filter((n: any) => n.Online).length)

function copyText(t: string) { navigator.clipboard?.writeText(t) }

function startDaemon() {
  act(async () => {
    await exec(`TS_SKIP_WAIT=1 sh ${MODDIR}/service.sh`)
    for (let i = 0; i < 10; i++) {
      await new Promise(r => setTimeout(r, 1000))
      await refresh()
      if (state.value.status?.BackendState === 'Running') break
    }
  })
}
function stopDaemon() {
  act(async () => {
    await exec('pkill -x tailscaled 2>/dev/null; true')
    // wait until the process is really gone, otherwise the status poll below
    // still sees it and the UI keeps showing "已连接"
    for (let i = 0; i < 12; i++) {
      await new Promise(r => setTimeout(r, 300))
      const p = await exec('pidof tailscaled 2>/dev/null | head -1')
      if (!p.stdout.trim()) break
    }
    await exec(`rm -f ${PIDFILE} ${SOCK}`)
    state.value.daemonRunning = false
    state.value.pid = 0
    state.value.etime = ''
    state.value.status = null
    state.value.authURL = ''
    upError.value = ''
  })
}
function restartDaemon() {
  act(async () => {
    await exec(`pkill -x tailscaled; rm -f ${PIDFILE}; sleep 1; TS_SKIP_WAIT=1 sh ${MODDIR}/service.sh`)
    for (let i = 0; i < 10; i++) {
      await new Promise(r => setTimeout(r, 1000))
      await refresh()
      if (state.value.status?.BackendState === 'Running') break
    }
  })
}
// KSU 的 WebView 里 window.open 不会落到系统浏览器，只能让 shell 用 am 拉起。
// 多个浏览器时先弹选择（安卓的默认浏览器是全局偏好，这里不替用户改）。
const browserOpen = ref(false)
const browserList = ref<{ pkg: string; label: string }[]>([])
const pendingUrl = ref('')

async function openAuthUrl(url: string) {
  if (!url) return
  const list = await listBrowsers()
  if (list.length <= 1) {
    await openUrl(url, list[0]?.pkg)
    return
  }
  browserList.value = list
  pendingUrl.value = url
  browserOpen.value = true
}

async function openWith(pkg?: string) {
  browserOpen.value = false
  const u = pendingUrl.value
  pendingUrl.value = ''
  if (!u) return
  await openUrl(u, pkg)
}

function tsUp() {
  act(async () => {
    upError.value = ''
    await exec(`rm -f ${UP_LOG}; sh ${MODDIR}/ts_up.sh > ${UP_LOG} 2>&1 &`)
    for (let i = 0; i < 20; i++) {
      await new Promise(r => setTimeout(r, 500))
      const log = await exec(`cat ${UP_LOG} 2>/dev/null`)
      const m = log.stdout.match(AUTH_URL_RE)
      if (m) {
        state.value.authURL = m[0]
        await openAuthUrl(m[0])
        startLoginPoll()
        return
      }
      await refresh()
      if (isOnline.value) return
    }
    // up 没打印新链接时用状态里已有的（换控制面后 daemon 可能早就生成了）
    if (state.value.authURL) {
      await openAuthUrl(state.value.authURL)
      startLoginPoll()
      return
    }
    const tail = await exec(`tail -6 ${UP_LOG} 2>/dev/null`)
    upError.value = tail.stdout.trim() || '没有拿到登录链接，请检查控制服务器设置与网络'
  })
}
function tsDown() {
  act(async () => {
    await exec(`${BIN} --socket=${SOCK} down`)
    await new Promise(r => setTimeout(r, 800))
  })
}
function tsLogout() {
  act(async () => {
    await exec(`${BIN} --socket=${SOCK} logout`)
    await new Promise(r => setTimeout(r, 1500))
  })
}
const diag = ref('')
const diagBusy = ref(false)

async function runDiag() {
  if (diagBusy.value) return
  diagBusy.value = true
  try {
    await exec(`sh ${MODDIR}/net_probe.sh now 2>&1`)
    const r = await exec(`tail -n 40 ${TS_DIR}/log/net_probe.log 2>/dev/null`)
    diag.value = r.stdout.trim()
  } finally {
    diagBusy.value = false
  }
}

function startGuard() {
  act(async () => {
    await exec(`nohup sh ${MODDIR}/svm_guard.sh </dev/null >/dev/null 2>&1 &`)
    await new Promise(r => setTimeout(r, 1200))
  })
}

let loginPoll: number | undefined

function startLoginPoll() {
  stopLoginPoll()
  loginPoll = setInterval(async () => {
    await refresh()
    if (isOnline.value) {
      state.value.authURL = ''
      upError.value = ''
      stopLoginPoll()
    }
  }, 3000) as unknown as number
}
function stopLoginPoll() {
  if (loginPoll) { clearInterval(loginPoll); loginPoll = undefined }
}

watch(() => state.value.etime, (v) => {
  uptimeSeconds.value = parseEtime(v)
})

let pollTimer: number | undefined

function startPoll() {
  if (pollTimer) return
  pollTimer = setInterval(() => {
    if (!busy.value) refresh()
  }, 5000) as unknown as number
}
function stopPoll() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = undefined }
}

onMounted(() => {
  loadAuthKey()
  refresh()
  startPoll()
  uptimeTimer = setInterval(() => {
    if (state.value.daemonRunning) uptimeSeconds.value++
  }, 1000) as unknown as number
})
// 切回本页时重拉一次；首次激活由上面的 onMounted 负责，这里不会重复
useAutoRefresh(() => { loadAuthKey(); refresh() })
onActivated(() => { startPoll() })
onDeactivated(() => {
  stopPoll()
})
onUnmounted(() => {
  stopLoginPoll()
  stopPoll()
  if (uptimeTimer) clearInterval(uptimeTimer)
})
</script>
