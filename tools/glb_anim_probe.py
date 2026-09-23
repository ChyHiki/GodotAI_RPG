"""GLB 动画名速查：直接解析 GLB 的 JSON chunk，打印所有 animation / mesh / node 名。

为什么不用 Godot：Godot 导入一次要十几秒，而"这个 GLB 里到底有没有我要的动画"
是一个纯文本问题 —— 直接读 JSON chunk 一秒出结果，能在覆盖 assets 之前先把关。

用法：
  python tools/glb_anim_probe.py <file.glb> [file2.glb ...]
"""
import json
import struct
import sys


def read_glb_json(path):
    """返回 (json_dict, bin_length)。GLB 结构：12 字节头 + chunk(JSON) + chunk(BIN)。"""
    with open(path, "rb") as f:
        data = f.read()
    magic, version, total = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, f"不是 GLB 文件: {path}"
    off = 12
    js = None
    bin_len = 0
    while off < total:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        if ctype == 0x4E4F534A:      # 'JSON'
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:    # 'BIN'
            bin_len = clen
        off += clen
    return js, bin_len


def main():
    for path in sys.argv[1:]:
        js, bin_len = read_glb_json(path)
        anims = [a.get("name", "?") for a in js.get("animations", [])]
        meshes = [m.get("name", "?") for m in js.get("meshes", [])]
        print(f"=== {path}")
        print(f"  bin_chunk : {bin_len} bytes")
        print(f"  meshes({len(meshes)}): {meshes}")
        print(f"  anims ({len(anims)}):")
        for i, a in enumerate(anims):
            print(f"    [{i:2d}] {a}")
        print()


if __name__ == "__main__":
    main()
