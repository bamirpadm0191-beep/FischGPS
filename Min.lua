-- ============================================================
-- Fisch GPS Helper — Universal Version v5 (English)
-- Live distance to each point, collapse on title text click,
-- separate X/Y/Z inputs, two save buttons,
-- RightShift to hide GUI, ☠ to destroy script
-- ============================================================

local STORAGE_FILE = "fisch_gps_points.json"
local STORAGE_GLOBAL = "__fisch_gps_points"

-- ============================================================
-- STORAGE ADAPTER
-- ============================================================

local Storage = {}
local mode = "memory"

local function has(fn_name)
    local ok, v = pcall(function() return rawget(getfenv(), fn_name) end)
    if ok and type(v) == "function" then return true end
    return false
end

if has("writefile") and has("readfile") and has("isfile") then
    mode = "file"
elseif type(rawget(getfenv(), "Xeno")) == "table"
    and type(Xeno.GetGlobal) == "function"
    and type(Xeno.SetGlobal) == "function" then
    mode = "xeno"
end

local function jsonEncode(tbl)
    local function enc(v)
        local t = type(v)
        if t == "nil" then return "null"
        elseif t == "boolean" then return tostring(v)
        elseif t == "number" then return tostring(v)
        elseif t == "string" then
            return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
        elseif t == "table" then
            local isArray = #v > 0
            local parts = {}
            if isArray then
                for _, item in ipairs(v) do
                    table.insert(parts, enc(item))
                end
                return "[" .. table.concat(parts, ",") .. "]"
            else
                for k, val in pairs(v) do
                    table.insert(parts, '"' .. tostring(k) .. '":' .. enc(val))
                end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        end
        return "null"
    end
    return enc(tbl)
end

local function jsonDecode(str)
    if not str or str == "" then return nil end
    local pos = 1
    local function skipWs()
        while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
    end
    local parseValue
    local function parseString()
        pos = pos + 1
        local out = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then pos = pos + 1 return table.concat(out)
            elseif c == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                if n == "n" then table.insert(out, "\n")
                elseif n == "t" then table.insert(out, "\t")
                elseif n == '"' then table.insert(out, '"')
                elseif n == "\\" then table.insert(out, "\\")
                else table.insert(out, n) end
                pos = pos + 2
            else
                table.insert(out, c)
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    local function parseNumber()
        local s = pos
        while pos <= #str and str:sub(pos, pos):match("[%d%.%-eE%+]") do pos = pos + 1 end
        return tonumber(str:sub(s, pos - 1))
    end
    local function parseObject()
        pos = pos + 1
        local obj = {}
        skipWs()
        if str:sub(pos, pos) == "}" then pos = pos + 1 return obj end
        while true do
            skipWs()
            local key = parseString()
            skipWs()
            pos = pos + 1
            skipWs()
            obj[key] = parseValue()
            skipWs()
            local c = str:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "}" then pos = pos + 1 break end
        end
        return obj
    end
    local function parseArray()
        pos = pos + 1
        local arr = {}
        skipWs()
        if str:sub(pos, pos) == "]" then pos = pos + 1 return arr end
        while true do
            skipWs()
            table.insert(arr, parseValue())
            skipWs()
            local c = str:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "]" then pos = pos + 1 break end
        end
        return arr
    end
    parseValue = function()
        skipWs()
        local c = str:sub(pos, pos)
        if c == "{" then return parseObject()
        elseif c == "[" then return parseArray()
        elseif c == '"' then return parseString()
        elseif c == "t" then pos = pos + 4 return true
        elseif c == "f" then pos = pos + 5 return false
        elseif c == "n" then pos = pos + 4 return nil
        else return parseNumber() end
    end
    local ok, res = pcall(parseValue)
    if ok then return res end
    return nil
end

function Storage.load()
    if mode == "file" then
        local ok, data = pcall(function()
            if isfile(STORAGE_FILE) then return readfile(STORAGE_FILE) end
        end)
        if ok and data and data ~= "" then
            local decoded = jsonDecode(data)
            if type(decoded) == "table" then return decoded end
        end
        return {}
    elseif mode == "xeno" then
        local ok, data = pcall(function() return Xeno.GetGlobal(STORAGE_GLOBAL) end)
        if ok and type(data) == "table" then return data end
        return {}
    else
        local g = getgenv and getgenv() or _G
        if type(g[STORAGE_GLOBAL]) == "table" then return g[STORAGE_GLOBAL] end
        return {}
    end
