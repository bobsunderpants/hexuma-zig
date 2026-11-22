#!/usr/bin/env python3
"""Convert REA/Ghidra decompiled room-action routines into a compact rule set.

The Turbo Pascal overlay stubs in HEXPRG.EXE are real INT 3F dispatch vectors.
Each of the eleven overlaid units exports one room-action routine from
HEXUMA.OVR.  Rooms 17 and 26 are dispatched instead to a main-module routine at
0x13e7d after inline prelude state machines.  This script reads the clean entry
decompilations produced from the unit code slices plus that main dispatcher and
turns their condition chains into JSON rules consumed by the Zig runtime.  The
output is evidence-derived data, not final source code.
"""
from __future__ import annotations

import json
import os
import re
import sys
from typing import Any, Dict, List, Optional, Tuple

TOKEN_RE = re.compile(
    r"""
    (?P<space>\s+)
  | (?P<line_comment>//[^\n]*)
  | (?P<block_comment>/\*.*?\*/)
  | (?P<char>'(?:\\.|[^'\\])*')
  | (?P<hex>0[xX][0-9a-fA-F]+)
  | (?P<num>\d+)
  | (?P<op><<|>>|<=|>=|==|!=|&&|\|\||\+\+|--|\+=|-=|\*=|/=|->)
  | (?P<ident>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>.)
    """,
    re.VERBOSE | re.DOTALL,
)

CAST_TYPES = {
    "uint", "int", "char", "byte", "short", "long", "ulong", "undefined1",
    "undefined2", "undefined4", "undefined8", "bool", "word", "dword", "void",
}

LOCAL_PREFIXES = ("uVar", "bVar", "iVar", "local_", "dat_", "puVar", "pcVar", "auStack", "aiStack", "in_")

SPECIAL_NAMES = {
    "_DAT_1000_be1b": "room",
    "DAT_1000_be1b": "room",
    "_DAT_1000_cac2": "verb",
    "DAT_1000_cac2": "verb",
    "_DAT_1000_be5c": "object",
    "DAT_1000_be5c": "object",
    "_DAT_1000_be5e": "object2",
    "DAT_1000_be5e": "object2",
    "_DAT_1000_c9be": "pending_room",
    "DAT_1000_c9be": "pending_room",
    "_DAT_1000_cae4": "score",
    "DAT_1000_cae4": "score",
    "_DAT_1000_c918": "scene",
    "DAT_1000_c918": "scene",
    # Ghidra mis-decodes the word table read at assembly 0x1561e
    # (OBNINT.field_b indexed by object id) as a RAM symbol. The original
    # guard is `room == field_b(object)`.
    "uRam000146c0": "object_gate",
}


def tokenize(text: str) -> List[str]:
    out: List[str] = []
    for m in TOKEN_RE.finditer(text):
        kind = m.lastgroup
        if kind in ("space", "line_comment", "block_comment"):
            continue
        out.append(m.group())
    return out


_ESCAPES = {
    "0": 0,
    "a": 7,
    "b": 8,
    "t": 9,
    "n": 10,
    "v": 11,
    "f": 12,
    "r": 13,
    "'": 0x27,
    '"': 0x22,
    "\\": 0x5c,
}


def decode_char_literal(body: str) -> int:
    values: List[int] = []
    i = 0
    while i < len(body):
        if body[i] != "\\":
            values.append(ord(body[i]) & 0xff)
            i += 1
            continue
        i += 1
        if i >= len(body):
            break
        esc = body[i]
        if esc == "x":
            i += 1
            start = i
            while i < len(body) and body[i] in "0123456789abcdefABCDEF":
                i += 1
            values.append(int(body[start:i] or "0", 16) & 0xff)
            continue
        if esc in _ESCAPES:
            values.append(_ESCAPES[esc])
        else:
            values.append(ord(esc) & 0xff)
        i += 1
    value = 0
    for shift, byte in enumerate(values):
        value |= byte << (8 * shift)
    return value


