# SnowWars — рефакторинг сетевого слоя

Документ фиксирует состояние продолжающегося рефакторинга сетевого слоя: что уже сделано
и какие направления рассматриваются для следующих этапов. Ориентирован на то, чтобы к работе
можно было вернуться без дополнительного контекста — только по коду и этому файлу.

Весь код находится в `src/GodotClientServer` (см. [`docs/index.md`](index.md) для общей
структуры проекта).

## Сделано

### Этап 0 — согласованные пути дерева сцены для адресации RPC

Godot адресует RPC по абсолютному `NodePath`, и вызывающий узел должен существовать по
идентичному пути на принимающей стороне. Поэтому пути дерева сцены для SERVER и CLIENT
режимов приведены к единому каноничному виду `/root/Game/Level` — в каждом процессе живёт
только одно дерево, конфликтов путей нет. Режим LOCAL (сервер и клиент в одном процессе,
без настоящего RPC) сохраняет собственную раздельную структуру из двух корней:
`/root/globalServer/game` (авторитетная часть) и `/root/visual/currentGame` (визуальная часть).

Заспавненные узлы игроков получают детерминированные имена `"Player_%d" % peer_id` на обеих
сторонах — это тоже требование адресации RPC по абсолютному пути.

Файл: `src/GodotClientServer/shared/scripts/net.gd`, функции `_setup_server_game`,
`_setup_client_visual`, `_get_server_game_root`, `_get_visual_game_root`,
`_spawn_authoritative_calculation`, `_ensure_client_view`.

### Этап 1 — движение/интерполяция/спавн вынесены из `Net` в иерархию классов

Раньше `Net` был god-object'ом, отвечавшим и за движение, и за интерполяцию, и за спавн.
Теперь эта логика разнесена по классам:

- **`CalculationBase`** (`shared/scripts/calculation_base.gd`, extends `CharacterBody2D`) —
  абстрактный базовый класс. Хранит `peer_id`, объявляет виртуальные `request_move_state()` и
  `receive_input()`.
- **`CalculationPhysics`** (`shared/scripts/calculation_physics.gd`) — статический помощник
  (`SPEED := 300.0`, `step()`), общий для `ServerCalculation` и `LocalCalculation`, чтобы не
  дублировать шаг физики.
- **`ServerCalculation`** (`server/scripts/server_calculation.gd` + `.tscn`) — авторитетная
  физика для реальных сетевых игроков. Владеет собственным `@rpc submit_move_state`
  с проверкой `multiplayer.get_remote_sender_id() != peer_id`. Эта проверка новая
  и критична для безопасности: раньше все RPC шли через единый адрес `Net`, а теперь они
  адресуются по узлу — без проверки клиент мог бы двигать чужого игрока, просто адресовав
  вызов по пути другого узла `Player_%d`.
- **`LocalCalculation`** (`server/scripts/local_calculation.gd` + `.tscn`) — авторитетная
  физика для одиночного процесса в режиме LOCAL, без RPC: ввод применяется прямым вызовом
  в рамках процесса.
- **`ClientCalculation`** (`client/scripts/client_calculation.gd` + `.tscn`) — клиентский
  кольцевой буфер снапшотов и интерполяция (100 мс задержки рендера,
  `RENDER_DELAY_MSEC := 100`, буфер на 8 слотов, `SNAPSHOT_BUFFER_SIZE := 8`) для реального
  сетевого игрока. Обязательно нулевой коллижн (`collision_layer = 0`, `collision_mask = 0`
  в `ClientCalculation.tscn`) — так как класс теперь наследует `CharacterBody2D`, коллижн-слои
  как у `ServerCalculation` заставили бы клиентские представления игроков сталкиваться со
  `SnowBullet`, чего не происходило со старым `VisualPlayer` (обычный `Node2D` без коллизии
  вообще).
