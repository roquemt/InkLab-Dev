################################################################################
# Automatically-generated file. Do not edit!
# Toolchain: GNU Tools for STM32 (13.3.rel1)
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../Core/Src/app_freertos.c \
../Core/Src/battery_defs.c \
../Core/Src/battery_soc.c \
../Core/Src/bq25798.c \
../Core/Src/diagnostics.c \
../Core/Src/error_manager.c \
../Core/Src/fpga.c \
../Core/Src/frontend_api.c \
../Core/Src/joystick.c \
../Core/Src/led_manager.c \
../Core/Src/main.c \
../Core/Src/ota.c \
../Core/Src/pinmux.c \
../Core/Src/powerMonitor.c \
../Core/Src/stm32g0xx_hal_msp.c \
../Core/Src/stm32g0xx_hal_timebase_tim.c \
../Core/Src/stm32g0xx_it.c \
../Core/Src/sys_power.c \
../Core/Src/syscalls.c \
../Core/Src/sysmem.c \
../Core/Src/system_stm32g0xx.c \
../Core/Src/user_diskio_spi.c 

OBJS += \
./Core/Src/app_freertos.o \
./Core/Src/battery_defs.o \
./Core/Src/battery_soc.o \
./Core/Src/bq25798.o \
./Core/Src/diagnostics.o \
./Core/Src/error_manager.o \
./Core/Src/fpga.o \
./Core/Src/frontend_api.o \
./Core/Src/joystick.o \
./Core/Src/led_manager.o \
./Core/Src/main.o \
./Core/Src/ota.o \
./Core/Src/pinmux.o \
./Core/Src/powerMonitor.o \
./Core/Src/stm32g0xx_hal_msp.o \
./Core/Src/stm32g0xx_hal_timebase_tim.o \
./Core/Src/stm32g0xx_it.o \
./Core/Src/sys_power.o \
./Core/Src/syscalls.o \
./Core/Src/sysmem.o \
./Core/Src/system_stm32g0xx.o \
./Core/Src/user_diskio_spi.o 

C_DEPS += \
./Core/Src/app_freertos.d \
./Core/Src/battery_defs.d \
./Core/Src/battery_soc.d \
./Core/Src/bq25798.d \
./Core/Src/diagnostics.d \
./Core/Src/error_manager.d \
./Core/Src/fpga.d \
./Core/Src/frontend_api.d \
./Core/Src/joystick.d \
./Core/Src/led_manager.d \
./Core/Src/main.d \
./Core/Src/ota.d \
./Core/Src/pinmux.d \
./Core/Src/powerMonitor.d \
./Core/Src/stm32g0xx_hal_msp.d \
./Core/Src/stm32g0xx_hal_timebase_tim.d \
./Core/Src/stm32g0xx_it.d \
./Core/Src/sys_power.d \
./Core/Src/syscalls.d \
./Core/Src/sysmem.d \
./Core/Src/system_stm32g0xx.d \
./Core/Src/user_diskio_spi.d 


# Each subdirectory must supply rules for building sources it contributes
Core/Src/%.o Core/Src/%.su Core/Src/%.cyclo: ../Core/Src/%.c Core/Src/subdir.mk
	arm-none-eabi-gcc "$<" -mcpu=cortex-m0plus -std=gnu11 '-DCMSIS_device_header=<stm32g0xx.h>' -DUSE_HAL_DRIVER -DSTM32G0B1xx -c -I../Core/Inc -I../FATFS/Target -I../FATFS/App -I../USB_Device/App -I../USB_Device/Target -I../Drivers/STM32G0xx_HAL_Driver/Inc -I../Drivers/STM32G0xx_HAL_Driver/Inc/Legacy -I../Middlewares/Third_Party/FreeRTOS/Source/include -I../Middlewares/Third_Party/FreeRTOS/Source/CMSIS_RTOS_V2 -I../Middlewares/Third_Party/FreeRTOS/Source/portable/GCC/ARM_CM0 -I../Middlewares/Third_Party/FatFs/src -I../Middlewares/ST/STM32_USB_Device_Library/Core/Inc -I../Middlewares/ST/STM32_USB_Device_Library/Class/CDC/Inc -I../Drivers/CMSIS/Device/ST/STM32G0xx/Include -I../Drivers/CMSIS/Include -Os -ffunction-sections -fdata-sections -Wall -fstack-usage -fcyclomatic-complexity -MMD -MP -MF"$(@:%.o=%.d)" -MT"$@" --specs=nano.specs -mfloat-abi=soft -mthumb -o "$@"

