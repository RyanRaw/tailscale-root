<template>
  <div
    class="h-full overflow-x-hidden overflow-y-auto"
    :style="padding"
  >
    <CtrlsBar>
      <div class="flex h-12 flex-row items-center gap-2 p-2 text-sm">
        <span>设置</span>
      </div>
    </CtrlsBar>

    <div class="mx-auto w-full max-w-3xl space-y-1 p-3 md:px-8 md:py-6">
      <div>
      <div class="settings-section-label">外观</div>
      <div class="settings-grid">
        <div class="setting-item">
          <div class="setting-item-label">自动切换主题</div>
          <input v-model="autoTheme" type="checkbox" class="toggle toggle-sm" />
        </div>
        <div class="setting-item">
          <div class="setting-item-label">{{ autoTheme ? '浅色主题' : '主题' }}</div>
          <select v-model="defaultTheme" class="select select-sm min-w-32">
            <option v-for="t in allThemes" :key="t" :value="t">{{ t }}</option>
          </select>
        </div>
        <div v-if="autoTheme" class="setting-item">
          <div class="setting-item-label">深色主题</div>
          <select v-model="darkTheme" class="select select-sm min-w-32">
            <option v-for="t in allThemes" :key="t" :value="t">{{ t }}</option>
          </select>
        </div>
      </div>
      </div>

      <div>
      <div class="settings-section-label flex items-center">
        <span class="flex-1">Tailscale 配置</span>
        <button class="btn btn-ghost btn-xs" :disabled="envLoading" @click="loadEnv">
          <ArrowPathIcon class="h-3.5 w-3.5" :class="envLoading ? 'animate-spin' : ''" />
        </button>
      </div>
      <div class="settings-grid">
        <div v-if="!envLoaded" class="setting-item justify-center">
          <span class="text-base-content/40 text-sm py-2">加载中…</span>
        </div>
        <template v-else>
          <div class="setting-item">
            <div class="setting-item-label">
              HTTP 代理
              <span class="text-base-content/30 ml-1 text-xs">TS_PROXY</span>
            </div>
            <input v-model="envVars.TS_PROXY" type="text" class="input input-sm w-40" placeholder="http://127.0.0.1:7890" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              监听端口
              <span class="text-base-content/30 ml-1 text-xs">TS_PORT</span>
            </div>
            <input v-model="envVars.TS_PORT" type="text" class="input input-sm w-24" placeholder="41641" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              主机名
              <span class="text-base-content/30 ml-1 text-xs">TS_HOSTNAME</span>
            </div>
            <input v-model="envVars.TS_HOSTNAME" type="text" class="input input-sm w-32" placeholder="自动" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              唤醒锁
              <span class="text-base-content/30 ml-1 text-xs">TS_WAKELOCK</span>
            </div>
            <input v-model="wakelockEnabled" type="checkbox" class="toggle toggle-sm" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              自动避开子网冲突
              <span class="text-base-content/30 ml-1 text-xs">TS_ROUTE_GUARD</span>
            </div>
            <input v-model="routeGuardEnabled" type="checkbox" class="toggle toggle-sm" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              监听网卡
              <span class="text-base-content/30 ml-1 text-xs">TS_TUN</span>
            </div>
            <input v-model="envVars.TS_TUN" type="text" class="input input-sm w-32" placeholder="tailscale0" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              日志级别
              <span class="text-base-content/30 ml-1 text-xs">TS_LOGLEVEL</span>
            </div>
            <select v-model="envVars.TS_LOGLEVEL" class="select select-sm min-w-24">
              <option value="quiet">静默</option>
              <option value="normal">标准</option>
              <option value="debug">调试</option>
            </select>
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              额外参数
              <span class="text-base-content/30 ml-1 text-xs">TS_EXTRA_ARGS</span>
            </div>
            <input v-model="envVars.TS_EXTRA_ARGS" type="text" class="input input-sm w-52" placeholder="如 --netfilter-mode=off" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              控制服务器
              <span class="text-base-content/30 ml-1 text-xs">TS_LOGIN_SERVER</span>
            </div>
            <input v-model="envVars.TS_LOGIN_SERVER" type="text" class="input input-sm w-52" placeholder="留空 = 官方，如 https://headscale.example.com" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              预授权密钥
              <span class="text-base-content/30 ml-1 text-xs">TS_AUTHKEY</span>
            </div>
            <input v-model="envVars.TS_AUTHKEY" type="text" class="input input-sm w-52" placeholder="可选，免交互登录" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              登录参数
              <span class="text-base-content/30 ml-1 text-xs">TS_UP_ARGS</span>
            </div>
            <input v-model="envVars.TS_UP_ARGS" type="text" class="input input-sm w-52" placeholder="如 --reset" />
          </div>
          <div class="setting-item">
            <div class="setting-item-label">
              自定义 DNS
              <span class="text-base-content/30 ml-1 text-xs">TS_DNS</span>
            </div>
            <input v-model="envVars.TS_DNS" type="text" class="input input-sm w-52" placeholder="留空自动，如 223.5.5.5 1.1.1.1" />
          </div>
          <div class="setting-item justify-end gap-2">
            <span v-if="saveMessage" class="text-xs" :class="saveError ? 'text-error' : 'text-success'">{{ saveMessage }}</span>
            <button class="btn btn-primary btn-sm" :disabled="saving" @click="saveEnv">
              {{ saving ? '保存并重启中…' : '保存并重启' }}
            </button>
          </div>
        </template>
      </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { exec, MODDIR, restartTailscaled } from '@/composables/useKsu'
