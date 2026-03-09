#include "pinmux.h"
#include "app_fatfs.h"
#include "cmsis_os.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

extern void USB_Printf(const char *format, ...);

// Internal representation of a Pin Mapping
typedef struct {
    const char* pinName;
    GPIO_TypeDef* port;
    uint16_t pin;
    uint32_t adcChannel; // 0xFF if not ADC capable
} PinMap_t;

typedef struct {
    osTimerId_t timer;
    const PinMap_t* pin;
} ToggleTimer_t;

// We need exactly one timer slot for every MCU pin
#define NUM_MCU_PINS 8
static ToggleTimer_t toggle_timers[NUM_MCU_PINS] = {0};

// The static definition of our physical MCU pins
static const PinMap_t mcuPins[NUM_MCU_PINS] = {
    {"PA5", GPIOA, GPIO_PIN_5, ADC_CHANNEL_5},
    {"PA6", GPIOA, GPIO_PIN_6, ADC_CHANNEL_6},
    {"PA7", GPIOA, GPIO_PIN_7, ADC_CHANNEL_7},
    {"PB0", GPIOB, GPIO_PIN_0, ADC_CHANNEL_8},
    {"PB1", GPIOB, GPIO_PIN_1, ADC_CHANNEL_9},
    {"PB2", GPIOB, GPIO_PIN_2, ADC_CHANNEL_10},
    {"B10", GPIOB, GPIO_PIN_10, ADC_CHANNEL_11},
    {"B11", GPIOB, GPIO_PIN_11, ADC_CHANNEL_15}
};

typedef enum {
    PINMUX_MODE_RESET,
    PINMUX_MODE_INPUT,
    PINMUX_MODE_OUTPUT,
    PINMUX_MODE_AF
} PinMode_t;

static PinMode_t active_pin_modes[NUM_MCU_PINS] = {0};

static int GetPinIndex(const char* pinName) {
    for (int i = 0; i < NUM_MCU_PINS; i++) {
        if (strcmp(mcuPins[i].pinName, pinName) == 0) return i;
    }
    return -1;
}

static const PinMap_t* GetPinInfo(const char* pinName) {
    int idx = GetPinIndex(pinName);
    if (idx >= 0) return &mcuPins[idx];
    return NULL;
}

// ==========================================
// PIN ROUTING CORE
// ==========================================

