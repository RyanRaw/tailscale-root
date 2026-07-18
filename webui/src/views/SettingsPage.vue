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
          <div class="setting-item justify-end gap-2">
            <span v-if="saveMessage" class="text-xs" :class="saveError ? 'text-error' : 'text-success'">{{ saveMessage }}</span>
            <button class="btn btn-primary btn-sm" :disabled="saving" @click="saveEnv">
              {{ saving ? '保存中…' : '保存' }}
            </button>
          </div>
        </template>
      </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { exec } from '@/composables/useKsu'
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

const envVars = reactive({ TS_PROXY: '', TS_PORT: '', TS_HOSTNAME: '', TS_WAKELOCK: '' })

const wakelockEnabled = computed({
  get: () => envVars.TS_WAKELOCK === '1' || envVars.TS_WAKELOCK === 'true',
  set: (val: boolean) => { envVars.TS_WAKELOCK = val ? '1' : '0' },
})

const loadEnv = async () => {
  if (envLoading.value) return
  envLoading.value = true
  saveMessage.value = ''
  try {
    const res = await exec(`cat ${TS_ENV_FILE} 2>/dev/null || echo ''`)
    envVars.TS_PROXY = ''; envVars.TS_PORT = ''; envVars.TS_HOSTNAME = ''; envVars.TS_WAKELOCK = ''
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
    envLoaded.value = true
  } finally { envLoading.value = false }
}

const saveEnv = async () => {
  if (saving.value) return
  saving.value = true; saveMessage.value = ''; saveError.value = false
  try {
    const res = await exec(`cat ${TS_ENV_FILE} 2>/dev/null || echo ''`)
    const known = new Set(['TS_PROXY', 'TS_PORT', 'TS_HOSTNAME', 'TS_WAKELOCK'])
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
    else { saveMessage.value = '已保存' }
  } catch (e) { saveMessage.value = '错误'; saveError.value = true }
  finally { saving.value = false }
}

onMounted(() => { loadEnv() })
</script>