class ExprParser:
    def __init__(self, tokens: List[str]):
        self.toks = tokens
        self.pos = 0

    def peek(self) -> Optional[str]:
        return self.toks[self.pos] if self.pos < len(self.toks) else None

    def take(self) -> str:
        t = self.peek()
        if t is None:
            raise ValueError("unexpected end of expression")
        self.pos += 1
        return t

    def accept(self, tok: str) -> bool:
        if self.peek() == tok:
            self.pos += 1
            return True
        return False

    ASSIGN_OPS = ("=", "+=", "-=", "*=", "/=", "|=", "&=", "^=", "<<=", ">>=")

    def parse(self) -> Any:
        return self.parse_assign()

    def parse_assign(self) -> Any:
        node = self.parse_or()
        if self.peek() in self.ASSIGN_OPS:
            op = self.take()
            return ("bin", op, node, self.parse_assign())
        return node

    def parse_or(self) -> Any:
        node = self.parse_and()
        while self.accept("||"):
            node = ("bin", "||", node, self.parse_and())
        return node

    def parse_and(self) -> Any:
        node = self.parse_eq()
        while self.accept("&&"):
            node = ("bin", "&&", node, self.parse_eq())
        return node

    def parse_eq(self) -> Any:
        node = self.parse_rel()
        while self.peek() in ("==", "!="):
            op = self.take()
            node = ("bin", op, node, self.parse_rel())
        return node

    def parse_rel(self) -> Any:
        node = self.parse_shift()
        while self.peek() in ("<", ">", "<=", ">="):
            op = self.take()
            node = ("bin", op, node, self.parse_shift())
        return node

    def parse_shift(self) -> Any:
        node = self.parse_add()
        while self.peek() in ("<<", ">>"):
            op = self.take()
            node = ("bin", op, node, self.parse_add())
        return node

    def parse_add(self) -> Any:
        node = self.parse_mul()
        while self.peek() in ("+", "-"):
            op = self.take()
            node = ("bin", op, node, self.parse_mul())
        return node

    def parse_mul(self) -> Any:
        node = self.parse_unary()
        while self.peek() in ("*", "/", "%"):
            op = self.take()
            node = ("bin", op, node, self.parse_unary())
        return node

    def parse_unary(self) -> Any:
        if self.peek() in ("!", "~", "-", "+", "*", "&", "++", "--"):
            op = self.take()
            return ("unary", op, self.parse_unary())
        if self.peek() == "(" and self.pos + 1 < len(self.toks) and self.toks[self.pos + 1] in CAST_TYPES:
            self.take()
            while self.peek() not in (")", None):
                self.take()
            self.accept(")")
            return self.parse_unary()
        return self.parse_primary()

    def parse_primary(self) -> Any:
        t = self.take()
        if t == "(":
            node = self.parse_or()
            self.accept(")")
            return node
        if len(t) >= 2 and t[0] == "'" and t[-1] == "'":
            return ("num", decode_char_literal(t[1:-1]))
        if re.match(r"^0[xX][0-9a-fA-F]+$", t):
            return ("num", int(t, 16))
        if t.isdigit():
            return ("num", int(t, 10))
        if re.match(r"^[A-Za-z_]", t):
            if self.peek() == "(":
                self.take()
                args: List[Any] = []
                if self.peek() != ")":
                    while True:
                        args.append(self.parse_or())
                        if not self.accept(","):
                            break
                self.accept(")")
                return ("call", t, args)
            return ("var", t)
        return ("raw", t)


def parse_expr(tokens: List[str]) -> Any:
    if not tokens:
        return ("raw", "")
    try:
        p = ExprParser(tokens)
        node = p.parse()
        return node
    except Exception:
        return ("raw", " ".join(tokens))