import CtrlsBar from '@/components/common/CtrlsBar.vue'
import { usePaddingForViews } from '@/composables/paddingViews'
import { autoTheme, darkTheme, defaultTheme } from '@/store/settings'
import { ALL_THEME } from '@/constant'
import { ArrowPathIcon } from '@heroicons/vue/24/outline'
import { computed, onMounted, reactive, ref } from 'vue'

const { padding } = usePaddingForViews({ offsetTop: 0, offsetBottom: 8 })
const TS_ENV_FILE = '/data/adb/tailscale/env'
const allThemes = ALL_THEME

const envLoading = ref(false)
const envLoaded = ref(false)
const saving = ref(false)
const saveMessage = ref('')
const saveError = ref(false)

const envVars = reactive({
  TS_PROXY: '', TS_PORT: '', TS_HOSTNAME: '', TS_WAKELOCK: '',
  TS_TUN: '', TS_EXTRA_ARGS: '', TS_LOGLEVEL: '',
  TS_LOGIN_SERVER: '', TS_AUTHKEY: '', TS_UP_ARGS: '', TS_DNS: '',
  TS_ROUTE_GUARD: '',
})
const ENV_KEYS = [
  'TS_PROXY', 'TS_PORT', 'TS_HOSTNAME', 'TS_WAKELOCK', 'TS_TUN', 'TS_EXTRA_ARGS',
  'TS_LOGLEVEL', 'TS_LOGIN_SERVER', 'TS_AUTHKEY', 'TS_UP_ARGS', 'TS_DNS',
  'TS_ROUTE_GUARD',
]

const wakelockEnabled = computed({
  get: () => envVars.TS_WAKELOCK === '1' || envVars.TS_WAKELOCK === 'true',
  set: (val: boolean) => { envVars.TS_WAKELOCK = val ? '1' : '0' },
})

// 默认开启：只有显式写 0 才关闭
const routeGuardEnabled = computed({
  get: () => envVars.TS_ROUTE_GUARD !== '0',
  set: (val: boolean) => { envVars.TS_ROUTE_GUARD = val ? '1' : '0' },
})

const loadEnv = async () => {
  if (envLoading.value) return
  envLoading.value = true
  saveMessage.value = ''
  try {
    const res = await exec(`cat ${TS_ENV_FILE} 2>/dev/null || echo ''`)
    for (const k of ENV_KEYS) (envVars as any)[k] = ''
    for (const line of res.stdout.split('\n')) {
      const t = line.trim()
      if (!t || t.startsWith('#')) continue
      const eq = t.indexOf('=')
      if (eq < 0) continue
      const key = t.slice(0, eq).trim()
      let val = t.slice(eq + 1).trim()
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) val = val.slice(1, -1)
      if (key in envVars) (envVars as any)[key] = val
    }
    if (!envVars.TS_LOGLEVEL) envVars.TS_LOGLEVEL = 'normal'
    envLoaded.value = true
  } finally { envLoading.value = false }
}

const saveEnv = async () => {
  if (saving.value) return
  saving.value = true; saveMessage.value = ''; saveError.value = false
  try {
    const res = await exec(`cat ${TS_ENV_FILE} 2>/dev/null || echo ''`)
    const known = new Set(ENV_KEYS)
    const preserved: string[] = []
    for (const line of res.stdout.split('\n')) {
      const t = line.trim()
      if (!t) continue
      if (t.startsWith('#')) { preserved.push(line); continue }
      const eq = t.indexOf('=')
      if (eq < 0) { preserved.push(line); continue }
      if (!known.has(t.slice(0, eq).trim())) preserved.push(line)
    }
    const newLines = [...preserved]
    for (const [key, val] of Object.entries(envVars)) {
      if (val) newLines.push(`${key}="${val}"`)
    }
    const content = newLines.join('\\n')
    const w = await exec(`printf '${content}\\n' > ${TS_ENV_FILE}`)
    if (w.errno !== 0) { saveMessage.value = '保存失败'; saveError.value = true }
    else {
      // 立刻按新配置重写 resolv.conf。清空 TS_DNS 时 --quick 在网络没变的情况下
      // 会直接退出，不跑这一次就会一直留着旧值。
      await exec(`sh ${MODDIR}/update_resolv.sh 2>&1`)
      // 保存即生效：env 里全是 tailscaled 的启动参数/进程环境，不重启等于没改。
      // 重启走 service.sh，它顺带处理控制服务器变化（不一致时自动切换并重新生成登录链接）。
      const up = await restartTailscaled()
      if (!up) {
        saveMessage.value = '已保存，守护进程正在启动…'
      } else if (envVars.TS_LOGIN_SERVER) {
        saveMessage.value = '已保存并重启；控制服务器若有变化，到状态页获取新的登录链接'
      } else {
        saveMessage.value = '已保存，守护进程已重启'
      }
    }
  } catch (e) { saveMessage.value = '错误'; saveError.value = true }
  finally { saving.value = false }
}

// 切回本页不重载 env：表单可能正有未保存的编辑，整份刷新会静默冲掉
onMounted(() => { loadEnv() })
</script>
