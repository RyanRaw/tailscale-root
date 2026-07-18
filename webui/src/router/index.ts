import { ROUTE_NAME } from '@/constant'
import HomePage from '@/views/HomePage.vue'
import StatusPage from '@/views/StatusPage.vue'
import PeersPage from '@/views/PeersPage.vue'
import InstallPage from '@/views/InstallPage.vue'
import LogsPage from '@/views/LogsPage.vue'
import SettingsPage from '@/views/SettingsPage.vue'
import { useTitle } from '@vueuse/core'
import { createRouter, createWebHashHistory } from 'vue-router'

export const ROUTE_LABELS: Record<string, string> = {
  [ROUTE_NAME.status]: '状态',
  [ROUTE_NAME.peers]: '节点',
  [ROUTE_NAME.install]: '安装',
  [ROUTE_NAME.logs]: '日志',
  [ROUTE_NAME.settings]: '设置',
}

const childrenRouter = [
  {
    path: 'status',
    name: ROUTE_NAME.status,
    component: StatusPage,
  },
  {
    path: 'peers',
    name: ROUTE_NAME.peers,
    component: PeersPage,
  },
  {
    path: 'install',
    name: ROUTE_NAME.install,
    component: InstallPage,
  },
  {
    path: 'logs',
    name: ROUTE_NAME.logs,
    component: LogsPage,
  },
  {
    path: 'settings',
    name: ROUTE_NAME.settings,
    component: SettingsPage,
  },
]

const renderRoutes = Object.values(ROUTE_NAME)

const router = createRouter({
  history: createWebHashHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      redirect: ROUTE_NAME.status,
      component: HomePage,
      children: childrenRouter,
    },
    {
      path: '/:catchAll(.*)',
      redirect: ROUTE_NAME.status,
    },
  ],
})

const title = useTitle('Tailscale')

router.beforeEach((to, from) => {
  const toIndex = renderRoutes.findIndex((item) => item === to.name)
  const fromIndex = renderRoutes.findIndex((item) => item === from.name)

  if (toIndex === 0 && fromIndex === renderRoutes.length - 1) {
    to.meta.transition = 'slide-left'
  } else if (toIndex === renderRoutes.length - 1 && fromIndex === 0) {
    to.meta.transition = 'slide-right'
  } else if (toIndex !== fromIndex) {
    to.meta.transition = toIndex < fromIndex ? 'slide-right' : 'slide-left'
  }
})

router.afterEach((to) => {
  if (typeof to.name === 'string') {
    title.value = `Tailscale | ${ROUTE_LABELS[to.name] || to.name}`
  } else {
    title.value = 'Tailscale'
  }
})

export { renderRoutes }
export default router
