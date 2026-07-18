<template>
  <div
    class="h-full overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
    <CtrlsBar>
      <div class="flex h-12 flex-row items-center gap-2 p-2 text-sm">
        <span>节点</span>
        <span class="text-base-content/40">|</span>
        <span class="tabular-nums"><span class="text-success">{{ onlineCount }}</span><span class="text-base-content/40"> / {{ totalCount }}</span></span>
        <div class="flex-1" />
        <label class="flex items-center gap-1.5">
          <span class="text-base-content/50 text-xs">离线</span>
          <input v-model="showOffline" type="checkbox" class="toggle toggle-xs" />
        </label>
        <button class="btn btn-ghost btn-sm btn-circle" @click="showIPs = !showIPs">
          <EyeIcon v-if="showIPs" class="h-4 w-4" />
          <EyeSlashIcon v-else class="h-4 w-4" />
        </button>
        <button
          class="btn btn-ghost btn-sm btn-circle"
          :disabled="refreshing"
          @click="refresh()"
        >
          <ArrowPathIcon class="h-4 w-4" :class="refreshing ? 'animate-spin' : ''" />
        </button>
      </div>
    </CtrlsBar>

    <div class="mx-auto w-full max-w-3xl space-y-1 p-3 md:px-8 md:py-6">

      <div
        v-if="!state.loaded"
        class="text-base-content/40 py-8 text-center text-sm"
      >
        加载中…
      </div>
      <div
        v-else-if="!hasPeers"
        class="text-base-content/40 py-8 text-center text-sm"
      >
        暂无节点
      </div>

      <div v-else class="base-container">
        <!-- Self node -->
        <div
          v-if="selfNode && state.status?.BackendState === 'Running'"
          class="hover:bg-base-200/40 flex flex-col gap-0.5 px-3 py-2 transition-colors border-b border-base-content/5"
        >
          <div class="flex items-center gap-2">
            <div class="bg-success h-2.5 w-2.5 shrink-0 rounded-full" />
            <span class="text-main truncate font-medium text-sm">{{ selfNode.HostName || selfNode.DNSName }}</span>
            <span class="badge badge-ghost badge-xs">本机</span>
            <span class="flex-1" />
            <span class="text-base-content/40 text-xs uppercase">{{ selfNode.OS }}</span>
          </div>
          <div class="text-base-content/50 flex items-center gap-3 pl-[18px] text-xs tabular-nums">
            <span>{{ showIPs ? (selfNode.TailscaleIPs?.[0] || '') : '***.***.***.***' }}</span>
          </div>
        </div>

        <!-- Peers -->
        <div
          v-for="(peer, idx) in filteredPeers"
          :key="peer.PublicKey"
          class="hover:bg-base-200/40 flex flex-col gap-0.5 px-3 py-2 transition-colors"
          :class="idx < filteredPeers.length - 1 && 'border-b border-base-content/5'"
        >
          <div class="flex items-center gap-2">
            <div class="h-2.5 w-2.5 shrink-0 rounded-full" :class="peer.Online ? 'bg-success' : 'bg-base-content/20'" />
            <span class="text-main truncate font-medium text-sm flex-1">{{ peer.HostName || peer.DNSName }}</span>
            <span class="text-base-content/40 text-xs uppercase">{{ peer.OS }}</span>
            <button
              v-if="peer.Online"
              class="btn btn-ghost btn-xs btn-circle"
              :disabled="busy"
              @click="openPingModal(peer)"
            >
              <SignalIcon class="h-3.5 w-3.5" />
            </button>
          </div>
          <div class="text-base-content/50 flex items-center gap-3 pl-[18px] text-xs tabular-nums">
            <span v-if="peer.TailscaleIPs?.length">{{ showIPs ? peer.TailscaleIPs[0] : '***.***.***.***' }}</span>
            <span v-if="peer.Online && peer.CurAddr" class="text-success">直连</span>
            <span v-else-if="peer.Online && peer.Relay">DERP({{ peer.Relay }})</span>
            <span v-else-if="!peer.Online && peer.LastSeen" class="text-base-content/30">{{ fmtLastSeen(peer.LastSeen) }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Ping Modal -->
    <DialogWrapper
      v-model="pingModalOpen"
      :title="'Ping ' + pingModalName"
    >
      <div class="flex flex-col gap-3">
        <!-- Latency Chart (zashboard style) -->
        <div class="flex h-24 items-end gap-0.5">
          <div
            v-for="(bar, i) in pingBars"
            :key="i"
            class="flex-1 rounded-[2px] transition-all duration-300"
            :class="bar.class"
            :style="{ height: bar.height }"
          />
        </div>

        <!-- Stats -->
        <div class="flex gap-4 text-[11px] tabular-nums">
          <template v-if="pingStats">
            <span><span class="text-base-content/40 mr-1">min</span><span :class="latencyColor(pingStats.min)">{{ pingStats.min }}ms</span></span>
            <span><span class="text-base-content/40 mr-1">avg</span><span>{{ pingStats.avg }}ms</span></span>
            <span><span class="text-base-content/40 mr-1">max</span><span :class="latencyColor(pingStats.max)">{{ pingStats.max }}ms</span></span>
            <span><span class="text-base-content/40 mr-1">loss</span><span :class="pingStats.loss > 0 ? 'text-error' : ''">{{ pingStats.loss }}%</span></span>
          </template>
          <span v-else class="text-base-content/30">--</span>
        </div>

        <!-- Route -->
        <div v-if="pingRoute" class="text-base-content/50 text-xs">
          {{ pingRoute }} → {{ pingModalIp }}
        </div>

        <div class="flex gap-2">
          <button
            class="btn btn-sm btn-primary flex-1"
            :disabled="pinging"
            @click="runPing"
          >
            {{ pinging ? '测试中…' : '重新测试' }}
          </button>
        </div>
      </div>
    </DialogWrapper>
  </div>
</template>

<script setup lang="ts">
import DialogWrapper from '@/components/common/DialogWrapper.vue'
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import { useKsu, BIN, SOCK } from '@/composables/useKsu'
import { usePaddingForViews } from '@/composables/paddingViews'
import { ArrowPathIcon, SignalIcon, EyeIcon, EyeSlashIcon } from '@heroicons/vue/24/outline'
import { computed, onMounted, ref } from 'vue'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const { state, busy, refreshing, refresh, act, exec } = useKsu()

const showOffline = ref(false)
const showIPs = ref(false)
const pingModalOpen = ref(false)
const pingModalName = ref('')
const pingModalIp = ref('')
const pinging = ref(false)
const pingRoute = ref('')
const ROUNDS = 10
const pingValues = ref<number[]>([])

const selfNode = computed(() => state.value.status?.Self || null)

const peers = computed(() => {
  if (!state.value.status?.Peer) return []
  return (Object.values(state.value.status.Peer) as any[]).sort((a, b) => {
    if (!!b.Online !== !!a.Online) return (b.Online ? 1 : 0) - (a.Online ? 1 : 0)
    return (a.HostName || '').localeCompare(b.HostName || '')
  })
})
const onlineCount = computed(() => peers.value.filter((p: any) => p.Online).length + (selfNode.value ? 1 : 0))
const totalCount = computed(() => peers.value.length + (selfNode.value ? 1 : 0))
const filteredPeers = computed(() => showOffline.value ? peers.value : peers.value.filter((p: any) => p.Online))
const hasPeers = computed(() => peers.value.length > 0)

function fmtLastSeen(iso: string) {
  if (!iso) return ''
  const d = Math.floor((Date.now() - new Date(iso).getTime()) / 86400000)
  if (d <= 0) return '今天在线'
  return d + ' 天前'
}

function latencyColor(ms: number) {
  if (ms < 60) return 'text-low-latency'
  if (ms < 150) return 'text-medium-latency'
  return 'text-high-latency'
}

function barColorClass(ms: number) {
  if (ms < 60) return 'bg-low-latency'
  if (ms < 150) return 'bg-medium-latency'
  return 'bg-high-latency'
}

const pingBars = computed(() => {
  const ceil = Math.max(...pingValues.value.filter(v => v > 0), 1)
  return Array.from({ length: ROUNDS }, (_, i) => {
    if (i >= pingValues.value.length) {
      return { class: 'bg-base-content/10', height: '18%' }
    }
    const v = pingValues.value[i]
    if (v <= 0) {
      return { class: 'bg-high-latency opacity-40', height: '100%' }
    }
    const pct = Math.max(18, Math.round((v / ceil) * 100))
    return { class: barColorClass(v), height: `${pct}%` }
  })
})

const pingStats = computed(() => {
  const ok = pingValues.value.filter(v => v > 0)
  if (!ok.length) return null
  const total = pingValues.value.length
  const lost = total - ok.length
  return {
    min: Math.round(Math.min(...ok)),
    avg: Math.round(ok.reduce((a, b) => a + b, 0) / ok.length),
    max: Math.round(Math.max(...ok)),
    loss: Math.round((lost / total) * 100),
  }
})

function parsePong(out: string) {
  const m = out.match(/in ([0-9.]+)ms/)
  if (!m) return null
  const direct = out.match(/via ([0-9a-fA-F.:\[\]]+:[0-9]+) in/)
  const derp = out.match(/via DERP\(([^)]+)\)/)
  return {
    ms: parseFloat(m[1]),
    route: direct ? '直连 ' + direct[1] : derp ? 'DERP(' + derp[1] + ')' : '?',
  }
}

function openPingModal(peer: any) {
  const ip = peer.TailscaleIPs?.[0]
  if (!ip) return
  pingModalName.value = peer.HostName || peer.DNSName || ip
  pingModalIp.value = ip
  pingValues.value = []
  pingRoute.value = ''
  pingModalOpen.value = true
  runPing()
}

async function runPing() {
  if (pinging.value) return
  pinging.value = true
  pingValues.value = []
  pingRoute.value = ''

  for (let i = 0; i < ROUNDS; i++) {
    if (!pingModalOpen.value) break
    const r = await exec(`timeout 6 ${BIN} --socket=${SOCK} ping -c 1 --timeout=3s ${pingModalIp.value} 2>&1 | grep -E "pong from|timed out" | tail -1`)
    const p = parsePong(r.stdout + r.stderr)
    if (p) {
      pingValues.value = [...pingValues.value, p.ms]
      pingRoute.value = p.route
    } else {
      pingValues.value = [...pingValues.value, 0]
    }
    if (i < ROUNDS - 1 && pingModalOpen.value) {
      await new Promise(r => setTimeout(r, 500))
    }
  }
  pinging.value = false
}

onMounted(() => { refresh() })
</script>
