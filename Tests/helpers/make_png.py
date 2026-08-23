"""Write a tiny solid-color PNG, for Tests/lib.test.icedit.sh.

Synthesized rather than committed: no binaries in the repository, and the code
below is a readable statement of exactly what the file contains - a square of
one opaque color, which is all any assertion in this suite asks of an image
layer. Written with the standard library's zlib and struct under the SYSTEM
python, so the fixture depends on neither the applet's embedded interpreter nor
any image tool being installed.

usage: make_png.py <path> <size> <red> <green> <blue>
"""

import struct
import sys
import zlib


def chunk(kind, payload):
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def main(argv):
    if len(argv) != 6:
        sys.stderr.write("usage: make_png.py <path> <size> <red> <green> <blue>\n")
        return 2
    path, size = argv[1], int(argv[2])
    red, green, blue = (int(v) for v in argv[3:6])
    # One filter byte (0, "None") per scanline, then size RGB triples.
    row = b"\x00" + bytes([red, green, blue]) * size
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", header))
        f.write(chunk(b"IDAT", zlib.compress(row * size)))
        f.write(chunk(b"IEND", b""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