clean: clean-Core-2f-Src

clean-Core-2f-Src:
	-$(RM) ./Core/Src/app_freertos.cyclo ./Core/Src/app_freertos.d ./Core/Src/app_freertos.o ./Core/Src/app_freertos.su ./Core/Src/battery_defs.cyclo ./Core/Src/battery_defs.d ./Core/Src/battery_defs.o ./Core/Src/battery_defs.su ./Core/Src/battery_soc.cyclo ./Core/Src/battery_soc.d ./Core/Src/battery_soc.o ./Core/Src/battery_soc.su ./Core/Src/bq25798.cyclo ./Core/Src/bq25798.d ./Core/Src/bq25798.o ./Core/Src/bq25798.su ./Core/Src/diagnostics.cyclo ./Core/Src/diagnostics.d ./Core/Src/diagnostics.o ./Core/Src/diagnostics.su ./Core/Src/error_manager.cyclo ./Core/Src/error_manager.d ./Core/Src/error_manager.o ./Core/Src/error_manager.su ./Core/Src/fpga.cyclo ./Core/Src/fpga.d ./Core/Src/fpga.o ./Core/Src/fpga.su ./Core/Src/frontend_api.cyclo ./Core/Src/frontend_api.d ./Core/Src/frontend_api.o ./Core/Src/frontend_api.su ./Core/Src/joystick.cyclo ./Core/Src/joystick.d ./Core/Src/joystick.o ./Core/Src/joystick.su ./Core/Src/led_manager.cyclo ./Core/Src/led_manager.d ./Core/Src/led_manager.o ./Core/Src/led_manager.su ./Core/Src/main.cyclo ./Core/Src/main.d ./Core/Src/main.o ./Core/Src/main.su ./Core/Src/ota.cyclo ./Core/Src/ota.d ./Core/Src/ota.o ./Core/Src/ota.su ./Core/Src/pinmux.cyclo ./Core/Src/pinmux.d ./Core/Src/pinmux.o ./Core/Src/pinmux.su ./Core/Src/powerMonitor.cyclo ./Core/Src/powerMonitor.d ./Core/Src/powerMonitor.o ./Core/Src/powerMonitor.su ./Core/Src/stm32g0xx_hal_msp.cyclo ./Core/Src/stm32g0xx_hal_msp.d ./Core/Src/stm32g0xx_hal_msp.o ./Core/Src/stm32g0xx_hal_msp.su ./Core/Src/stm32g0xx_hal_timebase_tim.cyclo ./Core/Src/stm32g0xx_hal_timebase_tim.d ./Core/Src/stm32g0xx_hal_timebase_tim.o ./Core/Src/stm32g0xx_hal_timebase_tim.su ./Core/Src/stm32g0xx_it.cyclo ./Core/Src/stm32g0xx_it.d ./Core/Src/stm32g0xx_it.o ./Core/Src/stm32g0xx_it.su ./Core/Src/sys_power.cyclo ./Core/Src/sys_power.d ./Core/Src/sys_power.o ./Core/Src/sys_power.su ./Core/Src/syscalls.cyclo ./Core/Src/syscalls.d ./Core/Src/syscalls.o ./Core/Src/syscalls.su ./Core/Src/sysmem.cyclo ./Core/Src/sysmem.d ./Core/Src/sysmem.o ./Core/Src/sysmem.su ./Core/Src/system_stm32g0xx.cyclo ./Core/Src/system_stm32g0xx.d ./Core/Src/system_stm32g0xx.o ./Core/Src/system_stm32g0xx.su ./Core/Src/user_diskio_spi.cyclo ./Core/Src/user_diskio_spi.d ./Core/Src/user_diskio_spi.o ./Core/Src/user_diskio_spi.su

.PHONY: clean-Core-2f-Src

