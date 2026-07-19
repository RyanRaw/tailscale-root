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
            <span class="text-sm">{{ state.binVersion || '未安装' }}</span>
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
          <div class="setting-item justify-end gap-2" :style="displayLog.length ? 'border-bottom: none' : ''"
          >
            <button
              class="btn btn-ghost btn-sm"
              :disabled="checking || installing"
              @click="checkLatest"
            >
              检查更新
            </button>
            <button
              class="btn btn-primary btn-sm"
              :disabled="installing || (!latestVersion && !customUrl)"
              @click="startInstall"
            >
              {{ installing ? '安装中…' : hasUpdate ? '更新' : '安装' }}
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
import { useKsu, TS_DIR, MODDIR, PIDFILE } from '@/composables/useKsu'
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import { usePaddingForViews } from '@/composables/paddingViews'
import { computed, nextTick, onMounted, ref } from 'vue'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const { state, busy, refreshing, refresh, act, exec } = useKsu()

const versionTag = ref('')
const customUrl = ref('')
const installing = ref(false)
const checking = ref(false)
const latestVersion = ref('')
const installLog = ref<string[]>([])
const logContainer = ref<HTMLElement>()

const hasUpdate = computed(() => {
  if (!latestVersion.value || !state.value.binVersion) return false
  return latestVersion.value !== state.value.binVersion
})

const displayLog = computed(() =>
  installLog.value.filter(l => !l.startsWith('__'))
)

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
  const lines = r.stdout.split('\n').filter((l: string) => l.trim())
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
  refresh()
  checkLatest()
})
</script>
