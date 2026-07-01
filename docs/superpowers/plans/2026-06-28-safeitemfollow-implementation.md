# SafeItemFollow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build SafeItemFollow, a read-only WoW auction-house addon that scans prices, stores a per-item daily price history, visualizes its evolution, and flags vendor-flip opportunities — with every buy/sell action left to the user.

**Architecture:** A WoW addon mirroring the existing Safe\* family layout: a flat set of `.lua` modules listed in a `.toc`, each receiving `local _, NS = ...` and hanging its table off the shared `NS` namespace, built on the Ace3 library stack. The tested core is three pure-logic modules — `Data` (daily aggregation, retention purge, realm+faction storage), `Rules` (throttle gate, row parsing, flip + historic-low detection), and `Scanner` (event-driven directed queries + full paginated scan). UI/glue modules (`Tooltip`, `Overlay`, `ActionButton`/`ActionState`, `MinimapButton`, `Config`, `Core`) wire those into the game and an AceGUI 3-tab window. Logic modules take all WoW APIs via global-with-fallback wrappers so plain-Lua tests can inject mocks (the exact pattern used by `tests/test_scanner.lua` in SafeProspecting).

**Tech Stack:** Lua 5.1 (WoW's interpreter), Ace3 (LibStub, CallbackHandler-1.0, AceAddon-3.0, AceDB-3.0, AceConsole-3.0, AceGUI-3.0, AceConfig-3.0, AceDBOptions-3.0), WoW classic auction API (`QueryAuctionItems`, `GetNumAuctionItems`, `GetAuctionItemInfo`, `CanSendAuctionQuery`).

## Global Constraints

These apply to **every** task. Exact values copied from the spec.

- **Target client:** WoW 20th Anniversary TBC Classic `Interface 20505`. The `.toc` first line is `## Interface: 20505`.
- **Compliance — read-only only.** Use only `QueryAuctionItems`, `GetNumAuctionItems("list")`, `GetAuctionItemInfo`. **Never** call `PlaceAuctionBid` or `PostAuction`. No automation of buy/sell. Any "buy" affordance only highlights/selects a row or triggers a read query; the user performs the purchase.
- **Throttle respected.** Every auction query passes through `CanSendAuctionQuery()` and waits for the `AUCTION_ITEM_LIST_UPDATE` event before reading or advancing a page.
- **Vendor price is local.** `vendorSell` comes only from `GetItemInfo` (the `sellPrice` field), never the network.
- **No binaries, no obfuscation, free.** Nothing the native UI cannot do.
- **DB scope:** data is separated by realm + faction. `SavedVariables: SafeItemFollowDB`.
- **Daily resolution only.** One summary bucket per item per UTC day; `dayKey = math.floor(serverTime / 86400)`. No intraday/raw per-scan storage.
- **Module pattern:** each `.lua` starts with `local _, NS = ...` (or `local addonName, NS = ...` for Bootstrap) and attaches to `NS`. Logic modules wrap WoW APIs in local functions that prefer the namespaced/`C_*` API and fall back to the `_G` global, so tests can override the global.
- **Load order (in `.toc`):** Libs → Bootstrap → Locales → Data → Rules → Scanner → Tooltip → Overlay → ActionState → ActionButton → MinimapButton → Config → Core.
- **Out of scope (YAGNI):** auto-buy/sniping, web export, intraday resolution, cross-realm/cross-character sync beyond realm+faction.

## Test Toolchain

Tests are plain Lua run from the addon root, e.g. `lua5.1 tests/test_data.lua`. The harness pattern: build a `namespace` table, set mock WoW globals, `assert(loadfile("Module.lua"))("SafeItemFollow", namespace)`, then `assert(...)`. WoW uses **Lua 5.1**, so test with `lua5.1`.

This environment has no Lua interpreter and `apt` needs a password. **Before executing Task 1**, the user runs once (via the `!` prefix in the Claude Code prompt, or any terminal):

```
sudo apt-get install -y lua5.1
```

This provides both `lua5.1` (run tests) and `luac5.1` (syntax-check UI modules that have no unit tests). Verify with `lua5.1 -v` (expect `Lua 5.1.x`). If `lua5.1` is unavailable, any Lua 5.1 interpreter works; substitute its name in the run commands below.

## File Structure

All paths are under `/home/dnthdev/proyectos/Addons/SafeItemFollow/`.

| File | Responsibility |
|---|---|
| `SafeItemFollow.toc` | Client versions, SavedVariables, load order |
| `Libs/` | Vendored Ace3 stack (copied from a known-good source) |
| `Bootstrap.lua` | Namespace constants, `NS.Addon` (AceAddon) |
| `Locales.lua` | enUS base + esES/esMX overrides into `NS.L` |
| `Data.lua` | Pure: realm+faction store, `DayKey`, `RecordScan` (running daily average), `Purge`, `GetHistory`, watchlist + vendor accessors |
| `Rules.lua` | Pure: `CanQuery` gate, `ParseRow`, `SummarizeListings`, `IsFlip`/`FlipGain`, `IsHistoricLow` |
| `Scanner.lua` | Event-driven directed (watchlist) queries + full paginated scan; pure page helpers for tests |
| `Tooltip.lua` | Inject daily history + flip line into item tooltips |
| `Overlay.lua` | Highlight cheap / below-vendor rows on the native AH browse list |
| `ActionState.lua` | Full-scan progress state object |
| `ActionButton.lua` | "Full scan" button + per-item directed-query trigger |
| `MinimapButton.lua` | Toggle the main window |
| `Config.lua` | AceDB init (defaults), options table (retentionDays, flipMargin, autoScanOnOpen) |
| `Core.lua` | AceGUI 3-tab window + event registration + `OnInitialize`/`OnEnable` |
| `tests/test_data.lua` | Data aggregation, purge, realm separation, lazy init |
| `tests/test_rules.lua` | Flip threshold, row parsing, throttle gate, historic-low |
| `tests/test_scanner.lua` | Pagination with mocked `GetAuctionItemInfo` (multi-page + partial final page) |
| `tests/IN_GAME_CHECKLIST.md` | Manual in-game verification steps |
| `README.md` | (exists) update if needed |

---

## Task 0: Project scaffold (.toc, Libs, Bootstrap, Locales)

Sets up the loadable addon skeleton. No unit tests yet; verification is "files exist and Lua parses".

**Files:**
- Create: `SafeItemFollow.toc`
- Create: `Libs/` (copied tree)
- Create: `Bootstrap.lua`
- Create: `Locales.lua`

**Interfaces:**
- Produces: `NS.ADDON_NAME` (string), `NS.VERSION` (string), `NS.DAY_SECONDS = 86400`, `NS.DEFAULT_PER_PAGE = 50`, `NS.Addon` (AceAddon object), `NS.L` (locale table). Later tasks consume these.

- [ ] **Step 1: Vendor the Ace3 libraries**

The addon needs the same Ace3 stack the Safe\* family already uses. Copy the vendored, known-good tree from the sibling addon (read-only reference — do not modify the sibling):

```bash
cp -R /home/dnthdev/proyectos/Addons/SafeProspecting/Libs /home/dnthdev/proyectos/Addons/SafeItemFollow/Libs
```

Verify the expected libraries are present:

```bash
ls /home/dnthdev/proyectos/Addons/SafeItemFollow/Libs
```
Expected to include: `LibStub`, `CallbackHandler-1.0`, `AceAddon-3.0`, `AceDB-3.0`, `AceConsole-3.0`, `AceGUI-3.0`, `AceConfig-3.0`, `AceDBOptions-3.0`.

(If the sibling is unavailable, download the current Ace3 bundle from https://www.curseforge.com/wow/addons/ace3 and place its `Libs` subfolders here instead.)

- [ ] **Step 2: Write `SafeItemFollow.toc`**

```
## Interface: 20505
## Title: SafeItemFollow
## Notes: Read-only auction price history and vendor-flip finder for TBC Classic Anniversary.
## Notes-esES: Historial de precios de subasta (solo lectura) y buscador de reventa al vendedor.
## Notes-esMX: Historial de precios de subasta (solo lectura) y buscador de reventa al vendedor.
## Author: SafeItemFollow contributors
## Version: 0.1.0
## SavedVariables: SafeItemFollowDB
## IconTexture: Interface\Icons\INV_Misc_Coin_01
## Category: Auction House
## Category-esES: Casa de subastas
## Category-esMX: Casa de subastas
## X-License: All Rights Reserved

Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.xml
Libs\AceAddon-3.0\AceAddon-3.0.xml
Libs\AceDB-3.0\AceDB-3.0.xml
Libs\AceConsole-3.0\AceConsole-3.0.xml
Libs\AceGUI-3.0\AceGUI-3.0.xml
Libs\AceConfig-3.0\AceConfig-3.0.xml
Libs\AceDBOptions-3.0\AceDBOptions-3.0.xml

Bootstrap.lua
Locales.lua
Data.lua
Rules.lua
Scanner.lua
Tooltip.lua
Overlay.lua
ActionState.lua
ActionButton.lua
MinimapButton.lua
Config.lua
Core.lua
```

- [ ] **Step 3: Write `Bootstrap.lua`**

```lua
local addonName, NS = ...

NS.ADDON_NAME = addonName
NS.VERSION = "0.1.0"
NS.DAY_SECONDS = 86400
NS.DEFAULT_PER_PAGE = 50

NS.Addon = LibStub("AceAddon-3.0"):NewAddon(
    "SafeItemFollow",
    "AceConsole-3.0"
)
```

- [ ] **Step 4: Write `Locales.lua`**

```lua
local _, NS = ...

local english = {
    ADDON_DESCRIPTION = "Read-only auction price history and vendor-flip finder.",
    WINDOW_TITLE = "SafeItemFollow",
    TAB_WATCHLIST = "Watchlist",
    TAB_MARKET = "Market scan",
    TAB_FLIP = "Vendor flip",
    BTN_FULL_SCAN = "Full scan",
    BTN_FULL_SCAN_RUNNING = "Scanning... page %d",
    BTN_ADD_WATCH = "Add to watchlist",
    BTN_REMOVE_WATCH = "Remove from watchlist",
    BTN_FIND = "Find in auction house",
    COL_ITEM = "Item",
    COL_MIN = "Min/unit",
    COL_AVG = "Avg/unit",
    COL_QTY = "Qty",
    COL_VENDOR = "Vendor",
    COL_GAIN = "Est. gain",
    COL_DAY = "Day",
    HISTORY_HEADER = "Daily price history:",
    HISTORY_EMPTY = "No history yet. Open the auction house to scan.",
    FLIP_EMPTY = "No vendor-flip opportunities in the last scan.",
    MARKET_EMPTY = "No scan results yet. Click Full scan at the auction house.",
    TOOLTIP_HISTORY = "SafeItemFollow - last %d days: min %s, avg %s",
    TOOLTIP_FLIP = "Vendor flip: buyout/unit %s < vendor %s (gain %s/unit)",
    TOOLTIP_HISTORIC_LOW = "Historic low buyout!",
    MINIMAP_TOOLTIP_TITLE = "SafeItemFollow",
    MINIMAP_TOOLTIP_LEFT = "Left-click: open the window.",
    MINIMAP_TOOLTIP_RIGHT = "Right-click: open options.",
    CONFIG_NAME = "SafeItemFollow",
    CONFIG_RETENTION = "History retention (days)",
    CONFIG_RETENTION_DESC = "Daily price buckets older than this are purged.",
    CONFIG_FLIP_MARGIN = "Flip margin (copper)",
    CONFIG_FLIP_MARGIN_DESC = "Extra margin required below vendor price before a listing counts as a flip.",
    CONFIG_AUTOSCAN = "Auto-scan watchlist on open",
    CONFIG_AUTOSCAN_DESC = "Send directed watchlist queries automatically when the auction house opens.",
    CONFIG_OVERLAYS = "Highlight cheap rows on the auction house",
    CONFIG_TOOLTIPS = "Show history and flip in tooltips",
    CONFIG_MINIMAP_BUTTON = "Show minimap button",
    CONFIG_PROFILES = "Profiles",
    MSG_SCAN_DONE = "Full scan complete: %d listings across %d items.",
    MSG_SCAN_ABORTED = "Scan aborted (auction house closed).",
    MSG_HELP = "Commands: /safeitemfollow show, /safeitemfollow config, /safeitemfollow scan",
    MSG_UNSUPPORTED = "This build targets WoW 20th Anniversary TBC Classic 2.5.x.",
}

local spanish = {
    ADDON_DESCRIPTION = "Historial de precios de subasta (solo lectura) y buscador de reventa al vendedor.",
    WINDOW_TITLE = "SafeItemFollow",
    TAB_WATCHLIST = "Seguidos",
    TAB_MARKET = "Escaneo de mercado",
    TAB_FLIP = "Reventa al vendedor",
    BTN_FULL_SCAN = "Escaneo completo",
    BTN_FULL_SCAN_RUNNING = "Escaneando... pagina %d",
    BTN_ADD_WATCH = "Anadir a seguidos",
    BTN_REMOVE_WATCH = "Quitar de seguidos",
    BTN_FIND = "Buscar en la subasta",
    COL_ITEM = "Objeto",
    COL_MIN = "Min/unidad",
    COL_AVG = "Media/unidad",
    COL_QTY = "Cantidad",
    COL_VENDOR = "Vendedor",
    COL_GAIN = "Ganancia est.",
    COL_DAY = "Dia",
    HISTORY_HEADER = "Historial diario de precios:",
    HISTORY_EMPTY = "Sin historial. Abre la subasta para escanear.",
    FLIP_EMPTY = "No hay oportunidades de reventa en el ultimo escaneo.",
    MARKET_EMPTY = "Sin resultados. Pulsa Escaneo completo en la subasta.",
    TOOLTIP_HISTORY = "SafeItemFollow - ultimos %d dias: min %s, media %s",
    TOOLTIP_FLIP = "Reventa: compra/unidad %s < vendedor %s (ganancia %s/unidad)",
    TOOLTIP_HISTORIC_LOW = "Minimo historico de compra!",
    MINIMAP_TOOLTIP_TITLE = "SafeItemFollow",
    MINIMAP_TOOLTIP_LEFT = "Clic izquierdo: abrir la ventana.",
    MINIMAP_TOOLTIP_RIGHT = "Clic derecho: abrir opciones.",
    CONFIG_NAME = "SafeItemFollow",
    CONFIG_RETENTION = "Retencion del historial (dias)",
    CONFIG_RETENTION_DESC = "Los puntos diarios mas viejos que esto se purgan.",
    CONFIG_FLIP_MARGIN = "Margen de reventa (cobre)",
    CONFIG_FLIP_MARGIN_DESC = "Margen extra exigido por debajo del precio de vendedor para contar como reventa.",
    CONFIG_AUTOSCAN = "Auto-escanear seguidos al abrir",
    CONFIG_AUTOSCAN_DESC = "Envia consultas dirigidas de la watchlist al abrir la subasta.",
    CONFIG_OVERLAYS = "Resaltar filas baratas en la subasta",
    CONFIG_TOOLTIPS = "Mostrar historial y reventa en tooltips",
    CONFIG_MINIMAP_BUTTON = "Mostrar boton del minimapa",
    CONFIG_PROFILES = "Perfiles",
    MSG_SCAN_DONE = "Escaneo completo: %d publicaciones en %d objetos.",
    MSG_SCAN_ABORTED = "Escaneo cancelado (subasta cerrada).",
    MSG_HELP = "Comandos: /safeitemfollow show, /safeitemfollow config, /safeitemfollow scan",
    MSG_UNSUPPORTED = "Esta version apunta a WoW 20 Aniversario TBC Classic 2.5.x.",
}

NS.L = {}
for key, value in pairs(english) do
    NS.L[key] = value
end

local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
if locale == "esES" or locale == "esMX" then
    for key, value in pairs(spanish) do
        NS.L[key] = value
    end
end
```

- [ ] **Step 5: Syntax-check the new Lua files**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && luac5.1 -p Bootstrap.lua Locales.lua`
Expected: no output, exit code 0 (a syntax error would print `luac5.1: file:line: ...`).

- [ ] **Step 6: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add SafeItemFollow.toc Bootstrap.lua Locales.lua Libs
git commit -m "feat: scaffold SafeItemFollow toc, libs, bootstrap, locales"
```

---

## Task 1: Data.lua — daily aggregation, retention, realm+faction store

Pure logic. Operates only on tables passed in (no WoW globals except an injected `serverTime`), so it is fully unit-testable.

**Files:**
- Create: `Data.lua`
- Test: `tests/test_data.lua`

**Interfaces:**
- Consumes: `NS.DAY_SECONDS` (from Bootstrap; tests set it on the namespace).
- Produces (all on `NS.Data`):
  - `Data.DayKey(serverTime) -> number` = `floor(serverTime / DAY_SECONDS)`.
  - `Data.GetStore(db, realmKey) -> store` — lazily creates `db.realms[realmKey] = { items = {} }` and returns it.
  - `Data.GetItem(store, itemID) -> itemEntry` — lazily creates `{ name=nil, vendorSell=nil, watched=false, history={} }`.
  - `Data.SetName(store, itemID, name)`, `Data.SetVendor(store, itemID, vendorSell)`, `Data.SetWatched(store, itemID, watched)`.
  - `Data.RecordScan(store, itemID, dayKey, summary)` where `summary = { minBuyout=number, avgBuyout=number, qty=number }`; updates today's bucket with the running-average rule.
  - `Data.Purge(store, currentDayKey, retentionDays) -> removedCount` — deletes buckets with `dayKey < currentDayKey - retentionDays`.
  - `Data.GetHistory(store, itemID) -> array` of `{ dayKey, minBuyout, avgBuyout, qty }` sorted ascending by `dayKey`.
  - `Data.GetWatched(store) -> array of itemID` sorted ascending.

- [ ] **Step 1: Write the failing test `tests/test_data.lua`**

```lua
local namespace = { DAY_SECONDS = 86400 }
assert(loadfile("Data.lua"))("SafeItemFollow", namespace)
local Data = namespace.Data

local function equal(actual, expected, label)
    assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

-- DayKey
equal(Data.DayKey(0), 0, "day 0")
equal(Data.DayKey(86399), 0, "still day 0")
equal(Data.DayKey(86400), 1, "day 1 boundary")
equal(Data.DayKey(90000 + 86400 * 5), 5, "day 5")

-- Lazy realm+faction separation
local db = {}
local realmA = Data.GetStore(db, "Stormrage-Alliance")
local realmB = Data.GetStore(db, "Stormrage-Horde")
assert(realmA ~= realmB, "different realm+faction keys give different stores")
assert(db.realms["Stormrage-Alliance"] == realmA, "store stored under its key")
assert(type(realmA.items) == "table", "store has items table")

-- Running daily average across scans
Data.RecordScan(realmA, 1234, 10, { minBuyout = 100, avgBuyout = 120, qty = 5 })
local bucket = realmA.items[1234].history[10]
equal(bucket.minBuyout, 100, "first min")
equal(bucket.avgBuyout, 120, "first avg")
equal(bucket.qty, 5, "first qty")
equal(bucket.scans, 1, "first scans")

Data.RecordScan(realmA, 1234, 10, { minBuyout = 80, avgBuyout = 140, qty = 7 })
bucket = realmA.items[1234].history[10]
equal(bucket.minBuyout, 80, "min takes the lower of the two")
equal(bucket.avgBuyout, 130, "avg is running mean (120+140)/2")
equal(bucket.qty, 7, "qty is the latest total")
equal(bucket.scans, 2, "scans incremented")

-- Realm B is untouched by realm A writes
equal(realmB.items[1234], nil, "realm B has no item 1234")

-- History read is sorted ascending
Data.RecordScan(realmA, 1234, 12, { minBuyout = 90, avgBuyout = 90, qty = 1 })
Data.RecordScan(realmA, 1234, 11, { minBuyout = 95, avgBuyout = 95, qty = 2 })
local history = Data.GetHistory(realmA, 1234)
equal(#history, 3, "three days recorded")
equal(history[1].dayKey, 10, "sorted: day 10 first")
equal(history[2].dayKey, 11, "sorted: day 11 second")
equal(history[3].dayKey, 12, "sorted: day 12 third")

-- Watchlist accessors
Data.SetWatched(realmA, 1234, true)
Data.SetWatched(realmA, 5678, true)
Data.SetWatched(realmA, 1234, false)
local watched = Data.GetWatched(realmA)
equal(#watched, 1, "one item watched after toggling 1234 off")
equal(watched[1], 5678, "5678 remains watched")

-- Vendor + name caching
Data.SetVendor(realmA, 5678, 250)
Data.SetName(realmA, 5678, "Test Item")
equal(realmA.items[5678].vendorSell, 250, "vendor cached")
equal(realmA.items[5678].name, "Test Item", "name cached")

-- Purge by retention
local removed = Data.Purge(realmA, 12, 1) -- keep dayKey >= 11
equal(removed, 1, "one stale bucket removed (day 10)")
equal(realmA.items[1234].history[10], nil, "day 10 purged")
assert(realmA.items[1234].history[11] ~= nil, "day 11 kept")
assert(realmA.items[1234].history[12] ~= nil, "day 12 kept")

print("SafeItemFollow data tests passed")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && lua5.1 tests/test_data.lua`
Expected: FAIL — `cannot open Data.lua` or `attempt to index ... Data (a nil value)`.

- [ ] **Step 3: Write `Data.lua`**

```lua
local _, NS = ...

local Data = {}
NS.Data = Data

local DAY_SECONDS = NS.DAY_SECONDS or 86400

function Data.DayKey(serverTime)
    return math.floor((tonumber(serverTime) or 0) / DAY_SECONDS)
end

function Data.GetStore(db, realmKey)
    db.realms = db.realms or {}
    if not db.realms[realmKey] then
        db.realms[realmKey] = { items = {} }
    end
    return db.realms[realmKey]
end

function Data.GetItem(store, itemID)
    itemID = tonumber(itemID)
    if not store.items[itemID] then
        store.items[itemID] = {
            name = nil,
            vendorSell = nil,
            watched = false,
            history = {},
        }
    end
    return store.items[itemID]
end

function Data.SetName(store, itemID, name)
    Data.GetItem(store, itemID).name = name
end

function Data.SetVendor(store, itemID, vendorSell)
    Data.GetItem(store, itemID).vendorSell = tonumber(vendorSell)
end

function Data.SetWatched(store, itemID, watched)
    Data.GetItem(store, itemID).watched = watched and true or false
end

function Data.RecordScan(store, itemID, dayKey, summary)
    local item = Data.GetItem(store, itemID)
    local bucket = item.history[dayKey]
    if not bucket then
        bucket = { minBuyout = summary.minBuyout, avgBuyout = summary.avgBuyout, qty = summary.qty, scans = 0 }
        item.history[dayKey] = bucket
    end

    if bucket.scans == 0 then
        bucket.minBuyout = summary.minBuyout
        bucket.avgBuyout = summary.avgBuyout
    else
        if summary.minBuyout < bucket.minBuyout then
            bucket.minBuyout = summary.minBuyout
        end
        bucket.avgBuyout = (bucket.avgBuyout * bucket.scans + summary.avgBuyout) / (bucket.scans + 1)
    end
    bucket.qty = summary.qty
    bucket.scans = bucket.scans + 1
    return bucket
end

function Data.Purge(store, currentDayKey, retentionDays)
    local cutoff = currentDayKey - retentionDays
    local removed = 0
    for _, item in pairs(store.items) do
        for dayKey in pairs(item.history) do
            if dayKey < cutoff then
                item.history[dayKey] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

function Data.GetHistory(store, itemID)
    local item = store.items[tonumber(itemID)]
    local out = {}
    if not item then
        return out
    end
    for dayKey, bucket in pairs(item.history) do
        out[#out + 1] = {
            dayKey = dayKey,
            minBuyout = bucket.minBuyout,
            avgBuyout = bucket.avgBuyout,
            qty = bucket.qty,
        }
    end
    table.sort(out, function(a, b) return a.dayKey < b.dayKey end)
    return out
end

function Data.GetWatched(store)
    local out = {}
    for itemID, item in pairs(store.items) do
        if item.watched then
            out[#out + 1] = itemID
        end
    end
    table.sort(out)
    return out
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && lua5.1 tests/test_data.lua`
Expected: PASS — prints `SafeItemFollow data tests passed`.

- [ ] **Step 5: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add Data.lua tests/test_data.lua
git commit -m "feat: add Data module with daily aggregation, retention and realm store"
```

---

## Task 2: Rules.lua — throttle gate, row parsing, flip & historic-low

Pure logic plus a thin throttle wrapper around `CanSendAuctionQuery` (global-with-fallback so tests can mock it).

**Files:**
- Create: `Rules.lua`
- Test: `tests/test_rules.lua`

**Interfaces:**
- Consumes: nothing from earlier tasks at runtime; tests build a bare namespace.
- Produces (all on `NS.Rules`):
  - `Rules.CanQuery() -> boolean` — returns `CanSendAuctionQuery()` truthiness; if the API is absent returns `true`.
  - `Rules.PerUnit(buyout, count) -> number|nil` — `floor(buyout / count)`; returns `nil` when `buyout` is 0/nil or `count` < 1 (no buyout listed → not usable).
  - `Rules.ParseRow(row) -> parsed|nil` where `row = { itemID, name, count, buyout }`; returns `{ itemID, name, count, perUnit }` or `nil` if no usable buyout.
  - `Rules.SummarizeListings(rows) -> map` from `itemID` to `{ minBuyout, avgBuyout, qty, name }` aggregating all parsed rows for that item (`minBuyout`=min perUnit, `avgBuyout`=mean perUnit over listings, `qty`=sum of counts).
  - `Rules.IsFlip(perUnit, vendorSell, flipMargin) -> boolean` — `perUnit ~= nil and vendorSell ~= nil and perUnit < vendorSell - flipMargin`.
  - `Rules.FlipGain(perUnit, vendorSell, qty) -> number` — `(vendorSell - perUnit) * qty`.
  - `Rules.IsHistoricLow(perUnit, history) -> boolean` — `true` if `history` is empty or `perUnit < min(history[*].minBuyout)`.

- [ ] **Step 1: Write the failing test `tests/test_rules.lua`**

```lua
local namespace = {}
assert(loadfile("Rules.lua"))("SafeItemFollow", namespace)
local Rules = namespace.Rules

local function equal(actual, expected, label)
    assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

-- Throttle gate uses the global and falls back to true when absent
CanSendAuctionQuery = function() return true end
equal(Rules.CanQuery(), true, "gate true when API allows")
CanSendAuctionQuery = function() return false end
equal(Rules.CanQuery(), false, "gate false when API blocks")
CanSendAuctionQuery = nil
equal(Rules.CanQuery(), true, "gate true when API absent")

-- PerUnit
equal(Rules.PerUnit(1000, 5), 200, "per unit of a stack")
equal(Rules.PerUnit(1001, 5), 200, "per unit floored")
equal(Rules.PerUnit(0, 5), nil, "no buyout -> nil")
equal(Rules.PerUnit(1000, 0), nil, "no count -> nil")

-- ParseRow skips rows with no buyout
equal(Rules.ParseRow({ itemID = 1, name = "A", count = 5, buyout = 0 }), nil, "bid-only row skipped")
local parsed = Rules.ParseRow({ itemID = 1, name = "A", count = 5, buyout = 1000 })
equal(parsed.perUnit, 200, "parsed per unit")
equal(parsed.qty, 5, "parsed qty")

-- SummarizeListings aggregates per item
local summary = Rules.SummarizeListings({
    { itemID = 1, name = "A", count = 5, buyout = 1000 }, -- 200/u
    { itemID = 1, name = "A", count = 10, buyout = 3000 }, -- 300/u
    { itemID = 1, name = "A", count = 2, buyout = 0 },     -- skipped
    { itemID = 2, name = "B", count = 1, buyout = 500 },   -- 500/u
})
equal(summary[1].minBuyout, 200, "item 1 min per unit")
equal(summary[1].avgBuyout, 250, "item 1 avg per unit (200+300)/2")
equal(summary[1].qty, 15, "item 1 total qty (only buyout rows)")
equal(summary[1].name, "A", "item 1 name")
equal(summary[2].minBuyout, 500, "item 2 min")
equal(summary[2].qty, 1, "item 2 qty")

-- Flip detection with margin
equal(Rules.IsFlip(200, 250, 0), true, "below vendor is a flip")
equal(Rules.IsFlip(250, 250, 0), false, "equal to vendor is not a flip")
equal(Rules.IsFlip(200, 250, 60), false, "margin pushes threshold below per unit")
equal(Rules.IsFlip(180, 250, 60), true, "clears the margin (180 < 190)")
equal(Rules.IsFlip(nil, 250, 0), false, "no per unit is not a flip")
equal(Rules.FlipGain(200, 250, 10), 500, "gain = (250-200)*10")

-- Historic low
equal(Rules.IsHistoricLow(100, {}), true, "empty history is always a low")
local history = {
    { dayKey = 1, minBuyout = 150 },
    { dayKey = 2, minBuyout = 120 },
}
equal(Rules.IsHistoricLow(119, history), true, "below previous min is a new low")
equal(Rules.IsHistoricLow(120, history), false, "tying the min is not below it")
equal(Rules.IsHistoricLow(200, history), false, "above min is not a low")

print("SafeItemFollow rules tests passed")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && lua5.1 tests/test_rules.lua`
Expected: FAIL — `cannot open Rules.lua`.

- [ ] **Step 3: Write `Rules.lua`**

```lua
local _, NS = ...

local Rules = {}
NS.Rules = Rules

function Rules.CanQuery()
    if type(_G.CanSendAuctionQuery) == "function" then
        return _G.CanSendAuctionQuery() and true or false
    end
    return true
end

function Rules.PerUnit(buyout, count)
    buyout = tonumber(buyout) or 0
    count = tonumber(count) or 0
    if buyout <= 0 or count < 1 then
        return nil
    end
    return math.floor(buyout / count)
end

function Rules.ParseRow(row)
    if not row then
        return nil
    end
    local perUnit = Rules.PerUnit(row.buyout, row.count)
    if not perUnit then
        return nil
    end
    return {
        itemID = tonumber(row.itemID),
        name = row.name,
        qty = tonumber(row.count) or 0,
        perUnit = perUnit,
    }
end

function Rules.SummarizeListings(rows)
    local acc = {}
    for index = 1, #rows do
        local parsed = Rules.ParseRow(rows[index])
        if parsed and parsed.itemID then
            local entry = acc[parsed.itemID]
            if not entry then
                entry = { minBuyout = parsed.perUnit, sum = 0, listings = 0, qty = 0, name = parsed.name }
                acc[parsed.itemID] = entry
            end
            if parsed.perUnit < entry.minBuyout then
                entry.minBuyout = parsed.perUnit
            end
            entry.sum = entry.sum + parsed.perUnit
            entry.listings = entry.listings + 1
            entry.qty = entry.qty + parsed.qty
            entry.name = entry.name or parsed.name
        end
    end

    local out = {}
    for itemID, entry in pairs(acc) do
        out[itemID] = {
            minBuyout = entry.minBuyout,
            avgBuyout = math.floor(entry.sum / entry.listings),
            qty = entry.qty,
            name = entry.name,
        }
    end
    return out
end

function Rules.IsFlip(perUnit, vendorSell, flipMargin)
    if not perUnit or not vendorSell then
        return false
    end
    return perUnit < (vendorSell - (flipMargin or 0))
end

function Rules.FlipGain(perUnit, vendorSell, qty)
    return ((vendorSell or 0) - (perUnit or 0)) * (qty or 0)
end

function Rules.IsHistoricLow(perUnit, history)
    if not perUnit then
        return false
    end
    if not history or #history == 0 then
        return true
    end
    local lowest
    for index = 1, #history do
        local m = history[index].minBuyout
        if m and (not lowest or m < lowest) then
            lowest = m
        end
    end
    if not lowest then
        return true
    end
    return perUnit < lowest
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && lua5.1 tests/test_rules.lua`
Expected: PASS — prints `SafeItemFollow rules tests passed`.

- [ ] **Step 5: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add Rules.lua tests/test_rules.lua
git commit -m "feat: add Rules module with throttle gate, parsing, flip and historic-low"
```

---

## Task 3: Scanner.lua — directed queries + full paginated scan

Event-driven scan engine. WoW auction APIs are wrapped so tests can inject mocks. Pagination helpers and page reading are pure and unit-tested; the event glue is driven by `Core` (Task 9).

**Files:**
- Create: `Scanner.lua`
- Test: `tests/test_scanner.lua`

**Interfaces:**
- Consumes: `NS.DEFAULT_PER_PAGE` (Bootstrap), `NS.Rules` (Task 2). Tests build a namespace with both.
- Produces (on `NS.Scanner`):
  - `Scanner.PerPage() -> number` — `NUM_AUCTION_ITEMS_PER_PAGE` global if present else `NS.DEFAULT_PER_PAGE`.
  - `Scanner.PageCount(total) -> number` — `ceil(total / PerPage())`, minimum 0.
  - `Scanner:ReadCurrentPage() -> rows, total` — reads `GetNumAuctionItems("list")` (numShown, total) and `GetAuctionItemInfo("list", i)` for each shown index, returning an array of `{ itemID, name, count, buyout }` (raw rows; parsing/skip happens in Rules) and the total count.
  - `Scanner:BeginFullScan() -> scan` — resets `self.scan = { page=0, rows={}, total=nil, active=true, token=n }`.
  - `Scanner:IngestCurrentPage() -> hasMore` — reads the current page into `self.scan.rows`, advances `page`, returns whether more pages remain. Sets `active=false` when done.
  - `Scanner:Abort()` — invalidates the in-flight scan token and sets `self.scan = nil`.
  - `Scanner:QueryFullPage(page)` and `Scanner:QueryItem(name)` — issue `QueryAuctionItems(...)` for a page / a single item name; both no-op when `Rules.CanQuery()` is false (caller retries on the next tick).

- [ ] **Step 1: Write the failing test `tests/test_scanner.lua`**

```lua
local namespace = { DEFAULT_PER_PAGE = 50 }
assert(loadfile("Rules.lua"))("SafeItemFollow", namespace)
assert(loadfile("Scanner.lua"))("SafeItemFollow", namespace)
local Scanner = namespace.Scanner

local function equal(actual, expected, label)
    assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

-- PageCount with a partial final page
NUM_AUCTION_ITEMS_PER_PAGE = 50
equal(Scanner.PerPage(), 50, "per page from global")
equal(Scanner.PageCount(0), 0, "no auctions -> zero pages")
equal(Scanner.PageCount(50), 1, "exactly one full page")
equal(Scanner.PageCount(51), 2, "one over -> two pages")
equal(Scanner.PageCount(120), 3, "two full pages plus a partial third")

-- Mock a 3-row page; one row has no buyout
local total = 120
local pageData = {
    [0] = {
        { name = "A", count = 5, buyout = 1000, itemId = 11 },
        { name = "B", count = 2, buyout = 0,    itemId = 12 }, -- bid only
        { name = "C", count = 1, buyout = 700,  itemId = 13 },
    },
    [1] = {
        { name = "A", count = 10, buyout = 3000, itemId = 11 },
    },
    [2] = {
        { name = "D", count = 4, buyout = 800, itemId = 14 },
    },
}
local currentPage = 0
-- Classic signature: GetAuctionItemInfo("list", index) returns many values;
-- indices we use: 1 name, 3 count, 10 buyoutPrice, 17 itemId.
GetNumAuctionItems = function(_)
    return #pageData[currentPage], total
end
GetAuctionItemInfo = function(_, index)
    local r = pageData[currentPage][index]
    return r.name, "texture", r.count, 1, true, 60, "", 0, 0, r.buyout, 0, nil, nil, nil, nil, 0, r.itemId, true
end

-- ReadCurrentPage returns raw rows including the bid-only one
local rows, readTotal = Scanner:ReadCurrentPage()
equal(#rows, 3, "all shown rows returned (raw)")
equal(readTotal, 120, "total reported")
equal(rows[1].itemID, 11, "row 1 itemID")
equal(rows[1].buyout, 1000, "row 1 buyout")
equal(rows[2].buyout, 0, "row 2 bid only preserved as raw")

-- Full scan across three pages (last is partial: 1 row)
Scanner:BeginFullScan()
currentPage = 0
local more0 = Scanner:IngestCurrentPage()
equal(more0, true, "more pages after page 0")
currentPage = 1
local more1 = Scanner:IngestCurrentPage()
equal(more1, true, "more pages after page 1")
currentPage = 2
local more2 = Scanner:IngestCurrentPage()
equal(more2, false, "no more pages after the partial final page")

equal(#Scanner.scan.rows, 5, "accumulated all 5 raw rows across pages")

-- Feeding the accumulation through Rules produces per-item summaries
local summary = namespace.Rules.SummarizeListings(Scanner.scan.rows)
equal(summary[11].qty, 15, "item 11 qty summed across pages (5+10)")
equal(summary[11].minBuyout, 200, "item 11 min per unit (1000/5 vs 3000/10)")
equal(summary[12], nil, "bid-only item never summarized")
equal(summary[13].minBuyout, 700, "item 13 min")
equal(summary[14].minBuyout, 200, "item 14 min (800/4)")

-- Abort invalidates the scan
Scanner:Abort()
equal(Scanner.scan, nil, "abort clears the scan")

print("SafeItemFollow scanner tests passed")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && lua5.1 tests/test_scanner.lua`
Expected: FAIL — `cannot open Scanner.lua`.

- [ ] **Step 3: Write `Scanner.lua`**

```lua
local _, NS = ...

local Scanner = {}
NS.Scanner = Scanner

Scanner.token = 0

local function GetNumList()
    if type(_G.GetNumAuctionItems) == "function" then
        return _G.GetNumAuctionItems("list")
    end
    return 0, 0
end

local function GetInfo(index)
    if type(_G.GetAuctionItemInfo) == "function" then
        return _G.GetAuctionItemInfo("list", index)
    end
    return nil
end

function Scanner.PerPage()
    return tonumber(_G.NUM_AUCTION_ITEMS_PER_PAGE) or NS.DEFAULT_PER_PAGE or 50
end

function Scanner.PageCount(total)
    total = tonumber(total) or 0
    if total <= 0 then
        return 0
    end
    return math.ceil(total / Scanner.PerPage())
end

function Scanner:ReadCurrentPage()
    local numShown, total = GetNumList()
    numShown = tonumber(numShown) or 0
    local rows = {}
    for index = 1, numShown do
        local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemId = GetInfo(index)
        if name then
            rows[#rows + 1] = {
                itemID = tonumber(itemId),
                name = name,
                count = tonumber(count) or 1,
                buyout = tonumber(buyout) or 0,
            }
        end
    end
    return rows, tonumber(total) or 0
end

function Scanner:BeginFullScan()
    self.token = self.token + 1
    self.scan = { page = 0, rows = {}, total = nil, active = true, token = self.token }
    return self.scan
end

function Scanner:IngestCurrentPage()
    local scan = self.scan
    if not scan or not scan.active then
        return false
    end
    local rows, total = self:ReadCurrentPage()
    scan.total = total
    for index = 1, #rows do
        scan.rows[#scan.rows + 1] = rows[index]
    end
    scan.page = scan.page + 1
    local hasMore = scan.page < Scanner.PageCount(total)
    if not hasMore then
        scan.active = false
    end
    return hasMore
end

function Scanner:Abort()
    self.token = self.token + 1
    self.scan = nil
end

function Scanner:QueryFullPage(page)
    if not NS.Rules.CanQuery() then
        return false
    end
    if type(_G.QueryAuctionItems) == "function" then
        -- name, minLevel, maxLevel, page, usable, rarity, getAll, exactMatch, filterData
        _G.QueryAuctionItems("", nil, nil, page or 0, false, 0, false)
        return true
    end
    return false
end

function Scanner:QueryItem(name)
    if not name or not NS.Rules.CanQuery() then
        return false
    end
    if type(_G.QueryAuctionItems) == "function" then
        _G.QueryAuctionItems(name, nil, nil, 0, false, 0, false, true)
        return true
    end
    return false
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && lua5.1 tests/test_scanner.lua`
Expected: PASS — prints `SafeItemFollow scanner tests passed`.

- [ ] **Step 5: Run all three test files together**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && for t in tests/test_*.lua; do lua5.1 "$t" || exit 1; done`
Expected: three "tests passed" lines, exit code 0.

- [ ] **Step 6: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add Scanner.lua tests/test_scanner.lua
git commit -m "feat: add Scanner with paginated full scan and directed queries"
```

---

## Task 4: Config.lua — AceDB defaults, options, realm store wiring

Initializes the database and the options panel, and exposes the active realm+faction store + settings to the rest of the addon. No unit test (depends on AceDB/WoW); verified by syntax check and in-game.

**Files:**
- Create: `Config.lua`

**Interfaces:**
- Consumes: `NS.Addon`, `NS.L`, `NS.Data`.
- Produces (on `NS.Config`):
  - `Config:InitializeDatabase()` — creates `Addon.db = AceDB:New("SafeItemFollowDB", defaults, true)` and sets `NS.Store = Data.GetStore(Addon.db.global, NS.Config:RealmKey())`.
  - `Config:RealmKey() -> string` — `realmName.."-"..faction` from WoW APIs.
  - `Config:Settings() -> table` — `Addon.db.profile.settings` (`retentionDays`, `flipMargin`, `autoScanOnOpen`, `showOverlays`, `showTooltips`, `showMinimapButton`).
  - `Config:RegisterOptions()`, `Config:Open()`.
- Settings defaults: `retentionDays = 30`, `flipMargin = 0`, `autoScanOnOpen = true`, `showOverlays = true`, `showTooltips = true`, `showMinimapButton = true`.

- [ ] **Step 1: Write `Config.lua`**

```lua
local _, NS = ...
local Addon = NS.Addon
local L = NS.L

local Config = {}
NS.Config = Config

local defaults = {
    global = {
        realms = {},
    },
    profile = {
        settings = {
            retentionDays = 30,
            flipMargin = 0,
            autoScanOnOpen = true,
            showOverlays = true,
            showTooltips = true,
            showMinimapButton = true,
        },
    },
}

function Config:RealmKey()
    local realm = (type(GetRealmName) == "function" and GetRealmName()) or "UnknownRealm"
    local faction = (type(UnitFactionGroup) == "function" and UnitFactionGroup("player")) or "Neutral"
    return tostring(realm) .. "-" .. tostring(faction)
end

function Config:Settings()
    return Addon.db.profile.settings
end

function Config:InitializeDatabase()
    Addon.db = LibStub("AceDB-3.0"):New("SafeItemFollowDB", defaults, true)
    NS.Store = NS.Data.GetStore(Addon.db.global, self:RealmKey())
end

function Config:RegisterOptions()
    local settings = function() return Addon.db.profile.settings end
    local options = {
        type = "group",
        name = L.CONFIG_NAME,
        args = {
            description = { type = "description", name = L.ADDON_DESCRIPTION, order = 1 },
            retention = {
                type = "range", name = L.CONFIG_RETENTION, desc = L.CONFIG_RETENTION_DESC,
                order = 10, min = 1, max = 365, step = 1,
                get = function() return settings().retentionDays end,
                set = function(_, v) settings().retentionDays = v end,
            },
            flipMargin = {
                type = "range", name = L.CONFIG_FLIP_MARGIN, desc = L.CONFIG_FLIP_MARGIN_DESC,
                order = 20, min = 0, max = 1000000, step = 1, bigStep = 100,
                get = function() return settings().flipMargin end,
                set = function(_, v) settings().flipMargin = v end,
            },
            autoScan = {
                type = "toggle", name = L.CONFIG_AUTOSCAN, desc = L.CONFIG_AUTOSCAN_DESC, order = 30,
                get = function() return settings().autoScanOnOpen end,
                set = function(_, v) settings().autoScanOnOpen = v end,
            },
            overlays = {
                type = "toggle", name = L.CONFIG_OVERLAYS, order = 40,
                get = function() return settings().showOverlays end,
                set = function(_, v) settings().showOverlays = v end,
            },
            tooltips = {
                type = "toggle", name = L.CONFIG_TOOLTIPS, order = 41,
                get = function() return settings().showTooltips end,
                set = function(_, v) settings().showTooltips = v end,
            },
            minimap = {
                type = "toggle", name = L.CONFIG_MINIMAP_BUTTON, order = 42,
                get = function() return settings().showMinimapButton end,
                set = function(_, v)
                    settings().showMinimapButton = v
                    if NS.MinimapButton then NS.MinimapButton:Refresh() end
                end,
            },
        },
    }

    local profileOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(Addon.db)
    profileOptions.name = L.CONFIG_PROFILES
    profileOptions.order = 100
    options.args.profiles = profileOptions

    LibStub("AceConfig-3.0"):RegisterOptionsTable("SafeItemFollow", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SafeItemFollow", L.CONFIG_NAME)
end

function Config:Open()
    LibStub("AceConfigDialog-3.0"):Open("SafeItemFollow")
end
```

- [ ] **Step 2: Syntax-check**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && luac5.1 -p Config.lua`
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add Config.lua
git commit -m "feat: add Config with AceDB defaults, settings and options panel"
```

---

## Task 5: Tooltip.lua — history + flip line in item tooltips

Injects, for any item with stored history, a daily summary line; and a flip line when the latest min buyout per unit beats vendor. Reads only cached data; never queries the network.

**Files:**
- Create: `Tooltip.lua`

**Interfaces:**
- Consumes: `NS.Addon`, `NS.L`, `NS.Data`, `NS.Rules`, `NS.Config`, `NS.Store`.
- Produces (on `NS.Tooltip`): `Tooltip:Initialize()`, `Tooltip:AddInfo(tooltip, data)`.

- [ ] **Step 1: Write `Tooltip.lua`**

```lua
local _, NS = ...
local Addon = NS.Addon
local L = NS.L

local Tooltip = {}
NS.Tooltip = Tooltip

local function Money(copper)
    if not copper then return "?" end
    if type(GetCoinTextureString) == "function" then
        return GetCoinTextureString(copper)
    end
    return tostring(copper) .. "c"
end

local function IsForbidden(tooltip)
    if not tooltip or type(tooltip.IsForbidden) ~= "function" then return false end
    local ok, forbidden = pcall(tooltip.IsForbidden, tooltip)
    return ok and forbidden == true
end

local function TooltipItemID(tooltip, data)
    if type(data) == "table" and type(data.id) == "number" then
        return data.id
    end
    if tooltip and type(tooltip.GetItem) == "function" then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and link then
            return tonumber(link:match("item:(%d+)"))
        end
    end
    return nil
end

local function LatestMin(history)
    if #history == 0 then return nil end
    return history[#history].minBuyout, history[#history].avgBuyout
end

function Tooltip:AddInfo(tooltip, data)
    if not Addon.db or not NS.Config:Settings().showTooltips or IsForbidden(tooltip) or not NS.Store then
        return
    end
    local itemID = TooltipItemID(tooltip, data)
    if not itemID or tooltip.__SafeItemFollowID == itemID then
        return
    end

    local history = NS.Data.GetHistory(NS.Store, itemID)
    if #history == 0 then
        return
    end
    tooltip.__SafeItemFollowID = itemID

    local latestMin, latestAvg = LatestMin(history)
    tooltip:AddLine(string.format(L.TOOLTIP_HISTORY, #history, Money(latestMin), Money(latestAvg)), 0.35, 0.85, 1.00)

    local item = NS.Store.items[itemID]
    local vendor = item and item.vendorSell
    local settings = NS.Config:Settings()
    if vendor and NS.Rules.IsFlip(latestMin, vendor, settings.flipMargin) then
        local gain = vendor - latestMin
        tooltip:AddLine(string.format(L.TOOLTIP_FLIP, Money(latestMin), Money(vendor), Money(gain)), 0.30, 1.00, 0.30)
    end

    -- Historic low excludes today's own bucket (compare against prior days).
    local prior = {}
    for i = 1, #history - 1 do prior[#prior + 1] = history[i] end
    if NS.Rules.IsHistoricLow(latestMin, prior) and #prior > 0 then
        tooltip:AddLine(L.TOOLTIP_HISTORIC_LOW, 1.00, 0.82, 0.00)
    end

    tooltip:Show()
end

function Tooltip:ClearMarker(tooltip)
    tooltip.__SafeItemFollowID = nil
end

function Tooltip:Initialize()
    local function callback(tooltip, data) Tooltip:AddInfo(tooltip, data) end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, callback)
    else
        if GameTooltip then GameTooltip:HookScript("OnTooltipSetItem", callback) end
        if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", callback) end
    end
    if GameTooltip then GameTooltip:HookScript("OnTooltipCleared", function(t) Tooltip:ClearMarker(t) end) end
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipCleared", function(t) Tooltip:ClearMarker(t) end) end
end
```

- [ ] **Step 2: Syntax-check**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && luac5.1 -p Tooltip.lua`
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add Tooltip.lua
git commit -m "feat: add Tooltip with history, flip and historic-low lines"
```

---

## Task 6: Overlay.lua — highlight cheap / below-vendor AH rows

Adds colored highlights over the native auction browse rows whose buyout-per-unit is below vendor (flip) or at a historic low. Pure read of cached data; no clicks intercepted.

**Files:**
- Create: `Overlay.lua`

**Interfaces:**
- Consumes: `NS.Addon`, `NS.Data`, `NS.Rules`, `NS.Config`, `NS.Store`.
- Produces (on `NS.Overlay`): `Overlay:Initialize()`, `Overlay:RefreshVisible()`.

- [ ] **Step 1: Write `Overlay.lua`**

```lua
local _, NS = ...
local Addon = NS.Addon

local Overlay = {}
NS.Overlay = Overlay

local highlights = {}

local function GetInfo(index)
    if type(_G.GetAuctionItemInfo) == "function" then
        return _G.GetAuctionItemInfo("list", index)
    end
    return nil
end

local function EnsureHighlight(button)
    if highlights[button] then
        return highlights[button]
    end
    local tex = button:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(button)
    tex:SetColorTexture(0.1, 1.0, 0.1, 0.18)
    tex:Hide()
    highlights[button] = tex
    return tex
end

-- offset = index of the first row on the current page in the "list" results
local function GetOffset()
    if type(_G.FauxScrollFrame_GetOffset) == "function" and _G.AuctionsScrollFrame then
        return _G.FauxScrollFrame_GetOffset(_G.AuctionsScrollFrame) or 0
    end
    return 0
end

function Overlay:RefreshVisible()
    if not Addon.db or not NS.Config:Settings().showOverlays or not NS.Store then
        return
    end
    if type(_G.NUM_BROWSE_TO_DISPLAY) ~= "number" then
        return
    end

    local offset = GetOffset()
    local settings = NS.Config:Settings()
    for row = 1, _G.NUM_BROWSE_TO_DISPLAY do
        local button = _G["BrowseButton" .. row]
        if button then
            local tex = EnsureHighlight(button)
            tex:Hide()
            if button:IsShown() then
                local index = offset + row
                local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemId = GetInfo(index)
                local perUnit = NS.Rules.PerUnit(buyout, count)
                local item = itemId and NS.Store.items[tonumber(itemId)]
                if perUnit and item then
                    local flip = NS.Rules.IsFlip(perUnit, item.vendorSell, settings.flipMargin)
                    local history = NS.Data.GetHistory(NS.Store, itemId)
                    local low = NS.Rules.IsHistoricLow(perUnit, history)
                    if flip then
                        tex:SetColorTexture(0.1, 1.0, 0.1, 0.18)
                        tex:Show()
                    elseif low then
                        tex:SetColorTexture(1.0, 0.82, 0.0, 0.16)
                        tex:Show()
                    end
                end
            end
        end
    end
end

function Overlay:Initialize()
    if type(hooksecurefunc) == "function" and type(_G.AuctionFrameBrowse_Update) == "function" then
        hooksecurefunc("AuctionFrameBrowse_Update", function() Overlay:RefreshVisible() end)
    end
end
```

- [ ] **Step 2: Syntax-check**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && luac5.1 -p Overlay.lua`
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add Overlay.lua
git commit -m "feat: add Overlay highlighting flip and historic-low AH rows"
```

---

## Task 7: ActionState.lua + ActionButton.lua — full-scan driver & button

`ActionState` is a tiny progress object (unit-tested). `ActionButton` is the on-screen "Full scan" button plus the per-item directed-query trigger, both ordinary (non-protected) buttons calling read-only queries.

**Files:**
- Create: `ActionState.lua`
- Create: `ActionButton.lua`
- Test: append to `tests/test_rules.lua` (reuses the same harness; `ActionState` is pure)

**Interfaces:**
- Produces (on `NS.ActionState`):
  - `ActionState:New() -> state`.
  - `state:Begin(totalPages) -> state` — sets `running=true, page=0, total=totalPages`.
  - `state:Advance() -> page` — increments and returns the current page.
  - `state:IsDone() -> boolean` — `page >= total`.
  - `state:Finish()` / `state:IsRunning()`.
- Produces (on `NS.ActionButton`, alias `NS.Action`):
  - `ActionButton:Initialize()`, `ActionButton:SetLabel(text)`, `ActionButton:SetEnabled(bool)`.
  - `ActionButton:RequestFullScan()` — delegates to `Core`/`Scanner` wiring (Task 9 connects the event loop).

- [ ] **Step 1: Append failing ActionState tests to `tests/test_rules.lua`**

Add before the final `print(...)` line:

```lua
-- ActionState progress object
assert(loadfile("ActionState.lua"))("SafeItemFollow", namespace)
local state = namespace.ActionState:New()
equal(state:IsRunning(), false, "new state idle")
state:Begin(3)
equal(state:IsRunning(), true, "running after begin")
equal(state:IsDone(), false, "not done at page 0 of 3")
equal(state:Advance(), 1, "advance to page 1")
equal(state:Advance(), 2, "advance to page 2")
equal(state:Advance(), 3, "advance to page 3")
equal(state:IsDone(), true, "done when page reaches total")
state:Finish()
equal(state:IsRunning(), false, "idle after finish")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && lua5.1 tests/test_rules.lua`
Expected: FAIL — `cannot open ActionState.lua`.

- [ ] **Step 3: Write `ActionState.lua`**

```lua
local _, NS = ...

local ActionState = {}
NS.ActionState = ActionState

function ActionState:New()
    local state = { running = false, page = 0, total = 0 }
    setmetatable(state, { __index = ActionState })
    return state
end

function ActionState:Begin(totalPages)
    self.running = true
    self.page = 0
    self.total = tonumber(totalPages) or 0
    return self
end

function ActionState:Advance()
    self.page = self.page + 1
    return self.page
end

function ActionState:IsDone()
    return self.page >= self.total
end

function ActionState:IsRunning()
    return self.running == true
end

function ActionState:Finish()
    self.running = false
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && lua5.1 tests/test_rules.lua`
Expected: PASS — `SafeItemFollow rules tests passed`.

- [ ] **Step 5: Write `ActionButton.lua`**

```lua
local _, NS = ...
local Addon = NS.Addon
local L = NS.L

local ActionButton = {}
NS.ActionButton = ActionButton
NS.Action = ActionButton

local button

function ActionButton:SetLabel(text)
    if button then button:SetText(text) end
end

function ActionButton:SetEnabled(enabled)
    if not button then return end
    if enabled then button:Enable() else button:Disable() end
end

function ActionButton:RequestFullScan()
    if NS.Core and NS.Core.StartFullScan then
        NS.Core:StartFullScan()
    end
end

function ActionButton:Initialize()
    if button then return end
    local parent = _G.AuctionFrame
    if not parent then
        return
    end
    button = CreateFrame("Button", "SafeItemFollowScanButton", parent, "UIPanelButtonTemplate")
    button:SetSize(120, 22)
    button:SetText(L.BTN_FULL_SCAN)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -180, -16)
    button:SetScript("OnClick", function()
        ActionButton:RequestFullScan()
    end)
end
```

- [ ] **Step 6: Syntax-check the button**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && luac5.1 -p ActionButton.lua ActionState.lua`
Expected: no output, exit code 0.

- [ ] **Step 7: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add ActionState.lua ActionButton.lua tests/test_rules.lua
git commit -m "feat: add ActionState progress object and full-scan button"
```

---

## Task 8: MinimapButton.lua — open the window

Minimap toggle that shows the main window (left click) and options (right click).

**Files:**
- Create: `MinimapButton.lua`

**Interfaces:**
- Consumes: `NS.Addon`, `NS.L`, `NS.Config`, `NS.Core`.
- Produces (on `NS.MinimapButton`): `MinimapButton:Initialize()`, `MinimapButton:Refresh()`.

- [ ] **Step 1: Write `MinimapButton.lua`**

```lua
local _, NS = ...
local Addon = NS.Addon
local L = NS.L

local MinimapButton = {}
NS.MinimapButton = MinimapButton

local button

local function IsShownInProfile()
    return not Addon.db or NS.Config:Settings().showMinimapButton ~= false
end

local function SetTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_TITLE, 0.35, 0.85, 1.00)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_LEFT, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_TOOLTIP_RIGHT, 0.85, 0.85, 0.85)
    GameTooltip:Show()
end

function MinimapButton:Refresh()
    if not button then return end
    if IsShownInProfile() then button:Show() else button:Hide() end
end

function MinimapButton:Initialize()
    if button or not Minimap then return end

    button = CreateFrame("Button", "SafeItemFollowMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -2, -2)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER", 1, 1)
    button.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            NS.Config:Open()
        elseif NS.Core then
            NS.Core:Toggle()
        end
    end)
    button:SetScript("OnEnter", function(self) SetTooltip(self) end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    self:Refresh()
end
```

- [ ] **Step 2: Syntax-check**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && luac5.1 -p MinimapButton.lua`
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add MinimapButton.lua
git commit -m "feat: add minimap button to open the window"
```

---

## Task 9: Core.lua — AceGUI 3-tab window + event wiring

The capstone: the AceGUI window with three tabs (Watchlist/History, Market scan, Vendor flip), the event registration that drives auto-scan and the paginated full scan via the throttle gate, and `OnInitialize`/`OnEnable`.

**Files:**
- Create: `Core.lua`
- Update: `tests/IN_GAME_CHECKLIST.md`

**Interfaces:**
- Consumes: every prior module (`NS.Config`, `NS.Data`, `NS.Rules`, `NS.Scanner`, `NS.ActionState`, `NS.ActionButton`, `NS.Tooltip`, `NS.Overlay`, `NS.MinimapButton`, `NS.Store`, `NS.L`).
- Produces (on `NS.Core`): `Core:Toggle()`, `Core:Show()`, `Core:Hide()`, `Core:StartFullScan()`, `Core:SelectTab(tab)`, `Core:RefreshActiveTab()`.

- [ ] **Step 1: Write `Core.lua`**

```lua
local _, NS = ...
local Addon = NS.Addon
local L = NS.L

local Core = {}
NS.Core = Core

local AceGUI = LibStub("AceGUI-3.0")

local frame, tabGroup
local currentTab = "watchlist"
local lastMarketSummary = {}   -- itemID -> summary, from last full scan
local fullScanState

local function IsSupportedClient()
    if WOW_PROJECT_BURNING_CRUSADE_CLASSIC then
        return WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
    end
    local interfaceVersion = select(4, GetBuildInfo())
    return interfaceVersion and interfaceVersion >= 20500 and interfaceVersion < 20600
end

local function Money(copper)
    if not copper then return "?" end
    if type(GetCoinTextureString) == "function" then return GetCoinTextureString(copper) end
    return tostring(copper) .. "c"
end

----------------------------------------------------------------------
-- Scanning glue (throttle-gated)
----------------------------------------------------------------------

local scanTicker

local function StopTicker()
    if scanTicker then
        scanTicker:Cancel()
        scanTicker = nil
    end
end

function Core:StartFullScan()
    if not _G.AuctionFrame or not _G.AuctionFrame:IsShown() then
        return
    end
    fullScanState = NS.ActionState:New()
    NS.Scanner:BeginFullScan()
    lastMarketSummary = {}
    NS.Action:SetLabel(string.format(L.BTN_FULL_SCAN_RUNNING, 1))
    -- Kick the first page; AUCTION_ITEM_LIST_UPDATE drives the rest.
    self:PumpFullScan(true)
end

-- Called both to send the next query and (on AUCTION_ITEM_LIST_UPDATE) to
-- ingest the page that just arrived.
function Core:PumpFullScan(initial)
    if not NS.Scanner.scan then
        return
    end
    if initial then
        if not NS.Scanner:QueryFullPage(0) then
            StopTicker()
            scanTicker = C_Timer.NewTicker(0.2, function() Core:PumpFullScan(true) end, 1)
        end
        return
    end
end

-- Invoked by HandleAuctionListUpdate after a page has loaded.
function Core:OnListUpdated()
    if not NS.Scanner.scan or not NS.Scanner.scan.active then
        -- a directed (watchlist) refresh may have arrived; record it
        self:RecordWatchlistPage()
        return
    end
    local hasMore = NS.Scanner:IngestCurrentPage()
    local page = NS.Scanner.scan and NS.Scanner.scan.page or 0
    NS.Action:SetLabel(string.format(L.BTN_FULL_SCAN_RUNNING, page))
    if hasMore then
        local nextPage = page
        local function send()
            if not (NS.Scanner.scan and NS.Scanner.scan.active) then return end
            if not NS.Scanner:QueryFullPage(nextPage) then
                StopTicker()
                scanTicker = C_Timer.NewTicker(0.2, function()
                    if NS.Scanner:QueryFullPage(nextPage) then StopTicker() end
                end, 50)
            end
        end
        send()
    else
        self:FinishFullScan()
    end
end

function Core:FinishFullScan()
    local rows = NS.Scanner.scan and NS.Scanner.scan.rows or {}
    local summary = NS.Rules.SummarizeListings(rows)
    lastMarketSummary = summary

    -- Persist into the daily history + flag flips.
    local dayKey = NS.Data.DayKey(GetServerTime())
    local count, items = 0, 0
    for itemID, s in pairs(summary) do
        items = items + 1
        NS.Data.SetName(NS.Store, itemID, s.name)
        local _, _, _, _, _, _, _, _, _, _, vendor = GetItemInfo(itemID)
        if vendor then NS.Data.SetVendor(NS.Store, itemID, vendor) end
        NS.Data.RecordScan(NS.Store, itemID, dayKey, s)
        count = count + s.qty
    end
    NS.Data.Purge(NS.Store, dayKey, NS.Config:Settings().retentionDays)

    if fullScanState then fullScanState:Finish() end
    NS.Scanner.scan = nil
    NS.Action:SetLabel(L.BTN_FULL_SCAN)
    Addon:Print(string.format(L.MSG_SCAN_DONE, count, items))
    NS.Overlay:RefreshVisible()
    self:RefreshActiveTab()
end

-- Directed watchlist queries: one item at a time on open.
local watchQueue = {}

function Core:QueueWatchlistScan()
    watchQueue = NS.Data.GetWatched(NS.Store)
    self:PumpWatchQueue()
end

function Core:PumpWatchQueue()
    if #watchQueue == 0 then return end
    local itemID = watchQueue[1]
    local name = NS.Store.items[itemID] and NS.Store.items[itemID].name
    if not name then
        name = GetItemInfo(itemID)
    end
    if not name then
        -- item data not loaded yet; request and retry next tick
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        C_Timer.After(0.3, function() Core:PumpWatchQueue() end)
        return
    end
    if NS.Scanner:QueryItem(name) then
        Core.__activeWatchID = itemID
    else
        C_Timer.After(0.2, function() Core:PumpWatchQueue() end)
    end
end

function Core:RecordWatchlistPage()
    local itemID = Core.__activeWatchID
    if not itemID then return end
    local rows = select(1, NS.Scanner:ReadCurrentPage())
    local summary = NS.Rules.SummarizeListings(rows)
    local s = summary[itemID]
    if s then
        local dayKey = NS.Data.DayKey(GetServerTime())
        NS.Data.SetName(NS.Store, itemID, s.name)
        local _, _, _, _, _, _, _, _, _, _, vendor = GetItemInfo(itemID)
        if vendor then NS.Data.SetVendor(NS.Store, itemID, vendor) end
        NS.Data.RecordScan(NS.Store, itemID, dayKey, s)
    end
    Core.__activeWatchID = nil
    table.remove(watchQueue, 1)
    if #watchQueue > 0 then
        C_Timer.After(0.2, function() Core:PumpWatchQueue() end)
    else
        NS.Data.Purge(NS.Store, NS.Data.DayKey(GetServerTime()), NS.Config:Settings().retentionDays)
        Core:RefreshActiveTab()
    end
end

----------------------------------------------------------------------
-- Window / tabs
----------------------------------------------------------------------

local function ClearContainer(container)
    container:ReleaseChildren()
end

local function DrawWatchlist(container)
    local watched = NS.Data.GetWatched(NS.Store)
    if #watched == 0 then
        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText(L.HISTORY_EMPTY)
        container:AddChild(label)
        return
    end
    for index = 1, #watched do
        local itemID = watched[index]
        local item = NS.Store.items[itemID]
        local history = NS.Data.GetHistory(NS.Store, itemID)
        local latest = history[#history]
        local row = AceGUI:Create("InteractiveLabel")
        row:SetFullWidth(true)
        row:SetText(string.format("%s  -  min %s  avg %s",
            (item and item.name) or ("item:" .. itemID),
            latest and Money(latest.minBuyout) or "?",
            latest and Money(latest.avgBuyout) or "?"))
        row:SetCallback("OnClick", function() Core:ShowHistory(container, itemID) end)
        container:AddChild(row)
    end
end

function Core:ShowHistory(container, itemID)
    local history = NS.Data.GetHistory(NS.Store, itemID)
    local header = AceGUI:Create("Label")
    header:SetFullWidth(true)
    header:SetText(L.HISTORY_HEADER)
    container:AddChild(header)
    for index = 1, #history do
        local point = history[index]
        local line = AceGUI:Create("Label")
        line:SetFullWidth(true)
        line:SetText(string.format("%s %d:  min %s  avg %s  qty %d",
            L.COL_DAY, point.dayKey, Money(point.minBuyout), Money(point.avgBuyout), point.qty))
        container:AddChild(line)
    end
end

local function DrawMarket(container)
    local button = AceGUI:Create("Button")
    button:SetText(L.BTN_FULL_SCAN)
    button:SetCallback("OnClick", function() Core:StartFullScan() end)
    container:AddChild(button)

    local sorted = {}
    for itemID, s in pairs(lastMarketSummary) do
        sorted[#sorted + 1] = { itemID = itemID, s = s }
    end
    table.sort(sorted, function(a, b) return a.s.minBuyout < b.s.minBuyout end)

    if #sorted == 0 then
        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText(L.MARKET_EMPTY)
        container:AddChild(label)
        return
    end
    for index = 1, #sorted do
        local e = sorted[index]
        local row = AceGUI:Create("Label")
        row:SetFullWidth(true)
        row:SetText(string.format("%s  -  min %s  avg %s  qty %d",
            e.s.name or ("item:" .. e.itemID), Money(e.s.minBuyout), Money(e.s.avgBuyout), e.s.qty))
        container:AddChild(row)
    end
end

local function DrawFlip(container)
    local settings = NS.Config:Settings()
    local flips = {}
    for itemID, s in pairs(lastMarketSummary) do
        local item = NS.Store.items[itemID]
        local vendor = item and item.vendorSell
        if vendor and NS.Rules.IsFlip(s.minBuyout, vendor, settings.flipMargin) then
            flips[#flips + 1] = {
                itemID = itemID, s = s, vendor = vendor,
                gain = NS.Rules.FlipGain(s.minBuyout, vendor, s.qty),
            }
        end
    end
    table.sort(flips, function(a, b) return a.gain > b.gain end)

    if #flips == 0 then
        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText(L.FLIP_EMPTY)
        container:AddChild(label)
        return
    end
    for index = 1, #flips do
        local e = flips[index]
        local row = AceGUI:Create("InteractiveLabel")
        row:SetFullWidth(true)
        row:SetText(string.format("%s  -  buy %s  vendor %s  %s %s",
            e.s.name or ("item:" .. e.itemID), Money(e.s.minBuyout), Money(e.vendor), L.COL_GAIN, Money(e.gain)))
        -- Read-only: clicking only triggers a search query so the user can buy manually.
        row:SetCallback("OnClick", function()
            if e.s.name then NS.Scanner:QueryItem(e.s.name) end
        end)
        container:AddChild(row)
    end
end

function Core:RefreshActiveTab()
    if not tabGroup then return end
    ClearContainer(tabGroup)
    if currentTab == "watchlist" then
        DrawWatchlist(tabGroup)
    elseif currentTab == "market" then
        DrawMarket(tabGroup)
    else
        DrawFlip(tabGroup)
    end
end

function Core:SelectTab(tab)
    currentTab = tab
    self:RefreshActiveTab()
end

local function BuildFrame()
    frame = AceGUI:Create("Frame")
    frame:SetTitle(L.WINDOW_TITLE)
    frame:SetLayout("Fill")
    frame:SetCallback("OnClose", function(widget) widget:Hide() end)

    tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("List")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    tabGroup:SetTabs({
        { text = L.TAB_WATCHLIST, value = "watchlist" },
        { text = L.TAB_MARKET, value = "market" },
        { text = L.TAB_FLIP, value = "flip" },
    })
    tabGroup:SetCallback("OnGroupSelected", function(_, _, tab) Core:SelectTab(tab) end)
    frame:AddChild(tabGroup)
    tabGroup:SelectTab("watchlist")
end

function Core:Show()
    if not frame then BuildFrame() end
    frame:Show()
    self:RefreshActiveTab()
end

function Core:Hide()
    if frame then frame:Hide() end
end

function Core:Toggle()
    if frame and frame.frame and frame.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local eventFrame

function Addon:HandleSlash(input)
    local command = tostring(input or ""):match("^%s*(.-)%s*$"):lower()
    if command == "config" or command == "options" then
        NS.Config:Open()
    elseif command == "scan" then
        NS.Core:StartFullScan()
    elseif command == "show" or command == "" then
        NS.Core:Show()
    elseif command == "hide" then
        NS.Core:Hide()
    else
        self:Print(L.MSG_HELP)
    end
end

function Addon:HandleEvent(event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        NS.Action:Initialize()
        if NS.Config:Settings().autoScanOnOpen then
            C_Timer.After(0.5, function() NS.Core:QueueWatchlistScan() end)
        end
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        NS.Core:OnListUpdated()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        NS.Scanner:Abort()
        if fullScanState then fullScanState:Finish() end
        StopTicker()
        watchQueue = {}
        NS.Action:SetLabel(L.BTN_FULL_SCAN)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- item data may now be available for a pending watchlist item
        if #watchQueue > 0 and not Core.__activeWatchID then
            NS.Core:PumpWatchQueue()
        end
    end
end

function Addon:RegisterEvents()
    eventFrame = CreateFrame("Frame")
    local events = {
        "AUCTION_HOUSE_SHOW",
        "AUCTION_ITEM_LIST_UPDATE",
        "AUCTION_HOUSE_CLOSED",
        "GET_ITEM_INFO_RECEIVED",
    }
    for index = 1, #events do
        eventFrame:RegisterEvent(events[index])
    end
    eventFrame:SetScript("OnEvent", function(_, event, ...) Addon:HandleEvent(event, ...) end)
end

function Addon:OnInitialize()
    NS.IsSupportedClient = IsSupportedClient()
    NS.Config:InitializeDatabase()
    NS.Config:RegisterOptions()
    NS.Tooltip:Initialize()
    NS.Overlay:Initialize()
    NS.MinimapButton:Initialize()
    self:RegisterEvents()
    self:RegisterChatCommand("safeitemfollow", "HandleSlash")
    self:RegisterChatCommand("sif", "HandleSlash")
end

function Addon:OnEnable()
    if not NS.IsSupportedClient then
        self:Print(L.MSG_UNSUPPORTED)
    end
end
```

- [ ] **Step 2: Syntax-check the whole addon**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && luac5.1 -p Bootstrap.lua Locales.lua Data.lua Rules.lua Scanner.lua Tooltip.lua Overlay.lua ActionState.lua ActionButton.lua MinimapButton.lua Config.lua Core.lua`
Expected: no output, exit code 0.

- [ ] **Step 3: Run the full test suite**

Run: `cd /home/dnthdev/proyectos/Addons/SafeItemFollow && for t in tests/test_*.lua; do lua5.1 "$t" || exit 1; done`
Expected: `SafeItemFollow data tests passed`, `SafeItemFollow rules tests passed`, `SafeItemFollow scanner tests passed`; exit code 0.

- [ ] **Step 4: Write `tests/IN_GAME_CHECKLIST.md`**

```markdown
# In-Game Checklist

Target client:

- WoW TBC Classic Anniversary 2.5.5 (`Interface 20505`)

1. Install the full `SafeItemFollow` folder under the active client AddOns path.
2. Log in; confirm no Lua errors at load.
3. `/sif` opens the window with three tabs: Watchlist, Market scan, Vendor flip.
4. Left-click the minimap button to toggle the window; right-click opens options.
5. Open the auction house. Confirm the "Full scan" button appears on the AuctionFrame.
6. Click "Full scan"; confirm the label shows page progress and a completion chat message.
7. Confirm the Market scan tab fills with results sorted by min price.
8. Confirm the Vendor flip tab lists only items with buyout/unit below vendor, sorted by est. gain.
9. Add an item to the watchlist; reopen the AH and confirm a directed query records that item.
10. Mouse over a known item; confirm the tooltip shows the daily history line (and a flip line where applicable).
11. With "Highlight cheap rows" enabled, browse the AH and confirm flip/historic-low rows are tinted.
12. Close the AH mid-scan; confirm the scan aborts cleanly with no errors.
13. Confirm NO automatic buying/selling ever occurs — every purchase requires your own click in the native AH.
14. Reload (`/reload`); confirm history persists and old buckets beyond retention are purged.
```

- [ ] **Step 5: Commit**

```bash
cd /home/dnthdev/proyectos/Addons/SafeItemFollow
git add Core.lua tests/IN_GAME_CHECKLIST.md
git commit -m "feat: add Core window, event wiring and in-game checklist"
```

---

## Self-Review notes (spec coverage)

- **Hybrid model** — directed watchlist queries (`Core:QueueWatchlistScan`/`PumpWatchQueue`, `Scanner:QueryItem`) + on-demand full paginated scan (`Core:StartFullScan`/`OnListUpdated`, `Scanner:QueryFullPage`/`IngestCurrentPage`). ✔ Tasks 3, 9
- **Compliance** — only read APIs; throttle via `Rules.CanQuery`/`CanSendAuctionQuery`; waits `AUCTION_ITEM_LIST_UPDATE`; vendor from `GetItemInfo`; no bid/post calls; flip "buy" only re-queries. ✔ Tasks 2, 3, 9
- **Data model** — realm+faction store, daily bucket, running average, retention purge, history read, watchlist/vendor caching. ✔ Task 1
- **Three tabs** — Watchlist/History, Market scan, Vendor flip. ✔ Task 9
- **Error handling** — item data not loaded → `RequestLoadItemDataByID` + retry; throttle-blocked → ticker retry; AH closed mid-scan → `Scanner:Abort`; empty DB → lazy realm init; API absent → `C_*`/`_G` fallbacks. ✔ Tasks 1, 3, 9
- **Tests** — `test_data`, `test_rules` (+ActionState), `test_scanner` with multi-page + partial final page. ✔ Tasks 1, 2, 3, 7
- **Load order / .toc / locales** — ✔ Task 0

**Known follow-ups (not blocking v1):** the full-scan page-advance retry loop in `Core:OnListUpdated` is conservative and may warrant tuning against real AH throttle timing during in-game testing (Task 9 checklist item 6); the sparkline mentioned in the spec is rendered here as a daily list (AceGUI has no native sparkline) — a drawn sparkline can be added later without schema changes.
```
