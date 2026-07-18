<script setup lang="ts">
import { computed, onMounted, ref, type Ref, watch } from 'vue'
import { RouterView } from 'vue-router'
import ConfirmDialogHost from './components/common/ConfirmDialogHost.vue'
import { initNotification } from './helper/notification'
import { isPreferredDark } from './helper/utils'
import { disablePullToRefresh, theme } from './store/settings'

const app = ref<HTMLElement>()
const toast = ref<HTMLElement>()

initNotification(toast as Ref<HTMLElement>)

const setThemeColor = () => {
  if (!app.value) return
  const themeColor = getComputedStyle(app.value!).getPropertyValue('background-color').trim()
  const metaThemeColor = document.querySelector('meta[name="theme-color"]')
  if (metaThemeColor) {
    metaThemeColor.setAttribute('content', themeColor)
  }
}

watch(isPreferredDark, setThemeColor)
watch(
  theme,
  () => {
    document.body.setAttribute('data-theme', theme.value)
    setThemeColor()
  },
  { immediate: true },
)

let touchStartX = 0
let touchStartY = 0

const onTouchStart = (event: TouchEvent) => {
  touchStartX = event.touches[0].clientX
  touchStartY = event.touches[0].clientY
}

const findScrollableY = (target: EventTarget | null) => {
  let el = target as HTMLElement | null
  while (el && el !== document.body && el !== document.documentElement) {
    const { overflowY } = getComputedStyle(el)
    if ((overflowY === 'auto' || overflowY === 'scroll') && el.scrollHeight > el.clientHeight) {
      return el
    }
    el = el.parentElement
  }
  return null
}

const onTouchMove = (event: TouchEvent) => {
  if (event.touches.length > 1) return
  const deltaX = event.touches[0].clientX - touchStartX
  const deltaY = event.touches[0].clientY - touchStartY
  if (Math.abs(deltaY) <= Math.abs(deltaX)) return
  const el = findScrollableY(event.target)
  if (!el) {
    event.preventDefault()
    return
  }
  const atTop = el.scrollTop <= 0
  const atBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 1
  if ((atTop && deltaY > 0) || (atBottom && deltaY < 0)) {
    event.preventDefault()
  }
}

watch(
  disablePullToRefresh,
  () => {
    const body = document.body
    if (disablePullToRefresh.value) {
      body.style.overscrollBehavior = 'none'
      body.style.overflow = 'hidden'
      document.addEventListener('touchstart', onTouchStart, { passive: true })
      document.addEventListener('touchmove', onTouchMove, { passive: false })
    } else {
      body.style.overscrollBehavior = ''
      body.style.overflow = ''
      document.removeEventListener('touchstart', onTouchStart)
      document.removeEventListener('touchmove', onTouchMove)
    }
  },
  { immediate: true },
)

onMounted(() => {
  setThemeColor()
})
</script>

<template>
  <div
    ref="app"
    id="app-content"
    :class="['bg-base-100 flex w-screen overflow-hidden']"
    :style="{ height: 'var(--app-height, 100dvh)' }"
  >
    <RouterView />
    <ConfirmDialogHost />
    <div
      ref="toast"
      class="toast-sm toast toast-end toast-top z-[100000] max-w-80 text-sm md:max-w-96 md:translate-y-8"
    />
  </div>
</template>
