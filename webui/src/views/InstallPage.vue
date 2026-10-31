<template>
  <div
    class="h-full overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
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
      <div>
        <div class="settings-section-label">版本管理</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">当前版本</div>
            <span class="text-sm">
              {{ state.binVersion || '未安装' }}
              <span v-if="bundle.custom" class="badge badge-xs badge-warning badge-outline ml-1">外置</span>
            </span>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">当前来源</div>
            <div class="flex flex-col">
              <span class="text-sm">{{ sourceLabel }}</span>
              <span class="text-xs text-base-content/40 break-all mt-0.5">
                {{ state.exePath || (state.binInstalled ? DAEMON : '—') }}
              </span>
            </div>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">离线包</div>
            <span class="text-sm">
              <template v-if="bundle.available">
                {{ bundle.version }}
                <span class="text-base-content/40 text-xs ml-1">{{ bundle.arch }}</span>
              </template>
              <span v-else class="text-base-content/40">不可用（{{ reasonText }}）</span>
            </span>
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
          <div class="setting-item justify-end gap-2 flex-wrap" :style="displayLog.length ? 'border-bottom: none' : ''"
          >
            <button
              class="btn btn-primary btn-sm"
              :disabled="installing || !bundle.available"
              @click="installBundle"
            >
              {{ bundleLabel }}
            </button>
            <button
              class="btn btn-ghost btn-sm"
              :disabled="checking || installing"
              @click="checkLatest"
            >
              检查更新
            </button>
            <button
              class="btn btn-ghost btn-sm"
              :disabled="installing || (!latestVersion && !customUrl)"
              @click="startInstall"
            >
              在线安装
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

      <!-- External (self-built) binaries -->
      <div>
        <div class="settings-section-label">外置二进制</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">守护进程路径</div>
            <input
              v-model="customDaemon"
              type="text"
              class="input input-sm w-52"
              placeholder="/sdcard/Download/tailscaled、目录或 .tgz"
              :disabled="installing"
            />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              CLI 路径
              <span class="text-base-content/30 ml-1 text-xs">可选</span>
            </div>
            <input
              v-model="customCli"
              type="text"
              class="input input-sm w-52"
              placeholder="留空则保留现有 CLI"
              :disabled="installing"
            />
          </div>
          <div class="setting-item justify-end gap-2 flex-wrap">
            <span class="text-xs text-base-content/40">外置版本不会被模块更新覆盖</span>
            <button class="btn btn-ghost btn-sm" :disabled="scanning || installing" @click="scanBinaries">
              {{ scanning ? '扫描中…' : '扫描设备文件' }}
            </button>
            <button
              class="btn btn-sm"
              :disabled="installing || !customDaemon.trim()"
              @click="installCustom"
            >
              {{ bundle.custom ? '重新切换为外置' : '切换为外置' }}
            </button>
            <button
              class="btn btn-ghost btn-error btn-sm"
              :disabled="installing || !bundle.custom"
              @click="deleteCustom"
            >
              删除外置
            </button>
          </div>
          <div v-if="candidates.length" class="flex flex-wrap gap-1 px-3 pt-1 pb-2">
            <button
              v-for="c in candidates"
              :key="c"
              class="btn btn-xs btn-ghost normal-case font-normal"
              :title="c"
              :disabled="installing"
              @click="customDaemon = c"
            >
              {{ baseName(c) }}
            </button>
          </div>
          <div v-if="bundle.customSrc" class="setting-item">
            <div class="setting-item-label">来源文件</div>
            <span class="text-xs text-base-content/50 break-all">{{ bundle.customSrc }}</span>
          </div>
        </div>
      </div>

      <!-- Advanced -->
      <div>
        <div class="settings-section-label">高级</div>
        <div class="settings-grid">
          <div class="setting-item">
            <div class="setting-item-label">指定版本</div>
            <input
              v-model="versionTag"
              type="text"
              class="input input-sm w-28"
              placeholder="如 1.98.8"
              :disabled="installing"
            />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">自定义 URL</div>
            <input
              v-model="customUrl"
              type="text"
              class="input input-sm w-40"
              placeholder="完整下载链接"
              :disabled="installing"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useKsu, TS_DIR, MODDIR, PIDFILE, DAEMON } from '@/composables/useKsu'
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import { usePaddingForViews } from '@/composables/paddingViews'
import { showConfirmDialog } from '@/helper/confirmDialog'
import { computed, nextTick, onMounted, ref } from 'vue'
import { useAutoRefresh } from '@/composables/useAutoRefresh'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const { state, busy, refreshing, refresh, act, exec } = useKsu()

