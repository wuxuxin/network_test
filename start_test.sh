#!/bin/bash

# ========== 配置区 ==========
TEST_DURATION=600          # 测试时长（秒）

# 网口配置（名称=IP:端口）
declare -A IFACE_MAP=(
    ["eth0"]="192.168.8.200:5201"   # 光口
    ["eth2"]="192.168.2.200:5202"   # 电口1
    ["eth3"]="192.168.3.200:5203"   # 电口2
    ["eth4"]="192.168.4.200:5204"   # 电口3
    ["eth5"]="192.168.5.200:5205"   # 电口4
)

# ========== 创建日志目录 ==========
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/test_logs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"
echo "日志目录: $LOG_DIR"
# 保存日志目录路径到固定位置，供 stop_test.sh 使用
echo "$LOG_DIR" > "${SCRIPT_DIR}/.current_test_logdir"
cd "$LOG_DIR" || exit 1

# ========== 1. 启动 iperf3 服务端 ==========
echo "启动 iperf3 服务端..."
for iface in "${!IFACE_MAP[@]}"; do
    ip_port="${IFACE_MAP[$iface]}"
    ip="${ip_port%:*}"
    port="${ip_port#*:}"
    iperf3 -s -B "$ip" -p "$port" --logfile "iperf3_server_${iface}.log" &
    echo "  iperf3 server: $iface ($ip:$port) PID: $!"
done

# ========== 2. 启动网络流量监控（关键补充） ==========
echo "启动网络流量监控..."

# 方法A: 使用 sar (推荐，精度高)
if command -v sar &> /dev/null; then
    sar -n DEV 1 $TEST_DURATION > "sar_network.log" 2>&1 &
    echo "  sar 网络监控 PID: $!"
fi

# 方法B: 使用 nload 或 iftop 记录各网口实时速率（备选）
# 这里用简单的循环脚本监控各网口，每秒记录一次
(
    # 获取有序的接口列表
    IFACES=($(echo "${!IFACE_MAP[@]}" | tr ' ' '\n' | sort))

    CSV_FILE="${LOG_DIR}/iface_rates.csv"

    # 写入CSV表头到文件
    header="Timestamp"
    for iface in "${IFACES[@]}"; do
        header="${header},${iface}_rx_MBps,${iface}_tx_MBps"
    done
    echo "$header" > "$CSV_FILE"

    # 初始化前一次的字节数（用于计算差值）
    declare -A prev_rx prev_tx
    for iface in "${IFACES[@]}"; do
        prev_rx[$iface]=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        prev_tx[$iface]=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    done
    sleep 1

    for ((i=1; i<$TEST_DURATION; i++)); do
        timestamp=$(date +%Y-%m-%d\ %H:%M:%S)
        line="$timestamp"
        for iface in "${IFACES[@]}"; do
            # 读取当前字节数
            rx_bytes=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
            tx_bytes=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)

            # 计算差值
            rx_diff=$((rx_bytes - ${prev_rx[$iface]:-0}))
            tx_diff=$((tx_bytes - ${prev_tx[$iface]:-0}))

            # 更新前一次的值
            prev_rx[$iface]=$rx_bytes
            prev_tx[$iface]=$tx_bytes

            # 转换为 MB/s（使用 awk 代替 bc，兼容性更好）
            rx_mbps=$(awk "BEGIN {printf \"%.2f\", $rx_diff / 1048576}")
            tx_mbps=$(awk "BEGIN {printf \"%.2f\", $tx_diff / 1048576}")

            line="${line},${rx_mbps},${tx_mbps}"
        done
        echo "$line" >> "$CSV_FILE"
        sleep 1
    done
) &
RATE_MONITOR_PID=$!
echo "  接口速率监控 PID: $RATE_MONITOR_PID"

# ========== 3. 启动 nmon 系统监控 ==========
echo "启动 nmon 系统监控..."
nmon -f -s 1 -c $TEST_DURATION -m . &
echo "  nmon PID: $!"

# ========== 保存 PID 以便停止 ==========
echo $RATE_MONITOR_PID > monitor.pid
jobs -p > all_pids.txt

echo ""
echo "=========================================="
echo "所有服务已启动，测试持续 ${TEST_DURATION} 秒"
echo "日志目录: $LOG_DIR"
echo "=========================================="
echo ""
echo "现在请在 5 台 PC 上分别执行打流命令:"
echo ""
echo "PC1 (光口对端): iperf3 -c 192.168.8.200 -p 5201 -u -b 200M -P 4 -t $TEST_DURATION"
echo "PC2 (电口1):    iperf3 -c 192.168.2.200 -p 5202 -u -b 200M -P 4 -t $TEST_DURATION"
echo "PC3 (电口2):    iperf3 -c 192.168.3.200 -p 5203 -u -b 200M -P 4 -t $TEST_DURATION"
echo "PC4 (电口3):    iperf3 -c 192.168.4.200 -p 5204 -u -b 200M -P 4 -t $TEST_DURATION"
echo "PC5 (电口4):    iperf3 -c 192.168.5.200 -p 5205 -u -b 200M -P 4 -t $TEST_DURATION"
echo ""
echo "测试结束后，执行 ./stop_test.sh 清理进程"
