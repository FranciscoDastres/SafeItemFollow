# SafeItemFollow

Addon de subasta para WoW 20 Aniversario (TBC Classic) de la familia **Safe\***.

Escanea precios de la casa de subastas, guarda historial por ítem y visualiza su
evolución en el tiempo. Modelo híbrido: queries dirigidas a una *watchlist* + un
scan completo paginado bajo demanda. Incluye una sección de **flip a vendedor**
(buyout por unidad vs. precio de venta al vendedor NPC).

**Solo lectura y visualización.** Toda compra/venta la realiza el usuario
manualmente — sin automatización de acciones, respetando las normas de Blizzard.

## Uso

- Copia la carpeta completa `SafeItemFollow` al directorio `Interface/AddOns` del cliente activo.
- Dentro del juego usa `/sif` o `/safeitemfollow show` para abrir la ventana.
- Si no aparece nada, usa `/sif debug` para confirmar que el addon registro comandos, tiene librerias y ve la API de subasta del cliente.
- Abre la casa de subastas y usa `Full scan` para registrar precios.
- Agrega items a la watchlist pegando un link o ID numerico.
- La pestana `Vendor flip` solo muestra oportunidades y ejecuta busquedas de lectura; la compra sigue siendo manual en la UI nativa.

## Desarrollo

Validacion local esperada:

```bash
luac5.1 -p Bootstrap.lua Locales.lua Data.lua Rules.lua Scanner.lua Tooltip.lua Overlay.lua ActionState.lua ActionButton.lua MinimapButton.lua Config.lua Core.lua
for t in tests/test_*.lua; do lua5.1 "$t" || exit 1; done
```

El diseno está en [`docs/superpowers/specs/`](docs/superpowers/specs/). El checklist manual está en [`tests/IN_GAME_CHECKLIST.md`](tests/IN_GAME_CHECKLIST.md).