const versionTag = ref('')
const customUrl = ref('')
const installing = ref(false)
const checking = ref(false)
const latestVersion = ref('')
const installLog = ref<string[]>([])
const logContainer = ref<HTMLElement>()

const bundle = ref({ available: false, version: '', arch: '', reason: '', custom: false, customSrc: '' })

const reasonText = computed(() => {
  switch (bundle.value.reason) {
    case 'missing': return '当前安装包不含二进制，刷完整包可恢复'
    case 'incomplete': return '包内文件不完整'
    case 'arch': return '架构未知'
    default: return '当前安装包不含二进制'
  }
})
const customDaemon = ref('')
const customCli = ref('')
const candidates = ref<string[]>([])
const scanning = ref(false)

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

const bundleLabel = computed(() => {
  if (installing.value) return '安装中…'
  if (!bundle.value.available) return '无离线包'
  if (!state.value.binInstalled) return '使用内置'
  // 外置（自定义/在线装的）也算"需要切回来"，否则标签会显示成"重装内置"
  if (bundle.value.custom) return '切换到内置'
  if (bundle.value.version && state.value.binVersion !== bundle.value.version) return '切换到内置'
  return '重装内置'
})

const sourceLabel = computed(() => {
  if (!state.value.binInstalled) return '未安装'
  return bundle.value.custom ? '外置（自定义/在线安装）' : '内置（离线包）'
})

const displayLog = computed(() =>
  installLog.value.filter(l => !l.startsWith('__'))
)

const pushLog = (text: string) => {
  const lines = text.split('\n').filter(l => l.trim() && !l.startsWith('__'))
  if (lines.length) installLog.value = [...installLog.value, ...lines]
  nextTick(() => {
    if (logContainer.value) logContainer.value.scrollTop = logContainer.value.scrollHeight
  })
}

const loadBundle = async () => {
  const r = await exec(`sh ${MODDIR}/install_bins.sh --info 2>/dev/null`)
  const kv: Record<string, string> = {}
  r.stdout.split('\n').forEach((l) => {
    const i = l.indexOf('=')
    if (i > 0) kv[l.slice(0, i)] = l.slice(i + 1).trim()
  })
  bundle.value = {
    available: kv.AVAILABLE === '1',
    version: kv.BUNDLED || '',
    arch: kv.ARCH || '',
    reason: kv.REASON || '',
    custom: kv.CUSTOM === '1',
    customSrc: kv.CUSTOM_SRC || '',
  }
}

const installBundle = async () => {
  if (installing.value) return
  installing.value = true
  installLog.value = []
  try {
    const r = await exec(`sh ${MODDIR}/install_bins.sh --force 2>&1`)
    pushLog(r.stdout + '\n' + r.stderr)
    if (r.errno === 0) {
      await exec(`TS_SKIP_WAIT=1 sh ${MODDIR}/service.sh 2>/dev/null`)
      pushLog('✓ 守护进程已重启')
      state.value.binInstalled = false
      await refresh()
    } else {
      pushLog('✗ 安装失败')
    }
  } finally {
    installing.value = false
    loadBundle()
  }
}

