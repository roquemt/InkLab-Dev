<script setup>
import { ref, reactive, computed, onMounted, onUnmounted } from 'vue'
import { useSystemStore } from '../../stores/systemStore'
import { useSerial } from '../../composables/useSerial'

const store = useSystemStore()
const { sendCommand } = useSerial()

// State to hold the user's selected configuration for each pin
const activeConfig = reactive({})

// Setup the Left Header (MCU & Power)
const leftPins = [
  { id: 'BATT', type: 'power', label: 'BATT' },
  { id: 'UPS',  type: 'power', label: 'UPS' },
  { id: '3V3_L',type: 'power', label: '3V3' },
  { id: 'SDA',  type: 'fixed', label: 'SDA' }, 
  { id: 'SCL',  type: 'fixed', label: 'SCL' }, 
  { id: 'DIO',  type: 'fixed', label: 'DIO' }, 
  { id: 'CLK',  type: 'fixed', label: 'CLK' }, 
  { id: 'GND1', type: 'power', label: 'GND' },
  { id: 'PA5',  type: 'mcu', label: 'PA5', options: ['Reset_State', 'ADC1_IN5', 'DAC1_OUT2', 'SPI1_SCK', 'TIM2_CH1', 'USART3_TX', 'GPIO_Input', 'GPIO_Output', 'EXTI'] },
  { id: 'PA6',  type: 'mcu', label: 'PA6', options: ['Reset_State', 'ADC1_IN6', 'SPI1_MISO', 'TIM3_CH1', 'TIM16_CH1', 'I2C2_SDA', 'I2C3_SDA', 'GPIO_Input', 'GPIO_Output'] },
  { id: 'B11',  type: 'mcu', label: 'B11', options: ['Reset_State', 'ADC1_IN15', 'I2C2_SDA', 'TIM2_CH4', 'USART3_RX', 'LPUART1_TX', 'GPIO_Input', 'GPIO_Output'] },
  { id: 'B10',  type: 'mcu', label: 'B10', options: ['Reset_State', 'ADC1_IN11', 'I2C2_SCL', 'TIM2_CH3', 'USART3_TX', 'LPUART1_RX', 'GPIO_Input', 'GPIO_Output'] },
  { id: 'GND2', type: 'power', label: 'GND' },
  { id: 'PB2',  type: 'mcu', label: 'PB2', options: ['Reset_State', 'ADC1_IN10', 'USART3_TX', 'LPTIM1_OUT', 'RCC_MCO2', 'GPIO_Input', 'GPIO_Output'] },
  { id: 'PB1',  type: 'mcu', label: 'PB1', options: ['Reset_State', 'ADC1_IN9', 'TIM3_CH4', 'TIM14_CH1', 'USART5_RX', 'FDCAN2_TX', 'GPIO_Input', 'GPIO_Output'] },
  { id: 'PB0',  type: 'mcu', label: 'PB0', options: ['Reset_State', 'ADC1_IN8', 'TIM3_CH3', 'USART5_TX', 'FDCAN2_RX', 'GPIO_Input', 'GPIO_Output'] },
  { id: 'PA7',  type: 'mcu', label: 'PA7', options: ['Reset_State', 'ADC1_IN7', 'SPI1_MOSI', 'TIM3_CH2', 'TIM14_CH1', 'TIM17_CH1', 'I2C2_SCL', 'I2C3_SCL', 'GPIO_Input', 'GPIO_Output'] },
  { id: 'GND3', type: 'power', label: 'GND' },
]

// Setup the Right Header (FPGA / Digital)
const rightPins = [ { id: '3V3_R', type: 'power', label: '3V3' } ]
for(let i=0; i<=15; i++) {
  rightPins.push({
    id: `D${i.toString(16).toUpperCase().padStart(2, '0')}`,
    type: 'fpga',
    label: `D0${i.toString(16).toUpperCase()}`.slice(-2),
    options: ['High-Z', 'FPGA_Input', 'FPGA_Output']
  })
}
rightPins.push({ id: 'GND4', type: 'power', label: 'GND' })

// Initialize default states
const allInteractivePins = leftPins.concat(rightPins);
allInteractivePins.forEach(p => {
  if(p.options) activeConfig[p.id] = p.options[0]
})

