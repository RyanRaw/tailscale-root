import { customThemes } from '@/store/settings'

export const applyCustomThemes = () => {
  document.querySelectorAll('.custom-theme').forEach((style) => {
    style.remove()
  })
  customThemes.value.forEach((theme) => {
    const style = document.createElement('style')
    const styleString = Object.entries(theme)
      .filter(([key]) => !['prefersdark', 'default', 'name', 'type', 'id'].includes(key))
      .map(([key, value]) => `${key}:${value}`)
      .join(';')

    style.innerHTML = `[data-theme="${theme.name}"] {
      ${styleString}
    }`

    style.className = `custom-theme ${theme.name}`
    document.head.appendChild(style)
  })
}

export const applyKsuTheme = () => {
  if ((window as any).ksu) {
    const link = document.createElement('link')
    link.rel = 'stylesheet'
    link.href = 'https://mui.kernelsu.org/internal/colors.css'
    document.head.appendChild(link)
  }
}