- **`View`** (`client/scripts/view.gd` + `.tscn`) — чистое представление (`Sprite2D` +
  `Camera2D`), хранит одностороннюю ссылку на связанный `CalculationBase` и — только для
  локально управляемого игрока — владеет `ManualController` для захвата ввода.
- Рассылка мирового состояния (`push_world_state.rpc(states)`) сознательно осталась на
  `Net`, один раз за тик, а не по-нодово — иначе была бы деградация по трафику (N пакетов
  за тик вместо одного). Изменилась только принимающая сторона: состояние теперь
  расфасовывается по `ClientCalculation.receive_snapshot(...)` прямыми локальными вызовами,
  а не через собственный буфер `Net`.
- Удалены: `server/scripts/player.gd`, `client/scripts/visual_player.gd`,
  `server/scripts/controllers/net_controller.gd` (вместе с соответствующими `.tscn`/`.uid`).
- Баг, найденный и исправленный в процессе этапа: в режиме LOCAL `View` изначально
  связывался с одноразовым `ClientCalculation`, чей `request_move_state()` безусловно
  отправляет RPC — но в LOCAL никогда не настраивается `multiplayer_peer`, и локальный игрок
  никогда не получал бы ввод движения. Исправлено добавлением `_ensure_local_view()`
  в `net.gd`, который связывает `View` напрямую с уже заспавненным `LocalCalculation`,
  минуя `ClientCalculation`/RPC для локальной игры.

### Этап 2 — бросок снежков вынесен из `Net` в иерархию классов

Раньше `Net` был god-object'ом и для стрельбы: владел `_apply_shoot`, `_spawn_server_snowball`,
RPC `spawn_snowball`/`snowball_hit`, `on_server_snowball_hit` и общим словарём
`_visual_snowballs`, а `server/scripts/server_snowball.gd` при попадании напрямую вызывал
`Net.on_server_snowball_hit(self)`. Теперь эта логика разнесена по классам, по аналогии
с движением на этапе 1:

- **`CalculationSnowball`** (`shared/scripts/calculation_snowball.gd`) — новый статический
  помощник без состояния, аналог `CalculationPhysics`. Владеет константами
  (`THROW_DELAY_SEC := 0.4`, `SNOWBALL_SPEED := 600.0`, `BULLET_SPAWN_OFFSET := 45.0`),
  `preload`'ами сцен `ServerSnowball`/`SnowBullet` и общей математикой/спавном
  (`compute_muzzle`, `spawn_server_snowball`, `spawn_visual_snowball`, `finalize_visual_hit`),
  общими для `ServerCalculation` и `LocalCalculation`, чтобы не дублировать их между двумя
  независимыми потомками `CalculationBase`.
- **`CalculationBase`** — добавлены виртуальные `request_shoot()` и `on_snowball_hit()`
  (по умолчанию пустая реализация/предупреждение, как и у `request_move_state`).
- **`ServerCalculation`** — новый `@rpc submit_shoot()` инициирует выстрел, спавнит
  `ServerSnowball` через `CalculationSnowball` и рассылает клиентам `spawn_snowball.rpc(...)`;
  `on_snowball_hit()` рассылает `snowball_hit.rpc(...)`. RPC-заглушки `spawn_snowball`/
  `snowball_hit` резолвятся в одноимённые методы `ClientCalculation` на клиентах.
- **`LocalCalculation`** — `request_shoot()` выполняет ту же последовательность прямым
  вызовом, без единого RPC, и сам же спавнит визуальный `SnowBullet` (как и для движения,
  `LocalCalculation` совмещает обе роли, минуя `ClientCalculation`).
- **`ClientCalculation`** — `request_shoot()` шлёт `submit_shoot.rpc_id(1)`, а `spawn_snowball`/
  `snowball_hit` спавнят/завершают визуальный `SnowBullet` через `CalculationSnowball`.
