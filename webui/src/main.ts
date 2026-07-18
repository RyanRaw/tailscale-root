import 'tippy.js/animations/scale.css'
import 'tippy.js/dist/tippy.css'
import { createApp } from 'vue'
import App from './App.vue'
import './assets/main.css'
import { applyKsuTheme } from './helper'
import router from './router'

applyKsuTheme()

const app = createApp(App)

app.use(router)
app.mount('#app')
