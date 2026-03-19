#!/bin/bash

mkdir -p logs

# --- НАСТРОЙКИ ПО УМОЛЧАНИЮ ---
DURATION=300
MODE=""

# Обработка аргументов
while getopts "t:" opt; do
  case $opt in
    t) DURATION=$OPTARG ;;
    *) echo "Использование: $0 [-t секунды] [cpu|gpu|all]"; exit 1 ;;
  esac
done
shift $((OPTIND -1))
MODE=$1

if [[ -z "$MODE" ]]; then
    echo "Ошибка: укажите режим (cpu, gpu или all)"
    echo "Пример: $0 -t 600 all"
    exit 1
fi

LOG_FILE="logs/stress_${MODE}_$(date +%Y%m%d_%H%M%S).log"

# --- ФУНКЦИИ СБОРА ИНФОРМАЦИИ ---

get_system_info() {
    echo "=== ИНФОРМАЦИЯ О СИСТЕМЕ ==="
    echo "Дата:       $(date)"
    echo "ОС:         $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '\"')"
    echo "Ядро:       $(uname -r)"
    echo "Процессор:  $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
    echo "Потоков:    $(nproc)"
    if [ -d /sys/class/drm/card0/device/hwmon ]; then
        echo "GPU:        $(lspci | grep -i vga | cut -d: -f3 | xargs)"
    fi
    echo "-------------------------------------------"
}

get_cpu_temp() {
    local temp_path=$(find /sys/class/hwmon/hwmon*/temp1_input -type f 2>/dev/null | head -n 1)
    [ -f "$temp_path" ] && echo $(($(cat "$temp_path") / 1000)) || echo "N/A"
}

get_gpu_info() {
    # Специфично для AMD GPU
    local gpu_temp_path=$(ls /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 1)
    local gpu_freq_path=$(ls /sys/class/drm/card*/device/pp_dpm_sclk 2>/dev/null | head -n 1)

    local temp="N/A"
    local freq="N/A"

    [ -f "$gpu_temp_path" ] && temp=$(($(cat "$gpu_temp_path") / 1000))
    [ -f "$gpu_freq_path" ] && freq=$(grep '*' "$gpu_freq_path" | awk '{print $2}' | tr -d 'Mhz')

    printf "%-7s | %-8s" "${temp}°C" "${freq}MHz"
}

# --- УПРАВЛЕНИЕ НАГРУЗКОЙ ---

run_cpu() {
    ( while true; do 7z b -mmt=* > /dev/null 2>&1; done ) &
    CPU_PID=$!
}

run_gpu() {
    furmark --width 1280 --height 720 --demo furmark-gl --max-time $DURATION --no-score-box > /dev/null 2>&1 &
    GPU_PID=$!
}

# --- ИСПОЛНЕНИЕ ---

# Печать инфо в лог и на экран
get_system_info | tee "$LOG_FILE"
echo "Режим: $MODE | Длительность: $DURATION сек" | tee -a "$LOG_FILE"
echo "-------------------------------------------" | tee -a "$LOG_FILE"

case "$MODE" in
    cpu) run_cpu ;;
    gpu) run_gpu ;;
    all) run_cpu; run_gpu ;;
    *) echo "Неверный режим. Используйте: cpu, gpu, all"; exit 1 ;;
esac

# Шапка таблицы (ровная)
printf "%-7s | %-8s | %-7s | %-8s | %-5s\n" "Время" "CPU Temp" "GPU T." "GPU Clk" "Load" | tee -a "$LOG_FILE"
echo "--------|----------|---------|----------|-------" | tee -a "$LOG_FILE"

start_time=$(date +%s)
while true; do
    elapsed=$(( $(date +%s) - start_time ))

    C_TEMP="$(get_cpu_temp)°C"
    G_INFO=$(get_gpu_info)
    LOAD=$(cat /proc/loadavg | awk '{print $1}')

    # Вывод ровной строки
    printf "%-7s | %-8s | %s | %-5s\n" "${elapsed}с" "$C_TEMP" "$G_INFO" "$LOAD" | tee -a "$LOG_FILE"

    if [ $elapsed -ge $DURATION ]; then break; fi
    # Проверка, не закрылся ли FurMark раньше времени в режиме gpu
    if [[ "$MODE" == "gpu" ]] && ! ps -p $GPU_PID > /dev/null; then break; fi

    sleep 10
done

# Очистка
kill $CPU_PID $GPU_PID 2>/dev/null
pkill 7z 2>/dev/null
echo "-------------------------------------------" | tee -a "$LOG_FILE"
echo "Тест завершен. Лог: $LOG_FILE"