- **`ServerSnowball`** — поле `shooter_peer_id: int` заменено на
  `shooter_calculation: CalculationBase` (хранить оба поля избыточно — `peer_id` при
  необходимости доступен как `shooter_calculation.peer_id`); добавлен флаг `_already_hit`
  от двойного срабатывания попадания; `_on_body_entered()` теперь вызывает
  `shooter_calculation.on_snowball_hit(...)` напрямую по ссылке вместо
  `Net.on_server_snowball_hit(self)`, с защитой `is_instance_valid(shooter_calculation)` на
  случай, если стрелок отключился, пока снежок ещё летел.
- Модель `shot_id`/`_visual_snowballs` сменилась с единой на `Net` на локальную —
  счётчик и словарь принадлежат конкретному экземпляру `ServerCalculation`/`LocalCalculation`/
  `ClientCalculation`, а не общему узлу.
- Найдена и закрыта уязвимость авторства в `submit_shoot`, аналогичная той, что уже была
  закрыта для `submit_move_state` на этапе 1: в старом `Net.submit_shoot()` проверки
  отправителя не было, и это было безопасно, пока RPC приходил на единый узел `Net`
  (`peer_id` брался напрямую из `get_remote_sender_id()`, подделать нечего). После переноса
  на `ServerCalculation` RPC стал адресоваться по конкретному пути `Player_%d`, а у каждого
  клиента в дереве есть `ClientCalculation` для всех игроков — без проверки клиент с одним
  `peer_id` мог бы вызвать `submit_shoot.rpc_id(1)` на чужом узле и заставить стрелять другого
  игрока. Добавлена проверка `multiplayer.get_remote_sender_id() != peer_id` в
  `ServerCalculation.submit_shoot()`.
- Принятый компромисс: `spawn_snowball`/`snowball_hit` теперь адресуются по узлу конкретного
  игрока, а не широковещательно с единого `Net`. При гонке подключения (снежок долетает до
  клиента, у которого ещё нет `ClientCalculation` стрелка) RPC для этого конкретного снежка
  молча теряется, но `SnowBullet` не "зависает" — он самостоятельно детектит столкновения
  независимо от RPC.

## Осталось

Ниже — кандидаты на следующие этапы. Порядок и состав **не согласованы окончательно**.

1. **`Game`/`Level` как оркестратор спавна вместо `Net`.** На раннем этапе обсуждения
   дизайна (до того, как остановились на `CalculationBase`) рассматривалась идея, что узел
   `Game` владеет загрузкой, а `Level` — ростером игроков и их спавном. Для этапа 1 эта идея
   осознанно отложена в пользу того, чтобы оркестратором спавна оставался `Net` — чтобы не
   смешивать в одном ревью два независимых рефакторинга (разделение Calculation/View и смену
   владельца оркестрации). `Net` по-прежнему хранит `_server_calculations`/
   `_client_calculations`/`_views` и сам вызывает `_spawn_authoritative_calculation`/
   `_ensure_client_view`/`_ensure_local_view`. Открытый вопрос на будущее: если этим
   заняться, стоит ли заодно перенести туда же владение снежками (снежок логически скорее
   принадлежит `Level`/полю боя, а не отдельному игроку).
2. **Рассмотренная и отклонённая альтернатива (для справки)**: использовать
   высокоуровневые `MultiplayerSpawner`/`MultiplayerSynchronizer` вместо ручных RPC.
   Отклонено, потому что потребовало бы слияния `ServerCalculation`/`ClientCalculation`
   в один реплицируемый тип с ветвлением по authority и замены уже настроенной кастомной
   интерполяции (100 мс задержки, буфер на 8 кадров) — риска и объёма работ больше, чем
   оправдывает текущее направление. Можно вернуться к этому варианту позже, если
   поддержка ручных RPC станет обузой.

Отдельно: в `net.gd` есть комментарий про `LOBBY_NAME` как точку расширения до
`lobbies/<id>` (пока не реализовано) — `_get_server_game_root()`/`_get_visual_game_root()`
спроектированы как единственное место, которое пришлось бы менять под это расширение.
