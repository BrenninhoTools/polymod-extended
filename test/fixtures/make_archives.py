import json
import os
import struct
import sys
import zipfile
import zlib


def vint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def rar5_block(data):
    size = vint(len(data))
    return struct.pack("<I", zlib.crc32(size + data) & 0xFFFFFFFF) + size + data


def rar5_file(name, content, method=0):
    if content is None:
        data = vint(2) + vint(2) + vint(0) + vint(1) + vint(0) + vint(0x10) + vint(0) + vint(0) + vint(len(name)) + name
        return rar5_block(data)
    data = (
        vint(2) + vint(2) + vint(len(content)) + vint(4) + vint(len(content)) + vint(0x20)
        + struct.pack("<I", zlib.crc32(content) & 0xFFFFFFFF)
        + vint(method << 7) + vint(0) + vint(len(name)) + name
    )
    return rar5_block(data) + content


def make_rar5(path, files, method=0):
    out = bytearray(b"Rar!\x1a\x07\x01\x00")
    out += rar5_block(vint(1) + vint(0) + vint(0))
    for name, content in files:
        out += rar5_file(name.encode("utf-8"), content, method)
    out += rar5_block(vint(5) + vint(0) + vint(0))
    with open(path, "wb") as handle:
        handle.write(out)


def rar4_block(head_type, flags, body):
    size = 7 + len(body)
    rest = struct.pack("<BHH", head_type, flags, size) + body
    return struct.pack("<H", zlib.crc32(rest) & 0xFFFF) + rest


def make_rar4(path, files):
    out = bytearray(b"Rar!\x1a\x07\x00")
    out += rar4_block(0x73, 0, struct.pack("<HI", 0, 0))
    for name, content in files:
        raw = name.replace("/", "\\").encode("latin-1")
        if content is None:
            body = struct.pack("<IIBIIBBHI", 0, 0, 2, 0, 0, 29, 0x30, len(raw), 0x10) + raw
            out += rar4_block(0x74, 0x8000 | 0xE0, body)
        else:
            crc = zlib.crc32(content) & 0xFFFFFFFF
            body = struct.pack("<IIBIIBBHI", len(content), len(content), 2, crc, 0, 29, 0x30, len(raw), 0x20) + raw
            out += rar4_block(0x74, 0x8000, body) + content
    out += rar4_block(0x7B, 0x4000, b"")
    with open(path, "wb") as handle:
        handle.write(out)


def meta(mod_id, title, extra=None):
    data = {
        "id": mod_id,
        "title": title,
        "description": "Sample archive mod used by the test suite",
        "author": "BrenninhoTools",
        "api_version": "0.1.0",
        "mod_version": "1.0.0",
        "license": "MIT",
    }
    if extra:
        data.update(extra)
    return json.dumps(data, indent=2).encode("utf-8")


def info(name):
    return json.dumps({"name": name}).encode("utf-8")


def main(target):
    os.makedirs(target, exist_ok=True)

    with zipfile.ZipFile(os.path.join(target, "zip_mod.zip"), "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("zip_mod_folder/", "")
        archive.writestr("zip_mod_folder/_polymod_meta.json", meta("zip_mod", "Zip Mod"))
        archive.writestr("zip_mod_folder/data/info.json", info("zip"))
        archive.writestr("zip_mod_folder/data/big.txt", ("polymod-extended " * 4000).encode("utf-8"))
        archive.writestr("__MACOSX/zip_mod_folder/._data", b"junk")

    make_rar5(os.path.join(target, "rar5_mod.rar"), [
        ("_polymod_meta.json", meta("rar5_mod", "Rar5 Mod")),
        ("data", None),
        ("data/info.json", info("rar5")),
        ("data/ação.txt", "unicode name".encode("utf-8")),
    ])

    make_rar4(os.path.join(target, "rar4_mod.rar"), [
        ("_polymod_meta.json", meta("rar4_mod", "Rar4 Mod")),
        ("data", None),
        ("data/info.json", info("rar4")),
    ])

    make_rar5(os.path.join(target, "compressed_mod.rar"), [
        ("_polymod_meta.json", meta("compressed_mod", "Compressed Mod")),
    ], method=3)

    with zipfile.ZipFile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "memory_mod.zip"), "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("_polymod_meta.json", meta("memory_mod", "Memory Mod"))
        archive.writestr("data/info.json", info("memory"))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "mods"))
