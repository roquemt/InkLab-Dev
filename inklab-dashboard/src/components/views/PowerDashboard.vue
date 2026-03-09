<script setup>
import { ref, onMounted, onBeforeUnmount, watch, computed } from 'vue'
import { useSystemStore } from '../../stores/systemStore'
import { useSerial } from '../../composables/useSerial'
import { Chart, LineController, LineElement, PointElement, LinearScale, CategoryScale, Tooltip } from 'chart.js'
import CustomSelect from '../CustomSelect.vue' 

Chart.register(LineController, LineElement, PointElement, LinearScale, CategoryScale, Tooltip)
const store = useSystemStore()
const { sendCommand } = useSerial()

// ==========================================
// ADVANCED CONFIG STATE (You were missing this part!)
// ==========================================
const showAdvancedConfig = ref(false)

const bqConfig = ref({
  autoRearm: true,
  votg: 5000,
  pfmFwd: false,
  pfmOtg: false,
  ema: 0.2
})

const applyBqConfig = (cmd, val) => {
  sendCommand(`BQ:${cmd}:${val}`)
}

// Watch hardware registers to keep UI permanently synced!
watch(() => store.bqData.rawRegs, (regs) => {
  if (!regs || regs.length < 0x13) return;
  // Parse VOTG (Registers 0x0B and 0x0C) -> LSB = 10mV, Offset = 2800mV
  const votgWord = (regs[0x0B] << 8) | regs[0x0C];
  bqConfig.value.votg = (votgWord * 10) + 2800;
  // Parse PFM (Register 0x12) -> Bit 4 & 5 (0 = Enabled, 1 = Disabled)
  bqConfig.value.pfmFwd = (regs[0x12] & (1 << 4)) === 0;
  bqConfig.value.pfmOtg = (regs[0x12] & (1 << 5)) === 0;
}, { deep: true, immediate: true })

watch(() => store.bqData.autoRearm, (val) => bqConfig.value.autoRearm = val === 1, { immediate: true })
watch(() => store.bqData.ema, (val) => { if(val !== undefined) bqConfig.value.ema = val }, { immediate: true })
// ==========================================
// CHART STATE
// ==========================================
const chartCanvas1 = ref(null)
const chartCanvas2 = ref(null)
let chart1 = null
let chart2 = null

const telemRate = ref(500) 
const activeRate = ref(500) 
const isFastMode1 = ref(false)
const isFastMode2 = ref(false)

const config = ref({
  c1: { source: 'vbus', metric: 'V', depth: 250, trigger: 'none', running: true },
  c2: { source: '3v3_ext', metric: 'I', depth: 250, trigger: 'none', running: true }
})

const chartStats = ref({
  c1: { max: 0, min: 0, pp: 0 },
  c2: { max: 0, min: 0, pp: 0 }
})

const optionsSource = [
  { label: '5V USB Input (VBUS)', value: 'vbus' },
  { label: 'Battery Pack (VBAT)', value: 'vbat' },
  { label: '1.2V Core (INA)', value: '1v2_core' },
  { label: '3.3V FPGA (INA)', value: '3v3_fpga' },
  { label: '3.3V MCU (INA)', value: '3v3_mcu' },
  { label: '3.3V Ext (INA)', value: '3v3_ext' }
]

const triggerOptions = [
  { label: 'Free Running (None)', value: 'none' },
  { label: 'FPGA Slot Changed', value: 'slot' },
  { label: 'System Clock Changed', value: 'clock' },
  { label: 'Sleep Mode Toggled', value: 'sleep' },
  { label: 'Charger State Changed', value: 'charge' },
  { label: 'Hardware Fault Detected', value: 'fault' },
  { label: 'Joystick / IO Pressed', value: 'gpio' }
]

const windowOptions = [
  { label: '100 Pts', value: 100 },
  { label: '250 Pts', value: 250 },
  { label: '500 Pts', value: 500 },
  { label: '1000 Pts', value: 1000 }
]

const unitMap = { 'V': 'V', 'I': 'mA', 'W': 'mW' }
const MASTER_MAX_POINTS = 10000 
const buffer1 = { labels: [], data: {} }
const buffer2 = { labels: [], data: {} }
let resetIndex1 = 0; let resetIndex2 = 0

// MODIFIED: 'opt.val' changed to 'opt.value'
const initBuffer = (buf) => {
  buf.labels = []
  buf.absoluteCount = 0
  optionsSource.forEach(opt => {
    ['V', 'I', 'W'].forEach(met => buf.data[`${opt.value}_${met}`] = [])
  })
}
initBuffer(buffer1); initBuffer(buffer2)

const activePointers1 = ref(new Array(10).fill(false))
const activePointers2 = ref(new Array(10).fill(false))

const handleChartClick = (chartNum, event) => {
  const chart = chartNum === 1 ? chart1 : chart2
  const pointers = chartNum === 1 ? activePointers1.value : activePointers2.value
  if (!chart) return
  const rect = chart.canvas.getBoundingClientRect()
  const chartArea = chart.chartArea
  const x = event.clientX - rect.left
  if (x >= chartArea.left && x <= chartArea.right && event.clientY - rect.top >= chartArea.top && event.clientY - rect.top <= chartArea.bottom) {
    const col = Math.floor(((x - chartArea.left) / (chartArea.right - chartArea.left)) * 10)
    if (col >= 0 && col < 10) { pointers[col] = !pointers[col]; chart.update('none') }
  }
}

const clearPointers = () => {
  activePointers1.value.fill(false); activePointers2.value.fill(false)
  if (chart1) chart1.update('none')
  if (chart2) chart2.update('none')
}

