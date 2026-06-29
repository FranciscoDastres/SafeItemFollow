local _, NS = ...

local enUS = {
    ADDON_DESCRIPTION = "Read-only auction price history and vendor-flip finder.",
    WINDOW_TITLE = "SafeItemFollow",

    TAB_WATCHLIST = "Watchlist",
    TAB_MARKET = "Market scan",
    TAB_FLIP = "Vendor flip",

    BTN_ADD = "Add",
    BTN_REMOVE = "Remove",
    BTN_SCAN = "Scan",
    BTN_FULL_SCAN = "Full scan",
    BTN_FULL_SCAN_RUNNING = "Scanning page %d",
    BTN_QUERY = "Search",
    BTN_WATCH = "Watch",

    ADD_WATCH_LABEL = "Item ID or item link",
    ADD_WATCH_DESC = "Paste an item link or numeric item ID.",
    WATCHLIST_EMPTY = "No watched items yet.",
    HISTORY_EMPTY = "No price history recorded yet.",
    HISTORY_HEADER = "Daily history",
    MARKET_EMPTY = "No full scan results yet.",
    FLIP_EMPTY = "No vendor-flip opportunities in the latest scan.",

    COL_DAY = "Day",
    COL_MIN = "Min",
    COL_AVG = "Avg",
    COL_QTY = "Qty",
    COL_GAIN = "Gain",

    TOOLTIP_HISTORY = "SafeItemFollow - last %d days: min %s, avg %s",
    TOOLTIP_VENDOR_FLIP = "Vendor flip: buy %s, vendor %s",
    OVERLAY_FLIP = "Vendor flip",
    OVERLAY_LOW = "Historic low",

    MINIMAP_TOOLTIP_TITLE = "SafeItemFollow",
    MINIMAP_TOOLTIP_LEFT = "Left-click: open window",
    MINIMAP_TOOLTIP_RIGHT = "Right-click: options",

    CONFIG_NAME = "SafeItemFollow",
    CONFIG_RETENTION = "Retention days",
    CONFIG_RETENTION_DESC = "Number of daily history buckets to keep per item.",
    CONFIG_FLIP_MARGIN = "Vendor margin",
    CONFIG_FLIP_MARGIN_DESC = "Extra copper required above break-even before an item is flagged as a vendor flip.",
    CONFIG_AUTO_SCAN = "Auto-scan watchlist",
    CONFIG_AUTO_SCAN_DESC = "Query watched items when the auction house opens.",
    CONFIG_TOOLTIPS = "Item tooltips",
    CONFIG_OVERLAYS = "Auction row highlights",
    CONFIG_MINIMAP_BUTTON = "Minimap button",
    CONFIG_PROFILES = "Profiles",

    MSG_HELP = "Commands: /safeitemfollow show, /safeitemfollow config, /safeitemfollow scan",
    MSG_UNSUPPORTED = "This build targets TBC Classic Anniversary 2.5.5 or Mists of Pandaria Classic 5.5.x.",
    MSG_AH_REQUIRED = "Open the auction house before scanning.",
    MSG_SCAN_STARTED = "Full auction scan started.",
    MSG_SCAN_DONE = "Scan complete: %d auctions across %d items.",
    MSG_SCAN_ABORTED = "Auction scan aborted.",
    MSG_WATCH_ADDED = "Watching item %d.",
    MSG_WATCH_REMOVED = "Removed item %d from watchlist.",
    MSG_INVALID_ITEM = "Paste a valid item link or numeric item ID.",
    MSG_QUERY_THROTTLED = "Auction query is throttled; waiting.",
}

local es = {
    ADDON_DESCRIPTION = "Historial de precios de subasta (solo lectura) y buscador de reventa al vendedor.",

    TAB_WATCHLIST = "Watchlist",
    TAB_MARKET = "Scan de mercado",
    TAB_FLIP = "Flip a vendedor",

    BTN_ADD = "Agregar",
    BTN_REMOVE = "Quitar",
    BTN_SCAN = "Escanear",
    BTN_FULL_SCAN = "Scan completo",
    BTN_FULL_SCAN_RUNNING = "Escaneando pagina %d",
    BTN_QUERY = "Buscar",
    BTN_WATCH = "Seguir",

    ADD_WATCH_LABEL = "ID o link de item",
    ADD_WATCH_DESC = "Pega un link de item o un ID numerico.",
    WATCHLIST_EMPTY = "Aun no hay items seguidos.",
    HISTORY_EMPTY = "Aun no hay historial de precios.",
    HISTORY_HEADER = "Historial diario",
    MARKET_EMPTY = "Aun no hay resultados de scan completo.",
    FLIP_EMPTY = "No hay oportunidades de flip a vendedor en el ultimo scan.",

    COL_DAY = "Dia",
    COL_MIN = "Min",
    COL_AVG = "Media",
    COL_QTY = "Cant",
    COL_GAIN = "Ganancia",

    TOOLTIP_HISTORY = "SafeItemFollow - ultimos %d dias: min %s, media %s",
    TOOLTIP_VENDOR_FLIP = "Flip a vendedor: compra %s, vendedor %s",
    OVERLAY_FLIP = "Flip vendedor",
    OVERLAY_LOW = "Minimo historico",

    MINIMAP_TOOLTIP_LEFT = "Click izquierdo: abrir ventana",
    MINIMAP_TOOLTIP_RIGHT = "Click derecho: opciones",

    CONFIG_RETENTION = "Dias de retencion",
    CONFIG_RETENTION_DESC = "Numero de buckets diarios que se guardan por item.",
    CONFIG_FLIP_MARGIN = "Margen a vendedor",
    CONFIG_FLIP_MARGIN_DESC = "Cobre extra sobre el punto de equilibrio antes de marcar flip a vendedor.",
    CONFIG_AUTO_SCAN = "Auto-scan watchlist",
    CONFIG_AUTO_SCAN_DESC = "Consulta los items seguidos al abrir la casa de subastas.",
    CONFIG_TOOLTIPS = "Tooltips de item",
    CONFIG_OVERLAYS = "Resaltado en subasta",
    CONFIG_MINIMAP_BUTTON = "Boton minimapa",
    CONFIG_PROFILES = "Perfiles",

    MSG_HELP = "Comandos: /safeitemfollow show, /safeitemfollow config, /safeitemfollow scan",
    MSG_UNSUPPORTED = "Esta version apunta a TBC Classic Anniversary 2.5.5 o Mists of Pandaria Classic 5.5.x.",
    MSG_AH_REQUIRED = "Abre la casa de subastas antes de escanear.",
    MSG_SCAN_STARTED = "Scan completo de subasta iniciado.",
    MSG_SCAN_DONE = "Scan completo: %d subastas en %d items.",
    MSG_SCAN_ABORTED = "Scan de subasta abortado.",
    MSG_WATCH_ADDED = "Siguiendo item %d.",
    MSG_WATCH_REMOVED = "Item %d quitado de la watchlist.",
    MSG_INVALID_ITEM = "Pega un link de item valido o un ID numerico.",
    MSG_QUERY_THROTTLED = "La consulta de subasta esta en throttle; esperando.",
}

local locale = type(GetLocale) == "function" and GetLocale() or "enUS"
local active = enUS

if locale == "esES" or locale == "esMX" then
    active = {}
    for key, value in pairs(enUS) do
        active[key] = value
    end
    for key, value in pairs(es) do
        active[key] = value
    end
end

NS.L = active
