<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue' // <-- Add imports
import { useSystemStore } from '../../stores/systemStore'
import { useSerial } from '../../composables/useSerial'

const store = useSystemStore()
const { sendCommand } = useSerial()

const ramAddr = ref('0000')
const ramData = ref('FF')

// --- GPIO LOGIC ---
const togglePinDir = (index) => {
  const mask = 1 << index;
  store.fpgaGpio.dir ^= mask;
  sendCommand(`SPI:GPIO_DIR:${store.fpgaGpio.dir.toString(16)}`)
}
const togglePinState = (index) => {
  const mask = 1 << index;
  store.fpgaGpio.states ^= mask;
  sendCommand(`SPI:GPIO_WR:${store.fpgaGpio.states.toString(16)}`)
}
const refreshGpio = () => sendCommand('SPI:GPIO_RD')

// --- RAM LOGIC (FIXED UX) ---
const readRam = () => sendCommand(`SPI:RAM_RD:${ramAddr.value}`)
const writeRam = async () => {
  sendCommand(`SPI:RAM_WR:${ramAddr.value}:${ramData.value}`)
  await new Promise(r => setTimeout(r, 50)) // Give FPGA a millisecond
  readRam() // Auto-read it back so it pops up in the UI table!
}

// --- MIXED SIGNAL STATES ---
const pwmDuty = ref(0)
const adcVoltage = ref(0.0)
const uartPayload = ref('TEST')
const fifoReadOutput = ref('--')

const handleAdcUpdate = (e) => adcVoltage.value = e.detail
onMounted(() => window.addEventListener('adc-update', handleAdcUpdate))
onBeforeUnmount(() => window.removeEventListener('adc-update', handleAdcUpdate))

const updatePwmAndReadAdc = async () => {
  if (!store.isConnected) return;
  const hexVal = parseInt(pwmDuty.value).toString(16).padStart(2, '0')
  sendCommand(`SPI:WR:0C:${hexVal}`)
  await new Promise(r => setTimeout(r, 50)) 
  sendCommand('ADC:READ')
}

// --- UART LOGIC (FIXED) ---
const runCrossProtocolTest = async () => {
  if (!store.isConnected || !uartPayload.value) return;
  fifoReadOutput.value = `Sending ${uartPayload.value.length} bytes...`;
  
  sendCommand(`UART:TX:${uartPayload.value}`)
  await new Promise(r => setTimeout(r, 150)) // Wait for UART physical transmission
  
  fifoReadOutput.value = 'Retrieving from FPGA FIFO...';
  
  // Read the FIFO exactly the number of times as the string length
  for(let i = 0; i < uartPayload.value.length; i++) {
    sendCommand('SPI:FIFO_RD');
    await new Promise(r => setTimeout(r, 30)); 
  }
  
  fifoReadOutput.value = 'Success! Check Terminal for ASCII output.';
}

// --- BENCHMARKS ---
const isBenchmarking = ref(false)
const runRamStressTest = async () => {
  isBenchmarking.value = true
  store.addLog(">>> Starting RAM Integrity Stress Test...", "var(--info)")
  for(let i=0; i<16; i++) {
    const testVal = Math.floor(Math.random() * 255).toString(16).padStart(2, '0')
    const testAddr = i.toString(16).padStart(4, '0')
    sendCommand(`SPI:RAM_WR:${testAddr}:${testVal}`)
    await new Promise(r => setTimeout(r, 50))
  }
  store.addLog("RAM Test sequence sent. Check logs for echoes.", "var(--success)")
  isBenchmarking.value = false
}
</script>