// --- POLLING ---
let pollInterval = null
let renderInterval = null

const getLiveValue = (source, metric) => {
  if (source === 'vbus') {
    // Force V, I, P to zero on the chart if we are running on battery
    if (store.bqData.mode === 'OTG') return 0 
    return metric === 'V' ? store.bqData.vbusVolt : metric === 'I' ? store.bqData.vbusCurr : store.bqData.vbusPwr || 0
  }
  if (source === 'vbat') return metric === 'V' ? store.bqData.batVolt : metric === 'I' ? store.bqData.batCurr : store.bqData.batPwr || 0
  const rail = store.powerData[source]
  if (rail) return metric === 'V' ? rail.v : metric === 'I' ? rail.i : rail.pwr || 0
  return 0
}

// Replace the current appendData function with this:
const appendData = (buf, now, overrideSource = null, overrideData = null) => {
  buf.labels.push(buf.absoluteCount)
  buf.absoluteCount++
  
  optionsSource.forEach(src => {
    if (overrideSource === src.value && overrideData) {
      let [v, i] = overrideData
      if (src.value === 'vbus' && store.bqData.mode === 'OTG') {
        v = 0; i = 0;
      }
      buf.data[`${src.value}_V`].push(v); 
      buf.data[`${src.value}_I`].push(i); 
      buf.data[`${src.value}_W`].push(v * i);
    } else {
      buf.data[`${src.value}_V`].push(getLiveValue(src.value, 'V')); 
      buf.data[`${src.value}_I`].push(getLiveValue(src.value, 'I')); 
      buf.data[`${src.value}_W`].push(getLiveValue(src.value, 'W'));
    }
  })

  if (buf.labels.length > MASTER_MAX_POINTS) {
    buf.labels.shift(); Object.keys(buf.data).forEach(k => buf.data[k].shift())
    if (buf === buffer1 && resetIndex1 > 0) resetIndex1--
    if (buf === buffer2 && resetIndex2 > 0) resetIndex2--
  }
}
// ==========================================
// EVENT TRIGGERS (Auto-Reset Watchers)
// ==========================================
const checkTriggers = (eventStr) => {
  if (config.value.c1.trigger === eventStr) resetChart(1)
  if (config.value.c2.trigger === eventStr) resetChart(2)
}

watch(() => store.activeSlot, () => checkTriggers('slot'))
watch(() => store.clockStatus, () => checkTriggers('clock'))
watch(() => store.bqData.mode, () => checkTriggers('charge'))

// --- NEW HIGH-PERFORMANCE WATCHER ---
// Sums up the IO values. If the sum changes, a button was pressed or released.
const ioSum = computed(() => store.ioData.w + store.ioData.a + store.ioData.s + store.ioData.d + store.ioData.c)
watch(ioSum, () => checkTriggers('gpio'))
// ------------------------------------

watch(() => store.activeFaults.length, (newLen, oldLen) => {
  if (newLen > oldLen) checkTriggers('fault')
})

watch(() => store.isSleeping, (isSleeping) => {
  checkTriggers('sleep')
  if (isSleeping) {
    if (isFastMode1.value) toggleFastMode(1)
    if (isFastMode2.value) toggleFastMode(2)
    
    // Auto-clamp rate to 500ms if sleep mode is enabled
    if (telemRate.value < 500) {
      telemRate.value = 500;
      updateRate(); 
    }
  }
})

// ==========================================
// MOUNT & INIT
// ==========================================
onMounted(() => {
  const saved = localStorage.getItem('powerChartConfig')
  if (saved) {
    try {
      const parsed = JSON.parse(saved)
      parsed.c1.running = true; parsed.c2.running = true
      
      const validDepths = [100, 250, 500]
      if (!validDepths.includes(Number(parsed.c1.depth))) parsed.c1.depth = 250
      if (!validDepths.includes(Number(parsed.c2.depth))) parsed.c2.depth = 250
      
      if (!parsed.c1.trigger) parsed.c1.trigger = 'none'
      if (!parsed.c2.trigger) parsed.c2.trigger = 'none'

      config.value = parsed
    } catch (e) { console.error("Failed to parse config", e) }
  }
  
  initCharts()

  let renderFrameId = null;

  const renderLoop = () => {
    if (config.value.c1.running) updateChart(1)
    if (config.value.c2.running) updateChart(2)
    renderFrameId = requestAnimationFrame(renderLoop)
  }
  
  pollInterval = setInterval(() => {
    if (!store.isConnected) return
    const now = new Date()
    if (!isFastMode1.value) appendData(buffer1, now)
    if (!isFastMode2.value) appendData(buffer2, now)
  }, 100) 

  window.addEventListener('fast-telemetry', (e) => {
    const data = e.detail; const now = new Date()
    if (isFastMode1.value && data["1"]) appendData(buffer1, now, config.value.c1.source, data["1"])
    if (isFastMode2.value && data["2"]) appendData(buffer2, now, config.value.c2.source, data["2"])
  })
  renderLoop() 
})

watch(config, (newCfg) => localStorage.setItem('powerChartConfig', JSON.stringify(newCfg)), { deep: true })

const updateRate = () => {
  const minLimit = store.isSleeping ? 500 : 50;
  
  // Ensure it's a number and respects the lower bound
  if (typeof telemRate.value !== 'number' || telemRate.value < minLimit) {
    telemRate.value = minLimit;
  }
  if (telemRate.value > 5000) telemRate.value = 5000;
  
  activeRate.value = telemRate.value;
  sendCommand(`TELEM:RATE:${telemRate.value}`);
  resetMaster();
}