// --- PROTOCOL LOGIC ---
const protocolGroups = {
  'USART3': ['USART3_TX', 'USART3_RX'],
  'USART5': ['USART5_TX', 'USART5_RX'],
  'LPUART1': ['LPUART1_TX', 'LPUART1_RX'],
  'SPI1': ['SPI1_SCK', 'SPI1_MISO', 'SPI1_MOSI'],
  'I2C2': ['I2C2_SDA', 'I2C2_SCL'],
  'I2C3': ['I2C3_SDA', 'I2C3_SCL'],
  'FDCAN2': ['FDCAN2_TX', 'FDCAN2_RX']
};

const getProtocolGroup = (funcName) => {
  for (const [group, funcs] of Object.entries(protocolGroups)) {
    if (funcs.includes(funcName)) return funcs;
  }
  return null;
};

const getResetStateFor = (pinId) => {
  const pin = allInteractivePins.find(p => p.id === pinId);
  return pin && pin.type === 'mcu' ? 'Reset_State' : 'High-Z';
};

// Reset Entire Columns
const resetAllMcu = () => leftPins.forEach(p => { if (p.type === 'mcu') activeConfig[p.id] = 'Reset_State' });
const resetAllFpga = () => rightPins.forEach(p => { if (p.type === 'fpga') activeConfig[p.id] = 'High-Z' });

// Check if an option should be grayed out because it lacks available partner pins
const isOptionDisabled = (pin, opt) => {
  const group = getProtocolGroup(opt);
  if (!group) return false;

  const neededFuncs = [];
  for (const reqFunc of group) {
    if (reqFunc === opt) continue;
    if (!Object.values(activeConfig).includes(reqFunc)) {
      neededFuncs.push(reqFunc);
    }
  }

  if (neededFuncs.length === 0) return false;

  const freePins = allInteractivePins.filter(p =>
    p.id !== pin.id && (activeConfig[p.id] === 'Reset_State' || activeConfig[p.id] === 'High-Z')
  );

  let availableCount = 0;
  let usedFreePins = new Set();

  for (const needed of neededFuncs) {
    const capablePin = freePins.find(p => !usedFreePins.has(p.id) && p.options?.includes(needed));
    if (capablePin) {
      usedFreePins.add(capablePin.id);
      availableCount++;
    }
  }

  return availableCount < neededFuncs.length;
};

// --- DROPDOWN & SELECTION ---
const menuState = reactive({ show: false, x: 0, y: 0, pin: null })

const openMenu = (e, pin) => {
  if (pin.type === 'power' || pin.type === 'fixed' || dragState.isDragging) return;

  const estimatedMenuHeight = 35 + (pin.options.length * 33);
  let targetY = e.clientY - 10;
  if (targetY + estimatedMenuHeight > window.innerHeight) targetY = window.innerHeight - estimatedMenuHeight - 20;

  menuState.x = e.clientX + 15
  menuState.y = targetY
  menuState.pin = pin
  menuState.show = true
}

const closeMenu = () => {
  menuState.show = false
  menuState.pin = null
}

const selectFunction = (opt) => {
  if (!menuState.pin || isOptionDisabled(menuState.pin, opt)) return;
  const pinId = menuState.pin.id;
  const oldFunc = activeConfig[pinId];

  // RULE 2: If changing away from a protocol, destroy the rest of the old protocol group
  if (oldFunc !== 'Reset_State' && oldFunc !== 'High-Z') {
    const oldGroup = getProtocolGroup(oldFunc);
    if (oldGroup) {
      oldGroup.forEach(f => {
         const pid = Object.keys(activeConfig).find(k => activeConfig[k] === f);
         if (pid) activeConfig[pid] = getResetStateFor(pid);
      });
    }
  }

  // RULE 1: If the new option is already on another pin, remove it from that pin
  if (opt !== 'Reset_State' && opt !== 'High-Z') {
     const existingPid = Object.keys(activeConfig).find(k => activeConfig[k] === opt);
     if (existingPid) {
        activeConfig[existingPid] = getResetStateFor(existingPid);
     }
  }

  activeConfig[pinId] = opt;
  closeMenu();

  // Auto-assign missing peers for the new protocol
  const group = getProtocolGroup(opt);
  if (group) {
    group.forEach(reqFunc => {
      if (reqFunc === opt || Object.values(activeConfig).includes(reqFunc)) return;
      
      const freePin = allInteractivePins.find(p =>
        p.id !== pinId &&
        (activeConfig[p.id] === 'Reset_State' || activeConfig[p.id] === 'High-Z') &&
        p.options?.includes(reqFunc)
      );

      if (freePin) activeConfig[freePin.id] = reqFunc;
    });
  }
}

