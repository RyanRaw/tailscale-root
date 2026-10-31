import { onMounted, onUnmounted, ref, type Ref } from 'vue'

/**
 * 页面级下拉刷新。
 *
 * 绑定在页面自己的滚动容器上：只有滚到顶（scrollTop <= 0）才接管手势，横向滑动、
 * 多指、正在刷新时都不介入；拉动距离做 0.5 的阻尼并封顶，松手超过阈值才真正触发，
 * 否则回弹。触发时给一次短振动，和原生下拉的反馈保持一致。
 */
export function usePullRefresh(
  el: Ref<HTMLElement | undefined>,
  onRefresh: () => unknown,
  options: { threshold?: number; max?: number } = {},
) {
  const threshold = options.threshold ?? 64
  const max = options.max ?? 96

  const distance = ref(0)
  const refreshing = ref(false)
  const dragging = ref(false)
  const ready = ref(false)

  let startX = 0
  let startY = 0
  let tracking = false

  const setDistance = (d: number) => {
    distance.value = d
    ready.value = d >= threshold
  }

  const onStart = (e: TouchEvent) => {
    if (refreshing.value || e.touches.length > 1) return
    const node = el.value
    if (!node || node.scrollTop > 0) return
    startX = e.touches[0].clientX
    startY = e.touches[0].clientY
    tracking = true
    dragging.value = true
  }

  const onMove = (e: TouchEvent) => {
    if (!tracking || refreshing.value) return
    const node = el.value
    if (!node) return
    // 拉到一半内容被滚上去了，交还给正常滚动
    if (node.scrollTop > 0) {
      tracking = false
      dragging.value = false
      setDistance(0)
      return
    }
    const dy = e.touches[0].clientY - startY
    const dx = e.touches[0].clientX - startX
    if (dy <= 0 || Math.abs(dx) > Math.abs(dy)) {
      if (dy <= 0) setDistance(0)
      return
    }
    // 阻尼 + 封顶，避免一下拽到底
    setDistance(Math.min(max, dy * 0.5))
    if (distance.value > 0) e.preventDefault()
  }

  const onEnd = async () => {
    if (!tracking) return
    tracking = false
    dragging.value = false
    if (!ready.value) {
      setDistance(0)
      return
    }
    refreshing.value = true
    setDistance(threshold)
    try {
      navigator.vibrate?.(10)
    } catch {
      // 部分 WebView 没有振动权限，忽略即可
    }
    try {
      await onRefresh()
    } finally {
      refreshing.value = false
      setDistance(0)
    }
  }

  onMounted(() => {
    const node = el.value
    if (!node) return
    node.addEventListener('touchstart', onStart, { passive: true })
    node.addEventListener('touchmove', onMove, { passive: false })
    node.addEventListener('touchend', onEnd)
    node.addEventListener('touchcancel', onEnd)
  })

  onUnmounted(() => {
    const node = el.value
    if (!node) return
    node.removeEventListener('touchstart', onStart)
    node.removeEventListener('touchmove', onMove)
    node.removeEventListener('touchend', onEnd)
    node.removeEventListener('touchcancel', onEnd)
  })

  return { distance, refreshing, dragging, ready, threshold }
}
