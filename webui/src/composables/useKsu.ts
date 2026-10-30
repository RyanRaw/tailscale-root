import { ref } from 'vue'

export interface ExecResult {
  errno: number
  stdout: string
  stderr: string
}

export function exec(cmd: string): Promise<ExecResult> {
  return new Promise((resolve) => {
    const cb = '__cb_' + Date.now() + '_' + Math.floor(Math.random() * 1e9)
    ;(window as any)[cb] = (errno: number, stdout: string, stderr: string) => {
      delete (window as any)[cb]
      resolve({ errno: errno | 0, stdout: stdout || '', stderr: stderr || '' })
    }
    try {
      ksu.exec(cmd, '{}', cb)
    } catch {
      try {
        const out = ksu.exec(cmd)
        delete (window as any)[cb]
        resolve({ errno: 0, stdout: (out as string) || '', stderr: '' })
      } catch (e2) {
        delete (window as any)[cb]
        resolve({ errno: -1, stdout: '', stderr: String(e2) })
      }
    }
  })
}

export const TS_DIR = '/data/adb/tailscale'
export const SOCK = TS_DIR + '/sock'
export const PIDFILE = TS_DIR + '/tailscaled.pid'
export const LOG = TS_DIR + '/log/tailscaled.log'
export const UP_LOG = TS_DIR + '/log/up.log'
export const BIN = TS_DIR + '/bin/tailscale'
export const DAEMON = TS_DIR + '/bin/tailscaled'
export const GUARD_PIDFILE = TS_DIR + '/svm_guard.pid'
export const SVM = '/proc/sys/net/ipv4/conf/all/src_valid_mark'
export const MODDIR = '/data/adb/modules/tailscale_root'

// tailscale: https://login.tailscale.com/a/xxxx
// headscale: https://<server>/register/xxxx
export const AUTH_URL_RE = /https:\/\/[^\s"'<>]*\/(?:a|register)\/[A-Za-z0-9]+/

export interface TailscaleState {
  binInstalled: boolean
  binVersion: string
  daemonRunning: boolean
  pid: number
  etime: string
  svm: string
  guardOn: boolean
  guardPid: number
  box: boolean
  status: any
  authURL: string
  loaded: boolean
}

// 模块级单例：所有页面共用同一份快照。
// 以前 useKsu() 每次调用都新建一份 state 并各自跑一次 tailscale status，
// 两个页面的数据属于不同时刻的快照，切网（peers 在线状态抖动）时状态页和
// 节点页会显示出不同的在线数。
const state = ref<TailscaleState>({
  binInstalled: false, binVersion: '',
  daemonRunning: false, pid: 0, etime: '',
  svm: '?', guardOn: false, guardPid: 0,
  box: false, status: null, authURL: '', loaded: false,
})
const busy = ref(false)
const refreshing = ref(false)
const lastRefresh = ref(0)
let pendingRefresh = false

async function refresh() {
  // never drop a refresh that lands while another one is running
  if (refreshing.value) {
    pendingRefresh = true
    return
  }
  refreshing.value = true
  try {
    if (!state.value.binInstalled) {
      const bv = await exec(`test -x ${BIN} && ${BIN} --version 2>/dev/null | head -1 || echo MISSING`)
      state.value.binInstalled = !bv.stdout.includes('MISSING')
      state.value.binVersion = state.value.binInstalled ? bv.stdout.trim() : ''
    }

    const cmd = [
      'p=$(pidof tailscaled | head -1)',
      'echo PID=$p',
      '[ -n "$p" ] && echo ETIME=$(ps -o etime= -p $p 2>/dev/null | sed "s/ //g")',
      'echo SVM=$(cat ' + SVM + ' 2>/dev/null)',
      'gp=$(cat ' + GUARD_PIDFILE + ' 2>/dev/null)',
      'if [ -n "$gp" ] && kill -0 "$gp" 2>/dev/null; then echo GUARD=$gp; else echo GUARD=; fi',
      '[ -d /data/adb/box ] && echo BOX=1',
    ].join('; ')
    const pr = await exec(cmd)
    const kv: Record<string, string> = {}
    pr.stdout.split('\n').forEach(l => { const i = l.indexOf('='); if (i > 0) kv[l.slice(0, i)] = l.slice(i + 1).trim() })
    state.value.pid = parseInt(kv.PID) || 0
    state.value.daemonRunning = state.value.pid > 0
    state.value.etime = kv.ETIME || ''
    state.value.svm = kv.SVM || '?'
    state.value.guardPid = parseInt(kv.GUARD) || 0
    state.value.guardOn = state.value.guardPid > 0
    state.value.box = kv.BOX === '1'

    if (state.value.daemonRunning && state.value.binInstalled) {
      const st = await exec(`${BIN} --socket=${SOCK} status --json 2>/dev/null`)
      try {
        const jsonStr = st.stdout.replace(/^[^{]*/, '')
        state.value.status = JSON.parse(jsonStr)
      } catch { state.value.status = null }
    } else {
      state.value.status = null
    }

    const beNow = state.value.status ? (state.value.status.BackendState || '') : ''
    if (state.value.status && state.value.status.AuthURL) {
      state.value.authURL = state.value.status.AuthURL
    } else if (beNow === 'NeedsLogin' || beNow === 'NoState') {
      const ul = await exec(`test -f ${UP_LOG} && tail -50 ${UP_LOG} || true`)
      const m = ul.stdout.match(AUTH_URL_RE)
      state.value.authURL = m ? m[0] : ''
    } else {
      state.value.authURL = ''
    }

    state.value.loaded = true
  } finally {
    refreshing.value = false
    lastRefresh.value = Date.now()
    if (pendingRefresh) {
      pendingRefresh = false
      refresh()
    }
  }
}

async function act(fn: () => Promise<void>, msg?: string) {
  if (busy.value) return
  busy.value = true
  try { await fn() } finally { busy.value = false; await refresh() }
}

export function useKsu() {
  return { state, busy, refreshing, lastRefresh, refresh, act, exec }
}
