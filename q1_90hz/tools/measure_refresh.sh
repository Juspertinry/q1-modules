#!/bin/sh
# Measure the panel's real refresh rate from hardware vsync timestamps.
#
# /sys/class/graphics/fb0/vsync_event carries the nanosecond timestamp of the
# most recent vsync interrupt. Poll it faster than the panel refreshes, keep the
# distinct values, and the spacing is the true refresh period.
#
# Do NOT compute the rate from pclk0_clk_src and the lcdc porches. That is the
# driver's view of what it programmed, it assumes no divider between that clock
# node and the pixel clock, and on this device it reads ~1.25x low.
#
# Use shell-builtin `read`, not `cat`: spawning a process per sample cannot keep
# up with the panel and silently undersamples, which yields a number that is
# really just your own polling rate.
#
# usage: adb shell < measure_refresh.sh
# A gap of exactly N frame periods in the output is the sampler being
# descheduled for that long, not the panel skipping: judge stability from the
# intervals around the median, not from the raw stdev.
N=${1:-30000}
i=0
while [ $i -lt $N ]; do
  read v < /sys/class/graphics/fb0/vsync_event
  echo "$v"
  i=$((i+1))
done
