# SafeItemFollow — Diseño

**Fecha:** 2026-06-28
**Estado:** Aprobado, pendiente de plan de implementación
**Objetivo de cliente (WoW):** TBC Classic Anniversary (Interface 20505) y Mists Classic (50504)

## Resumen

Addon de subasta para la familia **Safe\***. Escanea precios de la casa de
subastas, guarda historial por ítem y visualiza su evolución en el tiempo.
Modelo **híbrido**: queries dirigidas a una watchlist + un scan completo
paginado bajo demanda. Incluye una sección aparte de **flip a vendedor**
(comparar buyout por unidad contra el precio de venta al vendedor NPC) para
detectar oportunidades de compra-reventa. Toda acción de compra/venta es
manual; el addon solo lee y visualiza.

## Filosofía de compliance (el "Safe")

- **Solo lectura** de la subasta vía API clásica: `QueryAuctionItems`,
  `GetNumAuctionItems("list")`, `GetAuctionItemInfo`. Válida en TBC (20505) y
  MoP Classic (50504). No es acción protegida → el scan puede dispararse solo
  al abrir la AH.
- **Throttle respetado:** cada query pasa por `CanSendAuctionQuery()` y espera
  el evento `AUCTION_ITEM_LIST_UPDATE`. El scan paginado avanza página a página
  con esa compuerta.
- **Cero automatización de compra/venta.** No se invoca `PlaceAuctionBid` ni
  `PostAuction`. El botón de "comprar" del flip solo selecciona/resalta la fila;
  el clic final lo da el usuario (hardware event).
- **Precio de vendedor 100% local** vía `GetItemInfo` (campo `sellPrice`).
- Sin binarios, sin ofuscación, gratis, nada que la UI nativa no pueda hacer.

## Arquitectura (espejo de los addons Safe\* existentes)

Módulos cargados con `loadfile("X.lua")(addonName, NS)`; cada uno cuelga su
tabla de `NS`.

| Módulo | Responsabilidad |
|---|---|
| `Bootstrap.lua` | Namespace, AceAddon, constantes, defaults de DB |
| `Locales.lua` | esES / esMX / enUS |
| `Data.lua` | Esquema DB, registrar scan, agregación diaria (promedio corriente), purga por retención, lectura de historial |
| `Rules.lua` | Compuerta de throttle, parseo de resultados, lógica de flip (buyout/unidad vs vendor) y "precio bajo histórico" |
| `Scanner.lua` | Motor de scan: queries dirigidas (watchlist) + scan paginado completo; event-driven |
| `Tooltip.lua` | Inyecta historial + línea de flip en el tooltip del ítem |
| `Overlay.lua` | Sobre la AH nativa: resalta filas baratas / bajo vendedor |
| `Core.lua` | Ventana AceGUI con 3 pestañas + cableado |
| `ActionState.lua` / `ActionButton.lua` | Botón manual "Scan completo" y disparo de query por ítem |
| `MinimapButton.lua` | Abre la ventana |
| `Config.lua` | Días de retención, margen de flip, auto-scan al abrir (toggle) |
| `Libs/` | Stack Ace3 (LibStub, CallbackHandler, AceAddon/DB/Console/GUI/Config/DBOptions) |
| `tests/` | Tests Lua planos con asserts |

### `.toc`
```
## Interface: 20505, 50504
## Title: SafeItemFollow
## SavedVariables: SafeItemFollowDB
## Category: Auction House
```
Orden de carga igual al de SafeProspecting: Libs → Bootstrap → Locales → Data →
Rules → Scanner → Tooltip → Overlay → ActionState → ActionButton →
MinimapButton → Config → Core.

## Modelo de datos (`SafeItemFollowDB`)

Separado por realm + facción. Por ítem, **un punto resumen por día**:

