<template>
  <div
    ref="scrollEl"
    class="h-full overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
    <PullRefreshIndicator
      :distance="pullDistance"
      :refreshing="pullRefreshing"
      :dragging="pullDragging"
      :ready="pullReady"
      :threshold="pullThreshold"
    />
    <CtrlsBar>
      <div class="flex h-12 flex-row items-center gap-2 p-2 text-sm">
        <span>安装</span>
        <template v-if="state.binVersion">
          <span class="text-base-content/40">|</span>
          <span class="text-base-content/60">{{ state.binVersion }}</span>
        </template>
      </div>
    </CtrlsBar>

    <div class="mx-auto w-full max-w-3xl space-y-1 p-3 md:px-8 md:py-6">
      <!-- 唯一的一份版本 -->
      <div>
        <div class="settings-section-label">版本</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">当前版本</div>
            <span class="text-sm">
              {{ state.binVersion || '未安装' }}
              <span v-if="sourceLabel" class="badge badge-xs badge-outline ml-1">{{ sourceLabel }}</span>
              <span v-if="info.pinned" class="badge badge-xs badge-warning ml-1">已锁定</span>
            </span>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">运行路径</div>
            <span class="text-xs text-base-content/50 break-all">
              {{ state.exePath || (state.binInstalled ? DAEMON : '—') }}
            </span>
          </div>
          <div v-if="info.origin" class="setting-item">
            <div class="setting-item-label">安装来源</div>
            <span class="text-xs text-base-content/50 break-all">{{ info.origin }}</span>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">最新版本</div>
            <div class="flex items-center gap-2">
              <span v-if="checking" class="loading loading-spinner loading-xs"></span>
              <span v-else-if="latestVersion" class="text-sm">
                {{ latestVersion }}
                <span v-if="hasUpdate" class="text-success text-xs ml-1">可更新</span>
                <span v-else class="text-base-content/40 text-xs ml-1">已是最新</span>
              </span>
              <span v-else class="text-base-content/40 text-sm">未检查</span>
            </div>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              离线包
              <span class="text-base-content/30 ml-1 text-xs">仅兜底</span>
            </div>
            <span class="text-sm">
              <template v-if="info.available">
                {{ info.bundle }}
                <span class="text-base-content/40 text-xs ml-1">{{ info.arch }}</span>
              </template>
              <span v-else class="text-base-content/40">不可用（{{ reasonText }}）</span>
            </span>
          </div>
          <div class="setting-item justify-end gap-2 flex-wrap" :style="displayLog.length ? 'border-bottom: none' : ''">
            <button
              class="btn btn-primary btn-sm"
              :disabled="installing || checking || info.pinned || !latestVersion"
              :title="info.pinned ? '当前版本已锁定，先解除锁定' : ''"
              @click="runInstall('latest')"
            >
              {{ info.pinned ? '已锁定' : hasUpdate ? '更新到最新' : '是最新版' }}
            </button>
            <button
              class="btn btn-ghost btn-sm"
              :disabled="checking || installing"
              @click="checkLatest"
            >
              检查更新
            </button>
            <button
              v-if="info.pinned"
              class="btn btn-ghost btn-sm"
              :disabled="installing"
              @click="unpin"
            >
              解除锁定
            </button>
          </div>
          <!-- Install log -->
          <div v-if="displayLog.length > 0" class="bg-base-200/30 rounded-lg mx-3 mb-3 overflow-hidden" style="border-top: none">
            <div
              ref="logContainer"
              class="max-h-48 overflow-y-auto px-3 py-2"
            >
              <div
                v-for="(line, i) in displayLog"
                :key="i"
                class="text-xs leading-5"
                :class="line.startsWith('✗') ? 'text-error' : line.startsWith('✓') ? 'text-success' : 'text-base-content/60'"
              >
                {{ line }}
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- 指定版本 / 其他来源：都是往同一个位置装，装完即锁定 -->
      <div>
        <div class="settings-section-label">安装其他版本</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">指定版本</div>
            <div class="flex items-center gap-2">
              <input
                v-model="versionTag"
                type="text"
                class="input input-sm w-28"
                placeholder="如 1.98.8"
                :disabled="installing"
              />
              <button
                class="btn btn-sm"
                :disabled="installing || !versionTag.trim()"
                @click="runInstall('version')"
              >
                安装
              </button>
            </div>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">自定义 URL</div>
            <div class="flex items-center gap-2">
              <input
                v-model="customUrl"
                type="text"
                class="input input-sm w-52"
                placeholder="完整 .tgz 链接"
                :disabled="installing"
              />
              <button
                class="btn btn-sm"
                :disabled="installing || !customUrl.trim()"
                @click="runInstall('url')"
              >
                安装
              </button>
            </div>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">本地文件</div>
            <div class="flex items-center gap-2">
              <input
                v-model="localPath"
                type="text"
                class="input input-sm w-52"
                placeholder="tailscaled / 目录 / .tgz"
                :disabled="installing"
              />
              <button
                class="btn btn-ghost btn-sm"
                :disabled="scanning || installing"
                @click="scanBinaries"
              >
                {{ scanning ? '扫描中…' : '扫描' }}
              </button>
              <button
                class="btn btn-sm"
                :disabled="installing || !localPath.trim()"
                @click="runInstall('local')"
              >
                安装
              </button>
            </div>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              CLI 路径
              <span class="text-base-content/30 ml-1 text-xs">可选</span>
            </div>
            <input
              v-model="localCli"
              type="text"
              class="input input-sm w-52"
              placeholder="留空则保留现有 CLI"
              :disabled="installing"
            />
          </div>
          <div v-if="candidates.length" class="flex flex-wrap gap-1 px-3 pt-1 pb-2">
            <button
              v-for="c in candidates"
              :key="c"
              class="btn btn-xs btn-ghost normal-case font-normal"
              :title="c"
              :disabled="installing"
              @click="localPath = c"
            >
              {{ baseName(c) }}
            </button>
          </div>
          <div class="setting-item justify-end">
            <span class="text-xs text-base-content/40">指定版本 / 文件装完会锁定，不会被「更新到最新」覆盖</span>
          </div>
        </div>
      </div>

      <!-- 兜底 -->
      <div>
        <div class="settings-section-label">兜底</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">离线包重装</div>
            <span class="text-xs text-base-content/40">用模块自带的 {{ info.bundle || '—' }} 覆盖当前版本</span>
          </div>
          <div class="setting-item justify-end">
            <button
              class="btn btn-ghost btn-sm"
              :disabled="installing || !info.available"
              @click="installBundle"
            >
              用离线包重装
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useKsu, MODDIR, DAEMON, restartTailscaled } from '@/composables/useKsu'
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import PullRefreshIndicator from '@/components/common/PullRefreshIndicator.vue'
import { usePaddingForViews } from '@/composables/paddingViews'
import { computed, nextTick, onMounted, ref } from 'vue'
import { useAutoRefresh } from '@/composables/useAutoRefresh'
import { usePullRefresh } from '@/composables/usePullRefresh'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const { state, refresh, exec } = useKsu()

