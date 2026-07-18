import { ref } from 'vue'

export const confirmDialogState = ref({
  show: false,
  title: '',
  message: '',
})

let _resolve: ((v: boolean) => void) | null = null

export const showConfirmDialog = (title: string, message: string): Promise<boolean> => {
  confirmDialogState.value = { show: true, title, message }
  return new Promise((resolve) => { _resolve = resolve })
}

export const resolveConfirmDialog = (result: boolean) => {
  confirmDialogState.value.show = false
  _resolve?.(result)
  _resolve = null
}
