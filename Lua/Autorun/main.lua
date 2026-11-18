if SERVER then return end

local ok, failed, package = pcall(function() return trygetpackage("HealthTimer") end)
if not package then
    print("[HealthTimer] Error: package path not found")
    return 
end

local Configs = {
    isEnabled = nil,
    cooldown = nil,
    mode = nil,
    maxPredict = nil
}

local Timing = LuaUserData.CreateStatic("Barotrauma.Timing")
local timer = 0

local hudText = ""
local hudColor = Color.White

local sequence = {-1.0, -1.0, -1.0}

local function getValueConfig(key, typeName, configKey)
    local ok, success, config = pcall(function()
        return ConfigService.TryGetConfig(SettingBase[typeName], package, key)
    end)
    
    if ok and success and config then
        Configs[configKey] = config.Value
        pcall(function()
            config.OnValueChanged.add(function(changed)
                local successChanged, current = pcall(function() return changed.Value end)
                if successChanged and current ~= nil then
                    Configs[configKey] = current
                    print(string.format("Config value '%s' successfully changed to %s!", key, tostring(current)))
                end
            end)
        end)
    else
        print("[HealthTimer] Error: " .. key .. " (ok=" .. tostring(ok) .. ", success=" .. tostring(success) .. ")")
    end
end

getValueConfig("EnableHealthTimer", "Boolean", "isEnabled")
getValueConfig("CheckCooldown", "Single", "cooldown")
getValueConfig("Mode", "String", "mode")
getValueConfig("MaxPredict", "Int32", "maxPredict")

local function drawHUD(text, color)
    hudText = text or ""

    if type(color) == "table" then
        hudColor = Color(color[1] or 255, color[2] or 255, color[3] or 255, color[4] or 255)
    elseif color ~= nil then
        hudColor = color
    else
        hudColor = Color.White
    end
end

function sequenceNewVal(value)
    sequence[3] = sequence[2]
    sequence[2] = sequence[1]
    sequence[1] = value
end


local function calculateHealthNormal(char)
    local realVitality = char.Vitality
    local vitality = char.Vitality
    if sequence[1] == -1.0 or sequence[2] == -1.0 or sequence[3] == -1.0 then
        drawHUD(TextManager.get("HealthTimer.Stable").Value, Color.Blue)
        sequenceNewVal(vitality)
        return
    end

    local maxTurns = Configs.maxPredict
    local turn = 1.0

    local dynamic = (sequence[3] - sequence[2]) - (sequence[2] - sequence[1])
    local accel = sequence[1] - sequence[2]

    local time = ""

    if accel > 0 then
        while vitality <= char.MaxVitality and turn <= maxTurns do
            accel = accel + dynamic
            vitality = vitality + accel
            turn = turn + Configs.cooldown
        end

        turn = math.floor(turn + 1)
        if turn >= maxTurns then
            time = TextManager.get("HealthTimer.Healthy").Value .. ">" .. tostring(maxTurns) .. TextManager.get("HealthTimer.Second").Value
        else
            time = TextManager.get("HealthTimer.Healthy").Value .. tostring(turn) .. TextManager.get("HealthTimer.Second").Value
        end

        drawHUD(time, Color.Green)
    elseif accel < 0 then
        accel = math.abs(accel)

        while vitality >= 0 and turn <= maxTurns do
            accel = accel + dynamic
            vitality = vitality - accel
            turn = turn + Configs.cooldown
        end

        turn = math.floor(turn + 1)
        if turn >= maxTurns then
            time = TextManager.get("HealthTimer.Death").Value .. ">" .. tostring(maxTurns) .. TextManager.get("HealthTimer.Second").Value
        else
            time = TextManager.get("HealthTimer.Death").Value .. tostring(turn) .. TextManager.get("HealthTimer.Second").Value
        end

        drawHUD(time, Color.Orange)
    else
        drawHUD(TextManager.get("HealthTimer.Stable").Value, Color.Blue)
    end

    sequenceNewVal(realVitality)
end

local function calculateHealthMinimal(char)
    local realVitality = char.Vitality
    local vitality = char.Vitality
    if sequence[1] == -1.0 or sequence[2] == -1.0 or sequence[3] == -1.0 then
        drawHUD(TextManager.get("HealthTimer.Stable").Value, Color.Blue)
        sequenceNewVal(vitality)
        return
    end

    local maxTurns = Configs.maxPredict
    local turn = 1.0

    local accel = sequence[1] - sequence[2]

    local time = ""

    if accel > 0 then
        time = TextManager.get("HealthTimer.Death").Value .. tostring(math.floor(((char.MaxVitality - realVitality) / accel) + 1)) .. TextManager.get("HealthTimer.Second").Value

        drawHUD(time, Color.Green)
    elseif accel < 0 then
        time = TextManager.get("HealthTimer.Healthy").Value .. tostring(math.floor((realVitality / math.abs(accel)) + 1)) .. TextManager.get("HealthTimer.Second").Value

        drawHUD(time, Color.Orange)
    else
        drawHUD(TextManager.get("HealthTimer.Stable").Value, Color.Blue)
    end

    sequenceNewVal(realVitality)
end

Hook.Add("think", "HealthTimer", function(instance, ptable)
    if not Game.RoundStarted or not Configs.isEnabled then return end

    timer = timer + Timing.Step
    
    if timer < Configs.cooldown then return end
    timer = 0

    local char = Character.Controlled
    if not char then return end

    if Configs.mode == "Normal" then
        calculateHealthNormal(char)
    elseif Configs.mode == "Minimal" then
        calculateHealthMinimal(char)
    else
        calculateHealthNormal(char)
    end
end)

Hook.Patch("ClientHealthTimerHud", "Barotrauma.CharacterHUD", "Draw", function(instance, ptable)
    if hudText == "" then return end

    local char = Character.Controlled
    if char == nil or char.IsDead or GUI.DisableHUD then return end

    local spriteBatch = ptable["spriteBatch"]
    if spriteBatch == nil then return end

    local marginRightPercent = 0.085
    local marginBottomPercent = 0.15

    local posx = GUI.GUI.Canvas.Rect.Width * (1.0 - marginRightPercent)
    local posy = GUI.GUI.Canvas.Rect.Height * (1.0 - marginBottomPercent)

    GUI.DrawString(
        spriteBatch,
        Vector2(posx, posy),
        hudText,
        hudColor,
        Color(0, 0, 0, 180),
        2
    )
end, Hook.HookMethodType.After)