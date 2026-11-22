#!/usr/bin/env python3
"""Send scripted X11 keystrokes/clicks to a DOSBox window.

This is a parity-harness helper, not part of the Zig engine.  It uses ctypes so
it works without XTest development headers or a compiler: this environment has
libXtst.so.6 at runtime but no libXtst.so linker symlink and no XTest.h.

Usage:
  xtest_input.py WINDOW_ID TOKEN[,TOKEN...] [DELAY_MS]

Tokens are key names accepted by XStringToKeysym (for example `enter` maps to
`Return` through the alias table), single characters, `space`, `clickX,Y` where
X/Y are window-relative, or `pause:MS`. German umlaut keysyms that have no
keycode on the current X layout fall back to ae/oe/ue/ss transliteration.
"""
from __future__ import annotations

import ctypes
import os
import sys
import time

x11 = ctypes.CDLL("libX11.so.6")
xtst = ctypes.CDLL("libXtst.so.6")

XID = ctypes.c_ulong
Window = XID
Atom = XID
Bool = ctypes.c_int
DisplayPtr = ctypes.c_void_p

x11.XOpenDisplay.restype = DisplayPtr
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XCloseDisplay.restype = Bool
x11.XCloseDisplay.argtypes = [DisplayPtr]
x11.XFlush.restype = Bool
x11.XFlush.argtypes = [DisplayPtr]
x11.XStringToKeysym.restype = ctypes.c_ulong
x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
x11.XKeysymToKeycode.restype = ctypes.c_uint
x11.XKeysymToKeycode.argtypes = [DisplayPtr, ctypes.c_ulong]
x11.XInternAtom.restype = Atom
x11.XInternAtom.argtypes = [DisplayPtr, ctypes.c_char_p, Bool]
x11.XSetInputFocus.restype = Bool
x11.XSetInputFocus.argtypes = [DisplayPtr, Window, ctypes.c_int, ctypes.c_ulong]
x11.XRaiseWindow.restype = Bool
x11.XRaiseWindow.argtypes = [DisplayPtr, Window]
x11.XGetInputFocus.restype = Bool
x11.XGetInputFocus.argtypes = [DisplayPtr, ctypes.POINTER(Window), ctypes.POINTER(ctypes.c_int)]
x11.XSendEvent.restype = Bool
x11.XSendEvent.argtypes = [DisplayPtr, Window, Bool, ctypes.c_long, ctypes.c_void_p]
x11.XTranslateCoordinates.restype = Bool
x11.XTranslateCoordinates.argtypes = [
    DisplayPtr, Window, Window, ctypes.c_int, ctypes.c_int,
    ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
    ctypes.POINTER(Window),
]
x11.XDefaultRootWindow.restype = Window
x11.XDefaultRootWindow.argtypes = [DisplayPtr]

xtst.XTestFakeKeyEvent.restype = Bool
xtst.XTestFakeKeyEvent.argtypes = [DisplayPtr, ctypes.c_uint, Bool, ctypes.c_ulong]
xtst.XTestFakeMotionEvent.restype = Bool
xtst.XTestFakeMotionEvent.argtypes = [DisplayPtr, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.restype = Bool
xtst.XTestFakeButtonEvent.argtypes = [DisplayPtr, ctypes.c_uint, Bool, ctypes.c_ulong]

RevertToParent = 2
CurrentTime = 0
SubstructureRedirectMask = 1 << 20
SubstructureNotifyMask = 1 << 19

TRANSLIT = {
    "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
    "Ä": "Ae", "Ö": "Oe", "Ü": "Ue",
}

ALIASES = {
    "enter": "Return",
    "return": "Return",
    "esc": "Escape",
    "escape": "Escape",
    "space": "space",
    "backspace": "BackSpace",
    "tab": "Tab",
    "left": "Left",
    "right": "Right",
    "up": "Up",
    "down": "Down",
    "ä": "adiaeresis",
    "ö": "odiaeresis",
    "ü": "udiaeresis",
    "ß": "ssharp",
    "Ä": "Adiaeresis",
    "Ö": "Odiaeresis",
    "Ü": "Udiaeresis",
}


class ClientMessageEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", Bool),
        ("display", DisplayPtr),
        ("window", Window),
        ("message_type", Atom),
        ("format", ctypes.c_int),
        ("data", ctypes.c_long * 5),
    ]


