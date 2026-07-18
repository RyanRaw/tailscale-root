<template>
  <div
    ref="sidebarRef"
    class="sidebar border-base-300/30 bg-base-200 text-base-content scrollbar-hidden h-full overflow-x-hidden border-r p-2 transition-[width,padding] duration-320 ease-[cubic-bezier(0.34,0.1,0.2,1)]"
    :class="isSidebarCollapsed ? 'w-18 px-0' : 'w-64'"
    @transitionend="handleTransitionEnd"
  >
    <div :class="twMerge('flex h-full flex-col gap-2', isSidebarCollapsed ? 'w-18 px-0' : 'w-60')">
      <div
        ref="navRef"
        class="relative flex-1"
      >
        <div
          aria-hidden="true"
          class="sidebar-tab-indicator bg-neutral pointer-events-none absolute"
          :class="{ 'sidebar-tab-indicator-ready': indicatorReady }"
          :style="indicatorStyle"
        />
        <ul
          ref="menuRef"
          class="sidebar-route-menu menu h-full w-full"
        >
          <li
            v-for="r in renderRoutes"
            :key="r"
            :data-sidebar-route="r"
            @mouseenter="(e) => mouseenterHandler(e, r)"
          >
            <a
              :class="[
                r === route.name ? 'sidebar-tab-active' : 'hover:bg-base-300!',
                isSidebarCollapsed && 'justify-center',
                'relative z-10 py-2',
              ]"
              @click.passive="() => router.push({ name: r })"
            >
              <component
                :is="ROUTE_ICON_MAP[r]"
                class="h-5 w-5"
              />
              <template v-if="!isSidebarCollapsed">
                {{ ROUTE_LABELS[r] || r }}
              </template>
            </a>
          </li>
        </ul>
      </div>
      <template v-if="isSidebarCollapsed">
        <div class="flex flex-col items-center justify-center gap-2">
          <button
            class="btn btn-circle btn-sm"
            @click="isSidebarCollapsed = !isSidebarCollapsed"
          >
            <ArrowRightCircleIcon class="h-5 w-5" />
          </button>
        </div>
      </template>
      <template v-else>
        <div class="base-container flex flex-col gap-2 p-2 text-sm">
          <div class="text-base-content/50 text-center text-xs">Tailscale 管理器</div>
          <div class="flex gap-2">
            <button
              class="btn btn-circle btn-sm"
              @click="isSidebarCollapsed = !isSidebarCollapsed"
            >
              <ArrowLeftCircleIcon class="h-5 w-5" />
            </button>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ROUTE_ICON_MAP, ROUTE_NAME } from '@/constant'
import { renderRoutes } from '@/router'
import { useTooltip } from '@/helper/tooltip'
import router from '@/router'
import { isSidebarCollapsed } from '@/store/settings'
import { ArrowLeftCircleIcon, ArrowRightCircleIcon } from '@heroicons/vue/24/outline'
import { useResizeObserver } from '@vueuse/core'
import { twMerge } from 'tailwind-merge'
import { nextTick, ref, watch } from 'vue'
import { useRoute } from 'vue-router'

import { ROUTE_LABELS } from '@/router'

const emit = defineEmits<{
  transitionend: []
}>()

const sidebarRef = ref<HTMLDivElement>()
const navRef = ref<HTMLDivElement>()
const menuRef = ref<HTMLUListElement>()
const indicatorReady = ref(false)
const indicatorStyle = ref({
  height: '0px',
  opacity: '0',
  transform: 'translate3d(0, 0, 0)',
  width: '0px',
})
const { showTip } = useTooltip()

const mouseenterHandler = (e: MouseEvent, r: string) => {
  if (!isSidebarCollapsed.value) return
  showTip(e, ROUTE_LABELS[r] || r, { placement: 'right' })
}

const route = useRoute()

const syncTabIndicator = () => {
  const nav = navRef.value
  const menu = menuRef.value
  if (!nav || !menu || typeof route.name !== 'string') return

  const activeTab = menu.querySelector<HTMLElement>(
    `[data-sidebar-route="${CSS.escape(route.name)}"] > a`,
  )
  if (!activeTab) return

  const navRect = nav.getBoundingClientRect()
  const activeTabRect = activeTab.getBoundingClientRect()

  indicatorStyle.value = {
    height: `${activeTabRect.height}px`,
    opacity: '1',
    transform: `translate3d(${activeTabRect.left - navRect.left}px, ${activeTabRect.top - navRect.top}px, 0)`,
    width: `${activeTabRect.width}px`,
  }
}

watch(
  [() => route.name, isSidebarCollapsed],
  async () => {
    await nextTick()
    syncTabIndicator()
    requestAnimationFrame(() => {
      indicatorReady.value = true
    })
  },
  { immediate: true },
)

useResizeObserver(menuRef, syncTabIndicator)

const handleTransitionEnd = (e: TransitionEvent) => {
  if (e.target !== sidebarRef.value || e.propertyName !== 'width') return
  syncTabIndicator()
  emit('transitionend')
}
</script>
