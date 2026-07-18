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

    <div class="mx-auto w-full max-w-3xl space-y-1 p-3 md:px-8 md:py-6">
      <!-- Hero Status -->
      <div class="base-container">
        <div class="bg-base-200/30 flex items-center gap-4 rounded-xl p-4">
          <div
            class="h-4 w-4 shrink-0 rounded-full"
            :class="isOnline ? 'bg-success animate-pulse' : state.daemonRunning ? 'bg-warning' : 'bg-error'"
          />
          <div class="flex flex-col">
            <span class="text-xl font-bold">
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
            <template v-if="state.daemonRunning && isOnline">
              <button class="btn btn-sm" :disabled="busy" @click="restartDaemon">重启</button>
              <button class="btn btn-error btn-sm" :disabled="busy" @click="stopDaemon">停止</button>
            </template>
            <template v-else-if="needsLogin">
              <button v-if="!state.authURL" class="btn btn-primary btn-sm" :disabled="busy" @click="tsUp">获取链接</button>
            </template>
            <button
              v-else-if="!state.daemonRunning"
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
          <div class="text-base-content/40 text-xs">点击链接可复制</div>
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
          <div v-if="svmBad" class="setting-item justify-end">
            <button class="btn btn-error btn-xs" @click="fixSvm">修复</button>
          </div>
          <div v-else-if="state.daemonRunning && !state.guardOn" class="setting-item justify-end">
            <button class="btn btn-ghost btn-xs" @click="startGuard">启动</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import { useKsu, BIN, SOCK, PIDFILE, UP_LOG, SVM, MODDIR } from '@/composables/useKsu'
import { usePaddingForViews } from '@/composables/paddingViews'
import { EyeIcon, EyeSlashIcon } from '@heroicons/vue/24/outline'
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const { state, busy, refreshing, refresh, act, exec } = useKsu()

const showPrivacy = ref(false)
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
const selfOnline = computed(() => state.value.status?.Self ? 1 : 0)
const peerCount = computed(() => Object.keys(state.value.status?.Peer || {}).length + selfOnline.value)
const onlineCount = computed(() => Object.values(state.value.status?.Peer || {}).filter((p: any) => p.Online).length + selfOnline.value)

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
    await exec(`pkill -x tailscaled; rm -f ${PIDFILE}`)
    await new Promise(r => setTimeout(r, 800))
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
function tsUp() {
  act(async () => {
    await exec(`rm -f ${UP_LOG}; ${BIN} --socket=${SOCK} up --accept-routes --accept-dns=false > ${UP_LOG} 2>&1 &`)
    for (let i = 0; i < 20; i++) {
      await new Promise(r => setTimeout(r, 500))
      const log = await exec(`cat ${UP_LOG} 2>/dev/null`)
      const m = log.stdout.match(/https:\/\/login\.tailscale\.com\/a\/[a-zA-Z0-9]+/)
      if (m) {
        state.value.authURL = m[0]
        startLoginPoll()
        return
      }
      await refresh()
      if (isOnline.value) return
    }
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
function fixSvm() {
  act(async () => { await exec(`echo 0 > ${SVM}`) })
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

onMounted(() => {
  refresh()
  uptimeTimer = setInterval(() => {
    if (state.value.daemonRunning) uptimeSeconds.value++
  }, 1000) as unknown as number
})
onUnmounted(() => {
  stopLoginPoll()
  if (uptimeTimer) clearInterval(uptimeTimer)
})
</script>
