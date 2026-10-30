import { onActivated } from 'vue'

/**
 * KeepAlive 缓存的页面被切回来时重新拉一次数据。
 *
 * 首次激活紧跟在 onMounted 的首次加载之后，用 minInterval 挡掉，避免同一份
 * 数据连查两次；快速来回切页也不会连发 shell 请求。设置页这类带未保存编辑的
 * 表单不要整份重载，只挂只读的展示项即可。
 */
export function useAutoRefresh(load: () => unknown, minInterval = 2000) {
  let last = Date.now()
  onActivated(() => {
    const now = Date.now()
    if (now - last < minInterval) return
    last = now
    void load()
  })
}
