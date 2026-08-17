#!/usr/bin/env python3
import subprocess
import sys
import pty
import os
import tty
import termios
import select

# 連線參數
cmd = ["ipmitool", "-I", "lanplus", "-H", "10.1.9.86", "-U", "test", "-P", "gigabyte@123", "sol", "activate"]

# 保存原本的終端機設定，以便結束時還原
old_settings = termios.tcgetattr(sys.stdin)

try:
    # 建立偽終端 (PTY) 並啟動 ipmitool
    master, slave = pty.openpty()
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    # 關鍵：將本地終端機切換至 Raw Mode (鍵盤按鍵即時送出，不留緩衝)
    tty.setraw(sys.stdin.fileno())

    # 使用 select 機制，有效率地監聽「BMC 輸出」與「鍵盤輸入」
    while proc.poll() is None:
        r, w, x = select.select([master, sys.stdin], [], [], 0.05)
        
        # 1. 處理 BMC 輸出的畫面資料
        if master in r:
            try:
                data = os.read(master, 4096)
                if data:
                    # 強制將 CP437 轉成 UTF-8，完美渲染 BIOS 框線
                    sys.stdout.write(data.decode('cp437', errors='replace'))
                    sys.stdout.flush()
            except OSError:
                break

        # 2. 處理使用者的鍵盤輸入 (方向鍵、Delete、F2、Esc 隨按隨送)
        if sys.stdin in r:
            try:
                user_input = os.read(sys.stdin.fileno(), 4096)
                if user_input:
                    # 如果使用者按下 Ctrl+Q (ASCII 17)，作為腳本的逃脫暗號
                    if b'\x11' in user_input: 
                        break
                    os.write(master, user_input)
            except OSError:
                break

finally:
    # 恢復原本的終端機設定 (否則你的 Linux 畫面會壞掉)
    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
    
    # 確保關閉 ipmitool 程序
    try:
        proc.terminate()
    except:
        pass
    
    print("\n\r--- IPMI SOL 連線已結束，終端機設定已還原 ---")