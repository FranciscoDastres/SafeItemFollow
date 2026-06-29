local _, NS = ...

local Rules = {}
NS.Rules = Rules

function Rules.CanQuery()
    if type(CanSendAuctionQuery) == "function" then
        return CanSendAuctionQuery() == true
    end
    return true
end

function Rules.PerUnit(buyout, count)
    buyout = tonumber(buyout)
    count = tonumber(count)
    if not buyout or buyout <= 0 or not count or count < 1 then
        return nil
    end
    return math.floor(buyout / count)
end

function Rules.ParseRow(row)
    if type(row) ~= "table" then
        return nil
    end

    local itemID = tonumber(row.itemID or row[1])
    local name = row.name or row[2]
    local count = tonumber(row.count or row[3]) or 1
    local buyout = tonumber(row.buyout or row.buyoutPrice or row[4])
    local perUnit = Rules.PerUnit(buyout, count)

    if not itemID or not perUnit then
        return nil
    end

    return {
        itemID = math.floor(itemID),
        name = name,
        count = count,
        buyout = buyout,
        perUnit = perUnit,
        index = row.index,
        link = row.link,
    }
end

function Rules.SummarizeListings(rows)
    local summary = {}
    if type(rows) ~= "table" then
        return summary
    end

    for index = 1, #rows do
        local parsed = Rules.ParseRow(rows[index])
        if parsed then
            local entry = summary[parsed.itemID]
            if not entry then
                entry = {
                    itemID = parsed.itemID,
                    name = parsed.name,
                    minBuyout = parsed.perUnit,
                    avgBuyout = 0,
                    qty = 0,
                    listings = 0,
                    sum = 0,
                    bestIndex = parsed.index,
                    link = parsed.link,
                }
                summary[parsed.itemID] = entry
            end

            if parsed.perUnit < entry.minBuyout then
                entry.minBuyout = parsed.perUnit
                entry.bestIndex = parsed.index
            end
            if parsed.name then
                entry.name = parsed.name
            end
            if parsed.link then
                entry.link = parsed.link
            end

            entry.sum = entry.sum + parsed.perUnit
            entry.listings = entry.listings + 1
            entry.qty = entry.qty + parsed.count
            entry.avgBuyout = math.floor(entry.sum / entry.listings)
        end
    end

    for _, entry in pairs(summary) do
        entry.sum = nil
    end

    return summary
end

function Rules.IsFlip(perUnit, vendorSell, flipMargin)
    perUnit = tonumber(perUnit)
    vendorSell = tonumber(vendorSell)
    flipMargin = tonumber(flipMargin) or 0
    if not perUnit or not vendorSell or vendorSell <= 0 then
        return false
    end
    return perUnit < (vendorSell - flipMargin)
end

function Rules.FlipGain(perUnit, vendorSell, qty)
    perUnit = tonumber(perUnit) or 0
    vendorSell = tonumber(vendorSell) or 0
    qty = tonumber(qty) or 0
    return (vendorSell - perUnit) * qty
end

function Rules.IsHistoricLow(perUnit, history)
    perUnit = tonumber(perUnit)
    if not perUnit then
        return false
    end
    if type(history) ~= "table" or #history == 0 then
        return true
    end

    local lowest
    for index = 1, #history do
        local point = history[index]
        local value = tonumber(point and point.minBuyout)
        if value and (not lowest or value < lowest) then
            lowest = value
        end
    end

    if not lowest then
        return true
    end
    return perUnit < lowest
end

function Rules.SortSummaries(summary, field, descending)
    local rows = {}
    for itemID, entry in pairs(summary or {}) do
        rows[#rows + 1] = { itemID = tonumber(itemID), summary = entry }
    end

    field = field or "minBuyout"
    table.sort(rows, function(a, b)
        local av = tonumber(a.summary[field]) or 0
        local bv = tonumber(b.summary[field]) or 0
        if av == bv then
            return (a.summary.name or "") < (b.summary.name or "")
        end
        if descending then
            return av > bv
        end
        return av < bv
    end)
    return rows
end