const toggleFastMode = (chartNum) => {
  if (chartNum === 1) {
    isFastMode1.value = !isFastMode1.value
    sendCommand(`TELEM:FAST:1:${isFastMode1.value ? config.value.c1.source : 'OFF'}`)
    resetChart(1) 
  } else {
    isFastMode2.value = !isFastMode2.value
    sendCommand(`TELEM:FAST:2:${isFastMode2.value ? config.value.c2.source : 'OFF'}`)
    resetChart(2) 
  }
}

const handleSourceChange = (chartNum) => {
  if (chartNum === 1 && isFastMode1.value) sendCommand(`TELEM:FAST:1:${config.value.c1.source}`)
  if (chartNum === 2 && isFastMode2.value) sendCommand(`TELEM:FAST:2:${config.value.c2.source}`)
  updateChart(chartNum)
}

// Replace the current updateChart function with this:
const updateChart = (chartNum) => {
  const cfg = chartNum === 1 ? config.value.c1 : config.value.c2
  const chart = chartNum === 1 ? chart1 : chart2
  const resetIdx = chartNum === 1 ? resetIndex1 : resetIndex2
  const targetBuffer = chartNum === 1 ? buffer1 : buffer2
  if (!chart) return

  const startIndex = Math.max(resetIdx, targetBuffer.labels.length - cfg.depth)
  
  // Create fixed X-Axis indices to prevent dynamic stretching
  const visibleLabels =[];
  let baseAxisVal = 0;
  
  // If we've drawn more points than the window size, scroll the view.
  // Otherwise, lock the start of the axis to the reset point.
  if (targetBuffer.labels.length - resetIdx > cfg.depth) {
      baseAxisVal = targetBuffer.labels[targetBuffer.labels.length - cfg.depth];
  } else {
      baseAxisVal = resetIdx < targetBuffer.labels.length ? targetBuffer.labels[resetIdx] : targetBuffer.absoluteCount;
  }
  
  // Fill exactly 'depth' amount of labels so the graph width is fixed
  for (let i = 0; i < cfg.depth; i++) {
      visibleLabels.push(baseAxisVal + i);
  }

  const visibleData = targetBuffer.data[`${cfg.source}_${cfg.metric}`].slice(startIndex)

  chart.data.labels = visibleLabels
  chart.data.datasets[0].data = visibleData
  chart.update('none')

  if (visibleData.length > 0) {
    const max = Math.max(...visibleData)
    const min = Math.min(...visibleData)
    chartStats.value[`c${chartNum}`] = { max, min, pp: max - min }
  }
}

const isMasterRunning = computed(() => config.value.c1.running || config.value.c2.running)
const toggleMasterState = () => {
  const newState = !isMasterRunning.value
  config.value.c1.running = newState; config.value.c2.running = newState
}

// --- EFFICIENCY CALCULATIONS ---
const sysEfficiency = computed(() => {
  const pRailsOut = Object.values(store.powerData).reduce((sum, r) => sum + r.pwr, 0)
  
  if (store.bqData.mode === 'OTG') {
    // In backup mode, system is powered solely by battery discharge
    const pBat = Math.abs(store.bqData.batPwr)
    if (pBat <= 0 || pRailsOut <= 0) return '0.0%'
    const eff = (pRailsOut / pBat) * 100
    return eff > 100 ? '>100%' : eff.toFixed(1) + '%'
  } else {
    // Standard forward mode
    if (store.bqData.vbusVolt < 4.0) return '--'
    const pVbus = store.bqData.vbusPwr
    const pBat = store.bqData.batCurr > 0 ? store.bqData.batPwr : 0
    const pAvail = pVbus - pBat
    if (pAvail <= 0 || pRailsOut <= 0) return '0.0%'
    const eff = (pRailsOut / pAvail) * 100
    return eff > 100 ? '>100%' : eff.toFixed(1) + '%'
  }
})

const chgEfficiency = computed(() => {
  // Only valid if actively charging
  if (store.bqData.vbusVolt < 4.0 || store.bqData.batCurr <= 0) return '--'

  const pVbus = store.bqData.vbusPwr
  const pBat = store.bqData.batPwr

  // Calculate System Input Power. 
  // LDO Input Power = VBUS_Voltage * Total_Rail_Current
  const iRailsTotal = Object.values(store.powerData).reduce((sum, r) => sum + r.i, 0)
  const quiescentI = 9.0 // 4mA (INA sensors) + 5mA (BQ internal)
  const pSysIn = store.bqData.vbusVolt * (iRailsTotal + quiescentI) // V * mA = mW

  // Power specifically allocated to the charger's buck/boost converter
  const pChgIn = pVbus - pSysIn

  if (pChgIn <= 0 || pBat <= 0) return '0.0%'
  
  const eff = (pBat / pChgIn) * 100
  return eff > 100 ? '>100%' : eff.toFixed(1) + '%'
})


const resetAll = () => {
  store.resetPowerMetrics()
  
  // 1. Completely wipe all saved data and reset absoluteCount to 0
  initBuffer(buffer1)
  initBuffer(buffer2)
  
  // 2. Reset the visual offset trackers back to 0
  resetIndex1 = 0
  resetIndex2 = 0
  
  // 3. Force the charts to redraw immediately
  updateChart(1)
  updateChart(2)
}

const resetChart = (chartNum) => {
  if (chartNum === 1) resetIndex1 = buffer1.labels.length
  if (chartNum === 2) resetIndex2 = buffer2.labels.length
  updateChart(chartNum)
}
const resetMaster = () => { resetChart(1); resetChart(2) }

