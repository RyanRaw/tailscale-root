<template>
  <div
    class="h-full overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
    <CtrlsBar>
      <div class="flex h-12 flex-row items-center gap-2 p-2 text-sm">
        <span>安装</span>
        <span class="text-base-content/40">|</span>
        <span class="text-base-content/60">{{ state.binInstalled ? state.binVersion || '已安装' : '未安装' }}</span>
      </div>
    </CtrlsBar>

    <div class="mx-auto w-full max-w-3xl space-y-1 p-3 md:px-8 md:py-6">
      <div>
      <div class="settings-section-label">当前安装</div>
      <div class="settings-grid">
        <div class="setting-item">
          <div class="setting-item-label">二进制</div>
          <span class="text-sm">{{ state.binInstalled ? '已安装' : '未安装' }}</span>
        </div>
        <div v-if="state.binVersion" class="setting-item">
          <div class="setting-item-label">版本</div>
          <span class="text-sm">{{ state.binVersion }}</span>
        </div>
      </div>
      </div>

      <div>
      <div class="settings-section-label">安装 / 更新</div>
      <div class="settings-grid">
        <div class="setting-item">
          <div class="setting-item-label">版本号</div>
          <input
            v-model="versionTag"
            type="text"
            class="input input-sm w-32"
            placeholder="latest"
          />
        </div>
        <div class="setting-item">
          <div class="setting-item-label">自定义 URL</div>
          <input
            v-model="customUrl"
            type="text"
            class="input input-sm w-40"
            placeholder="可选"
          />
        </div>
        <div class="setting-item justify-end">
          <button
            class="btn btn-primary btn-sm"
            :disabled="installing"
            @click="startInstall"
          >
            {{ installing ? '安装中…' : '安装' }}
          </button>
        </div>
      </div>
      </div>

      <div
        v-if="installLog.length > 0"
        class="base-container"
      >
        <div
          ref="logContainer"
          class="max-h-64 overflow-y-auto"
        >
          <div
            v-for="(line, i) in installLog"
            :key="i"
            class="hover:bg-base-200/40 flex items-start gap-2 border-b border-base-content/5 px-3 py-2 text-sm transition-colors last:border-b-0"
          >
            <span class="text-base-content/30 min-w-5 text-xs tabular-nums">{{ String(i + 1).padStart(2, '0') }}</span>
            <span
              class="text-xs leading-5"
              :class="line.startsWith('ERROR') ? 'text-error' : line.startsWith('OK') ? 'text-success' : 'text-base-content/70'"
            >
              {{ line }}
            </span>
          </div>
        </div>
        <div
          v-if="installDone"
          class="flex gap-2 p-3 border-t border-base-content/5"
        >
          <button
            class="btn btn-success btn-sm"
            :disabled="busy"
            @click="restartDaemon"
          >
            重启守护进程
          </button>
          <button
            class="btn btn-sm"
            @click="installLog = []; installDone = false"
          >
            清空
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useKsu, TS_DIR, MODDIR } from '@/composables/useKsu'
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import { usePaddingForViews } from '@/composables/paddingViews'
import { nextTick, onMounted, ref } from 'vue'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const { state, busy, refreshing, refresh, act, exec } = useKsu()

const versionTag = ref('')
const customUrl = ref('')
const installing = ref(false)
const installDone = ref(false)
const installLog = ref<string[]>([])
const logContainer = ref<HTMLElement>()

const addLog = async (msg: string) => {
  installLog.value.push(msg)
  await nextTick()
  if (logContainer.value) logContainer.value.scrollTop = logContainer.value.scrollHeight
}

const LOG_FILE = '/data/local/tmp/ts_install.log'
let pollTimer: number | undefined

const pollLog = async () => {
  const r = await exec(`cat ${LOG_FILE} 2>/dev/null || echo ''`)
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
      installDone.value = true
      state.value.binInstalled = false
      refresh()
    }
  }
}

const startInstall = async () => {
  if (installing.value) return
  installing.value = true
  installDone.value = false
  installLog.value = []

  let url = customUrl.value.trim()
  const tag = versionTag.value.trim() || 'latest'

  if (!url) {
    if (tag === 'latest') {
      url = '__RESOLVE_LATEST__'
    } else {
      const ver = tag.replace(/^v/, '')
      url = `https://pkgs.tailscale.com/stable/tailscale_${ver}_arm64.tgz`
    }
  }

  const script = `
    exec > ${LOG_FILE} 2>&1
    echo "架构: arm64"
    URL="${url}"
    if [ "$URL" = "__RESOLVE_LATEST__" ]; then
      echo "正在获取最新版本…"
      TAG=$(curl -sL --max-time 10 https://api.github.com/repos/tailscale/tailscale/releases/latest | grep '"tag_name"' | head -1 | grep -o '"v[0-9.]*"' | tr -d '"v')
      if [ -z "$TAG" ]; then
        TAG=$(curl -sL --max-time 10 -x http://127.0.0.1:7890 --http1.1 https://api.github.com/repos/tailscale/tailscale/releases/latest | grep '"tag_name"' | head -1 | grep -o '"v[0-9.]*"' | tr -d '"v')
      fi
      if [ -z "$TAG" ]; then echo "__FAIL__ 无法获取最新版本"; exit 1; fi
      echo "最新版本: v$TAG"
      URL="https://pkgs.tailscale.com/stable/tailscale_\${TAG}_arm64.tgz"
    fi
    echo "下载: $URL"
    TMP="${TS_DIR}/dl.tgz"
    rm -f "$TMP"
    if ! curl -fL --max-time 180 -o "$TMP" "$URL" 2>&1 | tail -3; then
      echo "直连失败，通过代理重试…"
      rm -f "$TMP"
      if ! curl -fL --max-time 180 -x http://127.0.0.1:7890 --http1.1 -o "$TMP" "$URL" 2>&1 | tail -3; then
        echo "__FAIL__ 下载失败"
        exit 1
      fi
    fi
    if [ ! -f "$TMP" ]; then echo "__FAIL__ 下载失败"; exit 1; fi
    echo "OK: 下载完成"
    echo "解压中…"
    cd ${TS_DIR} && rm -rf tmp && mkdir tmp && tar -xzf dl.tgz -C tmp 2>&1 && cp tmp/*/tailscale bin/ && cp tmp/*/tailscaled bin/ && chmod 755 bin/tailscale bin/tailscaled && rm -rf tmp dl.tgz
    if [ $? -ne 0 ]; then echo "__FAIL__ 解压失败"; exit 1; fi
    echo "OK: 安装完成"
    VER=$(${TS_DIR}/bin/tailscale --version 2>/dev/null | head -1)
    echo "已安装版本: $VER"
    echo "__DONE__"
  `.trim()

  await exec(`: > ${LOG_FILE}; (${script}) &`)
  pollTimer = setInterval(pollLog, 800) as unknown as number
}

const restartDaemon = () => {
  act(async () => {
    await addLog('正在重启守护进程…')
    await exec(`pkill -x tailscaled; sleep 1; TS_SKIP_WAIT=1 sh ${MODDIR}/service.sh`)
    await new Promise(r => setTimeout(r, 2500))
    await addLog('OK: 已重启')
  })
}

onMounted(() => { refresh() })
</script>