const installCustom = async () => {
  const src = customDaemon.value.trim().replace(/'/g, '')
  if (!src || installing.value) return
  const cli = customCli.value.trim().replace(/'/g, '')
  installing.value = true
  installLog.value = []
  try {
    const cmd = `sh ${MODDIR}/install_custom.sh '${src}'` + (cli ? ` --cli '${cli}'` : '')
    const r = await exec(cmd + ' 2>&1')
    pushLog(r.stdout + '\n' + r.stderr)
    if (r.errno === 0) {
      await exec(`TS_SKIP_WAIT=1 sh ${MODDIR}/service.sh 2>/dev/null`)
      pushLog('✓ 守护进程已重启')
      state.value.binInstalled = false
      await refresh()
    } else {
      pushLog('✗ 安装失败')
    }
  } finally {
    installing.value = false
    loadBundle()
  }
}

const deleteCustom = async () => {
  if (installing.value || !bundle.value.custom) return
  const ok = await showConfirmDialog(
    '删除外置二进制',
    '将停止守护进程、删除外置副本与标记；来源文件若在 /sdcard 等外置存储上也会一并删除。模块带内置包时会自动回滚到内置版本。',
  )
  if (!ok) return
  installing.value = true
  installLog.value = []
  try {
    // 脚本内部已负责停 daemon -> 删副本 -> 回滚内置 -> 重启，这里不再重复调 service.sh
    const r = await exec(`sh ${MODDIR}/install_custom.sh --delete 2>&1`)
    pushLog(r.stdout + '\n' + r.stderr)
    if (r.errno !== 0) pushLog('✗ 删除失败')
    state.value.binInstalled = false
    await refresh()
  } finally {
    installing.value = false
    loadBundle()
  }
}

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
  await nextTick()
  if (logContainer.value) logContainer.value.scrollTop = logContainer.value.scrollHeight

  const last = lines[lines.length - 1] || ''
  if (last.startsWith('__DONE__') || last.startsWith('__FAIL__')) {
    clearInterval(pollTimer)
    pollTimer = undefined
    installing.value = false
    if (last.startsWith('__DONE__')) {
      state.value.binInstalled = false
      refresh()
      // 在线安装只动 /data/adb/tailscale/bin，模块里的离线包不受影响，
      // 不重载的话上面那行 "离线包" 会看起来像没生效
      await loadBundle()
      if (!bundle.value.available) {
        installLog.value = [
          ...lines,
          '提示：离线包仍不可用——在线安装只更新运行目录，刷完整包才会补回 bins。',
        ]
      }
    }
  }
}

const startInstall = async () => {
  if (installing.value) return
  installing.value = true
  installLog.value = []

  let url = customUrl.value.trim()
  const ver = versionTag.value.trim() || latestVersion.value || ''

  if (!url) {
    if (!ver) {
      installLog.value = ['正在获取最新版本…']
      await checkLatest()
      if (!latestVersion.value) {
        installLog.value = ['✗ 无法获取最新版本']
        installing.value = false
        return
      }
    }
    const v = (versionTag.value.trim() || latestVersion.value).replace(/^v/, '')
    url = 'https://pkgs.tailscale.com/stable/tailscale_' + v + '_arm64.tgz'
  }

  const script = [
    'exec > ' + LOG_FILE + ' 2>&1',
    'echo "下载: ' + url + '"',
    'TMP="' + TS_DIR + '/dl.tgz"',
    'rm -f "$TMP"',
    'if ! curl -fL --max-time 180 -o "$TMP" "' + url + '" 2>&1 | tail -3; then',
    '  echo "直连失败，通过代理重试…"',
    '  rm -f "$TMP"',
    '  if ! curl -fL --max-time 180 -x http://127.0.0.1:7890 --http1.1 -o "$TMP" "' + url + '" 2>&1 | tail -3; then',
    '    echo "__FAIL__ 下载失败"',
    '    exit 1',
    '  fi',
    'fi',
    '[ ! -f "$TMP" ] && echo "__FAIL__ 下载失败" && exit 1',
    'echo "✓ 下载完成"',
    'echo "停止守护进程…"',
    'pkill -x tailscaled 2>/dev/null; sleep 2',
    'rm -f ' + PIDFILE,
    'echo "解压安装中…"',
    'cd ' + TS_DIR + ' && rm -rf tmp && mkdir tmp && tar -xzf dl.tgz -C tmp 2>&1 && cp tmp/*/tailscale bin/ && cp tmp/*/tailscaled bin/ && chmod 755 bin/tailscale bin/tailscaled && rm -rf tmp dl.tgz',
    '[ $? -ne 0 ] && echo "__FAIL__ 解压失败" && exit 1',
    // user-installed binaries are no longer module managed
    'rm -f ' + TS_DIR + '/bin/.managed_version',
    'echo "✓ 安装完成"',
    'VER=$(' + TS_DIR + '/bin/tailscale --version 2>/dev/null | head -1)',
    'echo "已安装: $VER"',
    'echo "启动守护进程…"',
    'TS_SKIP_WAIT=1 sh ' + MODDIR + '/service.sh',
    'sleep 3',
    'if pidof tailscaled >/dev/null 2>&1; then echo "✓ 守护进程已启动"; else echo "✗ 守护进程启动失败"; fi',
    'echo "__DONE__"',
  ].join('\n')

  await exec(': > ' + LOG_FILE + '; (' + script + ') &')
  pollTimer = setInterval(pollLog, 800) as unknown as number
}

onMounted(() => {
  loadBundle()
  refresh()
  checkLatest()
})
// 只重读安装状态；checkLatest 要发网络请求，留给手动刷新
useAutoRefresh(refresh)
</script>
