<template>
  <div
    class="pointer-events-none flex items-end justify-center overflow-hidden"
    :style="{
      height: distance + 'px',
      transition: dragging ? 'none' : 'height 0.18s ease',
    }"
  >
    <div
      v-if="distance > 0"
      class="text-base-content/40 flex items-center gap-1 pb-1.5 text-xs"
    >
      <span v-if="refreshing" class="loading loading-spinner loading-xs"></span>
      <ArrowPathIcon
        v-else
        class="h-4 w-4"
        :class="ready ? 'text-primary' : ''"
        :style="{ transform: `rotate(${Math.min(270, (distance / threshold) * 270)}deg)` }"
      />
      <span>{{ refreshing ? '刷新中…' : ready ? '松手刷新' : '下拉刷新' }}</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ArrowPathIcon } from '@heroicons/vue/24/outline'

defineProps<{
  distance: number
  refreshing: boolean
  dragging: boolean
  ready: boolean
  threshold: number
}>()
</script>