HAL_StatusTypeDef Pinmux_SetPin(const char* pinName, const char* funcName) {
    int pinIdx = GetPinIndex(pinName);
    if (pinIdx < 0) return HAL_ERROR;

    const PinMap_t* pInfo = &mcuPins[pinIdx];
    GPIO_InitTypeDef GPIO_InitStruct = {0};
    GPIO_InitStruct.Pin = pInfo->pin;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;

    // 1. Reset State
    if (strcmp(funcName, "Reset_State") == 0) {
        GPIO_InitStruct.Mode = GPIO_MODE_ANALOG;
        GPIO_InitStruct.Pull = GPIO_NOPULL;
        HAL_GPIO_Init(pInfo->port, &GPIO_InitStruct);
        active_pin_modes[pinIdx] = PINMUX_MODE_RESET;
        return HAL_OK;
    }

    // 2. Standard GPIO
    if (strcmp(funcName, "GPIO_Input") == 0) {
        GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
        GPIO_InitStruct.Pull = GPIO_PULLDOWN;
        HAL_GPIO_Init(pInfo->port, &GPIO_InitStruct);
        active_pin_modes[pinIdx] = PINMUX_MODE_INPUT;
        return HAL_OK;
    }

    if (strcmp(funcName, "GPIO_Output") == 0) {
        GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
        GPIO_InitStruct.Pull = GPIO_NOPULL;
        HAL_GPIO_Init(pInfo->port, &GPIO_InitStruct);
        active_pin_modes[pinIdx] = PINMUX_MODE_OUTPUT;
        return HAL_OK;
    }

    // 3. Alternate Functions (EXPANDED TO MATCH VUE UI)
    active_pin_modes[pinIdx] = PINMUX_MODE_AF;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;

    if (strstr(funcName, "USART3")) {
        __HAL_RCC_USART3_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF4_USART3;
    }
    else if (strstr(funcName, "USART5")) {
        __HAL_RCC_USART5_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF8_USART5;
    }
    else if (strstr(funcName, "SPI1")) {
        __HAL_RCC_SPI1_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF0_SPI1;
    }
    else if (strstr(funcName, "I2C2")) {
        __HAL_RCC_I2C2_CLK_ENABLE();
        GPIO_InitStruct.Mode = GPIO_MODE_AF_OD;
        GPIO_InitStruct.Pull = GPIO_PULLUP;
        GPIO_InitStruct.Alternate = GPIO_AF6_I2C2;
    }
    else if (strstr(funcName, "I2C3")) {
        __HAL_RCC_I2C3_CLK_ENABLE();
        GPIO_InitStruct.Mode = GPIO_MODE_AF_OD;
        GPIO_InitStruct.Pull = GPIO_PULLUP;
        GPIO_InitStruct.Alternate = GPIO_AF6_I2C3;
    }
    else if (strstr(funcName, "FDCAN2")) {
        __HAL_RCC_FDCAN_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF3_FDCAN2;
    }
    else if (strstr(funcName, "TIM2")) {
        __HAL_RCC_TIM2_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF2_TIM2;
    }
    else if (strstr(funcName, "TIM3")) {
        __HAL_RCC_TIM3_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF1_TIM3;
    }
    else if (strstr(funcName, "TIM14")) {
        __HAL_RCC_TIM14_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF4_TIM14;
    }
    else if (strstr(funcName, "TIM16")) {
        __HAL_RCC_TIM16_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF5_TIM16;
    }
    else if (strstr(funcName, "TIM17")) {
        __HAL_RCC_TIM17_CLK_ENABLE();
        GPIO_InitStruct.Alternate = GPIO_AF5_TIM17;
    }
    else if (strstr(funcName, "ADC1") || strstr(funcName, "DAC1")) {
        GPIO_InitStruct.Mode = GPIO_MODE_ANALOG;
    }
    else {
        USB_Printf("ERR: Unsupported function %s\n", funcName);
        return HAL_ERROR;
    }

    HAL_GPIO_Init(pInfo->port, &GPIO_InitStruct);
    return HAL_OK;
}

// ==========================================
// TELEMETRY GENERATION
// ==========================================

void Pinmux_GetInputTelemetryJson(char* buffer, size_t max_len) {
    int offset = snprintf(buffer, max_len, "{\"type\":\"mcu_gpio\"");
    bool has_inputs = false;

    for (int i = 0; i < NUM_MCU_PINS; i++) {
        if (active_pin_modes[i] == PINMUX_MODE_INPUT) {
            uint8_t state = (HAL_GPIO_ReadPin(mcuPins[i].port, mcuPins[i].pin) == GPIO_PIN_SET) ? 1 : 0;
            offset += snprintf(buffer + offset, max_len - offset, ",\"%s\":%d", mcuPins[i].pinName, state);
            has_inputs = true;
        }
    }

    if (!has_inputs) {
        buffer[0] = '\0';
    } else {
        snprintf(buffer + offset, max_len - offset, "}");
    }
}

// ==========================================
// AGNOSTIC EXTERNAL COMMANDS (EXT:...)
// ==========================================

void EXT_UART_Tx(uint8_t uart_num, const char* payload) {
    if (uart_num == 3) {
        extern UART_HandleTypeDef huart3;
        HAL_UART_Transmit(&huart3, (uint8_t*)payload, strlen(payload), 100);
        USB_Printf("LOG: UART3 TX -> '%s'\n", payload);
    } else {
        USB_Printf("ERR: UART%d not configured.\n", uart_num);
    }
}

void EXT_I2C_Write(uint8_t i2c_num, uint8_t addr, uint8_t data) {
    if (i2c_num == 2) {
        extern I2C_HandleTypeDef hi2c2;
        if (HAL_I2C_Master_Transmit(&hi2c2, addr << 1, &data, 1, 100) == HAL_OK) {
            USB_Printf("LOG: I2C2 Write 0x%02X to Dev 0x%02X Success\n", data, addr);
        } else {
            USB_Printf("ERR: I2C2 NACK or Bus Error\n");
        }
    }
}