class StmtParser:
    def __init__(self, tokens: List[str]):
        self.toks = tokens
        self.pos = 0

    def peek(self) -> Optional[str]:
        return self.toks[self.pos] if self.pos < len(self.toks) else None

    def take(self) -> str:
        t = self.peek()
        if t is None:
            raise ValueError("unexpected end of statement stream")
        self.pos += 1
        return t

    def accept(self, tok: str) -> bool:
        if self.peek() == tok:
            self.pos += 1
            return True
        return False

    def parse_block(self) -> List[Any]:
        stmts: List[Any] = []
        if not self.accept("{"):
            return stmts
        while self.peek() is not None and self.peek() != "}":
            stmts.append(self.parse_statement())
        self.accept("}")
        return stmts

    def parse_statement(self) -> Any:
        t = self.peek()
        if t == "{":
            return ("block", self.parse_block())
        if t == "if":
            self.take()
            cond = self.parse_paren_expr()
            then = self.parse_statement()
            otherwise = None
            if self.accept("else"):
                otherwise = self.parse_statement()
            return ("if", cond, then, otherwise)
        if t == "while":
            self.take()
            cond = self.parse_paren_expr()
            body = self.parse_statement()
            return ("while", cond, body)
        if t == "for":
            self.take()
            parts = self.parse_paren_parts()
            body = self.parse_statement()
            return ("for", parts, body)
        if t == "return":
            self.take()
            value = None
            if self.peek() is not None and self.peek() != ";":
                toks: List[str] = []
                while self.peek() is not None and self.peek() != ";":
                    toks.append(self.take())
                value = parse_expr(toks)
            self.accept(";")
            return ("return", value)
        # expression statement
        expr: List[str] = []
        depth = 0
        while self.peek() is not None:
            tok = self.peek()
            if tok in ("(", "{"):
                depth += 1
            elif tok in (")", "}"):
                if depth == 0 and tok == "}":
                    break
                depth -= 1
            if tok == ";" and depth == 0:
                self.take()
                break
            expr.append(self.take())
        return ("expr", parse_expr(expr))

    def parse_paren_expr(self) -> Any:
        self.accept("(")
        toks: List[str] = []
        depth = 1
        while self.peek() is not None and depth:
            tok = self.take()
            if tok == "(":
                depth += 1
            elif tok == ")":
                depth -= 1
                if depth == 0:
                    break
            toks.append(tok)
        return parse_expr(toks)

    def parse_paren_parts(self) -> List[Any]:
        self.accept("(")
        parts: List[List[str]] = [[]]
        depth = 1
        while self.peek() is not None and depth:
            tok = self.take()
            if tok == "(":
                depth += 1
            elif tok == ")":
                depth -= 1
                if depth == 0:
                    break
            elif tok == ";" and depth == 1:
                parts.append([])
                continue
            parts[-1].append(tok)
        return [parse_expr(p) for p in parts]


def function_body(path: str) -> List[Any]:
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    # Cut off metadata and find the first function-level opening brace after the signature.
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^void\s+(__cdecl16far\s+)?", line.strip()):
            start = i
            break
    if start is None:
        return []
    code = "\n".join(lines[start:])
    toks = tokenize(code)
    try:
        open_brace = toks.index("{")
    except ValueError:
        return []
    parser = StmtParser(toks[open_brace:])
    return parser.parse_block()


def is_local(name: str, syms: Dict[str, int]) -> bool:
    return name in syms or name.startswith(LOCAL_PREFIXES) or name.startswith("FUN_")


def const_value(node: Any, syms: Dict[str, int]) -> Optional[int]:
    kind = node[0]
    if kind == "num":
        return node[1]
    if kind == "var":
        name = node[1]
        if name in syms:
            return syms[name]
        mapped = SPECIAL_NAMES.get(name)
        if mapped in ("room", "verb", "object", "object2", "score", "scene"):
            return None
        m = re.match(r"^_?DAT_1000_([0-9a-fA-F]+)$", name)
        if m:
            return None
        return None
    if kind == "unary" and node[1] in ("+", "-", "~"):
        v = const_value(node[2], syms)
        if v is None:
            return None
        if node[1] == "+":
            return v
        if node[1] == "-":
            return -v
        return ~v
    if kind == "bin":
        a = const_value(node[2], syms)
        b = const_value(node[3], syms)
        if a is None or b is None:
            return None
        op = node[1]
        try:
            if op == "+":
                return a + b
            if op == "-":
                return a - b
            if op == "*":
                return a * b
            if op == "/":
                return int(a / b)
            if op == "%":
                return a % b
            if op == "<<":
                return a << b
            if op == ">>":
                return a >> b
            if op == "&":
                return a & b
            if op == "|":
                return a | b
            if op == "^":
                return a ^ b
        except Exception:
            return None
    return None


def render_expr(node: Any, syms: Dict[str, int]) -> str:
    kind = node[0]
    if kind == "num":
        return str(node[1])
    if kind == "var":
        name = node[1]
        if name in syms:
            return str(syms[name])
        mapped = SPECIAL_NAMES.get(name)
        if mapped:
            return mapped
        m = re.match(r"^_?DAT_1000_([0-9a-fA-F]+)$", name)
        if m:
            return f"flag(0x{m.group(1)})"
        return name
    if kind == "unary":
        if node[1] == "!":
            inner = render_expr(node[2], syms)
            return f"!({inner})"
        v = const_value(node, syms)
        if v is not None:
            return str(v)
        return render_expr(node[2], syms)
    if kind == "bin":
        op = node[1]
        a = render_expr(node[2], syms)
        b = render_expr(node[3], syms)
        if op == "&&":
            return f"({a}&&{b})"
        if op == "||":
            return f"({a}||{b})"
        return f"({a}{op}{b})"
    if kind == "call":
        name = node[1]
        args = ",".join(render_expr(a, syms) for a in node[2])
        return f"{name}({args})"
    if kind == "raw":
        return node[1]
    return ""


