---
name: godot-verify
description: Run and read the full project check (content, balance, generated docs, Godot tests, scene smoke, optional screenshot). Use before saying a phase or change is done, or when tests fail.
---

# Проверка проекта «Туманные острова»

1. Найди Godot: переменная `GODOT` или `godot` в PATH. Нужна версия 4.7.x (`$GODOT --version`). Если Godot нет, скажи об этом и остановись: не подменяй проверку чтением кода.
2. Запусти `GODOT=$GODOT tools/verify.sh`. Шаги идут по порядку, первый упавший останавливает скрипт:
   - `content` → смотри `tools/validate_content.py`: ссылки, достижимость маяков;
   - `balance targets` → `python3 tools/progression_sim.py --detail <маяк>`, потом правь `content/*.json`, а не цели;
   - `generated docs` → `python3 tools/gen_content_doc.py`;
   - `godot import` → ошибки разбора скриптов;
   - `unit tests` → читай строки `FAIL`. Один тест: `-- --filter=<имя>`;
   - `main scene smoke` → сцена должна напечатать `SMOKE OK`.
3. Если менялись шейдеры, туман, камера или HUD, сделай скриншот:
   `xvfb-run -a $GODOT --path . --rendering-driver opengl3 -- --screenshot=/tmp/shot.png --light-at=10 --frames=160`
   Посмотри на него и сравни с `docs/images/p0_after.png` или макетом из `docs/mockups/`.
4. В ответе покажи хвост вывода verify (`tests: N, failed: 0`, `SMOKE OK`, `verify: OK`).