// --- CSV SAVER LOGIC ---
const storeWaveform = (chartNum) => {
  const cfg = chartNum === 1 ? config.value.c1 : config.value.c2
  const targetBuffer = chartNum === 1 ? buffer1 : buffer2
  const key = `${cfg.source}_${cfg.metric}`

  const windowPoints = cfg.depth
  const startIndex = Math.max(0, targetBuffer.labels.length - windowPoints)
  
  const expLabels = targetBuffer.labels.slice(startIndex)
  const expData = targetBuffer.data[key].slice(startIndex)

  if (expLabels.length === 0) return

  // Calculate the time step in seconds
  const effRateSec = getEffectiveRate(chartNum) / 1000;

  // Ensure this string construction below is IDENTICAL for both
  // We explicitly define the 3 columns: Point, Time (s), and Value
  let csv = `Point,Time (s),${cfg.source}_${cfg.metric}\n`
  
  for (let i = 0; i < expLabels.length; i++) {
    const pt = expLabels[i];
    const tSec = (pt * effRateSec).toFixed(3);
    
    // Ensure the data row is composed of 3 parts separated by commas
    csv += `${pt},${tSec},${expData[i]}\n`
  }
  
  const blob = new Blob([csv], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `inklab_CH${chartNum}_${cfg.source}_${cfg.metric}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

const saveBothWaveforms = () => {
  storeWaveform(1)
  setTimeout(() => storeWaveform(2), 200) 
}

onBeforeUnmount(() => {
  if (renderFrameId) cancelAnimationFrame(renderFrameId)
})

const columnPointersPlugin = {
  id: 'columnPointers',
  afterDraw(chart) {
    const chartNum = chart.canvas.id === 'canvas1' ? 1 : 2
    const pointers = chartNum === 1 ? activePointers1.value : activePointers2.value
    const cfg = chartNum === 1 ? config.value.c1 : config.value.c2
    const ctx = chart.ctx; const chartArea = chart.chartArea; const meta = chart.getDatasetMeta(0)
    if (!meta.data || !meta.data.length) return

    const colWidth = (chartArea.right - chartArea.left) / 10
    const colorTheme = chartNum === 1 ? '#3b82f6' : '#10b981'

    ctx.save(); ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.font = 'bold 11px "Fira Code", monospace'

    for (let i = 0; i < 10; i++) {
      if (pointers[i]) {
        const targetX = chartArea.left + (i + 0.5) * colWidth
        let closestIdx = 0, minDiff = Infinity
        for (let j = 0; j < meta.data.length; j++) {
          const diff = Math.abs(meta.data[j].x - targetX)
          if (diff < minDiff) { minDiff = diff; closestIdx = j }
        }

        const point = meta.data[closestIdx]
        const rawVal = chart.data.datasets[0].data[closestIdx]
        if (rawVal === undefined) continue

        let valStr = '';
        if (cfg.metric === 'W') valStr = formatPower(rawVal);
        else if (cfg.metric === 'I') valStr = `${rawVal.toFixed(2)} mA`;
        else valStr = `${rawVal.toFixed(2)} V`;

        ctx.beginPath(); ctx.moveTo(targetX, chartArea.top); ctx.lineTo(targetX, chartArea.bottom)
        ctx.lineWidth = 1; ctx.strokeStyle = 'rgba(148, 163, 184, 0.5)'; ctx.setLineDash([4, 4]); ctx.stroke(); ctx.setLineDash([]) 

        const boxWidth = ctx.measureText(valStr).width + 16
        let boxY = point.y - 22 - 12
        if (boxY < chartArea.top) boxY = point.y + 12

        ctx.fillStyle = colorTheme; ctx.beginPath(); ctx.roundRect(targetX - boxWidth/2, boxY, boxWidth, 22, 4); ctx.fill()
        ctx.fillStyle = '#ffffff'; ctx.fillText(valStr, targetX, boxY + 11)
        
        ctx.beginPath(); ctx.arc(point.x, point.y, 4, 0, 2 * Math.PI); ctx.fillStyle = '#ffffff'; ctx.fill()
        ctx.strokeStyle = colorTheme; ctx.lineWidth = 2; ctx.stroke()
      }
    }
    ctx.restore()
  }
}

const initCharts = () => {
  const commonOptions = {
    responsive: true, maintainAspectRatio: false, animation: false,
    elements: { point: { radius: 0, hitRadius: 10, hoverRadius: 5 }, line: { tension: 0.1, borderWidth: 2 } },
    interaction: { mode: 'index', intersect: false }, 
    plugins: { 
      legend: { display: false },
        tooltip: { 
        enabled: true, backgroundColor: 'rgba(15, 23, 42, 0.9)', 
        titleFont: { family: 'Fira Code' }, bodyFont: { family: 'Fira Code' },
        callbacks: {
          // 1. Changes the Tooltip Title (top line) from Point Number to Time in Seconds
          title: function(context) {
            const chartNum = context[0].chart.canvas.id === 'canvas1' ? 1 : 2;
            const effRateSec = getEffectiveRate(chartNum) / 1000;
            const pt = parseInt(context[0].label);
            const tSec = (pt * effRateSec).toFixed(3);
            return `t: ${tSec} s`;
          },
          // 2. Formats the data value, automatically converting to uW/mW/W
          label: function(context) {
            const chartNum = context.chart.canvas.id === 'canvas1' ? 1 : 2
            const cfg = chartNum === 1 ? config.value.c1 : config.value.c2
            
            if (cfg.metric === 'W') return formatPower(context.parsed.y);
            if (cfg.metric === 'I') return `${context.parsed.y.toFixed(2)} mA`;
            return `${context.parsed.y.toFixed(2)} V`;
          }
        }
      }
    },
    scales: {
      x: { 
        ticks: { 
          maxTicksLimit: 5, // <-- CHANGED from 6 to 4
          maxRotation: 0, 
          align: 'inner', 
          color: '#94a3b8' 
        }, 
        grid: { display: false } 
      },
      y: { 
        beginAtZero: false, 
        ticks: { color: '#64748b' }, 
        grid: { color: '#f1f5f9' } 
      }
    }
  }

  chart1 = new Chart(chartCanvas1.value, { type: 'line', data: { labels: [], datasets: [{ data: [], borderColor: '#3b82f6', backgroundColor: 'rgba(59, 130, 246, 0.1)', fill: true }] }, options: commonOptions, plugins: [columnPointersPlugin] })
  chart2 = new Chart(chartCanvas2.value, { type: 'line', data: { labels: [], datasets: [{ data: [], borderColor: '#10b981', backgroundColor: 'rgba(16, 185, 129, 0.1)', fill: true }] }, options: commonOptions, plugins: [columnPointersPlugin] })
}

const formatPower = (val_mW) => {
  const absVal = Math.abs(val_mW);
  if (absVal >= 1000) return `${(val_mW / 1000).toFixed(4)} W`;
  if (absVal >= 1) return `${val_mW.toFixed(3)} mW`;
  return `${(val_mW * 1000).toFixed(1)} µW`;
};

// Calculates the true polling rate in milliseconds (Handles Fast Mode automatically)
const getEffectiveRate = (chartNum) => {
  const isFast = chartNum === 1 ? isFastMode1.value : isFastMode2.value;
  if (!isFast) return activeRate.value;
  
  // In your MCU code, BQ sensors update every 20ms, INA sensors every 5ms
  const source = chartNum === 1 ? config.value.c1.source : config.value.c2.source;
  if (source === 'vbus' || source === 'vbat') return 20; 
  return 5; 
};

const isActivelyCharging = computed(() => {
  return !store.isSleeping && 
         store.bqData.mode !== 'Idle' && 
         store.bqData.mode !== 'Not Charging' && 
         store.bqData.mode !== 'OTG' &&
         store.bqData.batCurr > 0;
})


</script>

<template>
  <div class="power-dashboard">

    
    
    <!-- MASTER TOP BAR -->
    <div class="header-banner" style="justify-content: flex-end;">
      
<div class="master-controls">
        <button class="btn-secondary btn-small action-btn" @click="toggleMasterState" :class="{'is-running': !isMasterRunning}">
          {{ isMasterRunning ? '⏸ Pause' : '▶ Play' }}
        </button>
        <button class="btn-secondary btn-small action-btn" @click="saveBothWaveforms">💾 Save</button>
        <button class="btn-secondary btn-small action-btn" @click="resetAll">🔄 Reset All</button>

        <!-- MOVED HERE: Right next to Reset All -->
        <div class="config-dropdown-wrapper">
          <button class="btn-secondary btn-small action-btn" @click="showAdvancedConfig = !showAdvancedConfig">
            ⚙️ Config
          </button>
          
          <div v-if="showAdvancedConfig" class="advanced-popover">
            <div class="popover-header">Advanced Power Config</div>
            
            <div class="popover-row">
              <span>Auto-Rearm Backup</span>
              <label class="switch">
                <input type="checkbox" v-model="bqConfig.autoRearm" @change="applyBqConfig('AUTO_REARM', bqConfig.autoRearm ? 1 : 0)">
                <span class="slider round"></span>
              </label>
            </div>

            <div class="popover-row">
              <span>OTG Voltage</span>
              <div class="segmented-control" style="width: 110px">
                <button :class="{active: bqConfig.votg === 3600}" @click="bqConfig.votg = 3600; applyBqConfig('VOTG', 3600)">3.6V</button>
                <button :class="{active: bqConfig.votg === 5000}" @click="bqConfig.votg = 5000; applyBqConfig('VOTG', 5000)">5.0V</button>
              </div>
            </div>

            <div class="popover-row">
              <span title="Pulse Frequency Mod (Forward)">PFM (Input Power)</span>
              <label class="switch">
                <input type="checkbox" v-model="bqConfig.pfmFwd" @change="applyBqConfig('PFM_FWD', bqConfig.pfmFwd ? 1 : 0)">
                <span class="slider round"></span>
              </label>
            </div>

            <div class="popover-row">
              <span title="Pulse Frequency Mod (Battery Backup)">PFM (OTG Power)</span>
              <label class="switch">
                <input type="checkbox" v-model="bqConfig.pfmOtg" @change="applyBqConfig('PFM_OTG', bqConfig.pfmOtg ? 1 : 0)">
                <span class="slider round"></span>
              </label>
            </div>

            <div class="popover-row">
              <span title="ADC Exponential Moving Average Filter">BQ ADC Filter</span>
              <div style="display: flex; gap: 8px; align-items: center;">
                <input type="range" min="0.1" max="1.0" step="0.1" v-model.number="bqConfig.ema" @change="applyBqConfig('EMA', bqConfig.ema)" style="width: 70px; margin: 0; accent-color: var(--info);">
                <span style="font-family: 'Fira Code', monospace; font-size: 0.75rem; width: 24px; text-align: right; color: var(--info); font-weight: 700;">{{ Number(bqConfig.ema).toFixed(1) }}</span>
              </div>
            </div>
          </div>
        </div>
        <!-- END MOVED BLOCK -->

        <div class="rate-control">
          <label>Poll Rate:</label>
          <input type="number" v-model.number="telemRate" step="50" :min="store.isSleeping ? 500 : 50" max="5000" @keyup.enter="updateRate">
          <span class="ms-unit">ms</span>
          <button class="btn-secondary btn-small apply-btn" @click="updateRate" :disabled="!store.isConnected">Apply</button>
        </div>
        
        <div class="active-rate-badge">
          Active: <span style="color: var(--info)">{{ store.isSleeping ? '500ms' : activeRate + 'ms' }}</span>
        </div>
      </div>
    </div>

<!-- 1. HIGH-VISIBILITY HARDWARE STATUS -->
    <div class="status-panel" :class="{ 'is-faulty': store.activeFaults.length > 0 }">
      
      <!-- Existing Left Block -->
      <div class="status-left">
        <div class="status-title">Charger Status & Active Protections</div>
        <div class="status-body">
          <div class="state-badge" :class="{ charging: store.bqData.mode !== 'Not Charging' }">
            {{ store.bqData.mode }}
          </div>
          <div v-if="store.activeFaults.length === 0" class="normal-badge">
            ✅ System Normal
          </div>
          <div v-else class="fault-list">
            <div class="alert-pill" v-for="(fault, i) in store.activeFaults" :key="i">
              ⚠️ {{ fault }}
            </div>
          </div>
        </div>
      </div>

      <!-- NEW: Efficiency Block -->
<!-- NEW: Efficiency Block -->
      <div class="status-right">
         <div class="eff-stat" title="Total Rail Output / System Input Power">
            <span class="eff-label">Sys Eff.</span>
            <span class="eff-val">{{ sysEfficiency }}</span>
         </div>
         
         <!-- ONLY RENDER THIS BLOCK IF ACTIVELY CHARGING -->
         <div v-if="isActivelyCharging" class="eff-stat" title="Battery Power / Charger Conv. Input Power">
            <span class="eff-label">Chg Eff.</span>
            <span class="eff-val">{{ chgEfficiency }}</span>
         </div>
      </div>

    </div>

    <!-- 2. LIVE CHARTS -->
    <div class="charts-section">
      <!-- Chart 1 -->
      <div class="chart-card">
        <div class="chart-toolbar">
          <div class="toolbar-row">
            <CustomSelect v-model="config.c1.source" :options="optionsSource" @change="handleSourceChange(1)" size="small" style="width: 175px" />

            <div class="segmented-control">
              <button :class="{active: config.c1.metric === 'V'}" @click="config.c1.metric = 'V'; updateChart(1)">V</button>
              <button :class="{active: config.c1.metric === 'I'}" @click="config.c1.metric = 'I'; updateChart(1)">I</button>
              <button :class="{active: config.c1.metric === 'W'}" @click="config.c1.metric = 'W'; updateChart(1)">P</button>
            </div>

            <CustomSelect v-model.number="config.c1.depth" :options="windowOptions" @change="updateChart(1)" size="small" style="width: 95px" />

            <div class="chart-actions">
              <button @click="resetChart(1)" title="Clear Graph">🗑️</button>
              <button 
                @click="toggleFastMode(1)" 
                :disabled="!store.isConnected || store.isSleeping"
                class="fast-btn" :class="{'is-fast': isFastMode1}">
                {{ isFastMode1 ? '⚡ LIVE' : '⚡ FAST' }}
              </button>
            </div>
          </div>
          
          <div class="toolbar-row trigger-row">
            <div class="trigger-select-group">
              <label>Auto-Reset On:</label>
              <CustomSelect v-model="config.c1.trigger" :options="triggerOptions" size="small" class="trigger-dropdown" style="width: 195px" />
            </div>
            
            <!-- Pro Oscilloscope Feature: Window Stats -->
            <div class="scope-stats" style="color: #3b82f6;">
              <span>MAX: {{ chartStats.c1.max.toFixed(2) }}</span>
              <span>MIN: {{ chartStats.c1.min.toFixed(2) }}</span>
              <span>Δ: {{ chartStats.c1.pp.toFixed(2) }}</span>
            </div>
          </div>
        </div>
        <div class="canvas-wrapper" @click="handleChartClick(1, $event)"><canvas id="canvas1" ref="chartCanvas1"></canvas></div>
      </div>

      <!-- Chart 2 -->
      <div class="chart-card">
        <div class="chart-toolbar">
          <div class="toolbar-row">
            <CustomSelect v-model="config.c2.source" :options="optionsSource" @change="handleSourceChange(2)" size="small" style="width: 175px" />

            <div class="segmented-control">
              <button :class="{active: config.c2.metric === 'V'}" @click="config.c2.metric = 'V'; updateChart(2)">V</button>
              <button :class="{active: config.c2.metric === 'I'}" @click="config.c2.metric = 'I'; updateChart(2)">I</button>
              <button :class="{active: config.c2.metric === 'W'}" @click="config.c2.metric = 'W'; updateChart(2)">P</button>
            </div>

            <CustomSelect v-model.number="config.c2.depth" :options="windowOptions" @change="updateChart(2)" size="small" style="width: 95px" />

            <div class="chart-actions">
              <button @click="resetChart(2)" title="Clear Graph">🗑️</button>
              <button 
                @click="toggleFastMode(2)" 
                :disabled="!store.isConnected || store.isSleeping"
                class="fast-btn" :class="{'is-fast': isFastMode2}">
                {{ isFastMode2 ? '⚡ LIVE' : '⚡ FAST' }}
              </button>
            </div>
          </div>

          <div class="toolbar-row trigger-row">
            <div class="trigger-select-group">
              <label>Auto-Reset On:</label>
              <CustomSelect v-model="config.c2.trigger" :options="triggerOptions" size="small" class="trigger-dropdown" style="width: 195px" />
            </div>

            <!-- Pro Oscilloscope Feature: Window Stats -->
            <div class="scope-stats" style="color: #10b981;">
              <span>MAX: {{ chartStats.c2.max.toFixed(2) }}</span>
              <span>MIN: {{ chartStats.c2.min.toFixed(2) }}</span>
              <span>Δ: {{ chartStats.c2.pp.toFixed(2) }}</span>
            </div>
          </div>
        </div>
        <div class="canvas-wrapper" @click="handleChartClick(2, $event)"><canvas id="canvas2" ref="chartCanvas2"></canvas></div>
      </div>
    </div>

    <!-- 3. DETAILED POWER GRID -->
    <div class="power-grid">
      <div class="power-card" v-for="(rail, key) in store.powerData" :key="key">
        
        <div class="power-title">{{ rail.title }}</div>
        <div class="live-vi">
        <div class="vi-item"><span>Voltage</span><strong>{{ rail.v.toFixed(2) }} V</strong></div>
        <div class="vi-item"><span>Current</span><strong>{{ rail.i.toFixed(2) }} mA</strong></div>
        </div>
        <div class="p-row"><span>Live Power:</span><span>{{ formatPower(rail.pwr) }}</span></div>
        <div class="p-row" style="color:#94a3b8"><span>Avg (EMA):</span><span>{{ formatPower(rail.ema) }}</span></div>
        <div class="p-row" style="color:#ef4444"><span>Peak Limit:</span><span>{{ formatPower(rail.peak) }}</span></div>
      </div>
    </div>

  </div>
</template>

<style scoped>
.config-dropdown-wrapper { position: relative; display: flex; height: 100%; }
.config-dropdown-wrapper .action-btn { height: 100%; }
.config-dropdown-wrapper { position: relative; }
.advanced-popover {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  width: 260px;
  background: var(--paper);
  border: 1px solid var(--edge);
  border-radius: 8px;
  box-shadow: 0 10px 25px rgba(0,0,0,0.15);
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 14px;
  z-index: 100;
}
.popover-header {
  font-size: 0.75rem;
  font-weight: 800;
  color: #64748b;
  text-transform: uppercase;
  border-bottom: 1px solid var(--edge);
  padding-bottom: 8px;
  margin-bottom: 4px;
}
.popover-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.8rem;
  font-weight: 600;
  color: var(--ink);
}
/* Re-use your existing switch CSS if needed */
.switch { position: relative; display: inline-block; width: 36px; height: 20px; }
.switch input { opacity: 0; width: 0; height: 0; }
.slider { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: var(--edge); transition: .3s; border-radius: 20px; }
.slider:before { position: absolute; content: ""; height: 14px; width: 14px; left: 3px; bottom: 3px; background-color: white; transition: .3s; border-radius: 50%; }
input:checked + .slider { background-color: var(--info); }
input:checked + .slider:before { transform: translateX(16px); }
.power-dashboard { display: flex; flex-direction: column; gap: 20px; height: 100%; min-height: 0;}

/* HEADER AND MASTER CONTROLS */
.header-banner { display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 1px solid var(--edge); padding-bottom: 12px; }
.master-controls { display: flex; gap: 8px; align-items: stretch; height: 36px; }

.action-btn { padding: 0 16px; font-size: 0.75rem; font-weight: 600; border: 1px solid var(--edge); background: white; color: var(--ink); border-radius: 6px; cursor: pointer; transition: 0.2s; display: flex; align-items: center; justify-content: center; }
.action-btn:hover { background: var(--ghost); }
.action-btn.is-running { color: var(--error); border-color: #fca5a5; background: #fef2f2; }

.rate-control { display: flex; align-items: center; background: var(--ghost); padding: 0 4px 0 12px; border-radius: 6px; border: 1px solid var(--edge); margin-left: 8px; }
.rate-control label { font-size: 0.75rem; font-weight: 600; color: var(--accent); margin-right: 8px; }
.rate-control input { width: 70px; padding: 4px; font-size: 0.8rem; text-align: center; border: 1px solid var(--edge); border-radius: 4px; font-family: 'Fira Code', monospace; font-weight: 600; outline: none; background: white;}
.rate-control input:focus { border-color: var(--info); }
.ms-unit { font-size: 0.7rem; color: #94a3b8; font-weight: 700; margin-left: 6px; margin-right: 8px; }

.apply-btn { padding: 4px 10px; border-radius: 4px; font-size: 0.7rem; font-weight: 700; background: #e2e8f0; color: var(--ink); border: none; cursor: pointer; height: 26px; }
.apply-btn:hover:not(:disabled) { background: #cbd5e1; }

.active-rate-badge { display: flex; align-items: center; font-size: 0.75rem; font-weight: 700; color: #64748b; background: #f1f5f9; padding: 0 12px; border-radius: 6px; border: 1px solid var(--edge); margin-left: 8px; }
.active-rate-badge span { font-family: 'Fira Code', monospace; margin-left: 6px; }

/* STATUS PANEL */
/* Update status-panel to use flex layout */
.status-panel { 
  display: flex; 
  justify-content: space-between; 
  align-items: center; 
  background: #f8fafc; 
  border: 1px solid var(--edge); 
  border-left: 6px solid var(--success); 
  border-radius: 8px; 
  padding: 16px 20px; 
  transition: 0.3s; 
}

/* New CSS for the Right block */
.status-right { 
  display: flex; 
  gap: 32px; 
  align-items: center; 
  border-left: 1px solid var(--edge); 
  padding-left: 32px; 
}
.eff-stat { 
  display: flex; 
  flex-direction: column; 
  align-items: flex-end; 
}
.eff-label { 
  font-size: 0.65rem; 
  font-weight: 800; 
  color: #94a3b8; 
  text-transform: uppercase; 
}
.eff-val { 
  font-family: 'Fira Code', monospace; 
  font-size: 1.25rem; 
  font-weight: 700; 
  color: var(--info); 
}
.status-panel.is-faulty { background: #fef2f2; border-color: #fecaca; border-left-color: var(--error); }
.status-title { font-size: 0.75rem; font-weight: 800; color: #64748b; text-transform: uppercase; margin-bottom: 8px; }
.status-panel.is-faulty .status-title { color: #b91c1c; }
.status-body { display: flex; gap: 16px; align-items: center; flex-wrap: wrap; }

.state-badge { display: inline-flex; align-items: center; justify-content: center; background: white; color: var(--ink); padding: 6px 12px; border-radius: 6px; font-weight: 700; font-size: 0.85rem; border: 1px solid var(--edge); }
.state-badge.charging { background: #f0fdf4; color: var(--success); border-color: #bbf7d0; }

.normal-badge { display: inline-flex; align-items: center; font-weight: 700; font-size: 0.85rem; color: var(--success); }
.fault-list { display: flex; gap: 8px; flex-wrap: wrap; }
.alert-pill { background: var(--error); color: white; padding: 6px 12px; border-radius: 6px; font-size: 0.8rem; font-weight: 700; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }

/* CHARTS SECTION */
.charts-section { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; min-height: 250px; flex-shrink: 0; }
.chart-card { background: white; border: 1px solid var(--edge); border-radius: 8px; padding: 12px; display: flex; flex-direction: column; position: relative; }

.chart-toolbar { display: flex; flex-direction: column; gap: 8px; margin-bottom: 12px; }
.toolbar-row { display: flex; justify-content: space-between; align-items: center; gap: 8px; }

.window-select { width: 85px; }

.segmented-control { display: flex; background: var(--edge); border-radius: 6px; padding: 2px; flex-grow: 1; max-width: 120px; }
.segmented-control button { flex: 1; border: none; background: transparent; padding: 4px 0; font-size: 0.75rem; color: #64748b; border-radius: 4px; cursor: pointer; transition: 0.2s; font-weight: 700; }
.segmented-control button.active { background: white; color: var(--ink); box-shadow: 0 1px 3px rgba(0,0,0,0.1); }

.chart-actions { display: flex; gap: 6px; align-items: stretch; }
.chart-actions button { padding: 4px 10px; font-size: 0.7rem; font-weight: 700; border-radius: 6px; border: 1px solid var(--edge); background: var(--ghost); color: var(--ink); cursor: pointer; transition: 0.2s;}
.chart-actions button:hover:not(:disabled) { background: #e2e8f0; }

.fast-btn { border-color: #f59e0b !important; color: #d97706 !important; background: #fffbeb !important; }
.fast-btn:hover:not(:disabled) { background: #fef3c7 !important; border-color: #d97706 !important; }
.fast-btn.is-fast { background: #f59e0b !important; color: white !important; border-color: #d97706 !important; }
.fast-btn:disabled { opacity: 0.5; cursor: not-allowed; }

.trigger-row { background: var(--ghost); border: 1px solid var(--edge); border-radius: 6px; padding: 4px 12px; justify-content: space-between; align-items: center; }
.trigger-select-group { display: flex; align-items: center; gap: 8px; }
.trigger-row label { font-size: 0.7rem; font-weight: 800; color: var(--accent); text-transform: uppercase; }

/* Oscilloscope Stat Overlays */
.scope-stats { display: flex; gap: 16px; font-family: 'Fira Code', monospace; font-size: 0.75rem; font-weight: 700; background: white; padding: 2px 10px; border-radius: 4px; border: 1px solid var(--edge); }

.canvas-wrapper { position: relative; flex-grow: 1; width: 100%; min-height: 140px; cursor: crosshair; }

/* POWER GRID */
.power-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; overflow-y: auto; padding-right: 4px; padding-bottom: 10px; }
.power-card { background: var(--ghost); border: 1px solid var(--edge); border-radius: 8px; padding: 16px; }
.power-title { font-weight: 800; font-size: 0.8rem; margin-bottom: 12px; border-bottom: 1px solid var(--edge); padding-bottom: 6px; color: var(--ink); text-transform: uppercase; }

.live-vi { display: flex; justify-content: space-between; background: var(--paper); border: 1px solid var(--edge); padding: 8px 12px; border-radius: 6px; margin-bottom: 12px;}
.vi-item { display: flex; flex-direction: column; align-items: flex-start; }
.vi-item span { font-size: 0.6rem; color: #94a3b8; font-weight: 700; text-transform: uppercase; margin-bottom: 2px;}
.vi-item strong { font-family: 'Fira Code', monospace; font-size: 0.9rem; color: var(--info); font-weight: 600;}

.p-row { display: flex; justify-content: space-between; font-size: 0.75rem; margin-bottom: 6px; font-weight: 600; }
.p-row span:last-child { font-family: 'Fira Code', monospace; font-weight: 600; color: var(--ink); }

.trigger-dropdown :deep(.custom-select-btn) { 
  border: none; background: transparent; padding: 2px 8px; box-shadow: none; font-weight: 700;
}
.trigger-dropdown :deep(.custom-select-btn:hover:not(:disabled)) {
  background: rgba(148, 163, 184, 0.15); 
}
</style>