#!/usr/bin/env python3
"""Draw on the panel through SDL2 KMSDRM (no compositor). Run on the device:
    python3 sdl-kmsdrm-test.py [seconds]
Shows red, green, blue full-screen and a white box in the top-left corner, so
the orientation is visible. Prints the driver, the display mode and the
renderer SDL picked.
"""
import ctypes
import os
import sys
import time

os.environ.setdefault("SDL_VIDEODRIVER", "kmsdrm")
sdl = ctypes.CDLL("libSDL2-2.0.so.0")
sdl.SDL_GetError.restype = ctypes.c_char_p
sdl.SDL_GetCurrentVideoDriver.restype = ctypes.c_char_p
sdl.SDL_CreateWindow.restype = ctypes.c_void_p
sdl.SDL_CreateWindow.argtypes = [ctypes.c_char_p] + [ctypes.c_int] * 4 + [ctypes.c_uint32]
sdl.SDL_CreateRenderer.restype = ctypes.c_void_p
sdl.SDL_CreateRenderer.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_uint32]
for f in ("SDL_SetRenderDrawColor", "SDL_RenderClear", "SDL_RenderPresent", "SDL_RenderFillRect", "SDL_GetRendererInfo"):
    getattr(sdl, f).argtypes = None


class Mode(ctypes.Structure):
    _fields_ = [("format", ctypes.c_uint32), ("w", ctypes.c_int), ("h", ctypes.c_int),
                ("refresh_rate", ctypes.c_int), ("driverdata", ctypes.c_void_p)]


class Info(ctypes.Structure):
    _fields_ = [("name", ctypes.c_char_p), ("flags", ctypes.c_uint32), ("num_texture_formats", ctypes.c_uint32),
                ("texture_formats", ctypes.c_uint32 * 16), ("max_w", ctypes.c_int), ("max_h", ctypes.c_int)]


class Rect(ctypes.Structure):
    _fields_ = [("x", ctypes.c_int), ("y", ctypes.c_int), ("w", ctypes.c_int), ("h", ctypes.c_int)]


if sdl.SDL_Init(0x20) != 0:  # SDL_INIT_VIDEO
    sys.exit(f"SDL_Init: {sdl.SDL_GetError().decode()}")
mode = Mode()
sdl.SDL_GetCurrentDisplayMode(0, ctypes.byref(mode))
print(f"driver {sdl.SDL_GetCurrentVideoDriver().decode()}, display {mode.w}x{mode.h}@{mode.refresh_rate}")
win = sdl.SDL_CreateWindow(b"test", 0, 0, mode.w, mode.h, 0x1001)  # FULLSCREEN | SHOWN
if not win:
    sys.exit(f"SDL_CreateWindow: {sdl.SDL_GetError().decode()}")
ren = sdl.SDL_CreateRenderer(ctypes.c_void_p(win), -1, 0)
if not ren:
    sys.exit(f"SDL_CreateRenderer: {sdl.SDL_GetError().decode()}")
info = Info()
sdl.SDL_GetRendererInfo(ctypes.c_void_p(ren), ctypes.byref(info))
print(f"renderer {info.name.decode()}, max texture {info.max_w}x{info.max_h}")
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 6
box = Rect(0, 0, mode.w // 4, mode.h // 4)
end = time.time() + secs
i = 0
while time.time() < end:
    r, g, b = ((255, 0, 0), (0, 255, 0), (0, 0, 255))[int(i) % 3]
    sdl.SDL_SetRenderDrawColor(ctypes.c_void_p(ren), r, g, b, 255)
    sdl.SDL_RenderClear(ctypes.c_void_p(ren))
    sdl.SDL_SetRenderDrawColor(ctypes.c_void_p(ren), 255, 255, 255, 255)
    sdl.SDL_RenderFillRect(ctypes.c_void_p(ren), ctypes.byref(box))
    sdl.SDL_RenderPresent(ctypes.c_void_p(ren))
    time.sleep(0.05)
    i += 0.05 / (secs / 3)
sdl.SDL_Quit()
print("done")
