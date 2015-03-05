#!/bin/bash

read -d '' USAGE <<- EOF
nrfprog.sh

This is a loose shell port of the nrfjprog.exe program distributed by Nordic,
which relies on JLinkExe to interface with the JLink hardware.

usage:

nrfjprog.sh <action> [hexfile]

where action is one of
  --reset
  --pin-reset
  --erase-all
  --flash
  --flash-softdevice
  --rtt

EOF

GREEN="\033[32m"
RESET="\033[0m"
STATUS_COLOR=$GREEN

TOOLCHAIN_PREFIX=arm-none-eabi
# assume the tools are on the system path
TOOLCHAIN_PATH=
OBJCOPY=$TOOLCHAIN_PATH$TOOLCHAIN_PREFIX-objcopy
OBJDUMP=$TOOLCHAIN_PATH$TOOLCHAIN_PREFIX-objdump
JLINK_OPTIONS="-device nrf51822 -if swd -speed 1000"

HEX=$2

# assume there's an out and bin file next to the hexfile
OUT=${HEX/.hex/.out}
BIN=${HEX/.hex/.bin}

JLINK="JLinkExe $JLINK_OPTIONS"
JLINKGDBSERVER="JLinkGDBServer $JLINK_OPTIONS"

# the script commands come from Makefile.posix, distributed with nrf51-pure-gcc

TMPSCRIPT=/tmp/tmp_$$.jlink
TMPBIN=/tmp/tmp_$$.bin
if [ "$1" = "--reset" ]; then
    echo ""
    echo -e "${STATUS_COLOR}resetting...${RESET}"
    echo ""
    echo "r" > $TMPSCRIPT
    echo "g" >> $TMPSCRIPT
    echo "exit" >> $TMPSCRIPT
    $JLINK $TMPSCRIPT
    rm $TMPSCRIPT
elif [ "$1" = "--pin-reset" ]; then
    echo ""
    echo -e "${STATUS_COLOR}resetting with pin...${RESET}"
    echo ""
    echo "w4 40000544 1" > $TMPSCRIPT
    echo "r" >> $TMPSCRIPT
    echo "exit" >> $TMPSCRIPT
    $JLINK $TMPSCRIPT
    rm $TMPSCRIPT
elif [ "$1" = "--erase-all" ]; then
    echo ""
    echo -e "${STATUS_COLOR}perfoming full erase...${RESET}"
    echo ""
    echo "w4 4001e504 2" > $TMPSCRIPT
    echo "w4 4001e50c 1" >> $TMPSCRIPT
    echo "sleep 100" >> $TMPSCRIPT
    echo "r" >> $TMPSCRIPT
    echo "exit" >> $TMPSCRIPT
    $JLINK $TMPSCRIPT
    rm $TMPSCRIPT
elif [ "$1" = "--flash" ]; then
    echo ""
    echo -e "${STATUS_COLOR}flashing ${BIN}...${RESET}"
    echo ""
    FLASH_START_ADDRESS=`$OBJDUMP -h $OUT -j .text | grep .text | awk '{print $4}'`
    echo "r" > $TMPSCRIPT
    echo "loadbin $BIN $FLASH_START_ADDRESS" >> $TMPSCRIPT
    echo "r" >> $TMPSCRIPT
    echo "g" >> $TMPSCRIPT
    echo "exit" >> $TMPSCRIPT
    $JLINK $TMPSCRIPT
    rm $TMPSCRIPT
elif [ "$1" = "--flash-softdevice" ]; then
    echo ""
    echo -e "${STATUS_COLOR}flashing softdevice ${HEX}...${RESET}"
    echo ""
    $OBJCOPY -Iihex -Obinary $HEX $TMPBIN
    # Write to NVMC to enable erase, do erase all, wait for completion. reset
    echo "w4 4001e504 2" > $TMPSCRIPT
    echo "w4 4001e50c 1" >> $TMPSCRIPT
    echo "sleep 100" >> $TMPSCRIPT
    echo "r" >> $TMPSCRIPT
    # Write to NVMC to enable write. Write mainpart, write UICR. Assumes device is erased.
    echo "w4 4001e504 1" > $TMPSCRIPT
    echo "loadbin $TMPBIN 0" >> $TMPSCRIPT
    echo "r" >> $TMPSCRIPT
    echo "g" >> $TMPSCRIPT
    echo "exit" >> $TMPSCRIPT
    $JLINK $TMPSCRIPT
    rm $TMPSCRIPT
    rm $TMPBIN
elif [ "$1" = "--rtt" ]; then
    # trap the SIGINT signal so we can clean up if the user CTRL-C's out of the
    # RTT client
    trap ctrl_c INT
    function ctrl_c() {
        return
    }
    echo -e "${STATUS_COLOR}Starting RTT Server...${RESET}"
    JLinkExe -device nrf51822 -if swd -speed 1000 &
    JLINK_PID=$!
    sleep 1
    echo -e "\n${STATUS_COLOR}Connecting to RTT Server...${RESET}"
    #telnet localhost 19021
    JLinkRTTClient
    echo -e "\n${STATUS_COLOR}Killing RTT server ($JLINK_PID)...${RESET}"
    kill $JLINK_PID
else
    echo "$USAGE"
fi
