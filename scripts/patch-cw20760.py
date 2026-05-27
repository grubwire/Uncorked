#!/usr/bin/env python3
"""
Apply CW HACK 20760 (WoW64 lretq thunk — Rosetta 2 SIGUSR1 race fix) to
dlls/wow64cpu/cpu.c in a Gcenx/wine 11.x source tree.

Backports:
  - CW HACK 20760: replace ljmp with lretq in the WoW64 32->64 transition
    when running under Rosetta 2 (both entry CALLF and return lretq path).

Usage:  patch-cw20760.py <path-to-wine-src>

Idempotent: a second run detects the marker and exits 0.

Note: no #ifdef __APPLE__ guards. wow64cpu.dll is cross-compiled by MinGW
which does not define __APPLE__, so guards would silently compile to nothing.
The Rosetta detection (is_rosetta2) handles the non-Rosetta case at runtime.
"""
import os
import sys

MARKER = "CW HACK 20760"
TARGET = "dlls/wow64cpu/cpu.c"


def patch_cpu_c(src_root: str) -> None:
    path = os.path.join(src_root, TARGET)
    with open(path) as f:
        text = f.read()

    if MARKER in text:
        print(f"  cpu.c: already patched (found {MARKER!r}), skipping")
        return

    # ------------------------------------------------------------------ #
    # Patch 1: add #include <string.h> for strstr in is_rosetta2()        #
    # ------------------------------------------------------------------ #
    old1 = '#include "wine/debug.h"'
    new1 = '#include "wine/debug.h"\n#include <string.h>'
    if old1 not in text:
        raise SystemExit("ANCHOR NOT FOUND: wine/debug.h include")
    if text.count(old1) != 1:
        raise SystemExit(f"AMBIGUOUS: wine/debug.h matched {text.count(old1)} times")
    text = text.replace(old1, new1, 1)

    # ------------------------------------------------------------------ #
    # Patch 2: add use_rosetta2_workaround flag and is_rosetta2()         #
    # ------------------------------------------------------------------ #
    old2 = "void **__wine_unix_call_dispatcher = NULL;"
    new2 = """\
void **__wine_unix_call_dispatcher = NULL;

/* CW HACK 20760 */
static BOOL use_rosetta2_workaround;

static BOOL is_rosetta2(void)
{
    char brand[64];
    ULONG len = sizeof(brand);
    memset( brand, 0, sizeof(brand) );
    NtQuerySystemInformation( SystemProcessorBrandString, brand, len, NULL );
    return strstr( brand, "Apple" ) != NULL;
}"""
    if old2 not in text:
        raise SystemExit("ANCHOR NOT FOUND: __wine_unix_call_dispatcher declaration")
    if text.count(old2) != 1:
        raise SystemExit(f"AMBIGUOUS: __wine_unix_call_dispatcher matched {text.count(old2)} times")
    text = text.replace(old2, new2, 1)

    # ------------------------------------------------------------------ #
    # Patch 3: lretq conditional in syscall_32to64 (fast return path)    #
    # ------------------------------------------------------------------ #
    old3 = (
        '                   "movl 0xc4(%r13),%r14d\\n\\t"  /* context->Esp */\n'
        '                   "xchgq %r14,%rsp\\n\\t"\n'
        '                   "ljmp *(%r14)\\n"\n'
        '                   ".Lsyscall_32to64_return:\\n\\t"'
    )
    new3 = (
        '                   "movl 0xc4(%r13),%r14d\\n\\t"  /* context->Esp */\n'
        '                   "xchgq %r14,%rsp\\n\\t"\n'
        '                   /* CW HACK 20760: When running under Rosetta 2, use lretq\n'
        '                    * instead of ljmp to work around a SIGUSR1 race condition. */\n'
        '                   "cmpl $0,use_rosetta2_workaround(%rip)\\n\\t"\n'
        '                   "jz 1f\\n\\t"\n'
        '                   "subq $16,%rsp\\n\\t"\n'
        '                   "movl 0xb8(%r13),%eax\\n\\t"\n'
        '                   "movq %rax,(%rsp)\\n\\t"\n'
        '                   "movl 0xbc(%r13),%eax\\n\\t"\n'
        '                   "movq %rax,8(%rsp)\\n\\t"\n'
        '                   "lretq\\n"\n'
        '                   "1:\\n\\t"\n'
        '                   "ljmp *(%r14)\\n"\n'
        '                   ".Lsyscall_32to64_return:\\n\\t"'
    )
    if old3 not in text:
        raise SystemExit("ANCHOR NOT FOUND: syscall_32to64 xchgq+ljmp+.Lsyscall_32to64_return")
    if text.count(old3) != 1:
        raise SystemExit(f"AMBIGUOUS: syscall_32to64 ljmp anchor matched {text.count(old3)} times")
    text = text.replace(old3, new3, 1)

    # ------------------------------------------------------------------ #
    # Patch 4: lretq conditional in unix_call_32to64 (end of function)   #
    # ------------------------------------------------------------------ #
    old4 = (
        '                   "movl 0xc4(%r13),%r14d\\n\\t"  /* context->Esp */\n'
        '                   "xchgq %r14,%rsp\\n\\t"\n'
        '                   "ljmp *(%r14)" )'
    )
    new4 = (
        '                   "movl 0xc4(%r13),%r14d\\n\\t"  /* context->Esp */\n'
        '                   "xchgq %r14,%rsp\\n\\t"\n'
        '                   /* CW HACK 20760 */\n'
        '                   "cmpl $0,use_rosetta2_workaround(%rip)\\n\\t"\n'
        '                   "jz 1f\\n\\t"\n'
        '                   "subq $16,%rsp\\n\\t"\n'
        '                   "movl 0xb8(%r13),%eax\\n\\t"\n'
        '                   "movq %rax,(%rsp)\\n\\t"\n'
        '                   "movl 0xbc(%r13),%eax\\n\\t"\n'
        '                   "movq %rax,8(%rsp)\\n\\t"\n'
        '                   "lretq\\n"\n'
        '                   "1:\\n\\t"\n'
        '                   "ljmp *(%r14)" )'
    )
    if old4 not in text:
        raise SystemExit("ANCHOR NOT FOUND: unix_call_32to64 xchgq+ljmp (end of function)")
    if text.count(old4) != 1:
        raise SystemExit(f"AMBIGUOUS: unix_call_32to64 ljmp anchor matched {text.count(old4)} times")
    text = text.replace(old4, new4, 1)

    # ------------------------------------------------------------------ #
    # Patch 5: BTCpuProcessInit — detect Rosetta, use CALLF entry thunk  #
    # 0x2d = FF/5 (JMPF), 0x1d = FF/3 (CALLF). Both structs same size.  #
    # ------------------------------------------------------------------ #
    old5 = "    wow64info->CpuFlags |= WOW64_CPUFLAGS_MSFT64;"
    new5 = """\
    wow64info->CpuFlags |= WOW64_CPUFLAGS_MSFT64;

    /* CW HACK 20760 */
    use_rosetta2_workaround = is_rosetta2();"""
    if old5 not in text:
        raise SystemExit("ANCHOR NOT FOUND: wow64info->CpuFlags |= WOW64_CPUFLAGS_MSFT64")
    if text.count(old5) != 1:
        raise SystemExit(f"AMBIGUOUS: CpuFlags anchor matched {text.count(old5)} times")
    text = text.replace(old5, new5, 1)

    old5b = (
        "    thunk->syscall_thunk.ljmp  = 0xff;\n"
        "    thunk->syscall_thunk.modrm = 0x2d;\n"
        "    thunk->syscall_thunk.op    = PtrToUlong( &thunk->syscall_thunk.addr );\n"
        "    thunk->syscall_thunk.addr  = PtrToUlong( syscall_32to64 );\n"
        "    thunk->syscall_thunk.cs    = cs64_sel;\n"
        "\n"
        "    thunk->unix_thunk.ljmp  = 0xff;\n"
        "    thunk->unix_thunk.modrm = 0x2d;\n"
        "    thunk->unix_thunk.op    = PtrToUlong( &thunk->unix_thunk.addr );\n"
        "    thunk->unix_thunk.addr  = PtrToUlong( unix_call_32to64 );\n"
        "    thunk->unix_thunk.cs    = cs64_sel;"
    )
    new5b = (
        "    /* CW HACK 20760: use CALLF (0x1d) instead of JMPF (0x2d) under Rosetta */\n"
        "    thunk->syscall_thunk.ljmp  = 0xff;\n"
        "    thunk->syscall_thunk.modrm = use_rosetta2_workaround ? 0x1d : 0x2d;\n"
        "    thunk->syscall_thunk.op    = PtrToUlong( &thunk->syscall_thunk.addr );\n"
        "    thunk->syscall_thunk.addr  = PtrToUlong( syscall_32to64 );\n"
        "    thunk->syscall_thunk.cs    = cs64_sel;\n"
        "\n"
        "    thunk->unix_thunk.ljmp  = 0xff;\n"
        "    thunk->unix_thunk.modrm = use_rosetta2_workaround ? 0x1d : 0x2d;\n"
        "    thunk->unix_thunk.op    = PtrToUlong( &thunk->unix_thunk.addr );\n"
        "    thunk->unix_thunk.addr  = PtrToUlong( unix_call_32to64 );\n"
        "    thunk->unix_thunk.cs    = cs64_sel;"
    )
    if old5b not in text:
        raise SystemExit("ANCHOR NOT FOUND: thunk->syscall_thunk/unix_thunk setup block in BTCpuProcessInit")
    if text.count(old5b) != 1:
        raise SystemExit(f"AMBIGUOUS: thunk setup anchor matched {text.count(old5b)} times")
    text = text.replace(old5b, new5b, 1)

    with open(path, "w") as f:
        f.write(text)
    print(f"  cpu.c: patched (CW HACK 20760: lretq thunk + CALLF entry + Rosetta detection)")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src_root = sys.argv[1]
    if not os.path.isdir(src_root):
        raise SystemExit(f"not a directory: {src_root}")
    print(f"Patching Wine source tree at {src_root}")
    patch_cpu_c(src_root)
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
