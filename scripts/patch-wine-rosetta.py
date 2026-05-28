#!/usr/bin/env python3
"""
Apply CrossOver Rosetta-on-Apple-Silicon signal-handler hacks to a Gcenx/wine
11.x source tree.

Backports:
  - virtual.c read-fault -> write-fault reclassification (no CW#)
  - virtual.c CW HACK 24945: mprotect-toggle on W|X write fault
  - virtual.c CW HACK 25719: mprotect-toggle on X exec fault
  - virtual.c CW HACK 18947: toggle_executable_pages_for_rosetta after NtWriteVirtualMemory
  - signal_x86_64.c CW HACK 23427: emulate_xgetbv + sequoia_or_later flag
  - signal_x86_64.c CW HACK 24256: is_rosetta2 cached flag (needed by 23427)

Usage:  patch-wine-rosetta.py <path-to-wine-src>

Each insertion uses a unique anchor string from the unpatched source. The
script aborts loudly if any anchor is missing OR already patched (idempotent
on the "already patched" side: a second run detects the marker and exits 0).
"""
import os
import sys

MARKER = "CW Hack 24945"  # presence of this in virtual.c means already patched


def insert_after(text: str, anchor: str, payload: str, where: str) -> str:
    """Insert payload immediately after the line containing `anchor`."""
    idx = text.find(anchor)
    if idx == -1:
        raise SystemExit(f"ANCHOR NOT FOUND ({where}): {anchor!r}")
    # Find end of the line containing anchor.
    nl = text.find("\n", idx)
    if nl == -1:
        raise SystemExit(f"anchor on last line? ({where})")
    return text[: nl + 1] + payload + text[nl + 1 :]


