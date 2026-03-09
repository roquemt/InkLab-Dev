<script setup>
import { computed } from 'vue' // Removed 'ref'
import { useSystemStore } from '../../stores/systemStore'
import { useSerial } from '../../composables/useSerial'
import CustomSelect from '../CustomSelect.vue'  

const store = useSystemStore()
const { sendCommand } = useSerial()

const udOptions = [
  { value: 0, label: 'Adjust Active Slot Clock Speed' },
  { value: 1, label: 'Toggle PFM Efficiency Mode (FWD & OTG)' }
]
const lrOptions = [
  { value: 0, label: 'Browse Next/Prev Memory Slot' },
  { value: 1, label: 'Adjust OTG Output Voltage (3.6V - 5.5V)' }
]
const cenOptions = [
  { value: 0, label: 'Flash Selected Slot to FPGA' },
  { value: 1, label: 'Toggle Auto-Rearm Backup Status' }
]


// MCU maps GPIO_PIN_RESET (0) to a pressed button
const isUp = computed(() => store.ioData.w === 0)
const isLeft = computed(() => store.ioData.a === 0)
const isDown = computed(() => store.ioData.s === 0)
const isRight = computed(() => store.ioData.d === 0)
const isCenter = computed(() => store.ioData.c === 0)

// LED Controls are now mapped directly to the store!
const toggleMute = () => {
  store.ledState.muted = !store.ledState.muted
  sendCommand(`LED:MUTE:${store.ledState.muted ? 1 : 0}`)
}

const sendPwm = () => {
  if (!store.isConnected) return
  store.ledState.muted = false // Moving a slider automatically unmutes
  sendCommand(`LED:PWM:${store.ledState.r}:${store.ledState.g}:${store.ledState.b}`)
}

const updateJoyMap = () => {
  if (!store.isConnected) return
  sendCommand(`IO:MAP:${store.joyMap.ud}:${store.joyMap.lr}:${store.joyMap.cen}`)
}
</script>

