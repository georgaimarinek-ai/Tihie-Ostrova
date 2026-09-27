#!/usr/bin/env python3
"""Progression time model: how long does it take to light each beacon?

Usage:
  python3 tools/progression_sim.py              table for all three modes
  python3 tools/progression_sim.py --detail b06 breakdown of one beacon
  python3 tools/progression_sim.py --check      exit code 1 if a target in content/balance.json is missed

Model (docs/03_BALANCE.md §2): a player who knows what they need. For each beacon, starting from
the state after the previous one, it gathers raw materials, crafts, builds the first station of each
kind and the boat the region needs, then sails to the beacon and passes the trial / fight.
Gathering time = quantity / (rate x tool speed). Travel = round trips to each region it gathers in,
plus landing overhead. Leftovers are thrown away (the estimate errs on the slow side).
Home building beyond required stations is NOT counted: that is the player's free time.
"""
import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    with open(ROOT / "content" / f"{name}.json", encoding="utf-8") as f:
        return json.load(f)


class Model:
    def __init__(self):
        self.items = {i["id"]: i for i in load("items")["items"]}
        self.tool_speed = load("items")["tool_speed"]
        self.recipes = load("recipes")["recipes"]
        self.pieces = {p["id"]: p for p in load("buildables")["pieces"]}
        self.boats = {b["id"]: b for b in load("boats")["boats"]}
        self.regions = {r["id"]: r for r in load("regions")["regions"]}
        bj = load("beacons")
        self.beacons = bj["beacons"]
        self.trials = bj["trial_types"]
        self.bal = load("balance")
        self.by_output = {}
        for r in self.recipes:
            for out in r["output"]:
                self.by_output.setdefault(out, []).append(r)
        # state
        self.unlocked = {"start"}
        self.open_regions = {rid for rid, r in self.regions.items() if r["opened_by"] == "start"}
        self.tools = set()
        self.built = set()
        self.boat = "karbas"

    # -- helpers
    def best_tool_tier(self, ttype):
        tiers = [self.items[t]["tool"]["tier"] for t in self.tools if self.items[t]["tool"]["type"] == ttype]
        return max(tiers) if tiers else 0

    def recipe_for(self, item):
        rs = [r for r in self.by_output.get(item, []) if r["unlock"] in self.unlocked]
        return rs[0] if rs else None

    def tool_item_for(self, ttype, tier):
        cands = [i for i in self.items.values() if i.get("tool") and i["tool"]["type"] == ttype and i["tool"]["tier"] >= tier and self.recipe_for(i["id"])]
        cands.sort(key=lambda i: i["tool"]["tier"])
        return cands[0]["id"] if cands else None

    def gather_region(self, item):
        g = self.items[item]["gather"]
        opened = [rid for rid in ["r1", "r2", "r3", "r4"] if rid in self.open_regions and item in self.regions[rid]["resources"]]
        if not opened:
            raise RuntimeError(f"{item}: no open region provides it")
        return opened[0]

    # -- the expansion
    def need(self, item, qty, acc):
        it = self.items[item]
        if it["kind"] == "tool" and item in self.tools:
            return
        g = it.get("gather")
        if g:
            if g["tool"] != "hand":
                need_tier = g.get("tool_tier", 1)
                if self.best_tool_tier(g["tool"]) < need_tier:
                    tool = self.tool_item_for(g["tool"], need_tier)
                    if not tool:
                        raise RuntimeError(f"no tool {g['tool']} t{need_tier} for {item}")
                    self.need(tool, 1, acc)
                tier = self.best_tool_tier(g["tool"])
                speed = self.tool_speed[str(tier)]
            else:
                speed = self.tool_speed["hand"]
            minutes = qty / (g["rate"] * speed)
            acc["gather"] += minutes
            acc["raw"][item] = acc["raw"].get(item, 0) + qty
            acc["regions"].add(self.gather_region(item))
            return
        if it.get("source"):
            src = it["source"]
            self.ensure_piece(src, acc)
            per = self.pieces[src]["produces"]
            acc["passive"] += qty * per["every_min"] / 3  # three animals in the pen
            return
        r = self.recipe_for(item)
        if not r:
            raise RuntimeError(f"{item}: no unlocked recipe")
        if r["station"] != "hand":
            self.ensure_piece(r["station"], acc)
        crafts = math.ceil(qty / r["output"][item])
        for k, v in r["inputs"].items():
            self.need(k, v * crafts, acc)
        sim = self.bal["sim"]
        share = sim["background_active_share"] if r["time_s"] >= sim["background_craft_min_s"] else 1.0
        acc["craft"] += crafts * r["time_s"] / 60 * share  # long station crafts run in the background
        acc["background"] += crafts * r["time_s"] / 60 * (1 - share)
        if it["kind"] == "tool":
            self.tools.add(item)

    def ensure_piece(self, pid, acc):
        if pid in self.built:
            return
        p = self.pieces[pid]
        if p["unlock"] not in self.unlocked:
            raise RuntimeError(f"piece {pid} is locked")
        self.built.add(pid)
        acc["built"].append(pid)
        for k, v in p["cost"].items():
            self.need(k, v, acc)
        acc["craft"] += 1.0  # placing a station

    def speed(self):
        return self.boats[self.boat]["speed"]

    def step(self, b, mode):
        s = self.bal["sim"]
        acc = {"gather": 0.0, "craft": 0.0, "travel": 0.0, "trial": 0.0, "upkeep": s["home_upkeep_min"], "passive": 0.0, "background": 0.0,
               "raw": {}, "regions": set(), "built": []}
        # the first evening: a small izba (typical, not required)
        if b["id"] == self.beacons[0]["id"]:
            for pid, n in s["starter_home"].items():
                if self.pieces[pid].get("station"):
                    self.ensure_piece(pid, acc)
                else:
                    for k, v in self.pieces[pid]["cost"].items():
                        self.need(k, v * n, acc)
                    acc["craft"] += 0.3 * n
            acc["built"].append("izba")
        # tool upgrades as soon as they are craftable
        for t in s["tool_upgrades"]:
            if t not in self.tools and self.recipe_for(t):
                self.need(t, 1, acc)
        need_boat = self.regions[b["region"]]["boat_required"]
        if need_boat != self.boat and self.boats[need_boat]["speed"] and need_boat != "karbas":
            order = ["karbas", "shnyaka", "koch"]
            if order.index(need_boat) > order.index(self.boat):
                bt = self.boats[need_boat]
                self.ensure_piece(bt["station"], acc)
                for k, v in bt["cost"].items():
                    self.need(k, v, acc)
                acc["craft"] += 5
                acc["built"].append(need_boat)
                self.boat = need_boat
        for k, v in b["fuel"].items():
            self.need(k, v, acc)
        # travel: gather trips + beacon trip
        for rid in acc["regions"]:
            d = s["gather_distance_m"][rid]
            acc["travel"] += 2 * d / self.speed() / 60 + s["landing_overhead_min"]
        dist = math.hypot(*b["pos"])
        acc["travel"] += 2 * dist / self.speed() / 60 + s["beacon_overhead_min"]
        # trial / fight
        base = self.trials[b["trial"]]["minutes"]
        if mode == "quiet":
            acc["trial"] = base * s["quiet_trial_factor"]
        elif mode == "tale":
            acc["trial"] = base + s["tale_extra_min"]
        else:
            if b["saga"]["type"] == "guardian":
                acc["trial"] = s["saga_fight_min"][b["saga"]["id"]] + s["saga_defense_prep_min"]
            else:
                acc["trial"] = b["saga"]["seconds"] / 60 + s["saga_defense_prep_min"]
        acc["total"] = acc["gather"] + acc["craft"] + acc["travel"] + acc["trial"] + acc["upkeep"]
        # unlock
        self.unlocked.add(b["id"])
        if b["opens"]:
            self.open_regions.add(b["opens"])
        return acc


