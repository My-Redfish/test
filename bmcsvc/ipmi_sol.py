#!/usr/bin/env python3
import subprocess
import sys
import pty
import os
import tty
import termios
import select
import argparse

# 1. Use argparse to handle command line arguments
parser = argparse.ArgumentParser(
    description="IPMI SOL PTY Transcoder (CP437 -> UTF-8) with Auto-Deactivate and Clear Screen"
)
parser.add_argument("host", help="BMC IP address (e.g., 10.1.9.86)")
parser.add_argument("-U", "--user", default="test", help="BMC Username (default: test)")
parser.add_argument("-P", "--password", default="gigabyte@123", help="BMC Password (default: gigabyte@123)")

args = parser.parse_args()

# Assign arguments to variables
IPMI_HOST = args.host
IPMI_USER = args.user
IPMI_PASS = args.password

# IPMI command arrays
ACTIVATE_CMD = ["ipmitool", "-I", "lanplus", "-H", IPMI_HOST, "-U", IPMI_USER, "-P", IPMI_PASS, "sol", "activate"]
DEACTIVATE_CMD = ["ipmitool", "-I", "lanplus", "-H", IPMI_HOST, "-U", IPMI_USER, "-P", IPMI_PASS, "sol", "deactivate"]

# Save original terminal attributes to restore them later
old_settings = termios.tcgetattr(sys.stdin)

try:
    # Open a pseudo-terminal (PTY) pair to trick ipmitool into thinking it's interactive
    master, slave = pty.openpty()
    proc = subprocess.Popen(ACTIVATE_CMD, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    # Switch local terminal to RAW mode (instant keypress pass-through)
    tty.setraw(sys.stdin.fileno())

    sys.stdout.write(f"--- IPMI SOL PTY Transcoder Started to {IPMI_HOST} ---\r\n")
    sys.stdout.write("Press [Ctrl + Q] to exit and automatically DEACTIVATE the SOL session.\r\n\r\n")
    sys.stdout.flush()

    # I/O Multiplexing Loop
    while proc.poll() is None:
        r, w, x = select.select([master, sys.stdin], [], [], 0.05)
        
        # 1. Handle incoming payload from BMC
        if master in r:
            try:
                data = os.read(master, 4096)
                if data:
                    sys.stdout.write(data.decode('cp437', errors='replace'))
                    sys.stdout.flush()
            except OSError:
                break

        # 2. Handle keystrokes from Local Keyboard
        if sys.stdin in r:
            try:
                user_input = os.read(sys.stdin.fileno(), 4096)
                if user_input:
                    if b'\x11' in user_input: 
                        break
                    os.write(master, user_input)
            except OSError:
                break

finally:
    # 1. Restore terminal back to original Canonical mode first
    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
    
    # 2. Ensure the activation subprocess is terminated
    try:
        proc.terminate()
        proc.wait(timeout=1)
    except Exception:
        pass
    
    # 3. AUTOMATIC DEACTIVATE
    print(f"\n\rClosing connection... Sending SOL Deactivate to {IPMI_HOST}...")
    try:
        subprocess.run(DEACTIVATE_CMD, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
        print("SOL session deactivated successfully.")
    except subprocess.TimeoutExpired:
        print("Warning: Deactivate command timed out.")
    except Exception as e:
        print(f"Warning: Failed to deactivate SOL session: {e}")
        
    # 4. Clear screen and reset attributes
    sys.stdout.write("\033[0m\033[H\033[2J\033[3J")
    sys.stdout.flush()
    
    print(f"--- IPMI SOL session to {IPMI_HOST} closed. Terminal cleared and restored. ---")