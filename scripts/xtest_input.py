#!/usr/bin/env python3
"""Send scripted X11 keystrokes/clicks to a DOSBox window.

This is a parity-harness helper, not part of the Zig engine. It uses ctypes so
it works without XTest development headers or a compiler: this environment has
libXtst.so.6 at runtime but no libXtst.so linker symlink and no XTest.h.

Usage:
  xtest_input.py WINDOW_ID TOKEN[,TOKEN...] [DELAY_MS]

Tokens are key names accepted by XStringToKeysym (for example `enter` maps to
`Return` through the alias table), single characters, `space`, `clickX,Y` where
X/Y are window-relative, or `pause:MS`. German umlaut keysyms that have no
keycode on the current X layout fall back to ae/oe/ue/ss transliteration.

The XTestClient class is used by dosbox_parity.py with a token *array*, which
avoids shell/comma ambiguity for click coordinates and punctuation.
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
x11.XQueryTree.restype = Bool
x11.XQueryTree.argtypes = [
    DisplayPtr, Window, ctypes.POINTER(Window), ctypes.POINTER(Window),
    ctypes.POINTER(ctypes.POINTER(Window)), ctypes.POINTER(ctypes.c_uint),
]
x11.XFree.restype = None
x11.XFree.argtypes = [DisplayPtr]
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

# US X11 keycodes for DOSBox keyboardlayout=de on a US X layout.
# Avoids keysym remapping; send physical scancode DOSBox-de expects.
DE_DOSBOX_KEYCODES = {
    "a":38,"b":56,"c":54,"d":40,"e":26,"f":41,"g":42,"h":43,"i":31,"j":44,"k":45,"l":46,
    "m":58,"n":57,"o":32,"p":33,"q":24,"r":27,"s":39,"t":28,"u":30,"v":55,"w":25,"x":53,
    "y":52,"z":29," ":65,"ö":47,"ä":48,"ü":34,"ß":20,".":60,",":59,"-":20,
    "1":10,"2":11,"3":12,"4":13,"5":14,"6":15,"7":16,"8":17,"9":18,"0":19,
    "enter":36,"return":36,"space":65,"esc":9,"escape":9,"backspace":22,"tab":23,
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


x11.XChangeKeyboardMapping.restype = Bool
x11.XChangeKeyboardMapping.argtypes = [DisplayPtr, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_ulong), ctypes.c_int]
x11.XGetKeyboardMapping.restype = ctypes.POINTER(ctypes.c_ulong)
x11.XGetKeyboardMapping.argtypes = [DisplayPtr, ctypes.c_uint, ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
x11.XDisplayKeycodes.restype = Bool
x11.XDisplayKeycodes.argtypes = [DisplayPtr, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
x11.XSync.restype = Bool
x11.XSync.argtypes = [DisplayPtr, Bool]


class XTestClient:
    def __init__(self, display_name: str | None = None, de_dosbox_mode: bool = False):
        self.display_name = display_name or os.environ.get("DISPLAY", ":1")
        self.display = x11.XOpenDisplay(self.display_name.encode())
        if not self.display:
            raise RuntimeError(f"cannot open X display {self.display_name}")
        self._mapped_keycodes: list[int] = []
        self._saved_mappings: dict[int, tuple[int, list[int]]] = {}
        self.de_dosbox_mode = de_dosbox_mode

    def close(self) -> None:
        if self.display:
            self._restore_mappings()
            x11.XCloseDisplay(self.display)
            self.display = None

    def _restore_mappings(self) -> None:
        for code, (per, keysyms) in list(self._saved_mappings.items()):
            arr = (ctypes.c_ulong * len(keysyms))(*keysyms)
            x11.XChangeKeyboardMapping(self.display, code, per, arr, 1)
        if self._saved_mappings:
            x11.XSync(self.display, False)
        self._saved_mappings.clear()
        self._mapped_keycodes.clear()

    # German umlauts on US X layout: remap preferred de physical keycodes.
    _DE_KEYCODES = {
        'ä': 48, 'Ä': 48, 'ö': 47, 'Ö': 47, 'ü': 34, 'Ü': 34, 'ß': 20,
    }
    _UMLAUTS = set(_DE_KEYCODES.keys())

    def _ensure_keysym(self, token: str) -> int:
        sym = self.keysym_for(token)
        if sym == 0:
            raise ValueError(f"unknown key token: {token!r}")
        code = x11.XKeysymToKeycode(self.display, sym)
        if code != 0 and token not in self._UMLAUTS:
            return code
        preferred = self._DE_KEYCODES.get(token)
        min_k = ctypes.c_int(); max_k = ctypes.c_int()
        x11.XDisplayKeycodes(self.display, ctypes.byref(min_k), ctypes.byref(max_k))
        per = ctypes.c_int()
        candidates = [preferred] if preferred else []
        for kc in range(max_k.value, min_k.value - 1, -1):
            if kc not in candidates:
                candidates.append(kc)
        for kc in candidates:
            if kc is None or kc < min_k.value or kc > max_k.value:
                continue
            if kc in self._saved_mappings:
                per0, syms0 = self._saved_mappings[kc]
                if int(sym) == syms0[0] if syms0 else False:
                    return kc
                # re-remap
            ptr = x11.XGetKeyboardMapping(self.display, kc, 1, ctypes.byref(per))
            if not ptr:
                continue
            try:
                keysyms = [int(ptr[i]) for i in range(per.value)]
            finally:
                x11.XFree(ctypes.cast(ptr, ctypes.c_void_p))
            if kc in self._saved_mappings:
                # update existing remap
                perv, old = self._saved_mappings[kc]
                new_syms = old[:] if old else [0]
                new_syms[0] = int(sym)
                arr = (ctypes.c_ulong * len(new_syms))(*new_syms)
                x11.XChangeKeyboardMapping(self.display, kc, len(new_syms), arr, 1)
                x11.XSync(self.display, False)
                return kc
            if kc != preferred and any(k != 0 for k in keysyms):
                continue
            self._saved_mappings[kc] = (per.value, keysyms[:])
            new_syms = keysyms[:] if keysyms else [0]
            new_syms[0] = int(sym)
            if len(new_syms) > 1 and token.isupper():
                new_syms[1] = int(sym)
            arr = (ctypes.c_ulong * len(new_syms))(*new_syms)
            x11.XChangeKeyboardMapping(self.display, kc, len(new_syms), arr, 1)
            x11.XSync(self.display, False)
            mapped = x11.XKeysymToKeycode(self.display, sym)
            if mapped == kc:
                self._mapped_keycodes.append(kc)
                return kc
            if mapped != 0:
                self._mapped_keycodes.append(kc)
                return mapped
        if code != 0:
            return code
        raise ValueError(f"no X keycode for keysym 0x{sym:x} ({token})")

    def __enter__(self) -> "XTestClient":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def _focus_is_target(self, focused: int, target: int) -> bool:
        if focused == target:
            return True
        root = Window()
        parent = Window()
        children_ptr = ctypes.POINTER(Window)()
        count = ctypes.c_uint()
        if not x11.XQueryTree(
            self.display, target, ctypes.byref(root), ctypes.byref(parent),
            ctypes.byref(children_ptr), ctypes.byref(count),
        ):
            return False
        try:
            return any(children_ptr[i] == focused for i in range(count.value))
        finally:
            if children_ptr:
                x11.XFree(ctypes.cast(children_ptr, ctypes.c_void_p))

    def activate(self, window: int, strict: bool = True, retries: int = 5) -> bool:
        event_buf = ctypes.create_string_buffer(192)
        event = ctypes.cast(event_buf, ctypes.POINTER(ClientMessageEvent)).contents
        event.type = 33  # ClientMessage
        event.window = window
        event.message_type = x11.XInternAtom(self.display, b"_NET_ACTIVE_WINDOW", False)
        event.format = 32
        event.data[0] = 1  # request from normal application
        event.data[1] = CurrentTime
        for _ in range(retries):
            x11.XSendEvent(
                self.display, x11.XDefaultRootWindow(self.display), False,
                SubstructureRedirectMask | SubstructureNotifyMask, event_buf,
            )
            x11.XSetInputFocus(self.display, window, RevertToParent, CurrentTime)
            x11.XRaiseWindow(self.display, window)
            x11.XFlush(self.display)
            time.sleep(0.08)
            focused = Window()
            revert = ctypes.c_int()
            x11.XGetInputFocus(self.display, ctypes.byref(focused), ctypes.byref(revert))
            if self._focus_is_target(focused.value, window):
                return True
            if not strict:
                return True
        raise RuntimeError(
            f"X input focus is 0x{focused.value:x}, wanted 0x{window:x}"
        )

    def keysym_for(self, token: str) -> int:
        name = ALIASES.get(token, token)
        sym = x11.XStringToKeysym(name.encode("utf-8"))
        if sym == 0 and len(token) == 1:
            sym = ord(token)
        return sym

    def keycode(self, token: str) -> int:
        if self.de_dosbox_mode:
            code = DE_DOSBOX_KEYCODES.get(token.lower() if len(token)==1 else token.lower())
            if code is not None:
                return code
        return self._ensure_keysym(token)

    def press_key(self, token: str, delay: float) -> None:
        code = self.keycode(token)
        xtst.XTestFakeKeyEvent(self.display, code, True, CurrentTime)
        x11.XFlush(self.display)
        time.sleep(delay)
        xtst.XTestFakeKeyEvent(self.display, code, False, CurrentTime)
        x11.XFlush(self.display)
        time.sleep(delay)

    def send(self, token: str, delay: float) -> None:
        if len(token) > 1 and self.keysym_for(token) == 0:
            for char in token:
                self.send(char, delay)
            return
        try:
            self.press_key(token, delay)
        except ValueError:
            fallback = TRANSLIT.get(token)
            if fallback is None:
                raise
            for char in fallback:
                self.send(char, delay)

    def send_tokens(self, window: int, tokens: list[str], delay_ms: int = 60) -> None:
        self.activate(window, strict=True)
        delay = delay_ms / 1000.0
        origin_x = ctypes.c_int()
        origin_y = ctypes.c_int()
        child = Window()
        x11.XTranslateCoordinates(
            self.display, window, x11.XDefaultRootWindow(self.display), 0, 0,
            ctypes.byref(origin_x), ctypes.byref(origin_y), ctypes.byref(child),
        )
        for raw in tokens:
            token = str(raw).strip()
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
                    self.display, -1, origin_x.value + x, origin_y.value + y, CurrentTime,
                )
                x11.XFlush(self.display)
                time.sleep(0.05)
                xtst.XTestFakeButtonEvent(self.display, 1, True, CurrentTime)
                x11.XFlush(self.display)
                time.sleep(delay)
                xtst.XTestFakeButtonEvent(self.display, 1, False, CurrentTime)
                x11.XFlush(self.display)
                time.sleep(delay)
                continue
            self.send(token, delay)


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print("usage: xtest_input.py WINDOW TOKENS [DELAY_MS]", file=sys.stderr)
        return 2
    window = int(argv[1], 0)
    delay = int(argv[3]) / 1000.0 if len(argv) > 3 else 0.06
    tokens = [part.strip() for part in argv[2].split(",") if part.strip()]
    with XTestClient() as client:
        client.send_tokens(window, tokens, delay=int(delay * 1000))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Exception as exc:
        print(f"xtest_input.py: {exc}", file=sys.stderr)
        raise SystemExit(1)