def activate(display: int, window: int) -> None:
    # XEvent is larger than XClientMessageEvent; allocate enough bytes and fill
    # the leading client-message fields.
    event_buf = ctypes.create_string_buffer(192)
    event = ctypes.cast(event_buf, ctypes.POINTER(ClientMessageEvent)).contents
    event.type = 33  # ClientMessage
    event.window = window
    event.message_type = x11.XInternAtom(display, b"_NET_ACTIVE_WINDOW", False)
    event.format = 32
    event.data[0] = 1  # request from normal application
    event.data[1] = CurrentTime
    x11.XSendEvent(
        display, x11.XDefaultRootWindow(display), False,
        SubstructureRedirectMask | SubstructureNotifyMask, event_buf,
    )
    x11.XSetInputFocus(display, window, RevertToParent, CurrentTime)
    x11.XRaiseWindow(display, window)
    x11.XFlush(display)
    time.sleep(0.1)
    focused = Window()
    revert = ctypes.c_int()
    x11.XGetInputFocus(display, ctypes.byref(focused), ctypes.byref(revert))
    if focused.value != window:
        print(f"warning: X input focus is 0x{focused.value:x}, wanted 0x{window:x}", file=sys.stderr)


def keysym_for(token: str) -> int:
    name = ALIASES.get(token, token)
    sym = x11.XStringToKeysym(name.encode("utf-8"))
    if sym == 0 and len(token) == 1:
        sym = ord(token)
    return sym


def keycode(display: int, token: str) -> int:
    name = ALIASES.get(token, token)
    sym = keysym_for(token)
    if sym == 0:
        raise ValueError(f"unknown key token: {token!r}")
    code = x11.XKeysymToKeycode(display, sym)
    if code == 0:
        raise ValueError(f"no X keycode for keysym 0x{sym:x} ({name})")
    return code


def press_key(display: int, token: str, delay: float) -> None:
    code = keycode(display, token)
    xtst.XTestFakeKeyEvent(display, code, True, CurrentTime)
    x11.XFlush(display)
    time.sleep(delay)
    xtst.XTestFakeKeyEvent(display, code, False, CurrentTime)
    x11.XFlush(display)
    time.sleep(delay)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: xtest_input.py WINDOW TOKENS [DELAY_MS]", file=sys.stderr)
        return 2
    window = int(argv[1], 0)
    delay = int(argv[3]) / 1000.0 if len(argv) > 3 else 0.06
    display = x11.XOpenDisplay(os.environ.get("DISPLAY", ":1").encode())
    if not display:
        print("cannot open X display", file=sys.stderr)
        return 1
    try:
        activate(display, window)
        origin_x = ctypes.c_int()
        origin_y = ctypes.c_int()
        child = Window()
        x11.XTranslateCoordinates(
            display, window, x11.XDefaultRootWindow(display), 0, 0,
            ctypes.byref(origin_x), ctypes.byref(origin_y), ctypes.byref(child),
        )
        for raw in argv[2].split(","):
            token = raw.strip()
            if not token:
                continue
            if token.startswith("pause:"):
                time.sleep(int(token.split(":", 1)[1]) / 1000.0)
                continue
            if token.startswith("click"):
                coords = token[5:].split(",")
                if len(coords) != 2:
                    raise ValueError(f"bad click token: {token}")
                x, y = int(coords[0]), int(coords[1])
                xtst.XTestFakeMotionEvent(
                    display, -1, origin_x.value + x, origin_y.value + y, CurrentTime,
                )
                x11.XFlush(display)
                time.sleep(0.05)
                xtst.XTestFakeButtonEvent(display, 1, True, CurrentTime)
                x11.XFlush(display)
                time.sleep(delay)
                xtst.XTestFakeButtonEvent(display, 1, False, CurrentTime)
                x11.XFlush(display)
                time.sleep(delay)
                continue
            def send(token: str) -> None:
                if len(token) > 1 and keysym_for(token) == 0:
                    for char in token:
                        send(char)
                else:
                    try:
                        press_key(display, token, delay)
                    except ValueError:
                        fallback = TRANSLIT.get(token)
                        if not fallback:
                            raise
                        for char in fallback:
                            send(char)

            send(token)
    finally:
        x11.XCloseDisplay(display)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Exception as exc:
        print(f"xtest_input.py: {exc}", file=sys.stderr)
        raise SystemExit(1)