def patch_virtual_c(src_root: str) -> None:
    path = os.path.join(src_root, "dlls/ntdll/unix/virtual.c")
    with open(path) as f:
        text = f.read()

    if MARKER in text:
        print(f"  virtual.c: already patched (found {MARKER!r}), skipping")
        return

    # Patch 1: Apple block at top of virtual_handle_fault.
    apple_block = """
#ifdef __APPLE__
    /* Rosetta on Apple Silicon misreports certain write faults as read faults. */
    if (err == EXCEPTION_READ_FAULT && (get_unix_prot( vprot ) & PROT_READ))
    {
        WARN( "treating read fault in a readable page as a write fault, addr %p\\n", addr );
        err = EXCEPTION_WRITE_FAULT;
    }

    /* CW Hack 24945 */
    if (err == EXCEPTION_WRITE_FAULT &&
        ((get_unix_prot( vprot ) & (PROT_WRITE | PROT_EXEC)) == (PROT_WRITE | PROT_EXEC)))
    {
        FIXME( "HACK: write fault on a w|x page, addr %p\\n", addr );
        mprotect_range( page, page_size, 0, VPROT_EXEC );
        mprotect_range( page, page_size, VPROT_EXEC, 0 );
        ret = STATUS_SUCCESS;
        goto done;
    }

    /* CW Hack 25719 */
    if (err == EXCEPTION_EXECUTE_FAULT && (get_unix_prot( vprot ) & PROT_EXEC))
    {
        FIXME( "HACK: exec fault on executable page, addr %p\\n", addr );
        mprotect_range( page, page_size, 0, VPROT_EXEC );
        mprotect_range( page, page_size, VPROT_EXEC, 0 );
        ret = STATUS_SUCCESS;
        goto done;
    }
#endif
"""
    text = insert_after(
        text,
        "vprot = get_host_page_vprot( page );",
        apple_block,
        "virtual.c:virtual_handle_fault Apple block",
    )

    # Patch 2: is_apple_silicon + toggle_executable_pages_for_rosetta.
    # Anchor: the comment line just before NtWriteVirtualMemory.
    toggle_helpers = """
#ifdef __APPLE__
#include <sys/sysctl.h>
static int is_apple_silicon(void)
{
    static int apple_silicon_status, did_check = 0;
    if (!did_check)
    {
        int ret = 0;
        size_t size = sizeof(ret);
        if (sysctlbyname( "sysctl.proc_translated", &ret, &size, NULL, 0 ) == -1)
            apple_silicon_status = 0;
        else
            apple_silicon_status = ret;
        did_check = 1;
    }
    return apple_silicon_status;
}

/* CW HACK 18947
 * If mach_vm_write() is used to modify code cross-process (which is how we
 * implement NtWriteVirtualMemory), Rosetta won't notice the change and will
 * execute the "old" code. Toggle the executable bit on/off after the write to
 * force Rosetta to re-translate.
 */
static void toggle_executable_pages_for_rosetta( HANDLE process, void *addr, SIZE_T size )
{
    MEMORY_BASIC_INFORMATION info;
    NTSTATUS status;
    SIZE_T ret;

    if (!is_apple_silicon())
        return;

    status = NtQueryVirtualMemory( process, addr, MemoryBasicInformation, &info, sizeof(info), &ret );

    if (!status && (info.AllocationProtect & 0xf0))
    {
        DWORD origprot, noexec;
        noexec = info.AllocationProtect & ~0xf0;
        if (!noexec) noexec = PAGE_NOACCESS;

        NtProtectVirtualMemory( process, &addr, &size, noexec, &origprot );
        NtProtectVirtualMemory( process, &addr, &size, origprot, &noexec );
    }
}
#endif

"""
    text = insert_after(
        text,
        " *             NtWriteVirtualMemory   (NTDLL.@)",
        # Anchor not perfect; insert helpers BEFORE the function comment block.
        # Use a stable anchor further up: the closing brace of the preceding
        # NtReadVirtualMemory function body.
        "",  # placeholder; we'll do this differently below
        "virtual.c:toggle helpers (placeholder)",
    )
    # Redo: undo the no-op insert and use a real anchor.
    # The previous call effectively did nothing because payload was empty.
    # Now insert the helpers immediately BEFORE the comment block of NtWriteVirtualMemory.
    target = """
/***********************************************************************
 *             NtWriteVirtualMemory   (NTDLL.@)"""
    idx = text.find(target)
    if idx == -1:
        raise SystemExit("ANCHOR NOT FOUND: NtWriteVirtualMemory comment block")
    text = text[:idx] + "\n" + toggle_helpers + text[idx:]

    # Patch 3: insert toggle call in NtWriteVirtualMemory after SERVER_END_REQ
    # for the write_process_memory request. Anchor on the unique sequence:
    #     SERVER_END_REQ;
    #
    # immediately preceding the closing brace of the if(...) block, then the
    # else { status = STATUS_PARTIAL_COPY; ... }. Easier anchor: insert after
    # the specific SERVER_END_REQ inside NtWriteVirtualMemory followed by the
    # else clause.
    # Anchor that's unique to NtWriteVirtualMemory: it has wine_server_add_data
    # (write side) followed shortly by reply->written. NtReadVirtualMemory uses
    # wine_server_set_reply instead, so this picks the right function.
    unpatched = """            wine_server_add_data( req, buffer, size );
            status = wine_server_call( req );
            size = reply->written;
        }
        SERVER_END_REQ;
    }
    else
    {
        status = STATUS_PARTIAL_COPY;"""
    patched = """            wine_server_add_data( req, buffer, size );
            status = wine_server_call( req );
            size = reply->written;
        }
        SERVER_END_REQ;

#ifdef __APPLE__
        toggle_executable_pages_for_rosetta( process, addr, size );
#endif
    }
    else
    {
        status = STATUS_PARTIAL_COPY;"""
    if unpatched not in text:
        raise SystemExit("ANCHOR NOT FOUND: NtWriteVirtualMemory SERVER_END_REQ block")
    if text.count(unpatched) != 1:
        raise SystemExit(f"AMBIGUOUS ANCHOR: NtWriteVirtualMemory block matched {text.count(unpatched)} times")
    text = text.replace(unpatched, patched, 1)

    with open(path, "w") as f:
        f.write(text)
    print(f"  virtual.c: patched (3 Apple-block hacks + 18947 helpers + call)")


