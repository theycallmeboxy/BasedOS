/*
 * BasedOS's boot screen: drawn straight to the framebuffer (/dev/fb0) while no frontend owns the
 * display, so the boot shows BasedOS instead of console text.
 *
 *   basedos-splash [-r 0|90|270] [status text...]
 *
 * Draws a terminal-style wordmark ("> BasedOS" and a block cursor), the info lines from
 * /run/basedos/splash (one per line; a line starting with '!' is highlighted), and the status
 * text, if any, along the bottom. Every call redraws the whole screen (about 9 MB, a few ms).
 *
 * The panel's native mode is portrait; the 350H Ultra is held landscape, so on a portrait
 * framebuffer the drawing is turned the way BasedOS's SDL turns frames (-r 270, the default
 * there): landscape pixel (x, y) goes to native (y, H-1-x). -r 90 turns the other way, -r 0
 * not at all (a landscape framebuffer is never turned).
 *
 * Font: converted from Terminus Font (tools/boot-ui/font.h, OFL-Terminus.txt).
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "font.h"

#ifndef INFO_FILE
#define INFO_FILE "/run/basedos/splash"
#endif
#define MAX_LINES 12

static struct fb_var_screeninfo vi;
static struct fb_fix_screeninfo fi;
static uint8_t *fb;      /* the visible page */
static int rot;          /* 0, 90 or 270 */
static int lw, lh;       /* logical (as held) size */

static uint32_t pack(uint32_t rgb)
{
	uint32_t r = rgb >> 16 & 0xff, g = rgb >> 8 & 0xff, b = rgb & 0xff;

	return (r >> (8 - vi.red.length)) << vi.red.offset |
	       (g >> (8 - vi.green.length)) << vi.green.offset |
	       (b >> (8 - vi.blue.length)) << vi.blue.offset |
	       (vi.transp.length ? ((1u << vi.transp.length) - 1) << vi.transp.offset : 0);
}

static void put(int x, int y, uint32_t px)
{
	int nx, ny;
	uint8_t *p;

	if (x < 0 || y < 0 || x >= lw || y >= lh)
		return;
	switch (rot) {
	case 270: nx = y; ny = (int)vi.yres - 1 - x; break;
	case 90: nx = (int)vi.xres - 1 - y; ny = x; break;
	default: nx = x; ny = y; break;
	}
	p = fb + (size_t)ny * fi.line_length + (size_t)nx * (vi.bits_per_pixel / 8);
	switch (vi.bits_per_pixel) {
	case 32: *(uint32_t *)p = px; break;
	case 24: p[0] = px; p[1] = px >> 8; p[2] = px >> 16; break;
	case 16: *(uint16_t *)p = px; break;
	}
}

static void fill(int x0, int y0, int w, int h, uint32_t px)
{
	for (int y = y0; y < y0 + h; y++)
		for (int x = x0; x < x0 + w; x++)
			put(x, y, px);
}

static int glyph_index(unsigned char c)
{
	return (c >= 0x20 && c < 0x7f) ? c - 0x20 : '?' - 0x20;
}

/* Text at (x, y), top left, each font pixel scale x scale. */
static void text(int x, int y, const char *s, int scale, uint32_t px)
{
	for (; *s; s++, x += FONT_W * scale) {
		const unsigned char *g = font_glyphs[glyph_index((unsigned char)*s)];

		for (int r = 0; r < FONT_H; r++)
			for (int c = 0; c < FONT_W; c++)
				if (g[r * FONT_STRIDE + c / 8] & (0x80 >> (c % 8)))
					fill(x + c * scale, y + r * scale, scale, scale, px);
	}
}

static void centred(int y, const char *s, int scale, uint32_t px)
{
	int n = (int)strlen(s), max = lw / (FONT_W * scale) - 2;
	char buf[256];

	if (n > max) { /* too long for the screen: cut, with an ellipsis */
		snprintf(buf, sizeof(buf), "%.*s...", max > 3 ? max - 3 : 0, s);
		s = buf;
		n = (int)strlen(s);
	}
	text((lw - n * FONT_W * scale) / 2, y, s, scale, px);
}

