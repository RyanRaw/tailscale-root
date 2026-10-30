<template>
  <div
    class="h-full overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
    <CtrlsBar>
      <div class="flex h-12 flex-row items-center gap-2 p-2 text-sm">
        <span>日志</span>
        <span class="text-base-content/40">|</span>
        <span class="text-base-content/60 tabular-nums">{{ logs.length }} 条</span>
        <div class="flex-1" />
        <select v-model="source" class="select select-xs w-20" @change="loadLogs">
          <option v-for="s in SOURCES" :key="s.key" :value="s.key">{{ s.label }}</option>
        </select>
        <button
          class="btn btn-ghost btn-sm btn-circle"
          :disabled="loadingLogs"
          @click="loadLogs"
        >
          <ArrowPathIcon class="h-4 w-4" :class="loadingLogs ? 'animate-spin' : ''" />
        </button>
        <button
          class="btn btn-ghost btn-sm btn-circle"
          :disabled="loadingLogs"
          @click="clearLog"
        >
          <TrashIcon class="h-4 w-4" />
        </button>
        <label class="flex items-center gap-1.5">
          <span class="text-base-content/50 text-xs">跟随</span>
          <input v-model="follow" type="checkbox" class="toggle toggle-xs" />
        </label>
      </div>
    </CtrlsBar>

    <div class="mx-auto w-full max-w-3xl p-3 md:px-8 md:py-6">
      <div
        v-if="logs.length === 0 && !loadingLogs"
        class="text-base-content/40 py-12 text-center text-sm"
      >
        暂无日志
      </div>
      <div class="base-container">
        <div
          v-for="(entry, i) in logs"
          :key="i"
          class="hover:bg-base-200/40 flex flex-col gap-1 px-3 py-2 text-sm transition-colors"
          :class="i < logs.length - 1 && 'border-b border-base-content/5'"
        >
          <div class="flex items-center gap-2">
            <span class="text-base-content/30 min-w-6 text-xs tabular-nums">
              {{ String((entry as any).seq || i + 1).padStart(3, '0') }}
            </span>
            <span
              class="text-[11px] font-medium tracking-wide uppercase"
              :class="levelColor(entry.level)"
            >
              {{ entry.level }}
            </span>
            <div class="flex-1" />
            <span class="text-base-content/40 text-xs tabular-nums">
              {{ entry.time }}
            </span>
          </div>
          <div class="text-base-content/70 w-full break-words pl-8 leading-relaxed">
            {{ entry.msg }}
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import { exec, TS_DIR } from '@/composables/useKsu'
import { usePaddingForViews } from '@/composables/paddingViews'
import { showNotification } from '@/helper/notification'
import { ArrowPathIcon, TrashIcon } from '@heroicons/vue/24/outline'
import { computed, nextTick, onActivated, onDeactivated, onMounted, onUnmounted, ref, watch } from 'vue'
import { useAutoRefresh } from '@/composables/useAutoRefresh'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })

interface LogEntry { time: string; level: string; msg: string }

const SOURCES = [
  { key: 'tailscaled.log', label: '守护进程' },
  { key: 'net_probe.log', label: '网络诊断' },
  { key: 'up.log', label: '登录' },
  { key: 'watchdog.log', label: '看门狗' },
  { key: 'resolv.log', label: 'DNS' },
  { key: 'install_bins.log', label: '二进制' },
]
const source = ref('tailscaled.log')
const logPath = computed(() => `${TS_DIR}/log/${source.value}`)

const logs = ref<LogEntry[]>([])
const loadingLogs = ref(false)
const follow = ref(true)
let followTimer: number | undefined

function parseLine(line: string): LogEntry | null {
  if (!line.trim() || line.includes('[RATELIMIT]')) return null
  const m1 = line.match(/^time="([^"]+)"\s+level=(\w+)\s+msg="(.*)"$/)
  if (m1) {
    return {
      time: m1[1].replace(/T/, ' ').replace(/\.\d+\+.*/, ''),
      level: m1[2],
      msg: m1[3],
    }
  }
  const m2 = line.match(/^(\d{4}\/\d{2}\/\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.*)/)
  if (m2) {
    const msg = m2[2]
    const level = /error|fatal|panic/i.test(msg) ? 'error' : /warn/i.test(msg) ? 'warning' : 'info'
    return { time: m2[1], level, msg }
  }
  return { time: '', level: 'info', msg: line }
}

function levelColor(level: string) {
  switch (level.toLowerCase()) {
    case 'error': case 'fatal': case 'panic': return 'text-error'
    case 'warning': case 'warn': return 'text-warning'
    case 'info': return 'text-info'
    case 'debug': return 'text-accent'
    default: return 'text-base-content/50'
  }
}

const loadLogs = async () => {
  if (loadingLogs.value) return
  loadingLogs.value = true
  try {
    const res = await exec(`tail -300 ${logPath.value} 2>/dev/null || echo ''`)
    const parsed = res.stdout.split('\n').map(parseLine).filter(Boolean) as LogEntry[]
    parsed.forEach((e, i) => { (e as any).seq = i + 1 })
    logs.value = parsed.reverse()
  } finally {
    loadingLogs.value = false
  }
}

async function clearLog() {
  if (loadingLogs.value) return
  loadingLogs.value = true
  try {
    // 截断而不是 rm：tailscaled 长期持有这个 fd，删掉文件它只会继续往已删除的
    // inode 里写，日志页再也读不到（直到重启才重建）。截断后它从 0 接着写。
    await exec(`: > ${logPath.value} 2>/dev/null; true`)
    logs.value = []
    showNotification({ content: '已清空当前日志', type: 'alert-success', timeout: 2000 })
  } finally {
    loadingLogs.value = false
  }
}

const followTick = async () => {
  if (!follow.value) return
  const res = await exec(`tail -300 ${logPath.value} 2>/dev/null || echo ''`)
  const parsed = res.stdout.split('\n').map(parseLine).filter(Boolean) as LogEntry[]
  if (parsed.length !== logs.value.length || (parsed.length > 0 && parsed[parsed.length - 1].msg !== logs.value[0]?.msg)) {
    parsed.forEach((e, i) => { (e as any).seq = i + 1 })
    logs.value = parsed.reverse()
  }
}

function startFollow() {
  if (!follow.value || followTimer) return
  followTimer = setInterval(followTick, 3000) as unknown as number
}
function stopFollow() {
  if (!followTimer) return
  clearInterval(followTimer)
  followTimer = undefined
}

watch(follow, (val) => { if (val) startFollow(); else stopFollow() })

onMounted(() => {
  loadLogs()
  startFollow()
})
// 页面被 KeepAlive 缓存时定时器不会自己停，切走就关掉，省点开销
onActivated(() => { startFollow() })
onDeactivated(() => { stopFollow() })
onUnmounted(() => { stopFollow() })
useAutoRefresh(loadLogs)
</script>