// --- DRAG & DROP / KEYBOARD LOGIC ---
const isAltPressed = ref(false)
const hoveredPin = ref(null)
const dragState = reactive({ isDragging: false, sourcePin: null, func: null })

const handleKeydown = (e) => {
  if (e.key === 'Alt') {
    isAltPressed.value = true;
    e.preventDefault(); 
  }
  if (e.code === 'Space' && menuState.show && menuState.pin) {
    e.preventDefault(); 
    const resetVal = menuState.pin.type === 'mcu' ? 'Reset_State' : 'High-Z';
    selectFunction(resetVal); // Safely clears the pin and its group
  }
}

const handleKeyup = (e) => {
  if (e.key === 'Alt') isAltPressed.value = false;
}

onMounted(() => {
  window.addEventListener('keydown', handleKeydown)
  window.addEventListener('keyup', handleKeyup)
})
onUnmounted(() => {
  window.removeEventListener('keydown', handleKeydown)
  window.removeEventListener('keyup', handleKeyup)
})

const isFunctionActive = (pin) => {
  const f = activeConfig[pin.id];
  return f && f !== 'Reset_State' && f !== 'High-Z' && pin.type !== 'fixed' && pin.type !== 'power';
}

const isFunctionLocked = (pin) => {
  if (!isFunctionActive(pin)) return false;
  const func = activeConfig[pin.id];
  return !allInteractivePins.some(p => p.id !== pin.id && p.options?.includes(func));
}

const isDraggable = (pin) => {
  return isFunctionActive(pin) && !isFunctionLocked(pin);
}

const onDragStart = (e, pin) => {
  if (!isAltPressed.value || !isDraggable(pin)) {
    e.preventDefault();
    return;
  }
  closeMenu();
  dragState.isDragging = true;
  dragState.sourcePin = pin;
  dragState.func = activeConfig[pin.id];
  e.dataTransfer.effectAllowed = 'move';
}

const onDragEnd = () => {
  dragState.isDragging = false;
  dragState.sourcePin = null;
  dragState.func = null;
}

const onDrop = (e, targetPin) => {
  if (!isValidDropTarget(targetPin)) { onDragEnd(); return; }
  
  const funcToMove = dragState.func;
  const sourcePinId = dragState.sourcePin.id;
  const targetPinId = targetPin.id;
  const displacedFunc = activeConfig[targetPinId];
  
  if (sourcePinId === targetPinId) { onDragEnd(); return; }

  // 1. Handle displaced function
  if (displacedFunc && displacedFunc !== 'Reset_State' && displacedFunc !== 'High-Z') {
    const candidatePins = allInteractivePins.filter(p => 
      p.id !== targetPinId && 
      p.options?.includes(displacedFunc) && 
      (p.id === sourcePinId || activeConfig[p.id] === 'Reset_State' || activeConfig[p.id] === 'High-Z')
    );
    
    if (candidatePins.length > 0) {
      // Relocate safely
      const relocateTarget = candidatePins.find(p => p.id === sourcePinId) || candidatePins[0];
      activeConfig[relocateTarget.id] = displacedFunc;
      if (relocateTarget.id !== sourcePinId) {
        activeConfig[sourcePinId] = getResetStateFor(sourcePinId);
      }
    } else {
      // Nowhere to relocate: Destroy displaced function AND its protocol group
      const group = getProtocolGroup(displacedFunc);
      if (group) {
        group.forEach(f => {
           const pid = Object.keys(activeConfig).find(k => activeConfig[k] === f);
           if (pid) activeConfig[pid] = getResetStateFor(pid);
        });
      } else {
        activeConfig[targetPinId] = getResetStateFor(targetPinId);
      }
      activeConfig[sourcePinId] = getResetStateFor(sourcePinId);
    }
  } else {
    // Clean drop
    activeConfig[sourcePinId] = getResetStateFor(sourcePinId);
  }
  
  // 2. Assign the dragged function
  activeConfig[targetPinId] = funcToMove;
  
  onDragEnd();
}

