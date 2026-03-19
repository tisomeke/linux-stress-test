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

LOG_FILE="stress_${MODE}_$(date +%Y%m%d_%H%M%S).log"

# --- ДИНАМИЧЕСКИЙ ПОИСК ПУТЕЙ (AMD) ---
# Ищем активную видеокарту в системе
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
    [ -f "$temp_path" ] && echo "$(($(cat "$temp_path") / 1000))°C" || echo "N/A"
}

get_gpu_info() {
    local temp="N/A"
    local freq="N/A"

    # Читаем температуру AMD
    if [ -f "$GPU_HWMON" ]; then
        temp="$(($(cat "$GPU_HWMON") / 1000))°C"
    fi

    # Читаем частоту AMD (выбираем ту, что помечена '*')
    if [ -f "$GPU_FREQ_FILE" ]; then
        freq="$(grep '*' "$GPU_FREQ_FILE" | awk '{print $2}' | tr -d 'Mhz')MHz"
    fi

    printf "%-9s | %-9s" "$temp" "$freq"
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

# Шапка таблицы
printf "%-8s | %-10s | %-9s | %-9s | %-6s\n" "Время" "CPU Temp" "GPU Temp" "GPU Clock" "Load" | tee -a "$LOG_FILE"
echo "---------|------------|-----------|-----------|-------" | tee -a "$LOG_FILE"

start_time=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - start_time ))
    
    C_TEMP=$(get_cpu_temp)
    G_INFO=$(get_gpu_info)
    LOAD=$(awk '{print $1}' /proc/loadavg)

    printf "%-8s | %-10s | %s | %-6s\n" "${elapsed}с" "$C_TEMP" "$G_INFO" "$LOAD" | tee -a "$LOG_FILE"

    [ $elapsed -ge $DURATION ] && break
    sleep 10
done

kill $CPU_PID $GPU_PID 2>/dev/null
pkill 7z 2>/dev/null
echo "-------------------------------------------" | tee -a "$LOG_FILE"
echo "Лог сохранен: $LOG_FILE"