def expr_json(node: Any, syms: Dict[str, int]) -> Any:
    """Serialize a parsed expression into a compact JSON AST for the Zig runtime."""
    kind = node[0]
    if kind == "num":
        return {"n": node[1]}
    if kind == "var":
        name = node[1]
        if name in syms:
            return {"n": syms[name]}
        mapped = SPECIAL_NAMES.get(name)
        if mapped:
            return {"v": mapped}
        m = re.match(r"^_?DAT_1000_([0-9a-fA-F]+)$", name)
        if m:
            return {"flag": f"0x{m.group(1)}"}
        return {"v": name}
    if kind == "unary":
        return {"u": node[1], "a": expr_json(node[2], syms)}
    if kind == "bin":
        return {"b": node[1], "a": expr_json(node[2], syms), "c": expr_json(node[3], syms)}
    if kind == "call":
        return {"call": node[1], "args": [expr_json(a, syms) for a in node[2]]}
    return {"raw": render_expr(node, syms)}


def true_expr() -> Any:
    return ("num", 1)


def and_expr(a: Any, b: Any) -> Any:
    return ("bin", "&&", a, b)


def not_expr(a: Any) -> Any:
    return ("unary", "!", a)


def global_addr(node: Any, syms: Dict[str, int]) -> Optional[str]:
    if node[0] != "var":
        return None
    name = node[1]
    if name == "DAT_1000_be1b" or name == "_DAT_1000_be1b":
        return "room"
    if name == "DAT_1000_cac2" or name == "_DAT_1000_cac2":
        return "verb"
    if name == "DAT_1000_be5c" or name == "_DAT_1000_be5c":
        return "object"
    if name == "DAT_1000_be5e" or name == "_DAT_1000_be5e":
        return "object2"
    if name == "DAT_1000_c9be" or name == "_DAT_1000_c9be":
        return "pending_room"
    if name == "DAT_1000_cae4" or name == "_DAT_1000_cae4":
        return "score"
    if name == "DAT_1000_c918" or name == "_DAT_1000_c918":
        return "scene"
    m = re.match(r"^_?DAT_1000_([0-9a-fA-F]+)$", name)
    if m:
        return f"0x{m.group(1)}"
    return None


def const_or_render(node: Any, syms: Dict[str, int]) -> Any:
    v = const_value(node, syms)
    if v is not None:
        return v
    return render_expr(node, syms)


def action_for_call(name: str, args: List[Any], syms: Dict[str, int]) -> Optional[Dict[str, Any]]:
    if name == "func_0x00016c68":
        if len(args) >= 2:
            v = const_value(args[1], syms)
            if v is not None:
                return {"op": "msg", "id": v}
    if name == "func_0x0001bffd":
        if len(args) >= 2:
            v = const_value(args[1], syms)
            if v is not None:
                return {"op": "picture", "id": v}
    if name == "func_0x0002afb4":
        return {"op": "dialog"}
    if name == "func_0x00015206":
        return {"op": "clear_input"}
    return None


def resolve_expr(node: Any, syms: Dict[str, int]) -> Any:
    kind = node[0]
    if kind == "var" and node[1] in syms:
        return ("num", syms[node[1]])
    if kind == "unary":
        return ("unary", node[1], resolve_expr(node[2], syms))
    if kind == "bin":
        return ("bin", node[1], resolve_expr(node[2], syms), resolve_expr(node[3], syms))
    if kind == "call":
        return ("call", node[1], [resolve_expr(a, syms) for a in node[2]])
    return node


def is_true_expr(node: Any) -> bool:
    return node == true_expr()


def expr_unresolved(node: Any) -> bool:
    """True for decompiler locals or raw memory expressions with no stable
    original-global semantics. Those rules are gated off rather than guessed."""
    if isinstance(node, dict):
        if "raw" in node:
            return True
        value = node.get("v")
        if isinstance(value, str) and (value.startswith("uVar") or value.startswith("local_")):
            return True
        return any(expr_unresolved(item) for item in node.values())
    if isinstance(node, list):
        return any(expr_unresolved(item) for item in node)
    return False


