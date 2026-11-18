#!/usr/bin/env python3
"""Mainline experiment: the ES9018K2M's registers, straight from the chip (i2c-4, 0x48), for
comparing the stock driver's setup with the chip's power-on state.

  dac-dump.py [<count>]     registers 0..count-1 (default 0x48), as "reg value" in hex

Uses I2C_SLAVE_FORCE, since a kernel driver may hold the address; each read is a plain
write-register-then-read, which the chip's driver also does, so it changes nothing.
"""
import fcntl
import os
import sys

I2C_SLAVE_FORCE = 0x0706
BUS, ADDR = "/dev/i2c-4", 0x48


def main():
    count = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x48
    fd = os.open(BUS, os.O_RDWR)
    fcntl.ioctl(fd, I2C_SLAVE_FORCE, ADDR)
    for reg in range(count):
        try:
            os.write(fd, bytes([reg]))
            val = os.read(fd, 1)[0]
            print(f"{reg:02x} {val:02x}")
        except OSError as e:
            print(f"{reg:02x} error {e.errno}")
    os.close(fd)


if __name__ == "__main__":
    main()
