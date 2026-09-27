#!/usr/bin/env python3
"""Validate content/*.json: ids, references and progression reachability.

Usage: python3 tools/validate_content.py        (exit code 1 on errors)

Mirrors ContentDB.validate() in src/core/content_db.gd. If you change a rule here,
change it there too (tests/test_content.gd runs the Godot side).
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content"


def load():
    data = {}
    for name in ["items", "recipes", "buildables", "boats", "regions", "beacons", "creatures", "modes", "balance"]:
        with open(CONTENT / f"{name}.json", encoding="utf-8") as f:
            data[name] = json.load(f)
    return data


def index(rows, what, errors):
    out = {}
    for r in rows:
        rid = r.get("id")
        if not rid:
            errors.append(f"{what}: row without id: {r}")
            continue
        if rid in out:
            errors.append(f"{what}: duplicate id '{rid}'")
        out[rid] = r
    return out


def validate(data):
    errors, warnings = [], []
    items = index(data["items"]["items"], "items", errors)
    recipes = index(data["recipes"]["recipes"], "recipes", errors)
    pieces = index(data["buildables"]["pieces"], "buildables", errors)
    boats = index(data["boats"]["boats"], "boats", errors)
    regions = index(data["regions"]["regions"], "regions", errors)
    beacons = index(data["beacons"]["beacons"], "beacons", errors)
    creatures = index(data["creatures"]["creatures"], "creatures", errors)
    modes = index(data["modes"]["modes"], "modes", errors)
    trials = data["beacons"]["trial_types"]
    unlocks = {"start"} | set(beacons)
    stations = {pid for pid, p in pieces.items() if p.get("station")}
    tool_types = {}
    for iid, it in items.items():
        if it.get("tool"):
            tool_types.setdefault(it["tool"]["type"], []).append(it["tool"]["tier"])
        for lang in ("ru", "en"):
            if not it.get("name", {}).get(lang):
                errors.append(f"item {iid}: missing name.{lang}")

    def check_bag(bag, where):
        for k, v in bag.items():
            if k not in items:
                errors.append(f"{where}: unknown item '{k}'")
            if not (isinstance(v, (int, float)) and v > 0 and float(v).is_integer()):
                errors.append(f"{where}: quantity of '{k}' must be a positive integer, got {v}")

    # recipes
    produced_by = {}
    for rid, r in recipes.items():
        if r["station"] != "hand" and r["station"] not in stations:
            errors.append(f"recipe {rid}: station '{r['station']}' is not a station piece")
        if r["unlock"] not in unlocks:
            errors.append(f"recipe {rid}: unlock '{r['unlock']}' unknown")
        check_bag(r["inputs"], f"recipe {rid} inputs")
        check_bag(r["output"], f"recipe {rid} output")
        for out in r["output"]:
            produced_by.setdefault(out, []).append(rid)
        if r.get("time_s", 0) <= 0:
            errors.append(f"recipe {rid}: time_s must be > 0")

    # items: every item must be obtainable
    for iid, it in items.items():
        g = it.get("gather")
        if g:
            if g["tool"] != "hand" and g["tool"] not in tool_types:
                errors.append(f"item {iid}: gather tool '{g['tool']}' has no tool item")
            if g.get("tool_tier") and max(tool_types.get(g["tool"], [0])) < g["tool_tier"]:
                errors.append(f"item {iid}: needs {g['tool']} tier {g['tool_tier']}, none exists")
            if g["region"] not in regions:
                errors.append(f"item {iid}: gather region '{g['region']}' unknown")
            if g["rate"] <= 0:
                errors.append(f"item {iid}: gather rate must be > 0")
        elif it.get("source"):
            if it["source"] not in pieces:
                errors.append(f"item {iid}: source '{it['source']}' is not a piece")
        elif iid not in produced_by:
            errors.append(f"item {iid}: no gather, source or recipe produces it")

    # pieces and boats
    for pid, p in pieces.items():
        check_bag(p["cost"], f"piece {pid} cost")
        if p["unlock"] not in unlocks:
            errors.append(f"piece {pid}: unlock '{p['unlock']}' unknown")
        if p.get("produces"):
            for k in p["produces"]:
                if k != "every_min" and k not in items:
                    errors.append(f"piece {pid}: produces unknown item '{k}'")
        if p.get("grows") and p["grows"] not in items:
            errors.append(f"piece {pid}: grows unknown item '{p['grows']}'")
    for bid, b in boats.items():
        check_bag(b["cost"], f"boat {bid} cost")
        if b["unlock"] not in unlocks:
            errors.append(f"boat {bid}: unlock '{b['unlock']}' unknown")
        if b["station"] is not None and b["station"] not in stations:
            errors.append(f"boat {bid}: station '{b['station']}' is not a station")

    # regions
    for gid, g in regions.items():
        if g["opened_by"] not in unlocks:
            errors.append(f"region {gid}: opened_by '{g['opened_by']}' unknown")
        if g["boat_required"] not in boats:
            errors.append(f"region {gid}: boat '{g['boat_required']}' unknown")
        for r in g["resources"]:
            if r not in items:
                errors.append(f"region {gid}: resource '{r}' unknown")
        for c in g["creatures"]:
            if c not in creatures:
                errors.append(f"region {gid}: creature '{c}' unknown")
    for iid, it in items.items():
        g = it.get("gather")
        if g and g["region"] in regions and iid not in regions[g["region"]]["resources"]:
            errors.append(f"item {iid}: first region {g['region']} does not list it in resources")

    # beacons
    order = list(beacons)
    if order != sorted(order):
        errors.append("beacons: ids must be listed in order")
    guardians = {cid: c for cid, c in creatures.items() if c["group"] == "guardian"}
    for bid, b in beacons.items():
        reg = regions.get(b["region"])
        if not reg:
            errors.append(f"beacon {bid}: region '{b['region']}' unknown")
            continue
        d = math.hypot(*b["pos"])
        lo, hi = reg["ring_m"]
        if not (lo <= d <= hi):
            errors.append(f"beacon {bid}: distance {d:.0f} m outside region ring {lo}-{hi}")
        check_bag(b["fuel"], f"beacon {bid} fuel")
        if b["trial"] not in trials:
            errors.append(f"beacon {bid}: trial '{b['trial']}' unknown")
        s = b["saga"]
        if s["type"] == "guardian":
            g = guardians.get(s["id"])
            if not g:
                errors.append(f"beacon {bid}: guardian '{s['id']}' unknown")
            elif g.get("beacon") != bid:
                errors.append(f"beacon {bid}: guardian '{s['id']}' belongs to {g.get('beacon')}")
        elif s["type"] == "defense":
            if s.get("seconds", 0) <= 0:
                errors.append(f"beacon {bid}: defense needs seconds > 0")
        else:
            errors.append(f"beacon {bid}: saga type '{s['type']}' unknown")
        if b["opens"] is not None and b["opens"] not in regions:
            errors.append(f"beacon {bid}: opens unknown region '{b['opens']}'")
    for cid, c in creatures.items():
        if c.get("gift") and c["gift"] not in items:
            errors.append(f"creature {cid}: gift '{c['gift']}' is not an item")
        for k in c.get("drops", {}):
            if k not in items:
                errors.append(f"creature {cid}: drop '{k}' is not an item")
        for m in c["modes"]:
            if m not in modes:
                errors.append(f"creature {cid}: mode '{m}' unknown")
    if data["modes"]["default"] not in modes:
        errors.append("modes: default mode unknown")

    if errors:
        return errors, warnings

    # progression: before lighting beacon k, its fuel and the boat for its region must be obtainable
    def obtainable(unlocked, open_regions):
        have = set()
        built = set()
        changed = True
        while changed:
            changed = False
            for iid, it in items.items():
                if iid in have:
                    continue
                g = it.get("gather")
                if g and any(iid in regions[r]["resources"] for r in open_regions):
                    tool_ok = g["tool"] == "hand" or any(
                        items[t]["tool"]["type"] == g["tool"] and items[t]["tool"]["tier"] >= g.get("tool_tier", 1)
                        for t in have if items[t].get("tool"))
                    if tool_ok:
                        have.add(iid)
                        changed = True
            for pid, p in pieces.items():
                if pid not in built and p["unlock"] in unlocked and all(k in have for k in p["cost"]):
                    built.add(pid)
                    changed = True
                    for k in p.get("produces", {}):
                        if k in items and k not in have:
                            have.add(k)
            for rid, r in recipes.items():
                if r["unlock"] in unlocked and (r["station"] == "hand" or r["station"] in built) \
                        and all(k in have for k in r["inputs"]):
                    for out in r["output"]:
                        if out not in have:
                            have.add(out)
                            changed = True
        boats_ok = {bid for bid, b in boats.items() if b["unlock"] in unlocked and
                    (b["station"] is None or b["station"] in built) and all(k in have for k in b["cost"])}
        return have, built, boats_ok

    unlocked = {"start"}
    open_regions = {gid for gid, g in regions.items() if g["opened_by"] == "start"}
    for bid in order:
        b = beacons[bid]
        have, built, boats_ok = obtainable(unlocked, open_regions)
        if b["region"] not in open_regions:
            errors.append(f"progression: {bid} is in region {b['region']}, which is not open yet")
        for k in b["fuel"]:
            if k not in have:
                errors.append(f"progression: fuel '{k}' for {bid} is not obtainable yet")
        need_boat = regions[b["region"]]["boat_required"]
        if need_boat not in boats_ok:
            errors.append(f"progression: boat '{need_boat}' for {bid} is not buildable yet")
        unlocked.add(bid)
        if b["opens"]:
            open_regions.add(b["opens"])
    have, built, boats_ok = obtainable(unlocked, open_regions)
    for rid, r in recipes.items():
        if not all(o in have for o in r["output"]):
            warnings.append(f"recipe {rid} can never be crafted")
    for pid in pieces:
        if pid not in built:
            warnings.append(f"piece {pid} can never be built")
    return errors, warnings


def main():
    data = load()
    errors, warnings = validate(data)
    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("error:", e)
    if errors:
        print(f"content: {len(errors)} error(s)")
        sys.exit(1)
    counts = ", ".join(f"{len(data[k][f])} {f}" for k, f in [("items", "items"), ("recipes", "recipes"), ("buildables", "pieces"), ("boats", "boats"), ("regions", "regions"), ("beacons", "beacons"), ("creatures", "creatures"), ("modes", "modes")])
    print(f"content OK: {counts}")


if __name__ == "__main__":
    main()
