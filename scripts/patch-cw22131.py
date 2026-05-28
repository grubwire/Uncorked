#!/usr/bin/env python3
"""Apply CW HACK 22131 (fake STATUS_SUCCESS on debug-reg set under Rosetta) to
   dlls/ntdll/unix/signal_x86_64.c. Idempotent."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/wine-build/wine-src/dlls/ntdll/unix/signal_x86_64.c"
with open(path) as f:
    s = f.read()

if "faking success" in s:
    print("CW 22131 (faking success) already applied")
    sys.exit(0)

# AMD64: Wine 11.9 already has a partial Apple block that WARNs.
# Replace it with the full CW 22131 that fakes STATUS_SUCCESS.
amd64_old = (
    '        ret = set_thread_context( handle, context, &self, IMAGE_FILE_MACHINE_AMD64 );\n'
    '#ifdef __APPLE__\n'
    '        if ((flags & CONTEXT_DEBUG_REGISTERS) && (ret == STATUS_UNSUCCESSFUL))\n'
    '            WARN_(seh)( "Setting debug registers is not supported under Rosetta\\n" );\n'
    '#endif\n'
    '        if (ret || !self) return ret;'
)
amd64_new = (
    '        ret = set_thread_context( handle, context, &self, IMAGE_FILE_MACHINE_AMD64 );\n'
    '#ifdef __APPLE__\n'
    '        /* CW HACK 22131 */\n'
    '        if ((flags & CONTEXT_DEBUG_REGISTERS) && (ret == STATUS_UNSUCCESSFUL))\n'
    '        {\n'
    '            WARN_(seh)( "Setting debug registers is not supported under Rosetta, faking success\\n" );\n'
    '            ret = STATUS_SUCCESS;\n'
    '        }\n'
    '#endif\n'
    '        if (ret || !self) return ret;'
)
if amd64_old not in s:
    print("ERROR: AMD64 anchor not found")
    sys.exit(1)
s = s.replace(amd64_old, amd64_new, 1)

# I386: Wine 11.9 has no Apple block. Insert one.
i386_old = (
    '        NTSTATUS ret = set_thread_context( handle, context, &self, IMAGE_FILE_MACHINE_I386 );\n'
    '        if (ret || !self) return ret;'
)
i386_new = (
    '        NTSTATUS ret = set_thread_context( handle, context, &self, IMAGE_FILE_MACHINE_I386 );\n'
    '#ifdef __APPLE__\n'
    '        /* CW HACK 22131 */\n'
    '        if ((flags & CONTEXT_I386_DEBUG_REGISTERS) && (ret == STATUS_UNSUCCESSFUL))\n'
    '        {\n'
    '            WARN_(seh)( "Setting debug registers is not supported under Rosetta, faking success\\n" );\n'
    '            ret = STATUS_SUCCESS;\n'
    '        }\n'
    '#endif\n'
    '        if (ret || !self) return ret;'
)
if i386_old not in s:
    print("ERROR: I386 anchor not found")
    sys.exit(1)
s = s.replace(i386_old, i386_new, 1)

with open(path, "w") as f:
    f.write(s)
print("CW 22131 applied to both NtSetContextThread variants")
