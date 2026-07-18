<template>
  <div
    class="bg-base-200 home-page flex size-full"
    :class="sidebarLayoutCollapsed ? 'sidebar-collapsed' : 'sidebar-expanded'"
  >
    <div
      v-if="!isMiddleScreen"
      class="relative z-40 flex-none overflow-visible transition-none"
      :class="sidebarLayoutCollapsed ? 'w-18' : 'w-64'"
    >
      <SideBar
        class="absolute inset-y-0 left-0"
        @transitionend="syncSidebarLayoutState"
      />
    </div>
    <RouterView v-slot="{ Component, route }">
      <div class="relative flex-1 overflow-hidden">
        <div class="absolute flex h-full w-full flex-col overflow-y-auto">
          <Transition
            :name="(route.meta.transition as string) || 'fade'"
            v-if="isMiddleScreen"
          >
            <Component :is="Component" />
          </Transition>
          <Transition
            v-else
            name="page"
            mode="out-in"
          >
            <Component :is="Component" />
          </Transition>
        </div>

        <template v-if="isMiddleScreen">
          <div
            class="bg-base-100/20 dock dock-xs z-10 h-14 w-auto"
            :style="{
              padding: '0',
              bottom: 'calc(var(--spacing) * 2 + env(safe-area-inset-bottom))',
            }"
            ref="dockRef"
          >
            <button
              v-for="r in renderRoutes"
              :key="r"
              @click="router.push({ name: r, replace: true })"
              class="h-14 flex-col items-center justify-center pt-2"
              :class="r === route.name && 'dock-active'"
            >
              <component
                :is="ROUTE_ICON_MAP[r]"
                class="h-5 w-5 flex-shrink-0"
              />
              <span class="dock-label">
                {{ ROUTE_LABELS[r] || r }}
              </span>
            </button>
          </div>
          <div
            class="fixed bottom-0 z-10 w-full"
            style="
              background: linear-gradient(
                to top,
                rgba(0, 0, 0, 0.18) 0%,
                rgba(0, 0, 0, 0.1) 30%,
                rgba(0, 0, 0, 0.04) 60%,
                rgba(0, 0, 0, 0.01) 85%,
                rgba(0, 0, 0, 0) 100%
              );
              height: env(safe-area-inset-bottom);
            "
          ></div>
        </template>
      </div>
    </RouterView>
  </div>
</template>

<script setup lang="ts">
import SideBar from '@/components/sidebar/SideBar.vue'
import { dockTop } from '@/composables/paddingViews'
import { ROUTE_ICON_MAP, ROUTE_NAME } from '@/constant'
import { renderRoutes } from '@/router'
import { isMiddleScreen } from '@/helper/utils'
import { isSidebarCollapsed } from '@/store/settings'
import { useElementBounding } from '@vueuse/core'
import { ref, watch } from 'vue'
import { RouterView, useRouter } from 'vue-router'

import { ROUTE_LABELS } from '@/router'

const router = useRouter()
const sidebarLayoutCollapsed = ref(isSidebarCollapsed.value)

const dockRef = ref<HTMLDivElement>()
const { top: dockRefTop } = useElementBounding(dockRef)

const syncSidebarLayoutState = () => {
  sidebarLayoutCollapsed.value = isSidebarCollapsed.value
}

watch(isSidebarCollapsed, (value) => {
  if (value) {
    sidebarLayoutCollapsed.value = true
  }
})

watch(
  isMiddleScreen,
  (value) => {
    if (!value) {
      sidebarLayoutCollapsed.value = isSidebarCollapsed.value
    }
  },
  { immediate: true },
)

watch(
  dockRefTop,
  () => {
    dockTop.value = window.innerHeight - dockRefTop.value
  },
  { immediate: true },
)
</script>