void EXT_GPIO_Write(const char* pinName, uint8_t state) {
    int pinIdx = GetPinIndex(pinName);
    if (pinIdx < 0) { USB_Printf("ERR: Unknown Pin %s\n", pinName); return; }

    const PinMap_t* pInfo = &mcuPins[pinIdx];
    ToggleTimer_t* slot = &toggle_timers[pinIdx];

    // If a toggle timer is running, stop it
    if (slot->timer) {
        osTimerStop(slot->timer);
        osTimerDelete(slot->timer);
        slot->timer = NULL;
    }

    // Force pin to output if it isn't already!
    if (active_pin_modes[pinIdx] != PINMUX_MODE_OUTPUT) {
        GPIO_InitTypeDef GPIO_InitStruct = {0};
        GPIO_InitStruct.Pin = pInfo->pin;
        GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
        GPIO_InitStruct.Pull = GPIO_NOPULL;
        GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
        HAL_GPIO_Init(pInfo->port, &GPIO_InitStruct);
        active_pin_modes[pinIdx] = PINMUX_MODE_OUTPUT;
    }

    HAL_GPIO_WritePin(pInfo->port, pInfo->pin, state ? GPIO_PIN_SET : GPIO_PIN_RESET);
    USB_Printf("LOG: %s set to %s\n", pinName, state ? "HIGH" : "LOW");
}

void EXT_ADC_Read(const char* pinName) {
    extern ADC_HandleTypeDef hadc1;
    const PinMap_t* pInfo = GetPinInfo(pinName);

    if (!pInfo || pInfo->adcChannel == 0xFF) {
        USB_Printf("ERR: %s is not ADC capable.\n", pinName);
        return;
    }

    ADC_ChannelConfTypeDef sConfig = {0};
    sConfig.Channel = pInfo->adcChannel;
    sConfig.Rank = ADC_REGULAR_RANK_1;
    sConfig.SamplingTime = ADC_SAMPLINGTIME_COMMON_1;

    if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) == HAL_OK) {
        HAL_ADC_Start(&hadc1);
        if (HAL_ADC_PollForConversion(&hadc1, 10) == HAL_OK) {
            uint32_t raw = HAL_ADC_GetValue(&hadc1);
            float voltage = ((float)raw / 4095.0f) * 3.3f;
            USB_Printf("{\"type\":\"adc_res\",\"v\":%.3f}\n", voltage);
        }
        HAL_ADC_Stop(&hadc1);
    }
}

// Timer callback function
static void GPIO_Toggle_Callback(void *argument) {
    const PinMap_t* pInfo = (const PinMap_t*)argument;
    HAL_GPIO_TogglePin(pInfo->port, pInfo->pin);
}

void EXT_GPIO_Toggle(const char* pinName, uint32_t freq_hz) {
    int pinIdx = GetPinIndex(pinName);
    if (pinIdx < 0) { USB_Printf("ERR: Unknown pin %s\n", pinName); return; }

    const PinMap_t* pInfo = &mcuPins[pinIdx];
    ToggleTimer_t* slot = &toggle_timers[pinIdx];

    // Stop existing timer if running
    if (slot->timer) {
        osTimerStop(slot->timer);
        osTimerDelete(slot->timer);
        slot->timer = NULL;
    }

    if (freq_hz == 0) return; // Allow freq=0 to safely stop the timer

    // Force pin to output if it isn't already!
    if (active_pin_modes[pinIdx] != PINMUX_MODE_OUTPUT) {
        GPIO_InitTypeDef GPIO_InitStruct = {0};
        GPIO_InitStruct.Pin = pInfo->pin;
        GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
        GPIO_InitStruct.Pull = GPIO_NOPULL;
        GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_HIGH;
        HAL_GPIO_Init(pInfo->port, &GPIO_InitStruct);
        active_pin_modes[pinIdx] = PINMUX_MODE_OUTPUT;
    }

    uint32_t interval = 1000 / (2 * freq_hz);
    if (interval < 5) interval = 5; // Safety cap to prevent RTOS starvation

    slot->pin = pInfo;
    slot->timer = osTimerNew(GPIO_Toggle_Callback, osTimerPeriodic, (void*)pInfo, NULL);
    osTimerStart(slot->timer, interval);

    USB_Printf("LOG: %s toggling at %lu Hz\n", pinName, freq_hz);
}
