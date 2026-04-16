#!/bin/bash

echo "停止所有测试进程..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 杀死所有 iperf3 服务端
pkill -f "iperf3 -s"

# 杀死 stress-ng
pkill stress-ng

# 杀死 nmon
pkill nmon

# 杀死后台监控脚本（优先用 PID 文件，兜底用 pkill）
LOGDIR_FILE="${SCRIPT_DIR}/.current_test_logdir"
if [ -f "$LOGDIR_FILE" ]; then
    CURRENT_LOG_DIR=$(cat "$LOGDIR_FILE")
    PIDFILE="${CURRENT_LOG_DIR}/monitor.pid"
    if [ -f "$PIDFILE" ]; then
        kill $(cat "$PIDFILE") 2>/dev/null
    fi
fi
# 兜底：按关键字杀死残留的监控子shell
pkill -f "iface_rates"

# 如果有 sar 进程也杀掉
pkill -f "sar -n DEV"

echo "测试进程已停止"

# 简单汇总 nmon 数据（可选）
echo ""
echo "=========================================="
if [ -f "$LOGDIR_FILE" ]; then
    echo "测试完成。日志文件位于: $(cat "$LOGDIR_FILE")"
else
    echo "测试完成。日志文件位于当前目录下的 test_logs_* 文件夹"
fi
echo "主要输出文件:"
echo "  - iface_rates.csv    : 各网口每秒的收发速率 (MB/s)"
echo "  - sar_network.log    : sar 网络统计（如已安装）"
echo "  - iperf3_server_*.log: iperf3 服务端日志"
echo "  - *.nmon             : nmon 系统性能数据"
echo "  - stress-ng.log      : stress-ng 输出"
echo "=========================================="
