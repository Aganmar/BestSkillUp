"""Compares two generated BestSkillUp data files (e.g. the shipped one and one rebuilt from a fresh export).

    python3 Tools/diff_data.py <old Data_X.lua> <new Data_X.lua>

Prints recipes added and removed, and for recipes in both: changed output, amount made, colour thresholds
(orange/yellow/green/grey), source and reagents. Mining smelts are compared too.
"""
import re, sys

LINE = re.compile(r'^\s*\[(\d+)\]=\{"((?:[^"\\]|\\.)*)",(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),"(\w+)",\{([\d,]*)\}\},\s*$')


def load(path):
    out, section = {}, None
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if s in ("recipes = {", "mining = {", "items = {", "vendor = {"):
            section = s.split()[0]
            continue
        m = LINE.match(line)
        if m and section in ("recipes", "mining"):
            g = m.groups()
            reag = [int(x) for x in g[10].split(",") if x]
            out[(section, int(g[0]))] = {
                "name": g[1], "out": int(g[2]), "made": (int(g[3]), int(g[4])),
                "colours": tuple(int(x) for x in g[5:9]), "source": g[9],
                "reagents": dict(zip(reag[::2], reag[1::2])),
            }
    return out


def main(old_path, new_path):
    old, new = load(old_path), load(new_path)
    added = sorted(k for k in new if k not in old)
    removed = sorted(k for k in old if k not in new)
    changed = []
    for k in sorted(set(old) & set(new)):
        a, b, diffs = old[k], new[k], []
        for field in ("name", "out", "made", "colours", "source", "reagents"):
            if a[field] != b[field]:
                diffs.append(f"{field}: {a[field]} -> {b[field]}")
        if diffs:
            changed.append((k, b["name"], diffs))
    print(f"{len(old)} -> {len(new)} entries: {len(added)} added, {len(removed)} removed, {len(changed)} changed\n")
    for title, keys, src in (("Added", added, new), ("Removed", removed, old)):
        if keys:
            print(f"{title}:")
            for k in keys:
                r = src[k]
                print(f"  {k[1]} {r['name']} ({k[0]}) colours {r['colours']} source {r['source']}")
            print()
    if changed:
        print("Changed:")
        for k, name, diffs in changed:
            print(f"  {k[1]} {name} ({k[0]})")
            for d in diffs:
                print(f"      {d}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