const scrollEl = ref<HTMLElement>()
const {
  distance: pullDistance,
  refreshing: pullRefreshing,
  dragging: pullDragging,
  ready: pullReady,
  threshold: pullThreshold,
} = usePullRefresh(scrollEl, async () => {
  await loadInfo()
  await refresh()
})

const versionTag = ref('')
const customUrl = ref('')
const localPath = ref('')
const localCli = ref('')
const installing = ref(false)
const checking = ref(false)
const latestVersion = ref('')
const installLog = ref<string[]>([])
const logContainer = ref<HTMLElement>()
const candidates = ref<string[]>([])
const scanning = ref(false)

// 模块里只有一份二进制，来源只是信息，不是"内置/外置"两种状态
const info = ref({
  available: false,
  bundle: '',
  arch: '',
  reason: '',
  source: '',
  origin: '',
  pinned: false,
})

const SOURCE_LABEL: Record<string, string> = {
  bundle: '离线包',
  online: '在线安装',
  local: '本地文件',
  unknown: '来源未知',
}

const reasonText = computed(() => {
  switch (info.value.reason) {
    case 'missing': return '当前安装包不含二进制'
    case 'incomplete': return '包内文件不完整'
    case 'arch': return '架构未知'
    default: return '当前安装包不含二进制'
  }
})

const baseName = (p: string) => p.slice(p.lastIndexOf('/') + 1)

const scanBinaries = async () => {
  if (scanning.value) return
  scanning.value = true
  try {
    const r = await exec(
      "find /sdcard/Download /sdcard/Downloads /sdcard /data/local/tmp -maxdepth 1 -type f -iname '*tailscale*' 2>/dev/null | head -60",
    )
    candidates.value = r.stdout.split('\n').map((s) => s.trim()).filter(Boolean)
    if (!candidates.value.length) pushLog('未在常用目录找到 tailscale 相关文件')
  } finally {
    scanning.value = false
  }
}

const hasUpdate = computed(() => {
  if (!latestVersion.value || !state.value.binVersion) return false
  return latestVersion.value !== state.value.binVersion
})

const displayLog = computed(() => installLog.value.filter((l) => !l.startsWith('__')))

const pushLog = (text: string) => {
  const lines = text.split('\n').filter((l) => l.trim() && !l.startsWith('__'))
  if (lines.length) installLog.value = [...installLog.value, ...lines]
  scrollLogToEnd()
}

const scrollLogToEnd = () => {
  nextTick(() => {
    if (logContainer.value) logContainer.value.scrollTop = logContainer.value.scrollHeight
  })
}

