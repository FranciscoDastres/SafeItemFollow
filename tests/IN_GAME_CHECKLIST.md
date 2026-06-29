# In-Game Checklist

Target clients:

- WoW TBC Classic Anniversary 2.5.5 (`Interface 20505`)
- WoW Mists of Pandaria Classic 5.5.x (`Interface 505xx`)

1. Install the full `SafeItemFollow` folder under the active client AddOns path.
2. Log in and confirm there are no Lua errors during addon load.
3. Run `/sif`; confirm the window opens with Watchlist, Market scan, and Vendor flip tabs.
4. Left-click the minimap button; confirm it toggles the window.
5. Right-click the minimap button; confirm it opens addon options.
6. Paste an item link or item ID in the Watchlist tab and add it.
7. Open the auction house; confirm the `Full scan` button appears on the native AuctionFrame.
8. Click `Full scan`; confirm the button label advances through pages and a completion chat message appears.
9. Confirm the Market scan tab fills with results sorted by minimum unit buyout.
10. Confirm the Vendor flip tab lists only items where buyout per unit is lower than vendor sell value minus configured margin.
11. Click a Vendor flip `Search` button; confirm it only runs an auction search and does not buy anything.
12. Mouse over an item with recorded history; confirm the tooltip shows SafeItemFollow history.
13. With auction row highlights enabled, browse the AH and confirm vendor flips or historic lows are tinted.
14. Close the AH mid-scan; confirm the scan aborts cleanly with no Lua errors.
15. Reload with `/reload`; confirm watched items and price history persist.
16. Confirm no automatic buying, bidding, or auction posting ever occurs.