const isValidDropTarget = (targetPin) => {
  // If actively dragging, check against the pinned drag state
  if (dragState.isDragging) {
    return targetPin.id !== dragState.sourcePin.id &&
           targetPin.options?.includes(dragState.func);
  }
  
  // If merely holding ALT and hovering, simulate the valid targets
  if (isAltPressed.value && hoveredPin.value && isDraggable(hoveredPin.value)) {
    const activeFunc = activeConfig[hoveredPin.value.id];
    return targetPin.id !== hoveredPin.value.id &&
           targetPin.options?.includes(activeFunc);
  }
  
  return false;
}

const getPinColor = (pin) => {
  if (pin.type === 'power') {
    if (pin.id.includes('GND')) return '#64748b' 
    return '#ef4444' 
  }
  if (pin.type === 'fixed') {
    if (pin.id === 'SDA' || pin.id === 'SCL') return '#d97706' 
    return '#94a3b8' 
  }
  
  const currentMode = activeConfig[pin.id]
  if (!currentMode || currentMode === 'Reset_State' || currentMode === 'High-Z') return '#cbd5e1' 
  if (currentMode.includes('Input') || currentMode.includes('RX') || currentMode.includes('MISO')) return '#10b981' 
  if (currentMode.includes('Output') || currentMode.includes('TX') || currentMode.includes('MOSI')) return '#3b82f6' 
  if (currentMode.includes('ADC') || currentMode.includes('DAC')) return '#8b5cf6' 
  if (currentMode.includes('TIM') || currentMode.includes('EXTI')) return '#f59e0b' 
  return '#d97706' 
}

const isConfigCoherent = computed(() => {
  // Check if any protocol is "half-configured" (e.g. TX is set, but RX is missing)
  for (const pinId in activeConfig) {
    const opt = activeConfig[pinId]
    if (opt !== 'Reset_State' && opt !== 'High-Z') {
      const group = getProtocolGroup(opt)
      if (group) {
        const hasAll = group.every(reqFunc => Object.values(activeConfig).includes(reqFunc))
        if (!hasAll) return false
      }
    }
  }
  return true
})

// Sends the configuration sequentially to the MCU
// Sends the configuration sequentially to the MCU
const applyConfiguration = async () => {
  if (!store.isConnected) {
    store.addLog("ERR: Connect hardware to apply pin routing.", "var(--error)")
    return
  }

  store.addLog(">>> Compiling Hardware Multiplexer map...", "var(--info)")
  
  // 1. Send MCU Pin Mappings
  for (const pin of leftPins) {
    if (pin.type === 'mcu') {
      await sendCommand(`PINMUX:SET:${pin.id}:${activeConfig[pin.id]}`)
      await new Promise(r => setTimeout(r, 20)) // Prevent USB buffer overflow
    }
  }

  // 2. Send FPGA Pin Mappings (Compile into a 16-bit mask)
  let fpgaDirMask = 0x0000;
  for (let i = 0; i < 16; i++) {
    const fpgaPinId = `D${i.toString(16).toUpperCase().padStart(2, '0')}`;
    if (activeConfig[fpgaPinId] === 'FPGA_Output') {
      fpgaDirMask |= (1 << i);
    }
  }
  await sendCommand(`SPI:GPIO_DIR:${fpgaDirMask.toString(16)}`)
  
  // 3. Finalize
  await sendCommand(`PINMUX:APPLY`)
  
  // ---> ADD THIS TO POP A SUCCESS TOAST IN THE CORNER <---
  store.addNotification("Hardware Routing Matrix Applied!", "success")
}
</script>