```lua
items[itemID] = {
  name        = "...",
  vendorSell  = 1234,        -- copper, cacheado de GetItemInfo
  watched     = true,        -- pertenece a la watchlist
  history = {
    [dayKey] = {             -- dayKey = floor(serverTime / 86400) (UTC day)
      minBuyout = 0,         -- mínimo buyout/unidad visto en el día
      avgBuyout = 0,         -- promedio corriente ponderado por scans
      qty       = 0,         -- última cantidad total vista
      scans     = 0,         -- nº de scans agregados ese día
    },
  },
}
```

- Cada scan del día actualiza el bucket de hoy:
  - `avgBuyout = (avgBuyout * scans + nuevoAvg) / (scans + 1)`
  - `minBuyout = min(minBuyout, nuevoMin)`
  - `qty = nuevaQtyTotal`
  - `scans = scans + 1`
- Purga buckets más viejos que `settings.retentionDays`.
- Al seleccionar un ítem en la ventana se dibuja su historial diario
  (`minBuyout` / `avgBuyout` por día) como lista + sparkline.

```lua
settings = {
  retentionDays  = 30,
  flipMargin     = 0,      -- margen extra exigido sobre vendorSell (0 = cualquier ganancia)
  autoScanOnOpen = true,   -- queries de watchlist automáticas al abrir AH
}
```

## Las 3 pestañas (Core / AceGUI)

1. **Watchlist / Historial:** ítems seguidos; al seleccionar uno → gráfico de
   evolución diaria + min / media / cantidad. Añadir/quitar de la watchlist.
2. **Scan de mercado:** resultado del último scan paginado; tabla ordenable por
   precio/cantidad; botón "Scan completo".
3. **Flip a vendedor** (sección aparte): ítems con `buyoutPorUnidad < vendorSell
   - flipMargin`; ordenado por ganancia estimada `(vendorSell - buyoutPorUnidad)
   * qty`. El usuario decide y compra a mano.

## Flujo de datos

1. `AUCTION_HOUSE_SHOW` → si `autoScanOnOpen`, Scanner encola queries dirigidas
   de los ítems en watchlist.
2. Por cada query: comprobar `CanSendAuctionQuery()` → `QueryAuctionItems(...)`
   → al recibir `AUCTION_ITEM_LIST_UPDATE`, leer `GetNumAuctionItems("list")` y
   recorrer con `GetAuctionItemInfo("list", i)`.
3. Rules parsea filas (buyout/unidad, cantidad) → Data registra en el bucket de
   hoy.
4. Data alimenta: ventana (3 pestañas), Tooltip, Overlay y detección de flip.
5. **Scan completo:** recorre páginas `0..N` (`GetNumAuctionItems` total /
   resultados por página), cada página tras pasar la compuerta de throttle,
   acumulando hasta la última página.

## Manejo de errores

- Datos de ítem aún no cargados → `RequestLoadItemDataByID` (o `GetItemInfo`
  fallback) y reintento cuando lleguen.
- Query bloqueada por throttle → reintento en el siguiente tick cuando
  `CanSendAuctionQuery()` lo permita.
- AH cerrada a mitad de scan (`AUCTION_HOUSE_CLOSED`) → invalidar el token de
  scan en curso y limpiar estado.
- DB vacío / realm nuevo → inicialización perezosa de la rama realm+facción.
- API ausente (`C_Container` vs global) → mismo patrón de fallback que
  SafeProspecting/Scanner.lua.

## Tests (Lua plano, como los existentes)

- `test_data.lua`: promedio corriente diario, purga por retención, separación
  por realm+facción, inicialización perezosa.
- `test_rules.lua`: detección de flip (umbral `flipMargin`), parseo de filas,
  compuerta de throttle, "precio bajo histórico".
- `test_scanner.lua`: paginación con `GetAuctionItemInfo` mockeado (varias
  páginas, página parcial final).

## Fuera de alcance (YAGNI)

- Auto-compra / sniping (prohibido por compliance).
- Exportar datos a web (posible futuro, no en v1).
- Resolución intradía / cada-scan en bruto (se eligió resumen diario).
- Cross-realm / sincronización entre personajes más allá de realm+facción.
