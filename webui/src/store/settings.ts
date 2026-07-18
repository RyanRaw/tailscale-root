import {
  ALL_THEME,
  EMOJIS,
  FONTS,
  IS_APPLE_DEVICE,
  LANG,
  type THEME,
} from '@/constant'
import { isMiddleScreen, isPreferredDark } from '@/helper/utils'
import { useStorage } from '@vueuse/core'
import { computed } from 'vue'

// global
export const defaultTheme = useStorage<string>('config/default-theme', 'light')
export const darkTheme = useStorage<string>('config/dark-theme', 'dark')
export const autoTheme = useStorage<boolean>('config/auto-theme', true)
export const theme = computed(() => {
  if (autoTheme.value && isPreferredDark.value) {
    return darkTheme.value
  }
  return defaultTheme.value
})
export const customThemes = useStorage<THEME[]>('config/custom-themes', [])

const replaceLegacyTheme = (t: string, def: string) => {
  if (t === 'dark-apple') return 'dark'
  if ([...ALL_THEME, ...customThemes.value.map((th) => th.name)].includes(t)) return t
  return def
}

defaultTheme.value = replaceLegacyTheme(defaultTheme.value, 'light')
darkTheme.value = replaceLegacyTheme(darkTheme.value, 'dark')

export const language = useStorage<LANG>(
  'config/language',
  Object.values(LANG).includes(navigator.language as LANG)
    ? (navigator.language as LANG)
    : LANG.EN_US,
)
export const isSidebarCollapsedConfig = useStorage('config/is-sidebar-collapsed', true)
export const isSidebarCollapsed = computed({
  get: () => {
    if (isMiddleScreen.value) return true
    return isSidebarCollapsedConfig.value
  },
  set: (value) => {
    isSidebarCollapsedConfig.value = value
  },
})

const fontConfig = useStorage<FONTS>('config/font', FONTS.SYSTEM_UI)
export const font = computed({
  get: () => fontConfig.value,
  set: (val) => { fontConfig.value = val },
})
export const emoji = useStorage<EMOJIS>(
  'config/emoji',
  IS_APPLE_DEVICE ? EMOJIS.TWEMOJI : EMOJIS.NOTO_COLOR_EMOJI,
)

export const disablePullToRefresh = useStorage('config/disable-pull-to-refresh', true)
export const blurIntensity = useStorage('config/blur-intensity', 10)
