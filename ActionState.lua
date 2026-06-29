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