<template>
  <div class="spi-lab">
    <div class="grid-layout">
      
      <!-- GPIO CONTROLLER -->
      <div class="config-card gpio-card">
        <div class="card-header">
          <span class="section-label">13-Channel Connector (GPIO)</span>
          <button class="action-btn" @click="refreshGpio">🔄 Refresh Inputs</button>
        </div>
        
        <div class="gpio-grid">
          <!-- Reduced from 16 to 13 to protect dedicated test pins -->
          <div v-for="i in 13" :key="i-1" class="pin-cell">
            <div class="pin-header">CON_{{ (i+1).toString().padStart(2, '0') }}</div>
            <div class="pin-controls">
              <button @click="togglePinDir(i-1)" :class="{ active: (store.fpgaGpio.dir & (1 << (i-1))) }">
                {{ (store.fpgaGpio.dir & (1 << (i-1))) ? 'OUT' : 'IN' }}
              </button>
              <div 
                class="status-indicator" 
                @click="(store.fpgaGpio.dir & (1 << (i-1))) && togglePinState(i-1)"
                :class="{ 
                  high: (store.fpgaGpio.states & (1 << (i-1))), 
                  readonly: !(store.fpgaGpio.dir & (1 << (i-1))) 
                }"
              ></div>
            </div>
          </div>
        </div>
        <div class="gpio-note">
          * CON_15, CON_16, and CON_17 are dedicated to hardware routing tests below.
        </div>
      </div>

      <!-- RAM EXPLORER -->
      <div class="config-card ram-card">
        <span class="section-label" style="display:block; margin-bottom:15px;">Internal BRAM Explorer (1KB)</span>
        
        <div class="ram-controls">
          <div class="input-group">
            <label>Address (Hex)</label>
            <input type="text" v-model="ramAddr" maxlength="4" placeholder="0000">
          </div>
          <div class="input-group">
            <label>Data (Hex)</label>
            <input type="text" v-model="ramData" maxlength="2" placeholder="FF">
          </div>
          <div class="btn-row">
            <button class="btn-primary" @click="writeRam" :disabled="!store.isConnected">Write</button>
            <button class="btn-secondary" @click="readRam" :disabled="!store.isConnected">Read</button>
          </div>
        </div>

        <div class="ram-history">
          <div class="history-row header">
            <span>Address</span><span>Value (Hex)</span><span>Binary</span>
          </div>
          <div v-for="(entry, idx) in store.ramExplorer.history" :key="idx" class="history-row">
            <span class="addr">0x{{ entry.addr }}</span>
            <span class="val">{{ entry.val }}</span>
            <span class="bin">{{ parseInt(entry.val, 16).toString(2).padStart(8, '0') }}</span>
          </div>
        </div>
      </div>

      <!-- MIXED SIGNAL & CROSS-PROTOCOL CARD -->
      <div class="config-card full-width mixed-signal-card">
        <span class="section-label" style="color: var(--info); display:block; margin-bottom: 5px;">Mixed-Signal & Routing Benchmarks</span>
        
        <div class="bench-row split-row">
          
          <!-- PWM to ADC Loopback -->
          <div class="bench-item">
            <strong>Digital PWM → Analog ADC <span class="pin-route">(CON_17 → PB1)</span></strong>
            <p>FPGA generates a PWM wave. The MCU measures the resulting RC-filtered DC voltage via ADC.</p>
            
            <div class="pwm-control">
              <label>FPGA Duty Cycle: <strong>{{ Math.round((pwmDuty / 255) * 100) }}%</strong></label>
              <input type="range" min="0" max="255" v-model="pwmDuty" @change="updatePwmAndReadAdc" :disabled="!store.isConnected">
            </div>
            
            <div class="adc-result">
              <span>Measured Analog Voltage:</span>
              <strong style="color: var(--warning); font-size: 1.15rem;">{{ adcVoltage.toFixed(3) }} V</strong>
            </div>
          </div>

          <!-- UART to SPI Cross-Protocol -->
          <div class="bench-item">
            <strong>Cross-Protocol Routing <span class="pin-route">(PB2 → CON_15)</span></strong>
            <p>MCU transmits via UART. FPGA decodes it in hardware and pushes to the SPI FIFO for retrieval.</p>
            
            <div class="uart-control">
              <input type="text" v-model="uartPayload" maxlength="8" placeholder="Enter string..." :disabled="!store.isConnected">
              <button class="btn-primary" @click="runCrossProtocolTest" :disabled="!store.isConnected">Send & Fetch</button>
            </div>
            
            <div class="adc-result output-console" :class="{ success: fifoReadOutput.includes('Check') }">
              {{ fifoReadOutput }}
            </div>
          </div>

        </div>
      </div>

      <!-- BENCHMARK PANEL -->
      <div class="config-card full-width">
        <span class="section-label" style="display:block; margin-bottom: 15px;">FPGA Performance Benchmarks</span>
        <div class="bench-row">
          <div class="bench-item">
            <strong>Block RAM Stress</strong>
            <p>Verifies data integrity across the 1KB EBR space.</p>
            <button class="btn-secondary w-full" @click="runRamStressTest" :disabled="isBenchmarking || !store.isConnected">Run Test</button>
          </div>
          <div class="bench-item">
            <strong>SPI Bridge Latency</strong>
            <p>Measures MCU-to-FPGA round-trip time (10k packets).</p>
            <button class="btn-secondary w-full" @click="sendCommand('SPI:BENCH')" :disabled="!store.isConnected">Run Bench</button>
          </div>
          <div class="bench-item">
             <strong>Bulk DMA Throughput</strong>
             <p>Stress-tests the DMA channels with 400KB of random data.</p>
             <button class="btn-secondary w-full" @click="sendCommand('SPI:BULK')" :disabled="!store.isConnected">Run Bulk</button>
          </div>
        </div>
      </div>

    </div>
  </div>
</template>

<style scoped>
.spi-lab { padding: 20px; }
.grid-layout { display: grid; grid-template-columns: 1fr 400px; gap: 20px; align-items: start; }
.full-width { grid-column: span 2; }

.config-card { background: white; border: 1px solid var(--edge); border-radius: 12px; padding: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.02); }

