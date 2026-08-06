# SnowWars — архитектура сетевого слоя

Снимок текущего устройства сетевого слоя: как игроки и снежки адресуются по сети, какие
классы за что отвечают и почему.

Весь код находится в `src/GodotClientServer` (см. [`docs/index.md`](index.md) для общей
структуры проекта).

## Режимы

`Net` (автозагружаемый синглтон, `shared/scripts/net.gd`) работает в одном из трёх режимов
(`Net.Mode`): `SERVER`, `CLIENT`, `LOCAL`. `LOCAL` — сервер и клиент в одном процессе, без
настоящего сетевого пира, используется для игры в одиночку/офлайн-тестирования.

`Net` — это только точка входа в сеть: старт/остановка `ENetMultiplayerPeer`, режим и тонкие
сигналы (`peer_connected`, `peer_disconnected`, `connected_to_server`, `connection_failed`,
`server_disconnected`) поверх `MultiplayerAPI`. `Net` не знает о `Host`, `Lobby` или игровой
логике вообще — зависимость строго однонаправленная: `Host`/`Lobby` слушают `Net`, а не
наоборот. Дерево игры создаёт и запускает `Launcher` (`shared/scripts/launcher.gd`): после
успешного `Net.start_server()`/`start_client()`/`start_local()` он создаёт `Host` и добавляет
его в `/root`, после чего убирает себя из дерева сцены.

## Адресация RPC

Godot адресует RPC по абсолютному `NodePath`: вызывающий узел должен существовать по
идентичному пути на принимающей стороне. Дерево игры живёт по единому каноничному пути
`/root/Host/LobbyList/<имя лобби>/...` в каждом процессе (на этом этапе имя лобби всегда
`"Лобби_1"`, см. `Host.LOBBY_NAME`) — конфликтов путей между процессами нет, потому что сервер
и клиент физически разные процессы. Единственный `LevelBase` процесса всегда называется
`"Game"` — и на `SERVER`, и на `CLIENT`: путь до него (и до `Player_%d` внутри) обязан
совпадать на обеих сторонах, иначе RPC не находят адресата. Это верно и для режима `LOCAL`:
там нет настоящего RPC, но `Host`/`Lobby` создаются по тем же правилам, а авторитетная (`Game`)
и визуальная (`VisualGame`) половины разведены как два разных узла-потомка одного и того же
`Lobby` — совпадение имён здесь не требуется.

Узлы игроков получают детерминированные имена `"Player_%d" % peer_id` на обеих сторонах —
это тоже требование адресации RPC по абсолютному пути: сервер и клиент должны прийти к
одному и тому же пути для одного и того же игрока независимо друг от друга.

## Иерархия классов

- **`Host`** (`shared/scripts/host.gd`, extends `Node`, без `.tscn`) — создаётся `Launcher`'ом
  и добавляется в `/root` сразу после успешного `Net.start_*()`. Подписывается на сигналы
  `Net` и по ним поддерживает единственный (пока) `Lobby` внутри `LobbyList`: на `SERVER`/
  `LOCAL` лобби создаётся сразу при старте, на `CLIENT` — по факту `Net.connected_to_server`.
- **`LobbyList`** (`shared/scripts/lobby_list.gd`, extends `Node`) — контейнер потомков
  `Lobby`. На этом этапе всегда содержит ровно один `Lobby`; задел на будущее — несколько
  лобби на сервере одновременно.
- **`Lobby`** (`shared/scripts/lobby.gd`, extends `Node`) — конкретное поле боя: создаёт
  `game`/`visual_game` (см. «Кто чем владеет» ниже; узел единственного `LevelBase` процесса
  называется `"Game"` на `SERVER` и `CLIENT`, `"VisualGame"` — только для дополнительного узла
  в `LOCAL`), обрабатывает подключение/отключение игроков и рассылает мировое состояние только
  своим игрокам. Имя узла (`"Лобби_1"`, `Host.LOBBY_NAME`) — часть пути адресации RPC и должно
  совпадать на сервере и клиенте.
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
одновременно. На `SERVER`/`CLIENT` единственный инстанс `LevelBase` процесса всегда называется
`"Game"` (роль определяется тем, какие методы на нём вызываются, а не именем узла — на `SERVER`
это авторитетная половина, на `CLIENT` — визуальная). В режиме `LOCAL` это два разных инстанса
сцены `Level.tscn` в одном процессе: узлы `Game` (авторитетный) и `VisualGame` (визуальный),
оба — прямые потомки одного и того же `Lobby`; там реального RPC нет, поэтому отличающееся имя
второго узла не мешает адресации. Поэтому один класс безопасно совмещает API обеих ролей — для
конкретного инстанса используется только одна половина.

- **Авторитетная половина** (используется на узле `Game`, который создаёт
  `Lobby._create_game()`): `spawn_authoritative_calculation(peer_id)`,
  `despawn_authoritative_calculation(peer_id)`, `build_roster()`,
  `get_server_calculations()`, `next_shot_id()` (глобальный счётчик `shot_id`, общий для всех
  стрелков в матче/процессе).
- **Визуальная половина** (используется на визуальном `LevelBase`, который создаёт
  `Lobby._create_visual_game(node_name)` — узел `"Game"` на `CLIENT`, `"VisualGame"` в
  `LOCAL`): `ensure_client_view(peer_id, position, rotation)`,
  `ensure_local_view(peer_id, calculation)`, `remove_client_view(peer_id)`,
  `get_client_calculation(peer_id)`, `get_client_calculations()`, `spawn_visual_snowball(...)`,
  `finalize_snowball_hit(...)` (оба делегируют в статические методы `CalculationSnowball`).

Calculation-классы (`ServerCalculation`/`LocalCalculation`/`ClientCalculation`) спавнятся как
прямые потомки своего `LevelBase`, поэтому находят его через `get_parent()`, а не через
глобальный геттер — это не зависит от имени узла. `LocalCalculation` (режим `LOCAL`)
дополнительно поднимается на уровень выше, до `Lobby`, чтобы получить соседний узел
`VisualGame` по имени — это специфично только для `LOCAL`, где второй узел действительно так
называется.

### `Host` / `LobbyList` / `Lobby` (`shared/scripts/host.gd`, `lobby_list.gd`, `lobby.gd`)

Владеют игровой иерархией и сетевой логикой поверх `Net`, которую раньше держал сам `Net`:
подключение/отключение игроков (`Lobby.on_peer_connected`/`on_peer_disconnected` — то, что
раньше было `Net._on_peer_connected`/`_on_peer_disconnected`), рассылка мирового состояния раз
за физический тик (`Lobby.push_world_state.rpc(states)` — сознательно одним пакетом на всех
игроков лобби, а не по-нодово, чтобы не плодить N RPC-пакетов за тик), рассылка
ростера/спавна/деспавна визуальных игроков (`receive_player_roster`, `spawn_visual_player`,
`despawn_visual_player` — теперь RPC самого `Lobby`). `Host` — верхний уровень: слушает `Net`
и поддерживает состав `LobbyList`. Зависимость односторонняя: `Host`/`Lobby` знают про `Net`,
`Net` про них — нет.

### `ServerInfo` (`server/scripts/server_info.gd`)

Создаётся своим `Lobby` (`Lobby._create_server_info()`) как прямой потомок и через
`get_parent()` берёт у него имя лобби (`get_lobby_name()`) и список игроков
(`get_player_ids()` → `Lobby.get_known_player_ids()`).

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
