---
name: atmosphere-reference
description: Match the look and feel of the browser sketch (fog, light, camera, landing, torch, music layers) when building scenes in Godot. Use when working on the sea, boat, player camera, fog, beacons, VFX or music.
---

# Набросок как эталон ощущений

Набросок `reference/sketch/` — это играбельный прототип на three.js. Правила игры берутся из `docs/`, а **ощущения и числа камеры, тумана и света** — отсюда.

## Где что в `reference/sketch/src/main.js`
| Что | Функция или константа | Числа |
|---|---|---|
| Палитры глав | `PAL` | совпадают с `regions.json → chapter` |
| Туман с просветами | `patchFog`, `FOG_CLEAR_GLSL` | коэффициент 0,22 в центре, край smoothstep(0,3r, r) |
| Туман гуще на тёмном острове | `fogBoost` в `frame()` | ×2,3 пешком на острове с незажжённым маяком |
| Волны | `WAVE_GLSL`, `wave()` | = `Waves.PARAMS` |
| Лодка | блок «boat» в `frame()` | 9 м/с, разгон 0,7 с⁻¹, поворот 0,35–0,85 рад/с |
| Камера лодки | `desiredCam()` (ветка boat) | 15 м, высота 3 + pitch·12, над сушей +7,5 |
| Высадка | `findLanding()`, `disembark()`, `board()` | земля в 2–14 м, уклон < 1,3; сесть можно после 5 м пути |
| Пешком | `updateFoot()` | 4,2 м/с, бег 7, A/D поворачивают камеру 1,9 рад/с |
| Камера пешком | `desiredCam()` (ветка foot) | 7 м, не заходит в кроны (r·3,2) и в лодку |
| Факел | `makeTorch()`, `BEACONS[0]` | радиус просвета 13, сила 0,92 |
| Зажигание маяка | `lightBeacon()`, `finishLighting()` | камера перпендикулярно солнцу, разгорание 3,5 с |
| Музыка слоями | объект `AU`, `tick()` | слой 0 переборы, 1 аккорды Dm–F–C–G, 2 колокола и хор |

## Как пользоваться
- Открой `reference/sketch/fog-isles-standalone.html` в браузере и пройди его (около 10 минут), прежде чем делать этапы 1, 2 и 5.
- Переноси **числа и порядок действий**, но не код: в Godot архитектура своя (`docs/04_TECH_SPEC.md`).
- Если в Godot получается «не так, как в наброске», сделай скриншот той же сцены в наброске (`window.FOG.teleport`, `FOG.walkTo`) и сравни рядом.