def run(mode):
    m = Model()
    rows = []
    for b in m.beacons:
        rows.append((b, m.step(b, mode)))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--detail")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    bal = load("balance")
    by_region = bal["targets"]["beacon_minutes_by_region"]
    tlo, thi = bal["targets"]["total_hours_quiet"]
    results = {mode: run(mode) for mode in ["quiet", "tale", "saga"]}
    if args.detail:
        for b, a in results["quiet"]:
            if b["id"] == args.detail:
                print(f"{b['id']} {b['name']['ru']} (quiet)")
                for k in ["gather", "craft", "travel", "trial", "upkeep", "total"]:
                    print(f"  {k:7s} {a[k]:6.1f} min")
                print("  raw:", ", ".join(f"{k} {v}" for k, v in sorted(a["raw"].items())))
                print("  built:", ", ".join(a["built"]) or "-")
                print("  regions:", ", ".join(sorted(a["regions"])))
                if a["background"]:
                    print(f"  background crafting (kilns, bloomery, salt works): {a['background']:.0f} min")
                if a["passive"]:
                    print(f"  passive (sheep pen, runs in the background): {a['passive']:.0f} min")
        return
    print("Progression model — minutes per beacon (see docs/03_BALANCE.md §2)")
    print(f"{'beacon':<24}{'gather':>7}{'craft':>7}{'travel':>7}{'trial':>7}{'quiet':>7}{'tale':>7}{'saga':>7}  built")
    cum = {"quiet": 0.0, "tale": 0.0, "saga": 0.0}
    bad = []
    for i, (b, a) in enumerate(results["quiet"]):
        t = results["tale"][i][1]["total"]
        s = results["saga"][i][1]["total"]
        cum["quiet"] += a["total"]
        cum["tale"] += t
        cum["saga"] += s
        name = f"{b['id']} {b['name']['ru']}"
        print(f"{name:<24}{a['gather']:7.0f}{a['craft']:7.0f}{a['travel']:7.0f}{a['trial']:7.0f}{a['total']:7.0f}{t:7.0f}{s:7.0f}  {', '.join(a['built'])}")
        lo, hi = by_region[b["region"]]
        if not (lo <= a["total"] <= hi):
            bad.append(f"{b['id']}: {a['total']:.0f} min outside {lo}-{hi}")
    print(f"{'total, hours':<24}{'':>28}{cum['quiet'] / 60:7.1f}{cum['tale'] / 60:7.1f}{cum['saga'] / 60:7.1f}")
    ev = bal["targets"]["evening_session_min"]
    print(f"evenings of {ev} min (quiet): {cum['quiet'] / ev:.1f}")
    if not (tlo <= cum["quiet"] / 60 <= thi):
        bad.append(f"total quiet {cum['quiet'] / 60:.1f} h outside {tlo}-{thi} h")
    if args.check:
        if bad:
            print("targets missed:\n  " + "\n  ".join(bad))
            sys.exit(1)
        print("targets OK")


if __name__ == "__main__":
    main()
