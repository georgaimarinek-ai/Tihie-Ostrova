# Модели художника

Клади сюда `.glb` по правилам `docs/05_ART_AUDIO.md` §4:

```
art/models/pieces/<id>.glb      детали стройки (id из content/buildables.json)
art/models/boats/<id>.glb       karbas, shnyaka, koch
art/models/creatures/<id>.glb   звери, духи, твари, стражи (id из content/creatures.json)
art/models/props/<name>.glb     маяк, крест, часовня, пни, камни
art/models/player/pomor.glb     игрок
art/palette.png                 общая палитра 256×256
```

Пока файла нет, игра рисует заглушку. Масштаб 1 = 1 м, плоские грани, анимации с именами из таблицы §4.5. После добавления файлов запусти `tools/verify.sh`.
