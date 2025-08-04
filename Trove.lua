--!strict
-- Trove - A utility module for automatic resource cleanup
-- Essential for preventing memory leaks in long-running Roblox games (2025 pattern)

local Trove = {}
Trove.__index = Trove

-- Type definitions
type Trove = {
    Add: (self: Trove, item: any, cleanupMethod: string?) -> any,
    Remove: (self: Trove, item: any) -> boolean,
    Destroy: (self: Trove) -> nil,
    Clean: (self: Trove) -> nil,
    Connect: (self: Trove, signal: RBXScriptSignal, callback: (...any) -> ...any) -> RBXScriptConnection,
    AddPromise: (self: Trove, promise: any) -> any,
    _items: {any},
    _cleaning: boolean
}

-- Constructor
function Trove.new(): Trove
    local self = setmetatable({}, Trove)
    self._items = {}
    self._cleaning = false
    return self
end

-- Add an item to the Trove
function Trove:Add(item: any, cleanupMethod: string?): any
    if self._cleaning then
        error("Cannot add items to Trove while cleaning", 2)
    end
    
    local cleanupInfo = {
        item = item,
        cleanupMethod = cleanupMethod
    }
    
    table.insert(self._items, cleanupInfo)
    
    return item
end

-- Remove an item from the Trove
function Trove:Remove(item: any): boolean
    if self._cleaning then
        return false
    end
    
    for i = #self._items, 1, -1 do
        if self._items[i].item == item then
            table.remove(self._items, i)
            return true
        end
    end
    
    return false
end

-- Connect a signal and add the connection to the Trove
function Trove:Connect(signal: RBXScriptSignal, callback: (...any) -> ...any): RBXScriptConnection
    local connection = signal:Connect(callback)
    self:Add(connection)
    return connection
end

-- Add a Promise to the Trove (for Promise libraries)
function Trove:AddPromise(promise: any): any
    if promise and typeof(promise) == "table" and promise.cancel then
        self:Add(promise, "cancel")
    end
    return promise
end

-- Clean up all items in the Trove
function Trove:Clean()
    if self._cleaning then
        return
    end
    
    self._cleaning = true
    
    -- Clean in reverse order (LIFO)
    for i = #self._items, 1, -1 do
        local info = self._items[i]
        local item = info.item
        local cleanupMethod = info.cleanupMethod
        
        -- Determine cleanup method
        if cleanupMethod then
            -- Custom cleanup method specified
            local method = item[cleanupMethod]
            if method then
                method(item)
            end
        elseif typeof(item) == "function" then
            -- It's a cleanup function
            item()
        elseif typeof(item) == "thread" then
            -- Cancel thread
            task.cancel(item)
        elseif typeof(item) == "RBXScriptConnection" then
            -- Disconnect connection
            item:Disconnect()
        elseif typeof(item) == "Instance" then
            -- Destroy Instance
            item:Destroy()
        elseif typeof(item) == "table" then
            -- Check for common cleanup methods
            if item.Destroy then
                item:Destroy()
            elseif item.destroy then
                item:destroy()
            elseif item.Disconnect then
                item:Disconnect()
            elseif item.disconnect then
                item:disconnect()
            elseif item.cancel then
                item:cancel()
            end
        end
    end
    
    -- Clear the items table
    table.clear(self._items)
    self._cleaning = false
end

-- Destroy is an alias for Clean
function Trove:Destroy()
    self:Clean()
end

-- Advanced features for specific use cases

-- Attach Trove lifetime to an Instance
function Trove:AttachToInstance(instance: Instance): RBXScriptConnection
    local connection = instance.AncestryChanged:Connect(function()
        if not instance.Parent then
            self:Destroy()
        end
    end)
    
    -- Add the connection to the Trove so it gets cleaned up too
    self:Add(connection)
    
    return connection
end

-- Create a sub-Trove that will be cleaned when parent is cleaned
function Trove:Extend(): Trove
    local subTrove = Trove.new()
    self:Add(subTrove)
    return subTrove
end

-- Utility to wrap a function with automatic cleanup
function Trove:WrapClean(callback: () -> ()): () -> ()
    return function()
        self:Clean()
        if callback then
            callback()
        end
    end
end

return Trove