<template>
  <div class="pinout-page" :class="{'alt-active': isAltPressed}">
    <div class="header-banner">
      <span class="section-label" style="border: none; margin: 0; padding: 0;">Hardware Pin Multiplexer</span>
      
      <div class="header-controls">
        <div class="reset-group">
          <button class="reset-btn-top" @click="resetAllMcu" title="Reset All MCU Pins">↺ MCU</button>
          <button class="reset-btn-top" @click="resetAllFpga" title="Reset All FPGA Pins">↺ FPGA</button>
        </div>
        
        <div class="legend">
          <span class="leg-item"><div class="dot" style="background:#cbd5e1"></div>Reset/Hi-Z</span>
          <span class="leg-item"><div class="dot" style="background:#10b981"></div>Input/RX</span>
          <span class="leg-item"><div class="dot" style="background:#3b82f6"></div>Output/TX</span>
          <span class="leg-item"><div class="dot" style="background:#d97706"></div>Alternate</span>
          <span class="leg-item"><div class="dot" style="background:#8b5cf6"></div>Analog</span>
        </div>
      </div>
    </div>

    <button 
        class="btn-primary" 
        :disabled="!isConfigCoherent || !store.isConnected"
        @click="applyConfiguration"
        style="padding: 8px 24px; font-size: 0.8rem;"
    >
        Apply Routing to Hardware
    </button>

    <div class="board-wrapper">
      <div class="pcb-board">
        <div class="deco-rect-gray"></div>
        <div class="deco-rect-brown-1"></div>
        <div class="deco-rect-brown-2"></div>
        <div class="deco-rect-black"></div>
        <div class="deco-bar"></div>
        <div class="deco-triangle"></div>
        <div class="deco-yellow"></div>
        
        <div class="pcb-silk logo">InkLab V1.0</div>
        
        <div class="usb-port"></div>

        <div class="battery-holder">
          <div class="battery-cell">
            <div class="bat-plus">+</div>
          </div>
        </div>
        
        <div class="epaper-display">
        <!-- Outer Bezel/Background -->
        <div class="epaper-outer">
            <!-- Inner Screen Rectangle -->
            <div class="epaper-inner"></div>
        </div>
        </div>
        
        <div class="joystick">
          <div class="joy-stick"></div>
        </div>
        <div class="rgb-led" title="User RGB LED"></div>

        <div class="header-col left-col">
          <!-- MCU Header (Reset buttons moved) -->
          <div class="col-header-box">
            <div class="col-title">MCU PINS</div>
          </div>
          
          <div 
            v-for="pin in leftPins" 
            :key="pin.id" 
            class="pin-row left-align"
            @click="openMenu($event, pin)"
            @mouseenter="hoveredPin = pin"
            @mouseleave="hoveredPin = null"
          >
            <div class="pin-func-outside left-func" v-if="activeConfig[pin.id] && activeConfig[pin.id] !== 'Reset_State' && activeConfig[pin.id] !== 'High-Z'">
              {{ activeConfig[pin.id] }}
            </div>

            <div 
              class="pin-pad" 
              :class="{
                'valid-drop-target': isValidDropTarget(pin),
                'draggable-pad': isAltPressed && isDraggable(pin),
                'locked-pad': isAltPressed && isFunctionLocked(pin)
              }"
              :style="{ borderColor: getPinColor(pin) }"
              :draggable="isAltPressed && isDraggable(pin)"
              @dragstart="onDragStart($event, pin)"
              @dragover.prevent
              @dragenter.prevent
              @drop="onDrop($event, pin)"
              @dragend="onDragEnd"
            >
              <div class="pin-hole"></div>
            </div>

            <div class="pin-label-box">
              <span class="p-name">{{ pin.label }}</span>
            </div>
          </div>
        </div>

        <div class="header-col right-col">
          <!-- FPGA Header (Reset buttons moved) -->
          <div class="col-header-box right-align-header">
            <div class="col-title">FPGA PINS</div>
          </div>
          
          <div 
            v-for="pin in rightPins" 
            :key="pin.id" 
            class="pin-row right-align"
            @click="openMenu($event, pin)"
            @mouseenter="hoveredPin = pin"
            @mouseleave="hoveredPin = null"
          >
            <div class="pin-label-box">
              <span class="p-name">{{ pin.label }}</span>
            </div>

            <div 
              class="pin-pad" 
              :class="{
                'valid-drop-target': isValidDropTarget(pin),
                'draggable-pad': isAltPressed && isDraggable(pin),
                'locked-pad': isAltPressed && isFunctionLocked(pin)
              }"
              :style="{ borderColor: getPinColor(pin) }"
              :draggable="isAltPressed && isDraggable(pin)"
              @dragstart="onDragStart($event, pin)"
              @dragover.prevent
              @dragenter.prevent
              @drop="onDrop($event, pin)"
              @dragend="onDragEnd"
            >
              <div class="pin-hole"></div>
            </div>

            <div class="pin-func-outside right-func" v-if="activeConfig[pin.id] && activeConfig[pin.id] !== 'High-Z' && activeConfig[pin.id] !== 'Reset_State'">
              {{ activeConfig[pin.id] }}
            </div>
          </div>
        </div>

      </div>
    </div>

    <Teleport to="body">
      <div v-if="menuState.show" class="menu-overlay" @click="closeMenu" @contextmenu.prevent="closeMenu"></div>
      
      <div 
        v-if="menuState.show" 
        class="cube-dropdown" 
        :style="{ top: menuState.y + 'px', left: menuState.x + 'px' }"
      >
        <div class="dropdown-header">{{ menuState.pin.id }} Configuration</div>
        <div class="dropdown-body">
          <div 
            v-for="opt in menuState.pin.options" 
            :key="opt"
            class="dropdown-item"
            :class="{ 
              active: activeConfig[menuState.pin.id] === opt,
              disabled: isOptionDisabled(menuState.pin, opt)
            }"
            @click="selectFunction(opt)"
          >
            {{ opt }}
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.pinout-page {
  display: flex;
  flex-direction: column;
  height: 100%;
  gap: 20px;
}

