# SnowWars — архитектура сетевого слоя

Снимок текущего устройства сетевого слоя: как игроки и снежки адресуются по сети, какие
классы за что отвечают и почему. Для истории решений (что и зачем менялось, этап за этапом)
см. [`docs/roadmap.md`](roadmap.md).

Весь код находится в `src/GodotClientServer` (см. [`docs/index.md`](index.md) для общей
структуры проекта).

## Режимы

`Net` (автозагружаемый синглтон, `shared/scripts/net.gd`) работает в одном из трёх режимов
(`Net.Mode`): `SERVER`, `CLIENT`, `LOCAL`. `LOCAL` — сервер и клиент в одном процессе, без
настоящего сетевого пира, используется для игры в одиночку/офлайн-тестирования.

## Адресация RPC

Godot адресует RPC по абсолютному `NodePath`: вызывающий узел должен существовать по
идентичному пути на принимающей стороне. Отсюда — два инварианта дерева сцены:

- В режимах `SERVER` и `CLIENT` дерево сцены живёт по единому каноничному пути
  `/root/Game/Level` в каждом процессе — конфликтов путей между процессами нет, потому что
  сервер и клиент физически разные процессы.
- В режиме `LOCAL` (сервер и клиент в одном процессе, без RPC) используются два раздельных
  корня: `/root/globalServer/game` — авторитетная часть, `/root/visual/currentGame` —
  визуальная часть. Разделение нужно потому, что в одном процессе не может быть двух узлов
  по одному пути `/root/Game/Level`, а авторитетная и визуальная половины концептуально
  разные объекты (см. «Кто чем владеет» ниже).

Узлы игроков получают детерминированные имена `"Player_%d" % peer_id` на обеих сторонах —
это тоже требование адресации RPC по абсолютному пути: сервер и клиент должны прийти к
одному и тому же пути для одного и того же игрока независимо друг от друга.

## Иерархия классов

- **`CalculationBase`** (`shared/scripts/calculation_base.gd`, extends `CharacterBody2D`) —
  абстрактный базовый класс. Хранит `peer_id`, объявляет виртуальные `request_move_state()`,
  `receive_input()`, `request_shoot()`, `on_snowball_hit()` (реализации по умолчанию — пустые
  или предупреждение).
- **`CalculationPhysics`** (`shared/scripts/calculation_physics.gd`) — статический помощник
  без состояния (`SPEED := 300.0`, `step()`), общий для `ServerCalculation` и
  `LocalCalculation`, чтобы не дублировать шаг физики движения.
- **`CalculationSnowball`** (`shared/scripts/calculation_snowball.gd`) — статический помощник
  без состояния, аналог `CalculationPhysics` для броска снежков. Владеет константами
  (`THROW_DELAY_SEC`, `SNOWBALL_SPEED`, `BULLET_SPAWN_OFFSET`), preload'ами сцен
  `ServerSnowball`/`SnowBullet` и общей математикой/спавном (`compute_muzzle`,
  `spawn_server_snowball`, `spawn_visual_snowball`, `finalize_visual_hit`).
- **`ServerCalculation`** (`server/scripts/server_calculation.gd`) — авторитетная физика для
  реальных сетевых игроков. RPC `submit_move_state`/`submit_shoot` принимают ввод от клиента
  и обязательно проверяют `multiplayer.get_remote_sender_id() != peer_id` (см. «Модель
  безопасности» ниже). `submit_shoot` спавнит `ServerSnowball` через `CalculationSnowball` и
  рассылает клиентам `spawn_snowball.rpc(...)`; `on_snowball_hit()` рассылает
  `snowball_hit.rpc(...)`.
- **`LocalCalculation`** (`server/scripts/local_calculation.gd`) — авторитетная физика для
  режима `LOCAL`, без RPC: ввод применяется прямым локальным вызовом в рамках одного
  процесса, минуя сеть целиком.