end

function Storage.save(points)
    if mode == "file" then
        pcall(function() writefile(STORAGE_FILE, jsonEncode(points)) end)
    elseif mode == "xeno" then
        pcall(function() Xeno.SetGlobal(STORAGE_GLOBAL, points) end)
    else
        local g = getgenv and getgenv() or _G
        g[STORAGE_GLOBAL] = points
    end
end

-- ============================================================
-- CLEANUP SYSTEM
-- ============================================================

local Cleanup = {
    connections = {},
    instances = {},
    highlights = {},
    listRows = {},
}

local function track(conn)
    table.insert(Cleanup.connections, conn)
    return conn
end

local function trackInst(obj)
    table.insert(Cleanup.instances, obj)
    return obj
end

-- ============================================================
-- PLAYER POSITION & DISTANCE
-- ============================================================

local function getPlayerPosition()
    local char = game.Players.LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    return hrp.Position, hrp.CFrame.LookVector
end

local function formatDistance(playerPos, lookVec, targetPos)
    if not playerPos or not targetPos then return "—" end

    local delta = targetPos - playerPos
    local dist = delta.Magnitude
    local distStr = string.format("%.0f studs", dist)

    if lookVec then
        local flatLook = Vector3.new(lookVec.X, 0, lookVec.Z)
        local flatDelta = Vector3.new(delta.X, 0, delta.Z)

        if flatLook.Magnitude > 0.01 and flatDelta.Magnitude > 0.01 then
            flatLook = flatLook.Unit
            flatDelta = flatDelta.Unit

            local dot = flatLook:Dot(flatDelta)
            local cross = flatLook.X * flatDelta.Z - flatLook.Z * flatDelta.X

            local dir
            if dot > 0.7 then dir = "ahead"
            elseif dot < -0.7 then dir = "behind"
            else
                if cross > 0 then dir = "right"
                else dir = "left" end
            end

            return distStr .. " (" .. dir .. ")"
        end
    end

    return distStr
end

-- ============================================================
-- HIGHLIGHT
-- ============================================================

local highlights = Cleanup.highlights

local function createHighlight(name, position)
    if highlights[name] then
        if highlights[name].part then highlights[name].part:Destroy() end
        highlights[name] = nil
    end

    local part = Instance.new("Part")
    part.Name = "GPS_Marker_" .. name
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Transparency = 1
    part.Size = Vector3.new(2, 2, 2)
    part.Position = position
    part.Parent = workspace

    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(0, 200, 255)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = part
    hl.Parent = part

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.new(0, 240, 0, 60)
    billboard.StudsOffset = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = part

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, 0, 0.5, 0)
    text.Position = UDim2.new(0, 0, 0, 0)
    text.BackgroundTransparency = 1
    text.Text = name
    text.TextColor3 = Color3.fromRGB(0, 220, 255)
    text.TextStrokeTransparency = 0
    text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    text.Font = Enum.Font.GothamBold
    text.TextSize = 14
    text.Parent = billboard

    local distanceLabel = Instance.new("TextLabel")
    distanceLabel.Size = UDim2.new(1, 0, 0.5, 0)
    distanceLabel.Position = UDim2.new(0, 0, 0.5, 0)
    distanceLabel.BackgroundTransparency = 1
    distanceLabel.Text = "—"
    distanceLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
    distanceLabel.TextStrokeTransparency = 0
    distanceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    distanceLabel.Font = Enum.Font.GothamBold
    distanceLabel.TextSize = 13
    distanceLabel.Parent = billboard

    highlights[name] = {
        part = part,
        highlight = hl,
        billboard = billboard,
        distanceLabel = distanceLabel,
        position = position,
    }
    return part
end

local function removeHighlight(name)
    if highlights[name] then
        if highlights[name].part then highlights[name].part:Destroy() end
        highlights[name] = nil
    end
end

local function clearAllHighlights()
    for name, _ in pairs(highlights) do
        removeHighlight(name)
    end
end

-- ============================================================
-- GUI
-- ============================================================

local screenGui = trackInst(Instance.new("ScreenGui"))
screenGui.Name = "FischGPSHelper"
screenGui.ResetOnSpawn = false
screenGui.Parent = game.CoreGui