/* Card Headers */
.card-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; border-bottom: 1px solid var(--edge); padding-bottom: 10px; }
.section-label { font-weight: 800; font-size: 0.8rem; color: #1e293b; text-transform: uppercase; letter-spacing: 0.05em; }

/* General Buttons */
button { border-radius: 6px; font-weight: 600; cursor: pointer; transition: 0.2s; border: 1px solid var(--edge); font-family: inherit; }
button:disabled { opacity: 0.5; cursor: not-allowed; }
.btn-primary { background: var(--ink); color: white; border: none; padding: 10px; }
.btn-primary:hover:not(:disabled) { background: #334155; }
.btn-secondary { background: var(--ghost); color: var(--ink); padding: 10px; }
.btn-secondary:hover:not(:disabled) { background: #e2e8f0; }
.w-full { width: 100%; }

/* Action Button (Used for Refresh) */
.action-btn { padding: 6px 12px; font-size: 0.75rem; background: var(--paper); color: var(--ink); }
.action-btn:hover:not(:disabled) { background: #f8fafc; border-color: #cbd5e1; }

/* GPIO Grid */
.gpio-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); gap: 12px; margin-bottom: 15px;}
.pin-cell { background: var(--ghost); border: 1px solid var(--edge); border-radius: 8px; padding: 10px; }
.pin-header { font-size: 0.65rem; font-weight: 800; color: #94a3b8; margin-bottom: 8px; }
.pin-controls { display: flex; align-items: center; justify-content: space-between; }
.pin-controls button { width: 45px; font-size: 0.65rem; padding: 4px; border-radius: 4px; background: white; }
.pin-controls button.active { background: var(--ink); color: white; border: none; }
.gpio-note { font-size: 0.7rem; color: #64748b; font-style: italic; }

/* LED Indicator */
.status-indicator { width: 16px; height: 16px; border-radius: 4px; background: #cbd5e1; border: 2px solid transparent; cursor: pointer; transition: 0.2s;}
.status-indicator.high { background: var(--success); box-shadow: 0 0 8px rgba(16, 185, 129, 0.4); border-color: #34d399; }
.status-indicator.readonly { cursor: default; border-color: var(--edge); }

/* RAM Controls */
.ram-controls { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 20px; }
.input-group label { display: block; font-size: 0.7rem; font-weight: 700; color: #64748b; margin-bottom: 6px; }
.input-group input { width: 100%; padding: 10px; font-family: 'Fira Code', monospace; font-size: 0.85rem; border: 1px solid var(--edge); border-radius: 6px; background: var(--ghost); outline: none;}
.input-group input:focus { border-color: var(--info); }
.btn-row { grid-column: span 2; display: flex; gap: 10px; }
.btn-row button { flex: 1; height: 38px; }

/* RAM History */
.ram-history { background: #0f172a; border-radius: 8px; padding: 12px; color: #e2e8f0; font-family: 'Fira Code', monospace; font-size: 0.8rem; height: 200px; overflow-y: auto; }
.history-row { display: grid; grid-template-columns: 1fr 1fr 1.5fr; padding: 6px 0; border-bottom: 1px solid #1e293b; }
.history-row:last-child { border-bottom: none; }
.history-row.header { color: #64748b; font-size: 0.7rem; text-transform: uppercase; font-weight: 800; position: sticky; top: -12px; background: #0f172a; border-bottom: 2px solid #1e293b;}
.history-row .addr { color: var(--info); }
.history-row .val { color: var(--warning); font-weight: 800; }

/* Benchmarks */
.bench-row { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
.split-row { grid-template-columns: 1fr 1fr; } /* Used for the mixed signal card */
.bench-item { background: var(--ghost); padding: 16px; border-radius: 8px; border: 1px solid var(--edge); display: flex; flex-direction: column; }
.bench-item strong { display: block; font-size: 0.85rem; margin-bottom: 6px; color: var(--ink); }
.bench-item p { font-size: 0.75rem; color: #64748b; margin-bottom: 15px; line-height: 1.5; flex-grow: 1; }

/* Mixed Signal Card Tweaks */
.mixed-signal-card { border-left: 4px solid var(--info); }
.pin-route { color: var(--info); font-family: 'Fira Code', monospace; font-size: 0.75rem; background: #eff6ff; padding: 2px 6px; border-radius: 4px; margin-left: 4px; font-weight: 600;}

.pwm-control { display: flex; flex-direction: column; gap: 8px; margin-bottom: 15px; }
.pwm-control label { font-size: 0.75rem; color: #64748b; display: flex; justify-content: space-between;}
.pwm-control input[type="range"] { accent-color: var(--info); width: 100%; cursor: pointer;}

.adc-result { display: flex; justify-content: space-between; align-items: center; background: white; border: 1px solid var(--edge); padding: 12px 16px; border-radius: 6px; font-family: 'Fira Code', monospace; font-size: 0.85rem; }
.output-console { color: #94a3b8; justify-content: center; margin-top: auto; }
.output-console.success { color: var(--success); border-color: #a7f3d0; background: #f0fdf4; }

.uart-control { display: flex; gap: 10px; margin-bottom: 15px; }
.uart-control input { flex-grow: 1; padding: 10px; border-radius: 6px; border: 1px solid var(--edge); font-family: 'Fira Code', monospace; font-size: 0.85rem; background: white; outline: none;}
.uart-control input:focus { border-color: var(--info); }
.uart-control button { width: 130px; }
</style>