def patch_signal_c(src_root: str) -> None:
    path = os.path.join(src_root, "dlls/ntdll/unix/signal_x86_64.c")
    with open(path) as f:
        text = f.read()

    if "emulate_xgetbv" in text:
        print(f"  signal_x86_64.c: already patched, skipping")
        return

    # Patch A: static flags + sysctl include right after #include "dwarf.h"
    flags_block = """
#ifdef __APPLE__
/* CW Hack 24256 */
#include <sys/sysctl.h>
static BOOL is_rosetta2;

/* CW Hack 23427 */
static BOOL sequoia_or_later = FALSE;
#endif
"""
    text = insert_after(
        text,
        '#include "dwarf.h"',
        flags_block,
        "signal_x86_64.c: static flags after dwarf.h include",
    )

    # Patch B: emulate_xgetbv function. Insert immediately before is_privileged_instr.
    emulate_block = """
#ifdef __APPLE__
/***********************************************************************
 *           emulate_xgetbv
 *
 * Check if the fault location is an Intel XGETBV instruction for xcr0 and
 * emulate it if so. Actual Intel hardware supports this instruction, so this
 * will only take effect under Rosetta.
 * CW HACK 23427
 */
static inline BOOL emulate_xgetbv( ucontext_t *sigcontext, CONTEXT *context )
{
    BYTE instr[3];
    unsigned int len = virtual_uninterrupted_read_memory( (BYTE *)context->Rip, instr, sizeof(instr) );

    /* Prefixed xgetbv is illegal, so no need to check. */
    if (len < 3 || instr[0] != 0x0f || instr[1] != 0x01 || instr[2] != 0xd0 ||
        (RCX_sig(sigcontext) & 0xffffffff) != 0 /* only handling xcr0 (ecx==0) */)
    {
        return FALSE;
    }

    RDX_sig(sigcontext) = 0;
    if (sequoia_or_later)
        RAX_sig(sigcontext) = 0xe7;  /* fpu/mmx, sse, avx, full avx-512 */
    else
        RAX_sig(sigcontext) = 0x07;  /* fpu/mmx, sse */

    RIP_sig(sigcontext) += 3;
    TRACE_(seh)( "emulated an XGETBV instruction\\n" );
    return TRUE;
}
#endif

"""
    is_priv_anchor = """/***********************************************************************
 *           is_privileged_instr"""
    idx = text.find(is_priv_anchor)
    if idx == -1:
        raise SystemExit("ANCHOR NOT FOUND: is_privileged_instr comment block")
    text = text[:idx] + emulate_block + text[idx:]

    # Patch C: SIGILL handler hookup. Add emulate_xgetbv call in PRIVINFLT case.
    # Anchor: existing case TRAP_x86_PRIVINFLT body (which sets ExceptionCode).
    privinflt_unpatched = """    case TRAP_x86_PRIVINFLT:   /* Invalid opcode exception */
        rec.ExceptionCode = EXCEPTION_ILLEGAL_INSTRUCTION;
        break;"""
    privinflt_patched = """    case TRAP_x86_PRIVINFLT:   /* Invalid opcode exception */
#ifdef __APPLE__
        /* CW HACK 23427 */
        if (emulate_xgetbv( ucontext, &context.c )) return;
#endif
        rec.ExceptionCode = EXCEPTION_ILLEGAL_INSTRUCTION;
        break;"""
    if privinflt_unpatched not in text:
        raise SystemExit("ANCHOR NOT FOUND: TRAP_x86_PRIVINFLT case body (unpatched)")
    if text.count(privinflt_unpatched) != 1:
        raise SystemExit(f"AMBIGUOUS ANCHOR: PRIVINFLT block matched {text.count(privinflt_unpatched)} times")
    text = text.replace(privinflt_unpatched, privinflt_patched, 1)

    # Patch D: init of is_rosetta2 + sequoia_or_later. Insert in signal init
    # function right after signal_alloc_thread call.
    init_block = """
#ifdef __APPLE__
    /* CW Hack 24256: sysctl[byname] is not signal-safe; cache here. */
    {
        int ret = 0;
        size_t size = sizeof(ret);
        if (sysctlbyname( "sysctl.proc_translated", &ret, &size, NULL, 0 ) == -1)
            is_rosetta2 = 0;
        else
            is_rosetta2 = ret;
    }

    /* CW Hack 23427: __builtin_available presumably isn't signal-safe. */
    if (__builtin_available( macOS 15.0, * ))
        sequoia_or_later = TRUE;
#endif
"""
    text = insert_after(
        text,
        "signal_alloc_thread( teb );",
        init_block,
        "signal_x86_64.c: is_rosetta2 init after signal_alloc_thread",
    )

    with open(path, "w") as f:
        f.write(text)
    print(f"  signal_x86_64.c: patched (xgetbv emulation + is_rosetta2 + init)")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src_root = sys.argv[1]
    if not os.path.isdir(src_root):
        raise SystemExit(f"not a directory: {src_root}")
    print(f"Patching Wine source tree at {src_root}")
    patch_virtual_c(src_root)
    patch_signal_c(src_root)
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