.header-banner {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  border-bottom: 1px solid var(--edge);
  padding-bottom: 12px;
}

.header-controls {
  display: flex;
  align-items: center;
  gap: 24px;
}

.reset-group {
  display: flex;
  gap: 8px;
  white-space: nowrap; 
}

.reset-btn-top {
  background: white;
  border: 1px solid var(--edge);
  color: var(--ink);
  border-radius: 6px;
  padding: 4px 20px;
  font-size: 0.75rem;
  font-weight: 700;
  cursor: pointer;
  transition: 0.2s;
  display: flex;
  align-items: center;
  gap: 4px;
}

.reset-btn-top:hover {
  background: #fef2f2;
  border-color: #fca5a5;
  color: var(--error);
}

.legend {
  display: flex;
  gap: 16px;
  font-size: 0.75rem;
  font-weight: 700;
  color: #64748b;
  text-transform: uppercase;
}
.leg-item { display: flex; align-items: center; gap: 6px; }
.dot { width: 10px; height: 10px; border-radius: 50%; }

/* --- PCB BOARD STYLING --- */
.board-wrapper {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  min-height: 700px; /* Ensure enough height for the scaled board */
  background: transparent; /* Wrapper should be invisible */
}

.pcb-board {
  position: relative;
  width: 820px;
  height: 600px;
  
  /* RE-ADD THESE: They were likely lost because of the transform or container issues */
  background-color: #254a32 !important; 
  border-radius: 20px; 
  border: 2px solid #1a3523;
  
  /* Keep your existing patterns */
  background-image: radial-gradient(#305c3f 1px, transparent 1px);
  background-size: 20px 20px;
  
  /* Scaling logic */
  transform-origin: center center;
  transform: scale(min(1, calc(100vw / 950px)));
  box-shadow: 0 15px 35px rgba(0,0,0,0.2);
}

/* PCB Graphics */
.pcb-silk {
  position: absolute;
  color: white;
  font-family: 'Inter', sans-serif;
  font-weight: 800;
  opacity: 0.9;
}
.logo {
  top: 160px;
  left: 90px;
  font-size: 2rem;
  background: white;
  color: #254a32;
  padding: 4px 12px;
  border-radius: 20px;
}

/* Height Extended USB-C Receptacle */
.usb-port {
  position: absolute;
  top: -12px; 
  left: 90px;
  width: 110px;
  height: 90px; 
  background: #cbd5e1; 
  border: 2px solid #64748b;
  border-radius: 6px;
  box-shadow: 0 5px 15px rgba(0,0,0,0.4);
  z-index: 2;
}

/* Battery Holder horizontally aligned */
.battery-holder {
  position: absolute;
  top: 5px; 
  left: 220px; 
  width: 500px;
  height: 140px;
  background: #0f172a;
  border-radius: 8px;
  box-shadow: inset 0 5px 15px rgba(0,0,0,0.8);
  display: flex;
  align-items: center;
  justify-content: center;
}
.battery-cell {
  width: 460px;
  height: 100px;
  background: linear-gradient(to bottom, #1d4ed8, #3b82f6, #1d4ed8);
  border-radius: 6px;
  position: relative;
  box-shadow: 0 5px 10px rgba(0,0,0,0.5);
}
.bat-plus {
  position: absolute; right: 400px; top: 35px; color: white; font-weight: 800; font-size: 1.5rem; opacity: 0.5;
}

/* Update this container to move it down and shrink it slightly */
.epaper-display {
  position: absolute;
  bottom: 15px; /* Keep it pinned to the bottom */
  right: 60px;
  width: 490px;  /* Slightly smaller width */
  height: 360px; /* Slightly smaller height */
  background: transparent; /* Changed from green to transparent */
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none; /* Allows mouse interactions to pass through if needed */
}

.epaper-outer {
  width: 480px;
  height: 380px;
  background: #f8fafc; /* The outer light grey area */
  border: 4px solid #cbd5e1;
  display: flex;
  align-items: center;
  /* This creates the wider left side by pushing the inner box to the right */
  justify-content: flex-end; 
  padding-right: 20px; /* Adjusts how far it sits from the right edge */
}

.epaper-inner {
  width: 380px; /* Width of the inner black-bordered box */
  height: 320px;
  background: #e5e7eb;
  border: 4px solid #0f172a; /* The thick black border */
  /* No centering here! The parent's flex alignment handles the offset */
}


.e-ink-label {
  color: #94a3b8;
  font-family: sans-serif;
  font-weight: 900;
  font-size: 1.5rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  opacity: 0.7;
}

.deco-rect-gray {
  position: absolute;
  top: 245px;
  left: 95px;
  width: 50px;
  height: 130px;
  background: #cbd5e1;
  border-radius: 6px;
}

/* 2. Two brown transparent rectangles */
.deco-rect-brown-1 {
  position: absolute;
  top: 250px;
  left: 195px;
  width: 80px;
  height: 300px;
  background: rgba(217, 119, 6, 0.3); /* Brown with 30% opacity */
}

.deco-rect-brown-2 {
  position: absolute;
  top: 250px;
  left: 145px;
  width: 50px;
  height: 120px;
  background: rgba(217, 119, 6, 0.3);
}

.deco-bar {
  position: absolute;
  top: 280px;
  left: 295px;
  width: 10px;
  height: 150px;
  background: #cbd5e1;
  z-index: 10; 
}



/* Rotated Joystick */
.joystick {
  position: absolute;
  bottom: 30px;
  left: 85px; 
  width: 80px;
  height: 80px;
  background: #cbd5e1; 
  border-radius: 12px;
  border: 1px solid #94a3b8;
  box-shadow: 0 8px 15px rgba(0,0,0,0.4);
  display: flex;
  align-items: center;
  justify-content: center;
  transform: rotate(45deg); 
}
.joy-stick {
  width: 40px;
  height: 40px;
  background: #0f172a; 
  border-radius: 50%;
  box-shadow: inset -5px -5px 10px rgba(255,255,255,0.1), 0 5px 10px rgba(0,0,0,0.5);
}

.rgb-led {
  position: absolute;
  bottom: 20px; 
  left: 180px; 
  width: 20px;
  height: 20px;
  background: #ffffff;
  border: 2px solid #cbd5e1;
  border-radius: 3px;
  box-shadow: 0 0 12px rgba(59, 130, 246, 0.8), inset 0 0 4px #3b82f6;
}

/* --- PINOUT HEADERS & ROWS --- */
.header-col {
  position: absolute;
  top: 15px;
  bottom: 15px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
.left-col { left: 8px; } 
.right-col { right: 8px; } 

.col-header-box {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 5px;
  padding: 0 4px;
}
.right-align-header {
  justify-content: flex-end;
}

.col-title {
  color: rgba(255, 255, 255, 0.6);
  font-size: 0.65rem;
  font-weight: 800;
  letter-spacing: 0.1em;
  margin: 0;
}

.pin-row {
  position: relative;
  display: flex;
  align-items: center;
  gap: 10px;
  height: 24px;
  user-select: none; 
}
.left-align { flex-direction: row; }
.right-align { flex-direction: row; justify-content: flex-end;}

.pin-func-outside {
  position: absolute;
  background: rgba(15, 23, 42, 0.9);
  color: #38bdf8;
  font-family: 'Fira Code', monospace;
  font-size: 0.65rem;
  font-weight: 600;
  padding: 4px 8px;
  border-radius: 4px;
  border: 1px solid #3b82f6;
  white-space: nowrap;
  box-shadow: 0 2px 6px rgba(0,0,0,0.3);
  pointer-events: none;
  z-index: 10;
}
.left-func { right: 100%; margin-right: 12px; } 
.right-func { left: 100%; margin-left: 12px; } 

.pin-pad {
  position: relative;
  width: 14px; 
  height: 14px;
  background: #eab308; 
  border-radius: 50%;
  border: 4px solid; 
  box-sizing: content-box; 
  box-shadow: 0 2px 4px rgba(0,0,0,0.4);
  cursor: pointer;
  transition: transform 0.1s, box-shadow 0.2s, opacity 0.2s;
  flex-shrink: 0;
}
.pin-pad:hover { transform: scale(1.15); }

/* Drag and Drop styles */
.draggable-pad {
  cursor: grab;
}
.draggable-pad:active {
  cursor: grabbing;
}
.locked-pad {
  cursor: not-allowed;
  opacity: 0.4;
  box-shadow: 0 0 0 2px rgba(239, 68, 68, 0.9);
}
.locked-pad:hover {
  transform: scale(1);
}

.valid-drop-target {
  box-shadow: 0 0 0 4px rgba(56, 189, 248, 0.5), 0 0 15px rgba(56, 189, 248, 0.9);
  animation: drop-pulse 1.5s infinite;
  z-index: 5;
}
@keyframes drop-pulse {
  0% { transform: scale(1); }
  50% { transform: scale(1.3); }
  100% { transform: scale(1); }
}

.pin-hole {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  width: 6px;
  height: 6px;
  background: #0f172a; 
  border-radius: 50%;
}

.pin-label-box {
  display: flex;
  align-items: center;
  position: relative; 
  width: 45px; 
}
.right-align .pin-label-box { justify-content: flex-end; }

.p-name {
  color: white;
  font-family: 'Fira Code', monospace;
  font-size: 0.75rem;
  font-weight: 700;
  text-shadow: 1px 1px 0 #0f172a;
}

/* --- CUBEMX STYLE DROPDOWN --- */
.menu-overlay {
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  z-index: 9998;
}

.cube-dropdown {
  position: fixed;
  background: var(--paper);
  border: 1px solid var(--edge);
  border-radius: 6px;
  box-shadow: 0 10px 25px rgba(0,0,0,0.2);
  min-width: 160px;
  z-index: 9999;
  display: flex;
  flex-direction: column;
  animation: pop 0.1s ease-out;
}
@keyframes pop {
  from { opacity: 0; transform: scale(0.95); }
  to { opacity: 1; transform: scale(1); }
}

.dropdown-header {
  background: var(--ghost);
  padding: 8px 12px;
  font-size: 0.7rem;
  font-weight: 800;
  color: var(--accent);
  text-transform: uppercase;
  border-bottom: 1px solid var(--edge);
}

.dropdown-body {
  max-height: 250px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  scrollbar-width: thin;
}

.dropdown-item {
  padding: 8px 12px;
  font-size: 0.8rem;
  font-weight: 600;
  font-family: 'Fira Code', monospace;
  color: var(--ink);
  cursor: pointer;
  transition: background 0.1s;
}
.dropdown-item:hover:not(.disabled) {
  background: #f1f5f9;
}
.dropdown-item.active {
  background: #eff6ff;
  color: var(--info);
  border-left: 3px solid var(--info);
}

.dropdown-item.disabled {
  color: #94a3b8;
  cursor: not-allowed;
  opacity: 0.6;
}
</style>