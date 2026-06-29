local namespace = { DEFAULT_PER_PAGE = 50 }
assert(loadfile("Rules.lua"))("SafeItemFollow", namespace)
assert(loadfile("ActionState.lua"))("SafeItemFollow", namespace)

local Rules = namespace.Rules

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

CanSendAuctionQuery = function() return true end
equal(Rules.CanQuery(), true, "query allowed")
CanSendAuctionQuery = function() return false end
equal(Rules.CanQuery(), false, "query throttled")
CanSendAuctionQuery = nil
equal(Rules.CanQuery(), true, "missing throttle API is allowed in tests")

equal(Rules.PerUnit(1000, 5), 200, "per unit of stack")
equal(Rules.PerUnit(1001, 5), 200, "per unit floored")
equal(Rules.PerUnit(0, 5), nil, "zero buyout ignored")
equal(Rules.PerUnit(1000, 0), nil, "zero count ignored")

local parsed = Rules.ParseRow({ itemID = 42, name = "Runecloth", count = 20, buyout = 2000 })
equal(parsed.itemID, 42, "parsed id")
equal(parsed.perUnit, 100, "parsed per unit")

local summary = Rules.SummarizeListings({
    { itemID = 42, name = "Runecloth", count = 20, buyout = 2000, index = 1 },
    { itemID = 42, name = "Runecloth", count = 10, buyout = 900, index = 2 },
    { itemID = 99, name = "Crystal", count = 1, buyout = 500, index = 3 },
    { itemID = 100, name = "No Buyout", count = 1, buyout = 0, index = 4 },
})

equal(summary[42].minBuyout, 90, "summary min")
equal(summary[42].avgBuyout, 95, "summary average")
equal(summary[42].qty, 30, "summary qty")
equal(summary[42].listings, 2, "summary listings")
equal(summary[42].bestIndex, 2, "best index")
equal(summary[99].minBuyout, 500, "second item")
equal(summary[100], nil, "ignores no-buyout rows")

equal(Rules.IsFlip(90, 100, 0), true, "vendor flip")
equal(Rules.IsFlip(99, 100, 2), false, "margin blocks flip")
equal(Rules.FlipGain(90, 100, 30), 300, "flip gain")

equal(Rules.IsHistoricLow(80, { { minBuyout = 100 }, { minBuyout = 90 } }), true, "historic low")
equal(Rules.IsHistoricLow(95, { { minBuyout = 100 }, { minBuyout = 90 } }), false, "not low")
equal(Rules.IsHistoricLow(95, {}), true, "empty history is low")

local sorted = Rules.SortSummaries(summary, "minBuyout", false)
equal(sorted[1].itemID, 42, "sort by min")

local state = namespace.ActionState:New()
equal(state:IsRunning(), false, "new state idle")
state:Begin(3)
equal(state:IsRunning(), true, "running after begin")
equal(state:IsDone(), false, "not done at page zero")
equal(state:Advance(), 1, "advance one")
equal(state:Advance(), 2, "advance two")
equal(state:Advance(), 3, "advance three")
equal(state:IsDone(), true, "done at total")
state:Finish()
equal(state:IsRunning(), false, "idle after finish")

print("SafeItemFollow rules tests passed")
