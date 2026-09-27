---
name: content-change
description: Add or change items, recipes, buildables, boats, beacons, creatures, modes or balance numbers in content/*.json safely. Use for any gameplay number or new content entry.
---

# Изменение контента

1. Правь только `content/*.json`. Id — латиница snake_case. Имена обязательны на двух языках: `{"ru": ..., "en": ...}`.
2. Правила связей:
   - станция рецепта — деталь с `"station": true` или `"hand"`;
   - `unlock` — `"start"` или id маяка;
   - всё, что упомянуто (входы, стоимость, топливо, дары, добыча), существует в `items.json`;
   - у нового предмета есть источник: `gather`, `source` или рецепт.
3. Новое существо:
   - `group` из списка animal / predator / spirit / wonder / legend / fog / elite / guardian;
   - духи (spirit / wonder / legend) идут во всех трёх режимах с `damage: 0`;
   - fog / elite / guardian — только `["saga"]`;
   - добавь существо в `creatures` нужных регионов в `regions.json`.
4. Прогони:
   ```
   python3 tools/validate_content.py
   python3 tools/progression_sim.py --check
   python3 tools/gen_content_doc.py
   ```
   Если цели баланса не выполняются, разберись через `--detail <маяк>` и поправь стоимость или скорость сбора. Цели в `balance.json → targets` без обсуждения не трогай.
5. Если изменилось правило (а не просто число), добавь тест в `tests/` и обнови `docs/01_GDD.md`.
6. Обнови таблицы `docs/03_BALANCE.md`, если числа изменились. Добавь запись в `CHANGELOG.md`: что, почему, влияние на время прохождения.
7. В конце `tools/verify.sh` (навык godot-verify).
