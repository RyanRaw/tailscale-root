import {
  SignalIcon,
  UsersIcon,
  ArrowDownTrayIcon,
  DocumentTextIcon,
  Cog6ToothIcon,
} from '@heroicons/vue/24/outline'

export const IS_APPLE_DEVICE = /Mac|iPod|iPhone|iPad/.test(navigator.platform)

export enum LANG {
  EN_US = 'en-US',
  ZH_CN = 'zh-CN',
  ZH_TW = 'zh-TW',
  RU_RU = 'ru-RU',
}

export enum FONTS {
  MI_SANS = 'MiSans',
  SARASA_UI = 'SarasaUi',
  PING_FANG = 'PingFang',
  FIRA_SANS = 'FiraSans',
  SYSTEM_UI = 'SystemUI',
}

export enum EMOJIS {
  TWEMOJI = 'twemoji',
  NOTO_COLOR_EMOJI = 'noto-color-emoji',
}

export enum ROUTE_NAME {
  status = 'status',
  peers = 'peers',
  install = 'install',
  logs = 'logs',
  settings = 'settings',
}

export const ROUTE_ICON_MAP: Record<string, any> = {
  [ROUTE_NAME.status]: SignalIcon,
  [ROUTE_NAME.peers]: UsersIcon,
  [ROUTE_NAME.install]: ArrowDownTrayIcon,
  [ROUTE_NAME.logs]: DocumentTextIcon,
  [ROUTE_NAME.settings]: Cog6ToothIcon,
}

export const ALL_THEME = [
  'light',
  'dark',
  'light-neutral',
  'dark-neutral',
  ...(window.ksu ? ['light-monet', 'dark-monet'] : []),
  'halloween',
  'forest',
  'lofi',
  'wireframe',
  'black',
  'dracula',
  'business',
  'night',
  'dim',
  'nord',
  'sunset',
  'abyss',
  'cupcake',
  'dark-daisyui5',
]

export const DEFAULT_THEME = {
  name: 'custom',
  id: '',
  '--border': '1px',
  '--color-base-100': '#ffffff',
  '--color-base-200': '#fcfcfc',
  '--color-base-300': '#f2f2f2',
  '--color-base-content': '#2d2d33',
  '--color-primary': '#5a3cd2',
  '--color-primary-content': '#f3efff',
  '--color-secondary': '#ea4c5a',
  '--color-secondary-content': '#fff1f2',
  '--color-accent': '#49c6c1',
  '--color-accent-content': '#285e66',
  '--color-neutral': '#1e1e1f',
  '--color-neutral-content': '#ececec',
  '--color-info': '#5b90ff',
  '--color-info-content': '#273c66',
  '--color-success': '#44c07a',
  '--color-success-content': '#1d472f',
  '--color-warning': '#e5a300',
  '--color-warning-content': '#705322',
  '--color-error': '#d13a30',
  '--color-error-content': '#551d1d',
  '--depth': '0',
  '--noise': '0',
  '--radius-box': '1rem',
  '--radius-field': '0.5rem',
  '--radius-selector': '1rem',
  '--size-field': '0.25rem',
  '--size-selector': '0.25rem',
  'color-scheme': 'dark',
  default: false,
  prefersdark: false,
}

export type THEME = Record<string, string>