- **`ClientCalculation`** (`client/scripts/client_calculation.gd`) — клиентская интерполяция
  для реального сетевого игрока: кольцевой буфер снапшотов (`SNAPSHOT_BUFFER_SIZE := 8`),
  рендер с задержкой `RENDER_DELAY_MSEC := 100` мс для сглаживания сети. `request_move_state`/
  `request_shoot` шлют RPC на сервер (`rpc_id(1)`); `spawn_snowball`/`snowball_hit` — точки
  входа RPC с сервера, спавнящие/завершающие визуальный `SnowBullet` через
  `CalculationSnowball`. Коллизии отключены (`collision_layer = 0`, `collision_mask = 0`) —
  это чистое представление чужого состояния, оно не должно участвовать в физике клиента.
- **`View`** (`client/scripts/view.gd`) — чистое представление (`Sprite2D` + `Camera2D`),
  хранит одностороннюю ссылку на связанный `CalculationBase` и копирует его позицию/поворот
  каждый кадр. Только для локально управляемого игрока (`peer_id == Net.get_local_peer_id()`)
  дополнительно владеет `ManualController`, который захватывает ввод игрока и вызывает
  `request_move_state()`/`request_shoot()` на связанном `CalculationBase`.

## Кто чем владеет

### `LevelBase` (`shared/scripts/level_base.gd`)

Владеет составом конкретного поля боя — ростером игроков и снежками. В рантайме любой
инстанс `Level` играет ровно одну из двух ролей — авторитетную или визуальную — никогда обе
одновременно, даже в режиме `LOCAL`, где это два разных инстанса сцены `Level.tscn` в разных
поддеревьях (`/root/globalServer/game` и `/root/visual/currentGame`). Поэтому один класс
безопасно совмещает API обеих ролей — для конкретного инстанса используется только одна
половина.

- **Авторитетная половина** (используется на корне, который создаёт
  `Net._setup_server_game()`): `spawn_authoritative_calculation(peer_id)`,
  `despawn_authoritative_calculation(peer_id)`, `build_roster()`,
  `get_server_calculations()`, `next_shot_id()` (глобальный счётчик `shot_id`, общий для всех
  стрелков в матче/процессе).
- **Визуальная половина** (используется на корне, который создаёт
  `Net._setup_client_visual()`): `ensure_client_view(peer_id, position, rotation)`,
  `ensure_local_view(peer_id, calculation)`, `remove_client_view(peer_id)`,
  `get_client_calculation(peer_id)`, `get_client_calculations()`, `spawn_visual_snowball(...)`,
  `finalize_snowball_hit(...)` (оба делегируют в статические методы `CalculationSnowball`).

### `Net` (`shared/scripts/net.gd`)

Тонкий слой управления режимом (`SERVER`/`CLIENT`/`LOCAL`) и точки входа RPC верхнего
уровня: подключение/отключение пиров (`_on_peer_connected`/`_on_peer_disconnected`),
рассылка мирового состояния раз за физический тик (`push_world_state.rpc(states)` — сознательно
одним пакетом на всех игроков, а не по-нодово, чтобы не плодить N RPC-пакетов за тик), рассылка
ростера/спавна/деспавна визуальных игроков (`receive_player_roster`, `spawn_visual_player`,
`despawn_visual_player`). Также создаёт корневые контейнеры дерева сцены
(`_setup_server_game()`/`_setup_client_visual()`) и предоставляет геттеры канонических корней
(`_get_server_game_root()`/`_get_visual_game_root()`), которыми пользуются Calculation-классы
для доступа к `LevelBase`.

## Модель безопасности

RPC, которые изменяют состояние конкретного игрока (`submit_move_state`, `submit_shoot`),
адресуются по узлу этого игрока (`Player_%d`), а не на единый узел `Net`. Это означает, что
у клиента с `peer_id = A` в дереве сцены есть доступ к узлам всех игроков, включая чужие
`Player_%d` — Godot не ограничивает, по какому пути клиент может адресовать исходящий RPC.
Без явной проверки клиент мог бы вызвать `submit_move_state.rpc_id(1, ...)` или
`submit_shoot.rpc_id(1)`, адресовав вызов по пути чужого игрока, и подделать его ввод/выстрел.

Поэтому каждый такой RPC на `ServerCalculation` в первую же строку проверяет
`multiplayer.get_remote_sender_id() != peer_id` и молча игнорирует вызов при несовпадении —
подтверждает, что отправитель пакета (`get_remote_sender_id()`) — это тот же пир, что владеет
данным узлом (`peer_id`, установленный при спавне в `spawn_authoritative_calculation`).
