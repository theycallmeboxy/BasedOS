#!/usr/bin/env python3
"""Mainline experiment: fix a 32-bit overflow in dw-mipi-dsi2-rockchip.c.

dw_mipi_dsi2_get_lane_mbps() computes the PHY's pixel clock as
lane_rate_kbps * lanes * 1000 / bpp, with lane_rate_kbps an unsigned int and lanes a u32, so
the product is 32-bit and wraps above 4294967295: at 4 lanes, any lane rate over 1073 Mbps.
The 350H Ultra's panel needs 1131 Mbps (169.715 MHz, 24 bpp, burst +10/9); the product
4525732000 wraps to 230764704 and the DC-PHY is set to 57.69 MHz instead of 1131 MHz, so the
panel gets no usable picture. ROCKNIX's RG Vita Pro (1013 Mbps) stays just under the limit.
Worth sending upstream.

  dsi2-phyclk-overflow.py <linux tree>
"""
import os
import sys

OLD = "DIV_ROUND_CLOSEST_ULL(lane_rate_kbps * lanes * 1000, bpp)"
NEW = "DIV_ROUND_CLOSEST_ULL((u64)lane_rate_kbps * lanes * 1000, bpp)"


def main():
    p = os.path.join(sys.argv[1], "drivers/gpu/drm/rockchip/dw-mipi-dsi2-rockchip.c")
    s = open(p).read()
    if NEW in s:
        return
    if s.count(OLD) != 1:
        sys.exit("dw-mipi-dsi2-rockchip.c isn't the expected one; not patching")
    open(p, "w", newline="\n").write(s.replace(OLD, NEW))
    print("patched dw-mipi-dsi2-rockchip.c: PHY clock computed in 64 bits")


if __name__ == "__main__":
    main()