<template>
  <div class="joystick-page">
    <div class="header-banner">
      <div>
        <span class="section-label" style="border: none; margin: 0; padding: 0;">Hardware IO & Testing</span>
        <div style="font-size: 0.75rem; color: #64748b; margin-top: 4px;">Real-time 5-way joystick polling and system indicator brightness.</div>
      </div>
    </div>

    <div class="io-grid">
      <!-- Left Column: Joystick Vector Graphic -->
      <div class="io-card" style="justify-content: center;">
        <div class="card-title" style="margin-bottom: 0;">Live Joystick Vectors</div>
        <div class="joystick-wrapper">
          <svg viewBox="0 0 100 100" class="joystick-svg">
            <rect x="35" y="35" width="30" height="30" fill="#cbd5e1" />
            
            <polygon points="50,20 35,35 65,35" :fill="isUp ? 'var(--info)' : '#cbd5e1'" />
            <polygon points="20,50 35,35 35,65" :fill="isLeft ? 'var(--info)' : '#cbd5e1'" />
            <polygon points="50,80 35,65 65,65" :fill="isDown ? 'var(--info)' : '#cbd5e1'" />
            <polygon points="80,50 65,35 65,65" :fill="isRight ? 'var(--info)' : '#cbd5e1'" />
            
            <circle cx="50" cy="50" r="10" :fill="isCenter ? 'var(--info)' : '#94a3b8'" />
            <circle cx="50" cy="50" r="3" fill="#ffffff" />
          </svg>
        </div>
      </div>

      <!-- Right Column: Controls -->
      <div class="controls-column">
        <!-- LED Controls -->
        <div class="io-card" style="padding: 20px;">
          <div class="card-title" style="display:flex; justify-content:space-between; margin-bottom: 16px;">
            <span>Indicator Brightness Limits</span>
            <button class="mute-btn" :class="{ muted: store.ledState.muted }" @click="toggleMute">
              {{ store.ledState.muted ? '🔇 Unmute' : '🔊 Mute' }}
            </button>
          </div>

          <div class="slider-group" :class="{ disabled: store.ledState.muted }">
            <div class="slider-row">
              <span style="color:#ef4444; font-weight:700; width: 60px;">Error (R)</span>
              <input type="range" min="0" max="100" v-model="store.ledState.r" @change="sendPwm">
              <span class="val">{{ store.ledState.r }}%</span>
            </div>
            <div class="slider-row">
              <span style="color:#10b981; font-weight:700; width: 60px;">Ready (G)</span>
              <input type="range" min="0" max="100" v-model="store.ledState.g" @change="sendPwm">
              <span class="val">{{ store.ledState.g }}%</span>
            </div>
            <div class="slider-row">
              <span style="color:#3b82f6; font-weight:700; width: 60px;">Beat (B)</span>
              <input type="range" min="0" max="100" v-model="store.ledState.b" @change="sendPwm">
              <span class="val">{{ store.ledState.b }}%</span>
            </div>
          </div>
        </div>

        <!-- Hardware Mapping Controls -->
        <div class="io-card" style="padding: 20px;">
          <div class="card-title" style="margin-bottom: 16px;">Joystick Hardware Mapping</div>
          
          <div class="mapping-group">
            <label>Up / Down (Y-Axis)</label>
            <CustomSelect v-model="store.joyMap.ud" :options="udOptions" @change="updateJoyMap" :disabled="!store.isConnected" />
          </div>
          <div class="mapping-group">
            <label>Left / Right (X-Axis)</label>
            <CustomSelect v-model="store.joyMap.lr" :options="lrOptions" @change="updateJoyMap" :disabled="!store.isConnected" />
          </div>
          <div class="mapping-group" style="margin-bottom: 0;">
            <label>Center (Press)</label>
            <CustomSelect v-model="store.joyMap.cen" :options="cenOptions" @change="updateJoyMap" :disabled="!store.isConnected" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.header-banner { display: flex; justify-content: space-between; align-items: flex-end; margin-bottom: 24px; border-bottom: 1px solid var(--edge); padding-bottom: 12px; }
.io-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
.io-card { background: var(--ghost); border: 1px solid var(--edge); border-radius: 8px; padding: 24px; display: flex; flex-direction: column; }
.card-title { font-weight: 800; font-size: 0.85rem; color: var(--accent); margin-bottom: 24px; text-transform: uppercase; border-bottom: 1px solid var(--edge); padding-bottom: 8px; }

.joystick-wrapper { width: 200px; height: 200px; margin: 0 auto; }
.joystick-svg { width: 100%; height: 100%; drop-shadow: 0 4px 6px rgba(0,0,0,0.1); }
.joystick-svg polygon, .joystick-svg circle { transition: fill 0.1s; }

.mute-btn { width: auto; padding: 4px 10px; font-size: 0.7rem; background: var(--paper); border: 1px solid var(--edge); cursor: pointer; border-radius: 4px; }
.mute-btn.muted { background: #fef2f2; color: #ef4444; border-color: #fca5a5; }

.slider-group { display: flex; flex-direction: column; gap: 16px; transition: opacity 0.2s; }
.slider-group.disabled { opacity: 0.4; pointer-events: none; }
.slider-row { display: flex; align-items: center; gap: 12px; }
.slider-row input[type="range"] { flex-grow: 1; accent-color: var(--info); }
.slider-row .val { width: 40px; text-align: right; font-family: 'Fira Code', monospace; font-size: 0.8rem; font-weight: 600; }

.controls-column { display: flex; flex-direction: column; gap: 24px; }
.mapping-group { display: flex; flex-direction: column; gap: 6px; margin-bottom: 12px; }
.mapping-group label { font-size: 0.7rem; font-weight: 700; color: #64748b; }
.mapping-group select { 
  padding: 8px 10px; border-radius: 6px; border: 1px solid var(--edge); 
  background: var(--paper); font-size: 0.8rem; font-weight: 600; color: var(--ink); 
  outline: none; cursor: pointer; transition: 0.2s;
}

</style>