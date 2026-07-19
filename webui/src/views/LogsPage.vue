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
        <button
          class="btn btn-ghost btn-sm btn-circle"
          :disabled="loadingLogs"
          @click="loadLogs"
        >
          <ArrowPathIcon class="h-4 w-4" :class="loadingLogs ? 'animate-spin' : ''" />
        </button>
        <button
          class="btn btn-ghost btn-sm btn-circle"
          @click="logs = []"
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
import { exec, LOG } from '@/composables/useKsu'
import { usePaddingForViews } from '@/composables/paddingViews'
import { ArrowPathIcon, TrashIcon } from '@heroicons/vue/24/outline'
import { nextTick, onMounted, onUnmounted, ref, watch } from 'vue'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })

interface LogEntry { time: string; level: string; msg: string }

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
    const res = await exec(`tail -300 ${LOG} 2>/dev/null || echo ''`)
    const parsed = res.stdout.split('\n').map(parseLine).filter(Boolean) as LogEntry[]
    parsed.forEach((e, i) => { (e as any).seq = i + 1 })
    logs.value = parsed.reverse()
  } finally {
    loadingLogs.value = false
  }
}

const followTick = async () => {
  if (!follow.value) return
  const res = await exec(`tail -300 ${LOG} 2>/dev/null || echo ''`)
  const parsed = res.stdout.split('\n').map(parseLine).filter(Boolean) as LogEntry[]
  if (parsed.length !== logs.value.length || (parsed.length > 0 && parsed[parsed.length - 1].msg !== logs.value[0]?.msg)) {
    parsed.forEach((e, i) => { (e as any).seq = i + 1 })
    logs.value = parsed.reverse()
  }
}

watch(follow, (val) => {
  if (val) followTimer = setInterval(followTick, 3000) as unknown as number
  else if (followTimer) { clearInterval(followTimer); followTimer = undefined }
})

onMounted(() => {
  loadLogs()
  if (follow.value) followTimer = setInterval(followTick, 3000) as unknown as number
})
onUnmounted(() => { if (followTimer) clearInterval(followTimer) })
</script>