int main(int argc, char **argv)
{
	int fd, i = 1, n = 0, req = -1;
	char lines[MAX_LINES][200], status[400] = "";
	FILE *f;
	size_t size;
	uint8_t *map;

	if (argc > 2 && strcmp(argv[1], "-r") == 0) {
		req = atoi(argv[2]);
		i = 3;
	}
	for (; i < argc; i++) {
		if (status[0])
			strncat(status, " ", sizeof(status) - strlen(status) - 1);
		strncat(status, argv[i], sizeof(status) - strlen(status) - 1);
	}
	if ((f = fopen(INFO_FILE, "r"))) {
		while (n < MAX_LINES && fgets(lines[n], sizeof(lines[n]), f)) {
			lines[n][strcspn(lines[n], "\r\n")] = 0;
			n++;
		}
		fclose(f);
	}

	/* BASEDOS_SPLASH_PREVIEW=<file>: draw into a 1440x1600 XRGB8888 file shaped like the panel's
	 * framebuffer instead (for checking the drawing off the device). */
	const char *preview = getenv("BASEDOS_SPLASH_PREVIEW");

	if (preview) {
		vi.xres = vi.xres_virtual = 1440;
		vi.yres = vi.yres_virtual = 1600;
		vi.bits_per_pixel = 32;
		vi.red.offset = 16; vi.red.length = 8;
		vi.green.offset = 8; vi.green.length = 8;
		vi.blue.offset = 0; vi.blue.length = 8;
		fi.line_length = 1440 * 4;
		size = (size_t)fi.line_length * vi.yres_virtual;
		map = calloc(1, size);
		fd = -1;
	} else {
		fd = open("/dev/fb0", O_RDWR);
		if (fd < 0 || ioctl(fd, FBIOGET_VSCREENINFO, &vi) || ioctl(fd, FBIOGET_FSCREENINFO, &fi))
			return 1;
		if (vi.bits_per_pixel != 32 && vi.bits_per_pixel != 24 && vi.bits_per_pixel != 16)
			return 1;
		size = (size_t)fi.line_length * vi.yres_virtual;
		map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		if (map == MAP_FAILED)
			return 1;
	}
	fb = map + (size_t)vi.yoffset * fi.line_length + (size_t)vi.xoffset * (vi.bits_per_pixel / 8);

	/* A portrait framebuffer is shown turned (default 270, as BasedOS's SDL); landscape never is. */
	rot = vi.yres > vi.xres ? (req == 90 || req == 0 ? req : 270) : 0;
	lw = rot ? (int)vi.yres : (int)vi.xres;
	lh = rot ? (int)vi.xres : (int)vi.yres;

	uint32_t dim = pack(0x1f7f3a), green = pack(0x39ff7a),
		 info = pack(0x8fbf9f), hi = pack(0xffc857), white = pack(0xe6e6e6);
	int scale = lw >= 1200 ? 5 : lw >= 800 ? 3 : 2, ts = lw >= 1200 ? 1 : 1;
	int logo_w = 10 * FONT_W * scale, logo_x = (lw - logo_w) / 2;
	int logo_y = lh * 28 / 100;

	/* The background is black, all-zero in every pixel format: one memset per line. */
	for (int y = 0; y < (int)vi.yres; y++)
		memset(fb + (size_t)y * fi.line_length, 0, (size_t)vi.xres * (vi.bits_per_pixel / 8));

	/* "> BasedOS" and a block cursor, terminal style. */
	text(logo_x, logo_y, ">", scale, dim);
	text(logo_x + 2 * FONT_W * scale, logo_y, "BasedOS", scale, green);
	fill(logo_x + 9 * FONT_W * scale + scale, logo_y + 4 * scale, (FONT_W - 2) * scale, (FONT_H - 6) * scale, green);

	int y = logo_y + FONT_H * scale + FONT_H * ts;
	for (int l = 0; l < n; l++, y += (FONT_H + 10) * ts) {
		if (lines[l][0] == '!')
			centred(y, lines[l] + 1, ts, hi);
		else
			centred(y, lines[l], ts, info);
	}
	if (status[0])
		centred(lh - 2 * FONT_H * ts, status, ts, white);

	if (preview) {
		FILE *o = fopen(preview, "wb");

		if (!o || fwrite(map, 1, size, o) != size)
			return 1;
		fclose(o);
		return 0;
	}
	munmap(map, size);
	close(fd);
	return 0;
}