class RuleExtractor:
    ASSIGN_OPS = ("=", "+=", "-=", "*=", "/=", "|=", "&=", "^=", "<<=", ">>=")

    def __init__(self, unit: int):
        self.unit = unit
        self.rules: List[Dict[str, Any]] = []
        self.group = 0

    def add(self, guard: Any, actions: List[Dict[str, Any]]) -> None:
        if not actions:
            return
        when = expr_json(guard, {})
        if expr_unresolved(when):
            when = expr_json(("num", 0), {})
        signature = json.dumps(when, sort_keys=True, separators=(",", ":"))
        previous = json.dumps(self.rules[-1]["when"], sort_keys=True, separators=(",", ":")) if self.rules else None
        if previous != signature:
            self.group += 1
        self.rules.append({
            "group": self.group,
            "unit": self.unit,
            "when": when,
            "actions": actions,
        })

    def combine(self, guard: Any, cond: Any) -> Any:
        cond = resolve_expr(cond, {})
        return cond if is_true_expr(guard) else and_expr(guard, cond)

    def walk_block(self, stmts: List[Any], guard: Any, syms: Dict[str, int]) -> None:
        for stmt in stmts:
            self.walk(stmt, guard, dict(syms))

    def walk(self, stmt: Any, guard: Any, syms: Dict[str, int]) -> None:
        kind = stmt[0]
        if kind == "block":
            self.walk_block(stmt[1], guard, syms)
            return
        if kind == "if":
            cond = resolve_expr(stmt[1], syms)
            then_guard = self.combine(guard, cond)
            self.walk(stmt[2], then_guard, syms)
            if stmt[3] is not None:
                self.walk(stmt[3], self.combine(guard, not_expr(cond)), syms)
            return
        if kind in ("while", "for"):
            if kind == "while":
                cond = resolve_expr(stmt[1], syms)
            else:
                parts = stmt[1]
                cond = resolve_expr(parts[1], syms) if len(parts) > 1 and parts[1][0] != "raw" else true_expr()
            self.walk(stmt[2], self.combine(guard, cond), syms)
            return
        if kind == "return":
            self.add(guard, [{"op": "return"}])
            return
        if kind != "expr":
            return
        node = stmt[1]
        if node[0] == "call":
            action = action_for_call(node[1], node[2], syms)
            if action:
                self.add(guard, [action])
            return
        if node[0] == "unary" and node[1] in ("++", "--"):
            addr = global_addr(node[2], syms)
            if addr:
                value = 1 if node[1] == "++" else -1
                self.add(guard, [{"op": "add", "addr": addr, "value": value}])
            return
        if node[0] != "bin" or node[1] not in self.ASSIGN_OPS:
            return
        op, lhs, rhs = node[1], node[2], node[3]
        addr = global_addr(lhs, syms)
        if addr:
            if op == "=":
                if rhs[0] == "bin" and rhs[1] == "+" and global_addr(rhs[2], syms) == addr:
                    v = const_value(rhs[3], syms)
                    if v is not None:
                        self.add(guard, [{"op": "add", "addr": addr, "value": v}])
                        return
                if rhs[0] == "bin" and rhs[1] == "-" and global_addr(rhs[2], syms) == addr:
                    v = const_value(rhs[3], syms)
                    if v is not None:
                        self.add(guard, [{"op": "add", "addr": addr, "value": -v}])
                        return
                v = const_value(rhs, syms)
                if v is not None:
                    self.add(guard, [{"op": "set", "addr": addr, "value": v}])
                return
            v = const_value(rhs, syms)
            if v is not None:
                delta = v if op == "+=" else -v if op == "-=" else None
                if delta is not None:
                    self.add(guard, [{"op": "add", "addr": addr, "value": delta}])
                else:
                    self.add(guard, [{"op": "set", "addr": addr, "value": expr_json(rhs, syms)}])
            return
        if lhs[0] == "var":
            name = lhs[1]
            if is_local(name, syms) and op == "=":
                v = const_value(rhs, syms)
                if v is not None:
                    syms[name] = v
            return


