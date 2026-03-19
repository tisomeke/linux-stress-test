#!/bin/bash

# Создание директории для логов
mkdir -p logs

# Настройки
DURATION=300 # 5 минут
LOG_FILE="logs/stress_$(date +%H%M%S).log"

# --- ФУНКЦИИ СБОРА ДАННЫХ ---

get_cpu_temp() {
    # Ищем стандартный датчик температуры ядра в sysfs
    local temp_path=$(find /sys/class/hwmon/hwmon*/temp1_input -type f 2>/dev/null | head -n 1)
    if [ -f "$temp_path" ]; then
        echo $(($(cat "$temp_path") / 1000))
    else
        echo "N/A"
    fi
}

get_gpu_info() {
    if command -v nvidia-smi &> /dev/null; then
        # Для NVIDIA: Температура и Частота
        nvidia-smi --query-gpu=temperature.gpu,clocks.current.graphics --format=csv,noheader,nounits 2>/dev/null | tr ',' '|'
    else
        # Для AMD/Intel: через системные файлы
        local gpu_temp_path=$(ls /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 1)
        if [ -f "$gpu_temp_path" ]; then
            echo "$(($(cat "$gpu_temp_path") / 1000)) | N/A"
        else
            echo "N/A | N/A"
        fi
    fi
}

# --- РЕЖИМЫ НАГРУЗКИ ---

run_cpu() {
    echo "[+] Запуск нагрузки на CPU (7z)..."
    ( while true; do 7z b -mmt=* > /dev/null 2>&1; done ) &
    CPU_PID=$!
}

run_gpu() {
    echo "[+] Запуск нагрузки на GPU (FurMark)..."
    furmark --width 1280 --height 720 --demo furmark-gl --max-time $DURATION --no-score-box > /dev/null 2>&1 &
    GPU_PID=$!
}

# --- ОСНОВНОЙ ЦИКЛ ---

case "$1" in
    cpu) run_cpu ;;
    gpu) run_gpu ;;
    all) run_cpu; run_gpu ;;
    *) echo "Использование: ./stress.sh [cpu|gpu|all]"; exit 1 ;;
esac

echo "Время | CPU Temp | GPU Temp | GPU Clock | Load" | tee -a "$LOG_FILE"
start_time=$(date +%s)

while ps -p ${CPU_PID:-$!} > /dev/null || ps -p ${GPU_PID:-$!} > /dev/null; do
    elapsed=$(( $(date +%s) - start_time ))

    C_TEMP=$(get_cpu_temp)
    G_INFO=$(get_gpu_info)
    LOAD=$(cat /proc/loadavg | awk '{print $1}')

    echo "${elapsed}с | ${C_TEMP}°C | $G_INFO | $LOAD" | tee -a "$LOG_FILE"

    if [ $elapsed -ge $DURATION ]; then break; fi
    sleep 10
done

# Очистка
kill $CPU_PID $GPU_PID 2>/dev/null
pkill 7z
echo "=== Тест завершен. Лог: $LOG_FILE ==="