local mainFrame = trackInst(Instance.new("Frame"))
mainFrame.Size = UDim2.new(0, 340, 0, 540)
mainFrame.Position = UDim2.new(0, 20, 0, 100)
mainFrame.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local titleBar = trackInst(Instance.new("Frame"))
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local titleLabel = trackInst(Instance.new("TextButton"))
titleLabel.Size = UDim2.new(0, 200, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Fisch GPS Helper  ▾"
titleLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 16
titleLabel.AutoButtonColor = false
titleLabel.Parent = titleBar

local destroyBtn = trackInst(Instance.new("TextButton"))
destroyBtn.Size = UDim2.new(0, 36, 0, 28)
destroyBtn.Position = UDim2.new(1, -76, 0, 4)
destroyBtn.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
destroyBtn.BorderSizePixel = 0
destroyBtn.Text = "☠"
destroyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
destroyBtn.Font = Enum.Font.GothamBold
destroyBtn.TextSize = 16
destroyBtn.Parent = titleBar

local closeBtn = trackInst(Instance.new("TextButton"))
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = titleBar

local bodyFrame = trackInst(Instance.new("Frame"))
bodyFrame.Size = UDim2.new(1, 0, 1, -36)
bodyFrame.Position = UDim2.new(0, 0, 0, 36)
bodyFrame.BackgroundTransparency = 1
bodyFrame.Parent = mainFrame

-- Coordinate input section
local inputSection = trackInst(Instance.new("Frame"))
inputSection.Size = UDim2.new(1, -24, 0, 100)
inputSection.Position = UDim2.new(0, 12, 0, 8)
inputSection.BackgroundColor3 = Color3.fromRGB(38, 38, 44)
inputSection.BorderSizePixel = 0
inputSection.Parent = bodyFrame

local inputLabel = trackInst(Instance.new("TextLabel"))
inputLabel.Size = UDim2.new(1, -16, 0, 22)
inputLabel.Position = UDim2.new(0, 8, 0, 4)
inputLabel.BackgroundTransparency = 1
inputLabel.Text = "Enter coordinates per axis:"
inputLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
inputLabel.TextXAlignment = Enum.TextXAlignment.Left
inputLabel.Font = Enum.Font.Gotham
inputLabel.TextSize = 12
inputLabel.Parent = inputSection

local function makeAxisInput(parent, labelText, xPos)
    local container = trackInst(Instance.new("Frame"))
    container.Size = UDim2.new(0, 96, 0, 52)
    container.Position = UDim2.new(0, xPos, 0, 28)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local lbl = trackInst(Instance.new("TextLabel"))
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.Position = UDim2.new(0, 0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(150, 190, 240)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = container

    local box = trackInst(Instance.new("TextBox"))
    box.Size = UDim2.new(1, 0, 0, 28)
    box.Position = UDim2.new(0, 0, 0, 20)
    box.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
    box.BorderSizePixel = 0
    box.Text = ""
    box.PlaceholderText = "0"
    box.TextColor3 = Color3.fromRGB(230, 230, 240)
    box.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.Parent = container

    return box
end

local xInput = makeAxisInput(inputSection, "X", 8)
local yInput = makeAxisInput(inputSection, "Y", 110)
local zInput = makeAxisInput(inputSection, "Z", 212)

-- Save buttons
local savePlayerBtn = trackInst(Instance.new("TextButton"))
savePlayerBtn.Size = UDim2.new(0.5, -18, 0, 34)
savePlayerBtn.Position = UDim2.new(0, 12, 0, 116)
savePlayerBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 90)
savePlayerBtn.BorderSizePixel = 0
savePlayerBtn.Text = "Save player position"
savePlayerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
savePlayerBtn.Font = Enum.Font.GothamBold
savePlayerBtn.TextSize = 11
savePlayerBtn.TextWrapped = true
savePlayerBtn.Parent = bodyFrame

local saveCoordsBtn = trackInst(Instance.new("TextButton"))
saveCoordsBtn.Size = UDim2.new(0.5, -18, 0, 34)
saveCoordsBtn.Position = UDim2.new(0.5, 6, 0, 116)
saveCoordsBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 200)
saveCoordsBtn.BorderSizePixel = 0
saveCoordsBtn.Text = "Save X/Y/Z coords"
saveCoordsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
saveCoordsBtn.Font = Enum.Font.GothamBold
saveCoordsBtn.TextSize = 11
saveCoordsBtn.TextWrapped = true
saveCoordsBtn.Parent = bodyFrame

