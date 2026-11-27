#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Keep the S947B document scanner ABI on Exynos 2100.

ARMv8.2 has STLR but lacks the RCpc2 store-release instruction with an
unscaled immediate offset. Each compatible thunk computes the same address,
stores with release ordering, and resumes at the next original instruction.
"""

from argparse import ArgumentParser
from hashlib import sha256
from pathlib import Path
from struct import Struct, pack_into, unpack_from

ELF_HEADER = Struct("<16sHHIQQQIHHHHHH")
PROGRAM_HEADER = Struct("<IIQQQQQQ")
SECTION_HEADER = Struct("<IIQQQQIIQQ")
WORD = Struct("<I")

PT_LOAD = 1
PT_TLS = 7
PF_X = 1

CAMERA_LIBRARIES = {
    "libSmartScan.camera.samsung.so": (
        "66557f48b9c06f4ae4b6191106e1dea48facbc799c9566e00cafc35fe80c5971",
        (0x1D490, 0x1D4A4, 0x490EC, 0x4929C, 0x492B0,
         0x49768, 0x49780, 0x4978C, 0x49894),
    ),
    "libDocRectifyWrapper.camera.samsung.so": (
        "70188f24410d162ee2423623a282cf6c41f7e6ccd84ccbd343ad5a693a23cf27",
        (0x25C5C, 0x26ECC, 0x272D4, 0x27600, 0x28288, 0x283EC,
         0x28538, 0x285BC, 0x29040, 0x29044, 0x2907C, 0x291C0),
    ),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def branch(address, target):
    delta = target - address
    require(delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27),
            "ARM64 branch is out of range")
    return 0x14000000 | ((delta // 4) & 0x03FFFFFF)


def release_store_thunk(opcode, address, next_insn):
    register_mask = (1 << 10) - 1
    immediate_mask = 0x1FF << 12
    operation = opcode & ~(register_mask | immediate_mask)
    require(operation in (0x19000000, 0x99000000), "Expected STLURB or STLUR W")
    source = opcode & 31
    base = (opcode >> 5) & 31
    immediate = (opcode >> 12) & 0x1FF
    if immediate >= 256:
        immediate -= 512
    require(source != 16 and base not in (16, 31), "Unexpected use of scratch register or SP")

    add_or_sub = 0xD1000000 if immediate < 0 else 0x91000000
    stlr = 0x089FFC00 if operation == 0x19000000 else 0x889FFC00
    return (
        0xA9BF47F0,  # stp x16, x17, [sp, #-16]!
        add_or_sub | (abs(immediate) << 10) | (base << 5) | 16,
        stlr | (16 << 5) | source,
        0xA8C147F0,  # ldp x16, x17, [sp], #16
        branch(address + 16, next_insn),
    )


def patch_library(source, fingerprint, sites):
    require(sha256(source).hexdigest() == fingerprint, "Different S947B library revision")
    header = list(ELF_HEADER.unpack_from(source))
    ident, elf_type, machine, _, _, phoff, shoff, _, _, phsize, phnum, shsize, shnum, _ = header
    require(ident[:6] == b"\x7fELF\x02\x01" and elf_type == 3 and machine == 183,
            "Expected a little-endian AArch64 shared library")
    require(phsize == PROGRAM_HEADER.size and shsize == SECTION_HEADER.size,
            "Unexpected ELF header sizes")
    programs = [list(PROGRAM_HEADER.unpack_from(source, phoff + i * phsize)) for i in range(phnum)]
    sections = [list(SECTION_HEADER.unpack_from(source, shoff + i * shsize)) for i in range(shnum)]
    loads = [p for p in programs if p[0] == PT_LOAD]
    executable = [p for p in loads if p[1] & PF_X]
    require(len(executable) == 1, "Expected one executable load segment")
    rx = executable[0]
    offset, vaddr, filesz, memsz = rx[2], rx[3], rx[5], rx[6]
    cut = offset + filesz
    end = vaddr + memsz
    alignment = max(p[7] for p in loads)
    require(filesz == memsz and alignment == 0x4000 and phoff + phnum * phsize < cut < shoff,
            "Unexpected executable segment layout")
    next_load = min(p[3] for p in loads if p[3] > vaddr)
    require(all(p is rx or p[2] + p[5] <= cut or p[2] >= cut for p in programs),
            "Inserting the thunks would split another file segment")

    # Leave the virtual TLS range alone. Use the remaining gap before the data segment.
    tls_end = max((p[3] + p[6] for p in programs if p[0] == PT_TLS), default=end)
    first_thunk = (max(tls_end, end) + 3) & ~3
    thunk_bytes = first_thunk - end + len(sites) * 20
    require(end + thunk_bytes <= next_load and thunk_bytes < alignment,
            "The thunks do not fit in the executable segment's virtual gap")

    patched = bytearray(source[:cut] + bytes(alignment) + source[cut:])
    for index, site in enumerate(sites):
        require(vaddr <= site < end and site % 4 == 0, "Unsupported instruction outside executable mapping")
        site_offset = offset + site - vaddr
        thunk_addr = first_thunk + 20 * index
        thunk_offset = cut + thunk_addr - end
        (original,) = WORD.unpack_from(source, site_offset)
        pack_into("<5I", patched, thunk_offset, *release_store_thunk(original, thunk_addr, site + 4))
        WORD.pack_into(patched, site_offset, branch(site, thunk_addr))

    rx[5] += thunk_bytes
    rx[6] += thunk_bytes
    for index, program in enumerate(programs):
        if program[2] >= cut:
            program[2] += alignment
        PROGRAM_HEADER.pack_into(patched, phoff + index * phsize, *program)
    for index, section in enumerate(sections):
        if section[4] >= cut:
            section[4] += alignment
        SECTION_HEADER.pack_into(patched, shoff + alignment + index * shsize, *section)
    header[6] = shoff + alignment
    ELF_HEADER.pack_into(patched, 0, *header)
    return patched


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("donor_lib64", type=Path, help="lib64 from the matching S947B system image")
    parser.add_argument("output", type=Path, help="directory for the two compatible libraries")
    options = parser.parse_args()
    options.output.mkdir(parents=True, exist_ok=True)
    for library, (fingerprint, sites) in CAMERA_LIBRARIES.items():
        result = patch_library((options.donor_lib64 / library).read_bytes(), fingerprint, sites)
        (options.output / library).write_bytes(result)


if __name__ == "__main__":
    main()