# Derived from the far-call ranges in main dispatch 0x11d24-0x11e2b and the
# descriptor order checked against each block's +0x0e back-pointer/load segment.
UNIT_RANGES = [
    "170-175,177-183,239",     # segment 0x328
    "199-238,240",             # segment 0x32b
    "184-198",                 # segment 0x32e
    "160-169,176",             # segment 0x331
    "82-97",                   # segment 0x334
    "65-81",                   # segment 0x337
    "27-37",                   # segment 0x33a
    "146-157",                 # segment 0x33d
    "132-145",                 # segment 0x340
    "119-131",                 # segment 0x343
    "1-16,18-20,22,24",        # segment 0x346
]


def parse_room_ranges(spec: str) -> List[List[int]]:
    ranges: List[List[int]] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            first, last = part.split("-", 1)
            ranges.append([int(first), int(last)])
        else:
            value = int(part)
            ranges.append([value, value])
    return ranges


def scan_memory_addresses(path: str) -> set:
    """Hex addresses that occur in dereference expressions of a decompilation."""
    found = set()
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            if "*(" not in line:
                continue
            for m in re.finditer(r"0x([0-9a-fA-F]{4,6})", line):
                value = int(m.group(1), 16)
                if 0x1000 <= value <= 0xffff:
                    found.add(value)
    return found


def scan_overlay_dat_addresses(path: str) -> set:
    with open(path, encoding="utf-8", errors="ignore") as f:
        return {int(m.group(1), 16) for m in re.finditer(r"\b_?DAT_1000_([0-9a-fA-F]{4,6})\b", f.read())}


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "/tmp/opencode/ovr-entry-only"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "extracted/data/overlay_rules.json"
    main_root = sys.argv[3] if len(sys.argv) > 3 else "/tmp/opencode/hexuma-decompiled/functions"
    main_addresses = set()
    if os.path.isdir(main_root):
        for name in os.listdir(main_root):
            if name.endswith(".c"):
                main_addresses |= scan_memory_addresses(os.path.join(main_root, name))

    units = []
    overlay_dat_addresses = set()
    for i in range(11):
        cpath = os.path.join(root, f"{i}-dec", "functions", "0x10100.c")
        if not os.path.exists(cpath):
            print(f"missing {cpath}", file=sys.stderr)
            return 1
        overlay_dat_addresses |= scan_overlay_dat_addresses(cpath)
        ex = RuleExtractor(i)
        ex.walk_block(function_body(cpath), true_expr(), {})
        units.append({
            "unit": i,
            "rooms": UNIT_RANGES[i],
            "room_ranges": parse_room_ranges(UNIT_RANGES[i]),
            "source": cpath,
            "rules": ex.rules,
        })

    # Rooms 17 and 26 reach the main-module dispatcher at 0x13e7d rather than
    # an overlay unit. Its decompiled condition chain has the same action
    # vocabulary, so it is emitted as one additional room-ranged rule block.
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    main_dispatch_path = (
        sys.argv[4]
        if len(sys.argv) > 4
        else os.path.join(
            repo_root, "docs", "reports", "HEXPRG_0x13e7d_pseudocode.c"
        )
    )
    if os.path.exists(main_dispatch_path):
        ex = RuleExtractor(11)
        ex.walk_block(function_body(main_dispatch_path), true_expr(), {})
        units.append({
            "unit": 11,
            "rooms": "17,26",
            "room_ranges": [[17, 17], [26, 26]],
            "source": main_dispatch_path,
            "rules": ex.rules,
        })
    else:
        print(f"missing {main_dispatch_path}", file=sys.stderr)

    # DAT_1000_xxxx symbols not referenced by the load module live in each
    # overlay unit's own data area. Keep them out of the main global state.
    local_addresses = sorted(overlay_dat_addresses - main_addresses)
    payload = json.dumps({
        "source": "REA/Ghidra decompiled HEXUMA.OVR entry routines and main dispatcher 0x13e7d",
        "local_addresses": local_addresses,
        "units": units,
    }, ensure_ascii=False, separators=(",", ":")) + "\n"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(payload)
    # The extractor embeds this table so a fresh extraction is playable; keep
    # the embedded copy in sync with the runtime copy under extracted/.
    mirror_path = os.path.join(repo_root, "src", "data", "overlay_rules.json")
    if os.path.abspath(out_path) != os.path.abspath(mirror_path):
        with open(mirror_path, "w", encoding="utf-8") as f:
            f.write(payload)
    total = sum(len(u["rules"]) for u in units)
    print(f"wrote {out_path}: {total} rules, {len(local_addresses)} overlay-local addresses")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