-- List header
local listLabel = trackInst(Instance.new("TextLabel"))
listLabel.Size = UDim2.new(1, -160, 0, 22)
listLabel.Position = UDim2.new(0, 12, 0, 158)
listLabel.BackgroundTransparency = 1
listLabel.Text = "Saved points:"
listLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
listLabel.TextXAlignment = Enum.TextXAlignment.Left
listLabel.Font = Enum.Font.Gotham
listLabel.TextSize = 12
listLabel.Parent = bodyFrame

local clearBtn = trackInst(Instance.new("TextButton"))
clearBtn.Size = UDim2.new(0, 140, 0, 20)
clearBtn.Position = UDim2.new(1, -152, 0, 159)
clearBtn.BackgroundColor3 = Color3.fromRGB(120, 70, 70)
clearBtn.BorderSizePixel = 0
clearBtn.Text = "Clear all highlights"
clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
clearBtn.Font = Enum.Font.Gotham
clearBtn.TextSize = 11
clearBtn.Parent = bodyFrame

local scrollFrame = trackInst(Instance.new("ScrollingFrame"))
scrollFrame.Size = UDim2.new(1, -24, 1, -204)
scrollFrame.Position = UDim2.new(0, 12, 0, 182)
scrollFrame.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 4
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = bodyFrame

local listLayout = trackInst(Instance.new("UIListLayout"))
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

-- ============================================================
-- UI LOGIC
-- ============================================================

local collapsed = false
track(titleLabel.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    bodyFrame.Visible = not collapsed
    mainFrame.Size = collapsed and UDim2.new(0, 340, 0, 36) or UDim2.new(0, 340, 0, 540)
    titleLabel.Text = collapsed and "Fisch GPS Helper  ▸" or "Fisch GPS Helper  ▾"
end))

track(closeBtn.MouseButton1Click:Connect(function()
    screenGui.Enabled = false
end))

-- ============================================================
-- LIST
-- ============================================================

local function refreshList()
    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    Cleanup.listRows = {}

    local points = Storage.load()
    local index = 0
    for name, data in pairs(points) do
        index = index + 1
        local vec
        if type(data) == "table" then
            if data.position then
                vec = Vector3.new(data.position.X, data.position.Y, data.position.Z)
            elseif data.x then
                vec = Vector3.new(data.x, data.y, data.z)
            end
        end

        if vec then
            local row = trackInst(Instance.new("Frame"))
            row.Size = UDim2.new(1, 0, 0, 52)
            row.BackgroundColor3 = Color3.fromRGB(44, 44, 52)
            row.BorderSizePixel = 0
            row.LayoutOrder = index
            row.Parent = scrollFrame

            local nameLabel = trackInst(Instance.new("TextLabel"))
            nameLabel.Size = UDim2.new(1, -12, 0, 18)
            nameLabel.Position = UDim2.new(0, 6, 0, 2)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = name
            nameLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Font = Enum.Font.Gotham
            nameLabel.TextSize = 12
            nameLabel.Parent = row

            local coordsLabel = trackInst(Instance.new("TextLabel"))
            coordsLabel.Size = UDim2.new(1, -12, 0, 14)
            coordsLabel.Position = UDim2.new(0, 6, 0, 18)
            coordsLabel.BackgroundTransparency = 1
            coordsLabel.Text = string.format("(%.0f, %.0f, %.0f)", vec.X, vec.Y, vec.Z)
            coordsLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
            coordsLabel.TextXAlignment = Enum.TextXAlignment.Left
            coordsLabel.Font = Enum.Font.Gotham
            coordsLabel.TextSize = 10
            coordsLabel.Parent = row

            local distanceLabel = trackInst(Instance.new("TextLabel"))
            distanceLabel.Size = UDim2.new(1, -12, 0, 14)
            distanceLabel.Position = UDim2.new(0, 6, 0, 32)
            distanceLabel.BackgroundTransparency = 1
            distanceLabel.Text = "—"
            distanceLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
            distanceLabel.TextXAlignment = Enum.TextXAlignment.Left
            distanceLabel.Font = Enum.Font.GothamBold
            distanceLabel.TextSize = 11
            distanceLabel.Parent = row

            Cleanup.listRows[name] = {
                distanceLabel = distanceLabel,
                position = vec,
            }

            local hlBtn = trackInst(Instance.new("TextButton"))
            hlBtn.Size = UDim2.new(0, 75, 0, 22)
            hlBtn.Position = UDim2.new(0.35, 0, 0, 28)
            hlBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 200)
            hlBtn.BorderSizePixel = 0
            hlBtn.Text = "Highlight"
            hlBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            hlBtn.Font = Enum.Font.GothamBold
            hlBtn.TextSize = 10
            hlBtn.Parent = row

            local delBtn = trackInst(Instance.new("TextButton"))
            delBtn.Size = UDim2.new(0, 55, 0, 22)
            delBtn.Position = UDim2.new(0.72, 0, 0, 28)
            delBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
            delBtn.BorderSizePixel = 0
            delBtn.Text = "Delete"
            delBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            delBtn.Font = Enum.Font.GothamBold
            delBtn.TextSize = 10
            delBtn.Parent = row

            track(hlBtn.MouseButton1Click:Connect(function()
                createHighlight(name, vec)
            end))

            track(delBtn.MouseButton1Click:Connect(function()
                removeHighlight(name)
                local pts = Storage.load()
                pts[name] = nil
                Storage.save(pts)
                refreshList()
            end))
        end
    end

    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
