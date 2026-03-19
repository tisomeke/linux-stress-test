#!/bin/bash

mkdir -p logs

# --- НАСТРОЙКИ ---
DURATION=300
MODE=""

while getopts "t:" opt; do
  case $opt in
    t) DURATION=$OPTARG ;;
    *) echo "Использование: $0 [-t секунды] [cpu|gpu|all]"; exit 1 ;;
  esac
done
shift $((OPTIND -1))
MODE=$1

[ -z "$MODE" ] && { echo "Ошибка: укажите режим (cpu, gpu или all)"; exit 1; }

LOG_FILE="logs/stress_${MODE}_$(date +%Y%m%d_%H%M%S).log"

# Переменные для расчета AVR
CPU_SUM=0
GPU_T_SUM=0
GPU_C_SUM=0
LOAD_SUM=0
COUNT=0

# --- ДИНАМИЧЕСКИЙ ПОИСК ПУТЕЙ (AMD) ---
GPU_HWMON=$(ls /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 1)
GPU_FREQ_FILE=$(ls /sys/class/drm/card*/device/pp_dpm_sclk 2>/dev/null | head -n 1)

get_system_info() {
    echo "=== СИСТЕМНАЯ ИНФОРМАЦИЯ ==="
    echo "ОС:         $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '\"')"
    echo "Процессор:  $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
    echo "Ядра/Потоки: $(nproc)"
    echo "Видеокарта: $(lspci | grep -i vga | cut -d: -f3 | xargs)"
    echo "Датчик GPU: ${GPU_HWMON:-'НЕ НАЙДЕН'}"
    echo "-------------------------------------------"
}

get_cpu_temp() {
    local temp_path=$(find /sys/class/hwmon/hwmon*/temp1_input -type f 2>/dev/null | head -n 1)
    [ -f "$temp_path" ] && echo $(($(cat "$temp_path") / 1000)) || echo "0"
}

get_gpu_info() {
    local temp=0
    local freq=0
    [ -f "$GPU_HWMON" ] && temp=$(($(cat "$GPU_HWMON") / 1000))
    [ -f "$GPU_FREQ_FILE" ] && freq=$(grep '*' "$GPU_FREQ_FILE" | awk '{print $2}' | tr -cd '0-9')
    echo "$temp $freq"
}

run_cpu() { ( while true; do 7z b -mmt=* > /dev/null 2>&1; done ) & CPU_PID=$!; }
run_gpu() { furmark --width 1280 --height 720 --demo furmark-gl --max-time $DURATION --no-score-box > /dev/null 2>&1 & GPU_PID=$!; }

# --- СТАРТ ---
get_system_info | tee "$LOG_FILE"
case "$MODE" in
    cpu) run_cpu ;;
    gpu) run_gpu ;;
    all) run_cpu; run_gpu ;;
esac

printf "%-8s | %-10s | %-9s | %-9s | %-6s\n" "Время" "CPU Temp" "GPU Temp" "GPU Clock" "Load" | tee -a "$LOG_FILE"
echo "---------|------------|-----------|-----------|-------" | tee -a "$LOG_FILE"

start_time=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - start_time ))
    
    C_T=$(get_cpu_temp)
    read G_T G_C <<< $(get_gpu_info)
    L_V=$(awk '{print $1}' /proc/loadavg)

    # Накопление для AVR
    CPU_SUM=$(echo "$CPU_SUM + $C_T" | bc)
    GPU_T_SUM=$(echo "$GPU_T_SUM + $G_T" | bc)
    GPU_C_SUM=$(echo "$GPU_C_SUM + $G_C" | bc)
    LOAD_SUM=$(echo "$LOAD_SUM + $L_V" | bc)
    ((COUNT++))

    printf "%-8s | %-10s | %-9s | %-9s | %-6s\n" "${elapsed}с" "${C_T}°C" "${G_T}°C" "${G_C}MHz" "$L_V" | tee -a "$LOG_FILE"

    [ $elapsed -ge $DURATION ] && break
    sleep 10
done

# Расчет AVR (через bc для точности)
AVR_CPU=$(echo "scale=1; $CPU_SUM / $COUNT" | bc)
AVR_GPU_T=$(echo "scale=1; $GPU_T_SUM / $COUNT" | bc)
AVR_GPU_C=$(echo "scale=0; $GPU_C_SUM / $COUNT" | bc)
AVR_LOAD=$(echo "scale=2; $LOAD_SUM / $COUNT" | bc)

kill $CPU_PID $GPU_PID 2>/dev/null
pkill 7z 2>/dev/null

echo "---------|------------|-----------|-----------|-------" | tee -a "$LOG_FILE"
printf "%-8s | %-10s | %-9s | %-9s | %-6s\n" "AVR" "${AVR_CPU}°C" "${AVR_GPU_T}°C" "${AVR_GPU_C}MHz" "$AVR_LOAD" | tee -a "$LOG_FILE"
echo "-------------------------------------------" | tee -a "$LOG_FILE"
echo "Лог сохранен: $LOG_FILE"
