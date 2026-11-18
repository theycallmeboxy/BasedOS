#!/usr/bin/env python3
"""Mainline experiment: patch rockchip_drm_vop2.c so the VOP stops the bootloader's display
before attaching its IOMMU (see the comment it adds). Applied by fetch.sh after ROCKNIX's
patches; refuses if the source doesn't look as expected.

  vop2-standby-bootloader.py <linux tree>
"""
import os
import sys

HELPER = r'''/*
 * A bootloader that leaves its splash screen running (Rockchip's own U-Boot does) hands over a
 * VOP that is still scanning out through its IOMMU, with paging on and the bootloader's page
 * tables. That IOMMU won't stall ("Enable stall request timed out"), so the attach below fails
 * and nothing is ever shown. Rockchip's BSP kernel copes with a property that skips the reset
 * (rockchip,disable-first-mmu-reset); here, hand the hardware back in its power-on state:
 * every running video port into standby (it takes effect at the end of the current frame, so
 * wait a little over one, and the bus is quiet), then reset the VOP, IOMMU included, through
 * the resets the device tree gives it. Reads go straight to the hardware: the register cache
 * knows nothing of the bootloader's state.
 */
static void vop2_standby_bootloader_vps(struct vop2 *vop2)
{
	struct reset_control *rst;
	bool running = false;
	int i;

	for (i = 0; i < vop2->data->nr_vps; i++) {
		void __iomem *reg = vop2->regs + vop2->data->vp[i].offset + RK3568_VP_DSP_CTRL;
		u32 ctrl = readl(reg);

		if (!(ctrl & RK3568_VP_DSP_CTRL__STANDBY)) {
			writel(ctrl | RK3568_VP_DSP_CTRL__STANDBY, reg);
			running = true;
		}
	}
	if (!running)
		return;
	drm_info(vop2->drm, "stopping the bootloader's display before attaching the IOMMU\n");
	msleep(50);

	rst = of_reset_control_array_get_optional_exclusive(vop2->dev->of_node);
	if (IS_ERR_OR_NULL(rst)) {
		drm_warn(vop2->drm, "no VOP resets in the device tree: the IOMMU may not attach\n");
		return;
	}
	reset_control_assert(rst);
	udelay(10);
	reset_control_deassert(rst);
	reset_control_put(rst);
}

'''
INCLUDE = "#include <linux/regmap.h>\n"
ANCHOR = "static void vop2_enable(struct vop2 *vop2)\n{"
CALL = "\tret = rockchip_drm_dma_attach_device(vop2->drm, vop2->dev);\n"


def main():
    p = os.path.join(sys.argv[1], "drivers/gpu/drm/rockchip/rockchip_drm_vop2.c")
    s = open(p).read()
    if "vop2_standby_bootloader_vps" in s:
        return
    if s.count(ANCHOR) != 1 or s.count(CALL) != 1 or s.count(INCLUDE) != 1:
        sys.exit("rockchip_drm_vop2.c isn't the expected one; not patching")
    if "#include <linux/reset.h>" not in s:
        s = s.replace(INCLUDE, INCLUDE + "#include <linux/reset.h>\n")
    s = s.replace(ANCHOR, HELPER + ANCHOR)
    s = s.replace(CALL, "\tvop2_standby_bootloader_vps(vop2);\n\n" + CALL)
    open(p, "w", newline="\n").write(s)
    print("patched rockchip_drm_vop2.c: bootloader display stopped before the IOMMU attach")


if __name__ == "__main__":
    main()