end

-- ============================================================
-- SAVE LOGIC
-- ============================================================

track(clearBtn.MouseButton1Click:Connect(function()
    clearAllHighlights()
end))

local saveCounter = 0

track(savePlayerBtn.MouseButton1Click:Connect(function()
    local pos = getPlayerPosition()
    if not pos then return end

    saveCounter = saveCounter + 1
    local name = "Player_" .. tostring(os.time()) .. "_" .. tostring(saveCounter)

    local points = Storage.load()
    points[name] = { position = { X = pos.X, Y = pos.Y, Z = pos.Z } }
    Storage.save(points)

    createHighlight(name, pos)
    refreshList()
end))

track(saveCoordsBtn.MouseButton1Click:Connect(function()
    local x = tonumber(xInput.Text)
    local y = tonumber(yInput.Text)
    local z = tonumber(zInput.Text)

    if not x or not y or not z then
        saveCoordsBtn.Text = "Error: enter numbers"
        task.wait(1.5)
        saveCoordsBtn.Text = "Save X/Y/Z coords"
        return
    end

    saveCounter = saveCounter + 1
    local name = "Manual_" .. tostring(os.time()) .. "_" .. tostring(saveCounter)

    local points = Storage.load()
    points[name] = { position = { X = x, Y = y, Z = z } }
    Storage.save(points)

    local vec = Vector3.new(x, y, z)
    createHighlight(name, vec)
    refreshList()

    xInput.Text = ""
    yInput.Text = ""
    zInput.Text = ""
end))

-- ============================================================
-- DISTANCE UPDATE LOOP
-- ============================================================

task.spawn(function()
    while screenGui and screenGui.Parent do
        local pos, lookVec = getPlayerPosition()
        if pos then
            for name, hl in pairs(highlights) do
                if hl.distanceLabel and hl.position then
                    hl.distanceLabel.Text = formatDistance(pos, lookVec, hl.position)
                end
            end

            for name, row in pairs(Cleanup.listRows) do
                if row.distanceLabel and row.position then
                    row.distanceLabel.Text = formatDistance(pos, lookVec, row.position)
                end
            end
        end

        task.wait(0.1)
    end
end)

-- ============================================================
-- HOTKEY: RightShift
-- ============================================================

local UserInputService = game:GetService("UserInputService")
track(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        screenGui.Enabled = not screenGui.Enabled
    end
end))

-- ============================================================
-- DESTROY
-- ============================================================

local function destroyScript()
    for name, _ in pairs(highlights) do
        if highlights[name] and highlights[name].part then
            pcall(function() highlights[name].part:Destroy() end)
        end
    end
    highlights = {}

    for _, conn in ipairs(Cleanup.connections) do
        pcall(function() conn:Disconnect() end)
    end
    Cleanup.connections = {}

    for _, obj in ipairs(Cleanup.instances) do
        pcall(function()
            if obj and obj.Parent then obj:Destroy() end
        end)
    end
    Cleanup.instances = {}

    Cleanup.listRows = {}

    pcall(function()
        local existing = game.CoreGui:FindFirstChild("FischGPSHelper")
        if existing then existing:Destroy() end
    end)

    print("[Fisch GPS Helper] Script fully destroyed. Reinject to run again.")
end

track(destroyBtn.MouseButton1Click:Connect(destroyScript))

-- ============================================================
-- START
-- ============================================================

refreshList()
print("[Fisch GPS Helper] Loaded. Storage mode: " .. mode)
print("[Fisch GPS Helper] RightShift — show/hide GUI. Click title text — collapse.")
print("[Fisch GPS Helper] ☠ button — destroy script until re-injection.")