const loadInfo = async () => {
  const r = await exec(`sh ${MODDIR}/install_bins.sh --info 2>/dev/null`)
  const kv: Record<string, string> = {}
  r.stdout.split('\n').forEach((l) => {
    const i = l.indexOf('=')
    if (i > 0) kv[l.slice(0, i)] = l.slice(i + 1).trim()
  })
  info.value = {
    available: kv.AVAILABLE === '1',
    bundle: kv.BUNDLE || '',
    arch: kv.ARCH || '',
    reason: kv.REASON || '',
    source: kv.SOURCE || '',
    origin: kv.ORIGIN || '',
    pinned: kv.PINNED === '1',
  }
}

const sourceLabel = computed(() => SOURCE_LABEL[info.value.source] || '')

const checkLatest = async () => {
  checking.value = true
  try {
    let r = await exec('curl -sL --max-time 10 https://api.github.com/repos/tailscale/tailscale/releases/latest | grep \'"tag_name"\' | head -1')
    let m = r.stdout.match(/"v?([0-9.]+)"/)
    if (!m) {
      r = await exec('curl -sL --max-time 10 -x http://127.0.0.1:7890 --http1.1 https://api.github.com/repos/tailscale/tailscale/releases/latest | grep \'"tag_name"\' | head -1')
      m = r.stdout.match(/"v?([0-9.]+)"/)
    }
    latestVersion.value = m ? m[1] : ''
  } finally {
    checking.value = false
  }
}

const LOG_FILE = '/data/local/tmp/ts_install.log'
let pollTimer: number | undefined

const pollLog = async () => {
  const r = await exec('cat ' + LOG_FILE + ' 2>/dev/null || echo ""')
  const lines = r.stdout.split('\n').filter((l) => l.trim())
  installLog.value = lines
  scrollLogToEnd()

  const last = lines[lines.length - 1] || ''
  if (last.startsWith('__DONE__') || last.startsWith('__FAIL__')) {
    if (pollTimer) clearInterval(pollTimer)
    pollTimer = undefined
    installing.value = false
    state.value.binInstalled = false
    await refresh()
    await loadInfo()
  }
}

// 所有安装入口都走同一个脚本、同一个位置：这里只负责拼参数和收日志
const runInstall = async (kind: 'latest' | 'version' | 'url' | 'local') => {
  if (installing.value) return
  let arg = ''
  if (kind === 'version') arg = versionTag.value.trim()
  if (kind === 'url') arg = customUrl.value.trim()
  if (kind === 'local') arg = localPath.value.trim().replace(/'/g, '')
  if (kind !== 'latest' && !arg) return

  installing.value = true
  installLog.value = []

  const quoted = arg.replace(/'/g, "'\\''")
  let cmd = ''
  switch (kind) {
    case 'latest': cmd = `sh ${MODDIR}/install_version.sh --online`; break
    case 'version': cmd = `sh ${MODDIR}/install_version.sh --online '${quoted}'`; break
    case 'url': cmd = `sh ${MODDIR}/install_version.sh --online '${quoted}'`; break
    case 'local': {
      const cli = localCli.value.trim().replace(/'/g, '')
      cmd = `sh ${MODDIR}/install_version.sh --local '${quoted}'` + (cli ? ` --cli '${cli}'` : '')
      break
    }
  }

  // 脚本自己会停/起守护进程；这里把输出接到日志文件，前端轮询显示
  const wrapper = [
    `if ${cmd} > ${LOG_FILE} 2>&1; then echo "__DONE__" >> ${LOG_FILE}; else echo "__FAIL__" >> ${LOG_FILE}; fi`,
  ].join('\n')

  await exec(': > ' + LOG_FILE)
  await exec(`(${wrapper}) &`)
  if (pollTimer) clearInterval(pollTimer)
  pollTimer = setInterval(pollLog, 800) as unknown as number
}

const unpin = async () => {
  if (installing.value) return
  installing.value = true
  installLog.value = []
  try {
    const r = await exec(`sh ${MODDIR}/install_version.sh --pin off 2>&1`)
    pushLog(r.stdout)
    await loadInfo()
  } finally {
    installing.value = false
  }
}

// 兜底：用离线包覆盖当前版本（显式操作，会清掉锁定）
const installBundle = async () => {
  if (installing.value) return
  installing.value = true
  installLog.value = []
  try {
    const r = await exec(`sh ${MODDIR}/install_bins.sh --force 2>&1`)
    pushLog(r.stdout + '\n' + r.stderr)
    if (r.errno === 0) {
      const up = await restartTailscaled()
      pushLog(up ? '✓ 守护进程已重启' : '✗ 守护进程启动失败')
      state.value.binInstalled = false
      await refresh()
    } else {
      pushLog('✗ 安装失败')
    }
  } finally {
    installing.value = false
    loadInfo()
  }
}

onMounted(async () => {
  await loadInfo()
  refresh()
  checkLatest()
})
// 只重读安装状态；checkLatest 要发网络请求，留给手动刷新
useAutoRefresh(async () => {
  await loadInfo()
  await refresh()
})
</script>
