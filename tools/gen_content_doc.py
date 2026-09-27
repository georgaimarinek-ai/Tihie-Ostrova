#!/usr/bin/env python3
"""Generate docs/02_CONTENT.md from content/*.json (the JSON is the source of truth).

Usage: python3 tools/gen_content_doc.py          write the file
       python3 tools/gen_content_doc.py --check  exit code 1 if the file is out of date
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "02_CONTENT.md"


def load(name):
    with open(ROOT / "content" / f"{name}.json", encoding="utf-8") as f:
        return json.load(f)


def bag(d, items):
    return ", ".join(f"{items[k]['name']['ru']} ×{v}" for k, v in d.items()) or "—"


def unlock(u, beacons):
    return "с начала" if u == "start" else f"{u} «{beacons[u]['name']['ru']}»"


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out)


def build():
    items = {i["id"]: i for i in load("items")["items"]}
    recipes = load("recipes")["recipes"]
    pieces = {p["id"]: p for p in load("buildables")["pieces"]}
    boats = load("boats")["boats"]
    reg = load("regions")
    regions = reg["regions"]
    bj = load("beacons")
    beacons = {b["id"]: b for b in bj["beacons"]}
    creatures = load("creatures")["creatures"]
    modes = load("modes")
    name = lambda i: items[i]["name"]["ru"]
    L = ["# 02. Контент", "", "> Сгенерировано из `content/*.json` командой `python3 tools/gen_content_doc.py`. Не редактируй вручную: меняй JSON и перегенерируй.", ""]

    L += ["## 1. Режимы мира", ""]
    rows = []
    for m in modes["modes"]:
        r = m["rules"]
        rows.append([f"**{m['name']['ru']}** (`{m['id']}`)", m["summary"]["ru"], "да" if r["predators"] else "нет", "да" if r["fog_creatures"] else "нет", "бой" if r["guardians"] else "испытание", r["death"], r["storms"], r["cold"]])
    L += [table(["Режим", "Суть", "Хищники", "Туманные твари", "Маяк", "Смерть", "Шторма", "Холод"], rows), ""]

    L += ["## 2. Регионы", ""]
    rows = [[f"**{g['name']['ru']}** (`{g['id']}`)", f"{g['ring_m'][0]}–{g['ring_m'][1]} м", unlock(g["opened_by"], beacons), g["boat_required"], g["chapter"]["name"]["ru"], g["fog"]["density"], ", ".join(name(i) for i in g["resources"])] for g in regions]
    L += [table(["Регион", "Кольцо", "Открывает", "Лодка", "Глава погоды", "Туман", "Ресурсы"], rows), ""]

    L += ["## 3. Маяки", ""]
    rows = []
    for b in bj["beacons"]:
        s = b["saga"]
        saga = f"страж `{s['id']}`" if s["type"] == "guardian" else f"оборона огня {s['seconds']} с"
        rows.append([f"`{b['id']}` {b['name']['ru']}", b["region"], f"({b['pos'][0]}, {b['pos'][1]})", bag(b["fuel"], items), bj["trial_types"][b["trial"]]["ru"], saga, f"{b['clear_radius']} м", b["opens"] or "—"])
    L += [table(["Маяк", "Регион", "Место, м", "Топливо", "Испытание (Тихий/Сказание)", "Сага", "Просвет", "Открывает"], rows), ""]

    L += ["## 4. Предметы", ""]
    rows = []
    for i in items.values():
        extra = []
        if i.get("gather"):
            g = i["gather"]
            extra.append(f"сбор {g['rate']}/мин, {g['tool']}{' t' + str(g['tool_tier']) if g.get('tool_tier') else ''}, {g['region']}")
        if i.get("food"):
            f = i["food"]
            extra.append(f"еда: +{f['hp']} здоровья, +{f['stamina']} выносл., {f['minutes']} мин")
        if i.get("tool"):
            extra.append(f"инструмент {i['tool']['type']} t{i['tool']['tier']}")
        if i.get("light"):
            extra.append(f"свет: туман −{i['light']['fog_radius']} м")
        if i.get("weapon"):
            extra.append(f"урон {i['weapon']['damage']}")
        if i.get("source"):
            extra.append(f"даёт: {i['source']}")
        rows.append([f"{i['name']['ru']} (`{i['id']}`)", i["kind"], i["tier"], i["stack"], "; ".join(extra) or "—"])
    L += [table(["Предмет", "Вид", "Ярус", "Стопка", "Детали"], rows), ""]

    L += ["## 5. Рецепты", ""]
    by_station = {}
    for r in recipes:
        by_station.setdefault(r["station"], []).append(r)
    for st, rs in by_station.items():
        title = "Руками" if st == "hand" else pieces[st]["name"]["ru"]
        L += [f"### {title}", ""]
        L += [table(["Результат", "Из чего", "Время", "Открывается"], [[bag(r["output"], items), bag(r["inputs"], items), f"{r['time_s']} с", unlock(r["unlock"], beacons)] for r in rs]), ""]

    L += ["## 6. Постройки", ""]
    rows = []
    for p in pieces.values():
        extra = []
        if p.get("station"):
            extra.append("станция")
        if p.get("comfort"):
            extra.append(f"уют +{p['comfort']}")
        if p.get("fog_radius"):
            extra.append(f"туман −{p['fog_radius']} м")
        if p.get("marker"):
            extra.append("знак на карте")
        if p.get("produces"):
            extra.append(f"даёт шерсть раз в {p['produces']['every_min']} мин")
        rows.append([f"{p['name']['ru']} (`{p['id']}`)", p["category"], bag(p["cost"], items), unlock(p["unlock"], beacons), ", ".join(extra) or "—"])
    L += [table(["Постройка", "Тип", "Стоимость", "Открывается", "Свойства"], rows), ""]

    L += ["## 7. Лодки", ""]
    L += [table(["Лодка", "Экипаж", "Трюм", "Скорость", "Шторм", "Лёд", "Стоимость", "Открывается"], [[b["name"]["ru"], b["crew"], b["cargo_slots"], f"{b['speed']} м/с", b["storm"], "да" if b["ice"] else "нет", bag(b["cost"], items), unlock(b["unlock"], beacons)] for b in boats]), ""]

    L += ["## 8. Существа", ""]
    def extra(c):
        parts = [c.get("appears"), c.get("special"), c.get("rule") and "rule: " + c["rule"], c.get("boon") and "boon: " + c["boon"], c.get("gift") and "gift: " + items[c["gift"]]["name"]["ru"]]
        return "; ".join(p for p in parts if p) or "—"
    groups = {"animal": "звери", "predator": "хищники", "spirit": "духи", "wonder": "чудо", "legend": "предание", "fog": "туманные твари", "elite": "сильные (Сага)", "guardian": "стражи"}
    rows = [[f"{c['name']['ru']} (`{c['id']}`)", groups.get(c["group"], c["group"]), c["behaviour"], c["hp"] or "—", c["damage"] or "—", ", ".join(c["modes"]), extra(c)] for c in creatures]
    L += [table(["Существо", "Группа", "Поведение", "Здоровье", "Урон", "Режимы", "Особое"], rows), ""]
    return "\n".join(L)


def main():
    text = build()
    if "--check" in sys.argv:
        cur = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if cur != text:
            print("docs/02_CONTENT.md is out of date: run python3 tools/gen_content_doc.py")
            sys.exit(1)
        print("docs/02_CONTENT.md is up to date")
        return
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(text, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(text) // 1024} KB)")


if __name__ == "__main__":
    main()
