--[[
    LuiExtended
    License: The MIT License (MIT)
--]]

local CI = LUIE.CombatInfo
CI.CrowdControlTracker = {}
local CCT = CI.CrowdControlTracker

local E = LUIE.Effects
local CBT = LUIE.CastBarTable
local CC = LUIE.CrowdControl

local eventManager = EVENT_MANAGER
local animationManager = ANIMATION_MANAGER
local callbackManager = CALLBACK_MANAGER

local moduleName = LUIE.name .. "_CombatInfo"

local PriorityOne, PriorityTwo, PriorityThree, PriorityFour, PrioritySix

local CCT_STAGGER_DURATION = 800
local CCT_AREA_DURATION = 1100
local CCT_GRACE_TIME = 5

local CCT_ICON_FONT = "$(GAMEPAD_BOLD_FONT)|25|thick-outline"
local CCT_STAGGER_FONT = "$(GAMEPAD_BOLD_FONT)|36|thick-outline"
local CCT_ZOS_DEFAULT_ICON = "esoui/art/icons/ability_mage_065.dds"

local CCT_DEFAULT_STUN_ICON = "esoui/art/icons/ability_debuff_stun"
local CCT_DEFAULT_FEAR_ICON = "esoui/art/icons/ability_debuff_fear.dds"
local CCT_DEFAULT_DISORIENT_ICON = "esoui/art/icons/ability_debuff_disorient.dds"
local CCT_DEFAULT_SILENCE_ICON = "esoui/art/icons/ability_debuff_silence.dds"
local CCT_DEFAULT_IMMUNE_ICON = "LuiExtended/media/icons/abilities/ability_innate_cc_immunity.dds"

local CCT_DEFAULT_ICONBORDER = "esoui/art/actionbar/debuff_frame.dds"
local CCT_ICONBORDER = "LuiExtended/media/combatinfo/crowdcontroltracker/border.dds"

local CCT_SET_SCALE_FROM_SV = true
local CCT_BREAK_FREE_ID = 16565
local CCT_NEGATE_MAGIC_ID = 47158
local CCT_NEGATE_MAGIC_1_ID = 51894
local CCT_ICON_MISSING = "icon_missing"

local ACTION_RESULT_AREA_EFFECT=669966

CCT.controlTypes = {
    ACTION_RESULT_STUNNED,
    ACTION_RESULT_FEARED,
    ACTION_RESULT_DISORIENTED,
    ACTION_RESULT_SILENCED,
    ACTION_RESULT_STAGGERED,
    ACTION_RESULT_AREA_EFFECT,
}

CCT.actionResults = {
    [ACTION_RESULT_STUNNED]           = true,
    [ACTION_RESULT_FEARED]            = true,
    [ACTION_RESULT_DISORIENTED]       = true,
}

CCT.controlText = {
    [ACTION_RESULT_STUNNED]           = "STUNNED",
    [ACTION_RESULT_FEARED]            = "FEARED",
    [ACTION_RESULT_DISORIENTED]       = "DISORIENTED",
    [ACTION_RESULT_SILENCED]          = "SILENCED",
    [ACTION_RESULT_STAGGERED]         = "STAGGER",
    [ACTION_RESULT_IMMUNE]            = "IMMUNE",
    [ACTION_RESULT_DODGED]            = "DODGED",
    [ACTION_RESULT_BLOCKED]           = "BLOCKED",
    [ACTION_RESULT_BLOCKED_DAMAGE]    = "BLOCKED",
    [ACTION_RESULT_AREA_EFFECT]       = "AREA DAMAGE",
}

CCT.aoeHitTypes = {
    [ACTION_RESULT_BLOCKED]             = true,
    [ACTION_RESULT_BLOCKED_DAMAGE]      = true,
    [ACTION_RESULT_CRITICAL_DAMAGE]     = true,
    [ACTION_RESULT_DAMAGE]              = true,
    [ACTION_RESULT_DAMAGE_SHIELDED]     = true,
    [ACTION_RESULT_IMMUNE]              = true,
    [ACTION_RESULT_MISS]                = true,
    [ACTION_RESULT_PARTIAL_RESIST]      = true,
    [ACTION_RESULT_REFLECTED]           = true,
    [ACTION_RESULT_RESIST]              = true,
    [ACTION_RESULT_WRECKING_DAMAGE]     = true,
    [ACTION_RESULT_SNARED]              = true,
    [ACTION_RESULT_DOT_TICK]            = true,
    [ACTION_RESULT_DOT_TICK_CRITICAL]   = true,
}

function CCT:OnOff()
    if CI.SV.cct.enabled and not (CI.SV.cct.enabledOnlyInCyro and LUIE.ResolvePVPZone()) then
        if not self.addonEnabled then
            self.addonEnabled = true
            eventManager:RegisterForEvent(self.name, EVENT_PLAYER_ACTIVATED, self.Initialize)
            eventManager:RegisterForEvent(self.name, EVENT_COMBAT_EVENT, function(...) self:OnCombat(...) end)
            eventManager:RegisterForEvent(self.name, EVENT_PLAYER_STUNNED_STATE_CHANGED, function(...) self:OnStunnedState(...) end)
            eventManager:RegisterForEvent(self.name, EVENT_UNIT_DEATH_STATE_CHANGED, function(eventCode, unitTag, isDead) if isDead then self:FullReset() end end)
            eventManager:AddFilterForEvent(self.name, EVENT_UNIT_DEATH_STATE_CHANGED, REGISTER_FILTER_UNIT_TAG, "player")
            self.Initialize()
        end
    else
        if self.addonEnabled then
            self.addonEnabled = false
            eventManager:UnregisterForEvent(self.name, EVENT_PLAYER_ACTIVATED)
            eventManager:UnregisterForEvent(self.name, EVENT_COMBAT_EVENT)
            eventManager:UnregisterForEvent(self.name, EVENT_PLAYER_STUNNED_STATE_CHANGED)
            eventManager:UnregisterForEvent(self.name, EVENT_UNIT_DEATH_STATE_CHANGED)
            LUIE_CCTracker:SetHidden(true)
        end
    end
end

function CCT.Initialize()
    CCT:OnOff()
    if CI.SV.cct.enabled then
        CCT.currentlyPlaying = nil
        CCT.breakFreePlaying = nil
        CCT.immunePlaying = nil
        CCT:FullReset()
    end
end






function CCT.UpdateAOEList()

    local priority = 0 -- Counter for priority, we increment by one for each active category added
    CCT.aoeTypesId = { }

    if CI.SV.cct.aoePlayerUltimate then
        for k, v in pairs(CC.aoePlayerUltimate) do
            CCT.aoeTypesId[k] = priority
        end
        priority = priority + 1
    end

    if CI.SV.cct.aoePlayerNormal then
        for k, v in pairs(CC.aoePlayerNormal) do
            CCT.aoeTypesId[k] = priority
        end
        priority = priority + 1
    end

    if CI.SV.cct.aoePlayerUltimate then
        for k, v in pairs(CC.aoePlayerSet) do
            CCT.aoeTypesId[k] = priority
        end
        priority = priority + 1
    end

    if CI.SV.cct.aoeTraps then
        for k, v in pairs(CC.aoeTraps) do
            CCT.aoeTypesId[k] = priority
        end
        priority = priority + 1
    end

    if CI.SV.cct.aoeNPCBoss then
        for k, v in pairs(CC.aoeNPCBoss) do
            CCT.aoeTypesId[k] = priority
        end
        priority = priority + 1
    end

    if CI.SV.cct.aoeNPCElite then
        for k, v in pairs(CC.aoeNPCElite) do
            CCT.aoeTypesId[k] = priority
        end
        priority = priority + 1
    end

    if CI.SV.cct.aoeNPCNormal then
        for k, v in pairs(CC.aoeNPCNormal) do
            CCT.aoeTypesId[k] = priority
        end
        priority = priority + 1
    end

    CCT.GeneratePriorityTable()

end



















-- GAP between INIT and code for now

































function LUIE_CCTracker_SavePosition()
    local coordX, coordY = LUIE_CCTracker:GetCenter()
    CI.SV.cct.offsetX = coordX - (GuiRoot:GetWidth() / 2)
    CI.SV.cct.offsetY = coordY - (GuiRoot:GetHeight() / 2)
    LUIE_CCTracker:ClearAnchors()
    LUIE_CCTracker:SetAnchor(CENTER, GuiRoot, CENTER, CI.SV.cct.offsetX, CI.SV.cct.offsetY)
end

function LUIE_CCTracker_OnUpdate(control)
    if CCT.Timer == 0 or not CCT.Timer then
        return
    end

    local timeLeft = math.ceil(CCT.Timer - GetFrameTimeSeconds())
    if timeLeft > 0 then
        LUIE_CCTracker_Timer_Label:SetText(timeLeft)
    end
end

function CCT:OnProc(ccDuration, interval)
    self:OnAnimation(LUIE_CCTracker, "proc")
    if CI.SV.cct.playSound then
        PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
        PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
    end
    self.Timer = GetFrameTimeSeconds() + (interval / 1000)

    local remaining, duration, global = GetSlotCooldownInfo(1)
    if remaining > 0 then
        LUIE_CCTracker_IconFrame_GlobalCooldown:ResetCooldown()
        if CI.SV.cct.showGCD and LUIE.ResolvePVPZone() then
            LUIE_CCTracker_IconFrame_GlobalCooldown:SetHidden(false)
            LUIE_CCTracker_IconFrame_GlobalCooldown:StartCooldown(remaining, remaining, CD_TYPE_RADIAL, CD_TIME_TYPE_TIME_UNTIL, false)
            zo_callLater(function() LUIE_CCTracker_IconFrame_GlobalCooldown:SetHidden(true) end, remaining)
        end
    end
    LUIE_CCTracker_IconFrame_Cooldown:ResetCooldown()
    LUIE_CCTracker_IconFrame_Cooldown:StartCooldown(interval, ccDuration, CD_TYPE_RADIAL, CD_TIME_TYPE_TIME_REMAINING, false)

    self:SetupDisplay("timer")
end

function CCT:OnAnimation(control, animationType, param)
    self:SetupDisplay(animationType)
    if CI.SV.cct.playAnimation then
        if animationType == "immune" then
            self.immunePlaying = self:StartAnimation(control, animationType)
        elseif animationType == "breakfree" then
            self.breakFreePlaying = self:BreakFreeAnimation()
        else
            self.currentlyPlaying = self:StartAnimation(control, animationType)
        end
    elseif param then
        LUIE_CCTracker:SetHidden(not CI.SV.cct.unlocked)
    end
end

function CCT.GeneratePriorityTable()
    CCT.aoeTypes = {}
    for k,v in pairs (CCT.aoeTypesId) do
        CCT.aoeTypes[GetAbilityName(k)] = v
    end
end

function CCT:AoePriority(abilityName, result)
    if self.aoeTypes[abilityName] and self.aoeHitTypes[result] and ((not self.aoeTypes[PrioritySix.abilityName]) or (self.aoeTypes[abilityName]<=self.aoeTypes[PrioritySix.abilityName])) then
        return true
    else
        return false
    end
end

local function ResolveAbilityName(abilityId)
    local abilityName = GetAbilityName(abilityId)
    if E.MapDataOverride[abilityId] then
        local index = GetCurrentMapZoneIndex()
        if E.MapDataOverride[abilityId][index] then
            abilityName = E.MapDataOverride[abilityId][index].name
        end
    end
    return abilityName
end

local function ResolveAbilityIcon(abilityId)
    local abilityIcon = GetAbilityIcon(abilityId)
    if E.MapDataOverride[abilityId] then
        local index = GetCurrentMapZoneIndex()
        if E.MapDataOverride[abilityId][index] then
            abilityIcon = E.MapDataOverride[abilityId][index].icon
        end
    end
    return abilityIcon
end

function CCT:OnCombat(eventCode, result, isError, abilityName, abilityGraphic, abilityActionSlotType, sourceName, sourceType, targetName, targetType, hitValue, powerType, damageType, combat_log, sourceUnitId, targetUnitId, abilityId)
    -- LuiExtended Addition
    abilityName = ResolveAbilityName(abilityId)
    local abilityIcon = ResolveAbilityIcon(abilityId)

    if CC.IgnoreList[abilityId] then return end
    local function StringEnd(String,End)
        return End == '' or string.sub(String,-string.len(End)) == End
    end

    local malformedName

    if not StringEnd(LUIE.PlayerNameRaw,'^Mx') and not StringEnd(LUIE.PlayerNameRaw,'^Fx') then
        malformedName = true
    end

    if result == ACTION_RESULT_EFFECT_GAINED_DURATION and ((not malformedName and sourceName == LUIE.PlayerNameRaw) or (malformedName and (sourceName == LUIE.PlayerNameRaw..'^Mx' or sourceName == LUIE.PlayerNameRaw..'^Fx'))) and (abilityName == "Break Free" or abilityName == GetAbilityName(CCT_BREAK_FREE_ID) or abilityId == CCT_BREAK_FREE_ID) then
        if CI.SV.cct.showOptions == "text" then
            self:StopDraw(true)
        else
            self:StopDrawBreakFree()
        end
        return
    end

    --51894
    -----------------DISORIENT PROCESSING-------------------------------

    if result == ACTION_RESULT_EFFECT_FADED and ((not malformedName and targetName == LUIE.PlayerNameRaw) or (malformedName and (targetName == LUIE.PlayerNameRaw..'^Mx' or targetName == LUIE.PlayerNameRaw..'^Fx'))) then
        if GetFrameTimeMilliseconds() <= (PriorityTwo.endTime + CCT_GRACE_TIME) and #self.fearsQueue ~= 0 then
            local found_k
            for k, v in pairs (self.fearsQueue) do
                if v == abilityId then
                    found_k = k
                    break
                end
            end
            if found_k then
                table.remove(self.fearsQueue, found_k)
                if #self.fearsQueue == 0 then
                    self:RemoveCC(2, PriorityTwo.endTime)
                end
            end
        elseif GetFrameTimeMilliseconds() <= (PriorityThree.endTime + CCT_GRACE_TIME) and #self.disorientsQueue ~= 0 then
            local found_k
            for k, v in pairs (self.disorientsQueue) do
                if v == abilityId then
                    found_k = k
                    break
                end
            end
            if found_k then
                table.remove(self.disorientsQueue, found_k)
                if #self.disorientsQueue == 0 then self:RemoveCC(3, PriorityThree.endTime) end
            end
        end
    end

    ------------------------------------------------

    -- If AoE effect is flagged as self damage (mostly from lava) id then don't use the normal return statement, otherwise return based off primary conditions.
    if ((not malformedName and sourceName == LUIE.PlayerNameRaw) or (malformedName and (sourceName == LUIE.PlayerNameRaw..'^Mx' or sourceName == LUIE.PlayerNameRaw..'^Fx'))) and CC.LavaAlerts[abilityId] then
        --
    else
        if ((not malformedName and targetName ~= LUIE.PlayerNameRaw) or (malformedName and (targetName ~= LUIE.PlayerNameRaw..'^Mx' and targetName ~= LUIE.PlayerNameRaw..'^Fx'))) or targetName == "" or targetType ~= 1 or ((not malformedName and sourceName == LUIE.PlayerNameRaw) or (malformedName and (sourceName == LUIE.PlayerNameRaw..'^Mx' or sourceName == LUIE.PlayerNameRaw..'^Fx'))) or sourceName == "" or sourceUnitId == 0 or self.breakFreePlaying then
            return
        end
    end

    if CI.SV.cct.showAoe and (self:AoePriority(abilityName, result) or (CC.SpecialCC[abilityId] and result == ACTION_RESULT_EFFECT_GAINED)) then
        if not CCT.aoeTypesId[abilityId] then
            return
        end
        if CC.SpecialCC[abilityId] and result ~= ACTION_RESULT_EFFECT_GAINED then
            return
        end

        -- TODO: This entire block needs updated with better criteria (once we separate aoes into the proper categories)

        if CCT.aoeTypesId[abilityId] <= 199 then
            if not CI.SV.cct.showAoeT1 then
                return
            end
            if CI.SV.cct.PlaySoundAoeT1 then
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
            end
        end

        if CCT.aoeTypesId[abilityId] >= 200 and CCT.aoeTypesId[abilityId] <= 499 then
            if not CI.SV.cct.showAoeT2 then
                return
            end
            if CI.SV.cct.PlaySoundAoeT2 then
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
            end
        end

        if CCT.aoeTypesId[abilityId] >= 500 and CCT.aoeTypesId[abilityId] <= 599 then
            if not CI.SV.cct.showAoeT3 then
                return
            end
            if CI.SV.cct.PlaySoundAoeT3 then
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
            end
        end

        if CCT.aoeTypesId[abilityId] >= 600 and CCT.aoeTypesId[abilityId] <= 699 then
            if not CI.SV.cct.showAoeT4 then
                return
            end
            if CI.SV.cct.PlaySoundAoeT4 then
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
            end
        end

        if CCT.aoeTypesId[abilityId] >= 700 and CCT.aoeTypesId[abilityId] <= 799 then
            if not CI.SV.cct.showAoeT5 then
                return
            end
            if CI.SV.cct.PlaySoundAoeT5 then
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
            end
        end

        if CCT.aoeTypesId[abilityId] >= 800 then
            if not CI.SV.cct.showAoeT6 then
                return
            end
            if CI.SV.cct.PlaySoundAoeT6 then
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
                PlaySound(SOUNDS.DEATH_RECAP_KILLING_BLOW_SHOWN)
            end
        end

        local currentEndTimeArea = GetFrameTimeMilliseconds() + CCT_AREA_DURATION
        PrioritySix = {endTime = currentEndTimeArea, abilityId = abilityId, abilityIcon = abilityIcon, hitValue = hitValue, result = ACTION_RESULT_AREA_EFFECT, abilityName = abilityName}
        if PriorityOne.endTime == 0 and PriorityTwo.endTime == 0 and PriorityThree.endTime == 0 and PriorityFour.endTime == 0 then
            self.currentCC = 6
            zo_callLater(function() self:RemoveCC(6, currentEndTimeArea) end, CCT_AREA_DURATION + CCT_GRACE_TIME)
            self:OnDraw(abilityId, abilityIcon, CCT_AREA_DURATION, ACTION_RESULT_AREA_EFFECT, abilityName, CCT_AREA_DURATION)
        end
    end

    local validResults = {
        [ACTION_RESULT_EFFECT_GAINED_DURATION] = true,
        [ACTION_RESULT_STUNNED] = true,
        [ACTION_RESULT_FEARED] = true,
        [ACTION_RESULT_STAGGERED] = true,
        [ACTION_RESULT_IMMUNE] = true,
        [ACTION_RESULT_DODGED] = true,
        [ACTION_RESULT_BLOCKED] = true,
        [ACTION_RESULT_BLOCKED_DAMAGE] = true,
        [ACTION_RESULT_DISORIENTED] = true,
    }

    if not validResults[result] then
        return
    end

    -- if result == ACTION_RESULT_STUNNED then
        -- d('STUNNED after')
    -- end

    -- if result~=ACTION_RESULT_EFFECT_GAINED_DURATION and result~=ACTION_RESULT_STUNNED and result~=ACTION_RESULT_FEARED and result~=ACTION_RESULT_STAGGERED and result~=ACTION_RESULT_IMMUNE and result~=ACTION_RESULT_DISORIENTED then return end

    if abilityName == "Hiding Spot" then -- TODO: Put ID here instead or add to blacklist instead
        return
    end

    -------------STAGGERED EVENT TRIGGER--------------------
    if CI.SV.cct.showStaggered and result == ACTION_RESULT_STAGGERED and self.currentCC == 0 then
        zo_callLater(function() self:RemoveCC(5, GetFrameTimeMilliseconds()) end, CCT_STAGGER_DURATION)
        self:OnDraw(abilityId, abilityIcon, CCT_STAGGER_DURATION, result, abilityName, CCT_STAGGER_DURATION)
    end
    --------------------------------------------------------

    -------------IMMUNE EVENT TRIGGER-----------------------
    if CI.SV.cct.showImmune and (result == ACTION_RESULT_IMMUNE or (PVP_Alerts_Main_Table and (result == ACTION_RESULT_DODGED or result == ACTION_RESULT_BLOCKED or result == ACTION_RESULT_BLOCKED_DAMAGE) and PVP_Alerts_Main_Table.snipeId[abilityId])) and not (CI.SV.cct.showImmuneOnlyInCyro and not LUIE.ResolvePVPZone()) and (not self.currentlyPlaying) and self.currentCC == 0 and GetAbilityIcon(abilityId) ~= nil then
        self:OnDraw(abilityId, abilityIcon, CI.SV.cct.immuneDisplayTime, result, abilityName, CI.SV.cct.immuneDisplayTime)
    end
    -------------------------------------------------------

    if not self.incomingCC then
        self.incomingCC = {}
    end

    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        if (abilityName == GetAbilityName(CCT_NEGATE_MAGIC_ID) or abilityId == CCT_NEGATE_MAGIC_ID or abilityId == CCT_NEGATE_MAGIC_1_ID) then
            local currentEndTimeSilence = GetFrameTimeMilliseconds() + hitValue
            PriorityFour = {endTime = currentEndTimeSilence, abilityId = abilityId, abilityIcon = abilityIcon, hitValue = hitValue, result = ACTION_RESULT_SILENCED, abilityName = abilityName}
            if PriorityOne.endTime == 0 and PriorityTwo.endTime == 0 and PriorityThree.endTime == 0 then
                self.currentCC = 4
                zo_callLater(function() self:RemoveCC(4, currentEndTimeSilence) end, hitValue + CCT_GRACE_TIME)
                self:OnDraw(abilityId, abilityIcon, hitValue, ACTION_RESULT_SILENCED, abilityName, hitValue)
            end
        else
            -- d("EVENT " .. " DURATION " .. tostring(GetFrameTimeMilliseconds()))
            -- if self.incomingCC[ACTION_RESULT_FEARED] then
                -- d("FEAR DURATION " .. tostring(GetFrameTimeMilliseconds()))
            -- end
            local currentTime = GetFrameTimeMilliseconds()
            local currentEndTime = currentTime + hitValue
            if abilityId == self.incomingCC[ACTION_RESULT_STUNNED] and (currentEndTime + 200) > PriorityOne.endTime then
                -- self.incomingCC[ACTION_RESULT_STUNNED] = nil
                -- callbackManager:RegisterCallback("OnIncomingStun", function()
                    if self.breakFreePlaying then
                        return
                    end
                    PriorityOne = {endTime = (GetFrameTimeMilliseconds() + hitValue), abilityId = abilityId, abilityIcon = abilityIcon, hitValue = hitValue, result = ACTION_RESULT_STUNNED, abilityName = abilityName}
                    self.currentCC = 1
                    zo_callLater(function() self:RemoveCC(1, currentEndTime) end, hitValue + CCT_GRACE_TIME+1000)
                    self:OnDraw(abilityId, abilityIcon, hitValue, ACTION_RESULT_STUNNED, abilityName, hitValue)
                -- end)
                -- zo_callLater(function() callbackManager:UnregisterAllCallbacks("OnIncomingStun") end, 1)
                self.incomingCC = {}
            elseif abilityId == self.incomingCC[ACTION_RESULT_FEARED] and (currentEndTime + 200) > PriorityOne.endTime and (currentEndTime + 200) > PriorityTwo.endTime then
                table.insert(self.fearsQueue, abilityId)
                PriorityTwo = {endTime = currentEndTime, abilityId = abilityId, abilityIcon = abilityIcon, hitValue = hitValue, result = ACTION_RESULT_FEARED, abilityName = abilityName}
                if PriorityOne.endTime == 0 then
                    self.currentCC = 2
                    zo_callLater(function() self:RemoveCC(2, currentEndTime) end, hitValue + CCT_GRACE_TIME)
                    self:OnDraw(abilityId, abilityIcon, hitValue, ACTION_RESULT_FEARED, abilityName, hitValue)
                end
                self.incomingCC = {}
            elseif abilityId == self.incomingCC[ACTION_RESULT_DISORIENTED] and (currentEndTime + 200) > PriorityOne.endTime and (currentEndTime + 200) > PriorityTwo.endTime and currentEndTime > PriorityThree.endTime then
                -- self.incomingCC[ACTION_RESULT_DISORIENTED] == nil
                table.insert(self.disorientsQueue, abilityId)
                PriorityThree = {endTime = currentEndTime, abilityId = abilityId, abilityIcon = abilityIcon, hitValue = hitValue, result = ACTION_RESULT_DISORIENTED, abilityName = abilityName}
                if PriorityOne.endTime == 0 and PriorityTwo.endTime == 0 then
                    self.currentCC = 3
                    zo_callLater(function() self:RemoveCC(3, currentEndTime) end, hitValue + CCT_GRACE_TIME)
                    self:OnDraw(abilityId, abilityIcon, hitValue, ACTION_RESULT_DISORIENTED, abilityName, hitValue)
                end
                self.incomingCC = {}
            else
                table.insert(self.effectsGained, {abilityId = abilityId, hitValue = hitValue, sourceUnitId = sourceUnitId, abilityGraphic = abilityGraphic})
            end
        end
    elseif #self.effectsGained > 0 then
        local foundValue = self:FindEffectGained(abilityId, sourceUnitId, abilityGraphic)
        -- if not foundValue then return end

        if foundValue then
            local currentTime = GetFrameTimeMilliseconds()
            local currentEndTime = currentTime + foundValue.hitValue

            if result == ACTION_RESULT_FEARED and (currentEndTime + 200) > PriorityOne.endTime and (currentEndTime + 200) > PriorityTwo.endTime then
                table.insert(self.fearsQueue, abilityId)
                PriorityTwo = {endTime = currentEndTime, abilityId = abilityId, abilityIcon = abilityIcon, hitValue = foundValue.hitValue, result = result, abilityName = abilityName}
                if PriorityOne.endTime == 0 then
                    self.currentCC = 2
                    zo_callLater(function() self:RemoveCC(2, currentEndTime) end, foundValue.hitValue + CCT_GRACE_TIME)
                    self:OnDraw(abilityId, abilityIcon, foundValue.hitValue, result, abilityName, foundValue.hitValue)
                end
            end
            self.effectsGained = {}
        end
    end

    if self.actionResults[result] then
        self.incomingCC[result] = abilityId
        -- if result == ACTION_RESULT_FEARED then
            -- d("FEAR EVENT " .. tostring(GetFrameTimeMilliseconds()))
        -- end

        -- d("EVENT " .. tostring(result) .. " " .. tostring(GetFrameTimeMilliseconds()))
        -- return
    end


    -- else
        -- if #self.effectsGained>0 then
            -- local foundValue=self:FindEffectGained(abilityId, sourceUnitId, abilityGraphic)
            -- if not foundValue then return end

            -- local currentTime=GetFrameTimeMilliseconds()
            -- local currentEndTime=currentTime+foundValue.hitValue
            -- if result==ACTION_RESULT_STUNNED and (currentEndTime+200)>PriorityOne.endTime then
                -- callbackManager:RegisterCallback("OnIncomingStun", function()
                    -- if self.breakFreePlaying then return end
                    -- PriorityOne = {endTime=(GetFrameTimeMilliseconds()+foundValue.hitValue), abilityId=abilityId, hitValue=foundValue.hitValue, result=result, abilityName=abilityName}
                    -- self.currentCC = 1
                    -- zo_callLater(function() self:RemoveCC(1, currentEndTime) end, foundValue.hitValue+CCT_GRACE_TIME+1000)
                    -- d('draw stun')
                    -- self:OnDraw(abilityId, abilityIcon, foundValue.hitValue, result, abilityName, foundValue.hitValue)
                -- end)
                -- zo_callLater(function() callbackManager:UnregisterAllCallbacks("OnIncomingStun") end, 1)

            -- elseif result==ACTION_RESULT_FEARED and (currentEndTime+200)>PriorityOne.endTime and (currentEndTime+200)>PriorityTwo.endTime then
                -- table.insert(self.fearsQueue, abilityId)
                -- PriorityTwo = {endTime=currentEndTime, abilityId=abilityId, hitValue=foundValue.hitValue, result=result, abilityName=abilityName}
                -- if PriorityOne.endTime==0 then
                    -- self.currentCC=2
                    -- zo_callLater(function() self:RemoveCC(2, currentEndTime) end, foundValue.hitValue+CCT_GRACE_TIME)
                    -- self:OnDraw(abilityId, abilityIcon, foundValue.hitValue, result, abilityName, foundValue.hitValue)
                -- end

            -- elseif result==ACTION_RESULT_DISORIENTED and (currentEndTime+200)>PriorityOne.endTime and (currentEndTime+200)>PriorityTwo.endTime and currentEndTime>PriorityThree.endTime then
                -- table.insert(self.disorientsQueue, abilityId)
                -- PriorityThree = {endTime=currentEndTime, abilityId=abilityId, hitValue=foundValue.hitValue, result=result, abilityName=abilityName}
                -- if PriorityOne.endTime==0 and PriorityTwo.endTime==0 then
                    -- self.currentCC=3
                    -- zo_callLater(function() self:RemoveCC(3, currentEndTime) end, foundValue.hitValue+CCT_GRACE_TIME)
                    -- self:OnDraw(abilityId, abilityIcon, foundValue.hitValue, result, abilityName, foundValue.hitValue)
                -- end
            -- end
            -- self.effectsGained={}
        -- end
    -- end
end


function CCT:RemoveCC(ccType, currentEndTime)
    local stagger
    if (self.currentCC == 0 and (ccType ~= 5)) or self.breakFreePlaying then
        return
    end
    local currentTime = GetFrameTimeMilliseconds()
    local secondInterval, thirdInterval, fourthInterval, sixthInterval = PriorityTwo.endTime - currentTime, PriorityThree.endTime - currentTime, PriorityFour.endTime - currentTime, PrioritySix.endTime - currentTime
----STUN-----
    if ccType == 1 then
        if self.currentCC == 1 and PriorityOne.endTime ~= currentEndTime then
            return
        end
        PriorityOne = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
        if secondInterval > 0 then
            self.currentCC = 2
            zo_callLater(function() self:RemoveCC(2, PriorityTwo.endTime) end, secondInterval)
            self:OnDraw(PriorityTwo.abilityId, PriorityTwo.abilityIcon, PriorityTwo.hitValue, PriorityTwo.result, PriorityTwo.abilityName, secondInterval)
            return
        elseif thirdInterval > 0 then
            self.currentCC = 3
            zo_callLater(function() self:RemoveCC(3, PriorityThree.endTime) end, thirdInterval)
            self:OnDraw(PriorityThree.abilityId, PriorityThree.abilityIcon, PriorityThree.hitValue, PriorityThree.result, PriorityThree.abilityName, thirdInterval)
            return
        elseif fourthInterval > 0 then
            self.currentCC = 4
            zo_callLater(function() self:RemoveCC(4, PriorityFour.endTime) end, fourthInterval)
            self:OnDraw(PriorityFour.abilityId, PriorityFour.abilityIcon, PriorityFour.hitValue, PriorityFour.result, PriorityFour.abilityName, fourthInterval)
            return
        elseif sixthInterval > 0 then
            self.currentCC = 6
            zo_callLater(function() self:RemoveCC(6, PriorityFour.endTime) end, sixthInterval)
            self:OnDraw(PrioritySix.abilityId, PrioritySix.abilityIcon, PrioritySix.hitValue, PrioritySix.result, PrioritySix.abilityName, sixthInterval)
            return
        end
----FEAR----
    elseif ccType == 2 then
        if (self.currentCC == 1 or self.currentCC == 2) and PriorityTwo.endTime ~= currentEndTime then
            return
        end
        PriorityTwo = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
        if PriorityOne.endTime > 0 and self.currentCC == 1 then
            return
        end
        if thirdInterval > 0 then
            self.currentCC = 3
            zo_callLater(function() self:RemoveCC(3, PriorityThree.endTime) end, thirdInterval)
            self:OnDraw(PriorityThree.abilityId, PriorityThree.abilityIcon, PriorityThree.hitValue, PriorityThree.result, PriorityThree.abilityName, thirdInterval)
            return
        elseif fourthInterval > 0 then
            self.currentCC = 4
            zo_callLater(function() self:RemoveCC(4, PriorityFour.endTime) end, fourthInterval)
            self:OnDraw(PriorityFour.abilityId, PriorityFour.abilityIcon, PriorityFour.hitValue, PriorityFour.result, PriorityFour.abilityName, fourthInterval)
            return
        elseif sixthInterval > 0 then
            self.currentCC = 6
            zo_callLater(function() self:RemoveCC(6, PriorityFour.endTime) end, sixthInterval)
            self:OnDraw(PrioritySix.abilityId, PrioritySix.abilityIcon, PrioritySix.hitValue, PrioritySix.result, PrioritySix.abilityName, sixthInterval)
            return
        end
----DISORIENT----
    elseif ccType == 3 then
        if (self.currentCC > 0 and self.currentCC < 4) and PriorityThree.endTime ~= currentEndTime then --d("DISORIENT discarded")
            return
        end
        PriorityThree = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
        if (PriorityOne.endTime > 0 and self.currentCC == 1) or (PriorityTwo.endTime > 0 and self.currentCC == 2) then
            return
        end
        if fourthInterval > 0 then
            self.currentCC = 4
            zo_callLater(function() self:RemoveCC(4, PriorityFour.endTime) end, fourthInterval)
            self:OnDraw(PriorityFour.abilityId, PriorityFour.abilityIcon, PriorityFour.hitValue, PriorityFour.result, PriorityFour.abilityName, thirdInterval)
            return
        elseif sixthInterval > 0 then
            self.currentCC = 6
            zo_callLater(function() self:RemoveCC(6, PriorityFour.endTime) end, sixthInterval)
            self:OnDraw(PrioritySix.abilityId, PrioritySix.abilityIcon, PrioritySix.hitValue, PrioritySix.result, PrioritySix.abilityName, sixthInterval)
            return
        end
----SILENCE----
    elseif ccType == 4 then
        if self.currentCC ~= 0 and PriorityFour.endTime ~= currentEndTime then
            return
        end
        PriorityFour = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
        if (PriorityOne.endTime > 0 and self.currentCC == 1) or (PriorityTwo.endTime > 0 and self.currentCC == 2) or (PriorityThree.endTime > 0 and self.currentCC == 3) then
            return
        end
        elseif sixthInterval > 0 then
            self.currentCC = 6
            zo_callLater(function() self:RemoveCC(6, PriorityFour.endTime) end, sixthInterval)
            self:OnDraw(PrioritySix.abilityId, PrioritySix.abilityIcon, PrioritySix.hitValue, PrioritySix.result, PrioritySix.abilityName, sixthInterval)
        return
----STAGGER----
    elseif ccType == 5 then
        if self.currentCC ~= 0 then
            return
        else
            stagger = true
        end
----AOE----
    elseif ccType == 6 then
        if self.currentCC ~= 0 and PrioritySix.endTime ~= currentEndTime then
            return
        end
        PrioritySix = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
        if (PriorityOne.endTime > 0 and self.currentCC == 1) or (PriorityTwo.endTime > 0 and self.currentCC == 2) or (PriorityThree.endTime > 0 and self.currentCC == 3) or (PriorityFour.endTime > 0 and self.currentCC == 4) then
            return
        end
    end

    if CI.SV.cct.showOptions == "text" then
        stagger=true
    end
    self:StopDraw(stagger)
end

function CCT:OnStunnedState(eventCode, playerStunned)
    -- d('playerStunned: '..tostring(playerStunned))
    if not playerStunned then
        -- d("PriorityOne.endTime", PriorityOne.endTime)
        if PriorityOne.endTime ~= 0 then
            self:RemoveCC(1, PriorityOne.endTime)
        end
    else
        -- callbackManager:FireCallbacks("OnIncomingStun")
    end
end

function CCT:GetDefaultIcon(ccType)
    if ccType == ACTION_RESULT_STUNNED then return CCT_DEFAULT_STUN_ICON
    elseif ccType == ACTION_RESULT_FEARED then return CCT_DEFAULT_FEAR_ICON
    elseif ccType == ACTION_RESULT_DISORIENTED then return CCT_DEFAULT_DISORIENT_ICON
    elseif ccType == ACTION_RESULT_SILENCED then return CCT_DEFAULT_SILENCE_ICON
    elseif ccType == ACTION_RESULT_AREA_EFFECT then return CCT_ZOS_DEFAULT_ICON
    elseif ccType == ACTION_RESULT_IMMUNE then return CCT_DEFAULT_IMMUNE_ICON
    elseif ccType == ACTION_RESULT_DODGED then return CCT_DEFAULT_IMMUNE_ICON
    elseif ccType == ACTION_RESULT_BLOCKED then return CCT_DEFAULT_IMMUNE_ICON
    elseif ccType == ACTION_RESULT_BLOCKED_DAMAGE then return CCT_DEFAULT_IMMUNE_ICON
    end
end

function CCT:OnDraw(abilityId, abilityIcon, ccDuration, result, abilityName, interval)
    if result == ACTION_RESULT_STAGGERED then
        self:OnAnimation(LUIE_CCTracker, "stagger")
        return
    end

    local wasDefault

    -- TODO: Override icon with default here if needed
    -- ADD  THIS SV
    if CI.SV.cct.defaultIcon or abilityIcon == CCT_ZOS_DEFAULT_ICON then
        abilityIcon = self:GetDefaultIcon(result)
        wasDefault = true
    end

    local ccText
    if CI.SV.cct.useAbilityName then
        ccText = zo_strformat(SI_ABILITY_NAME, abilityName)
    else
        ccText = self.controlText[result]
    end
    if CC.UnbreakableList[abilityId] then
        self:SetupInfo(ccText, CI.SV.cct.colors.unbreakable, abilityIcon, wasDefault)
    else
        self:SetupInfo(ccText, CI.SV.cct.colors[result], abilityIcon, wasDefault)
    end

    if result == ACTION_RESULT_SILENCED or result == ACTION_RESULT_AREA_EFFECT then
        if CI.SV.cct.showOptions == "text" then
            self:OnAnimation(LUIE_CCTracker_TextFrame, "silence")
        else
            self:OnAnimation(LUIE_CCTracker_IconFrame, "silence")
        end
    elseif result == ACTION_RESULT_IMMUNE or result == ACTION_RESULT_DODGED or result == ACTION_RESULT_BLOCKED or result == ACTION_RESULT_BLOCKED_DAMAGE then
        self:OnAnimation(LUIE_CCTracker, "immune")
        if wasDefault then
            LUIE_CCTracker_IconFrame_Icon:SetTextureCoords(0.2,0.8,0.2,0.8)
        end
    else
        self:OnProc(ccDuration, interval)
    end
end

function CCT:IconHidden(hidden)
    if CI.SV.cct.showOptions == "text" then
        LUIE_CCTracker_IconFrame:SetHidden(true)
    else
        LUIE_CCTracker_IconFrame:SetHidden(hidden)
    end
end

function CCT:TimerHidden(hidden)
    if CI.SV.cct.showOptions == "text" then
        LUIE_CCTracker_Timer:SetHidden(true)
    else
        LUIE_CCTracker_Timer:SetHidden(hidden)
    end
end

function CCT:TextHidden(hidden)
    if CI.SV.cct.showOptions == "icon" then
        LUIE_CCTracker_TextFrame:SetHidden(true)
    else
        LUIE_CCTracker_TextFrame:SetHidden(hidden)
    end
end

function CCT:BreakFreeHidden(hidden)
    if CI.SV.cct.showOptions == "text" then
        LUIE_CCTracker_BreakFreeFrame:SetHidden(true)
    else
        LUIE_CCTracker_BreakFreeFrame:SetHidden(hidden)
    end
end

function CCT:SetupInfo(ccText, ccColor, abilityIcon, wasDefault)
    LUIE_CCTracker_TextFrame_Label:SetFont(CCT_ICON_FONT)
    LUIE_CCTracker_TextFrame_Label:SetText(ccText)
    LUIE_CCTracker_TextFrame_Label:SetColor(unpack(ccColor))
    LUIE_CCTracker_IconFrame_Icon:SetTexture(abilityIcon)

    if wasDefault then
        LUIE_CCTracker_IconFrame_Icon:SetColor(unpack(ccColor))
    else
        LUIE_CCTracker_IconFrame_Icon:SetColor(1,1,1,1)
    end

    LUIE_CCTracker_IconFrame_IconBG:SetColor(unpack(ccColor))

    LUIE_CCTracker_IconFrame_IconBorder:SetColor(unpack(ccColor))
    LUIE_CCTracker_IconFrame_IconBorderHighlight:SetColor(unpack(ccColor))

    LUIE_CCTracker_Timer_Label:SetColor(unpack(ccColor))
end

function CCT:SetupDisplay(displayType)
    if displayType == "silence" then
        LUIE_CCTracker_IconFrame_Cooldown:SetHidden(true)
        LUIE_CCTracker_IconFrame_GlobalCooldown:SetHidden(true)
        LUIE_CCTracker_IconFrame_IconBorderHighlight:SetHidden(false)
        LUIE_CCTracker_IconFrame_Icon:SetTextureCoords(0,1,0,1)
        self:IconHidden(false)
        self:TextHidden(false)
        self:TimerHidden(true)
        self:BreakFreeHidden(true)
        LUIE_CCTracker:SetHidden(false)

    elseif displayType == "immune" then
        LUIE_CCTracker_IconFrame_Cooldown:SetHidden(true)
        LUIE_CCTracker_IconFrame_GlobalCooldown:SetHidden(true)
        LUIE_CCTracker_IconFrame_IconBorderHighlight:SetHidden(true)
        LUIE_CCTracker_IconFrame_Icon:SetTextureCoords(0,1,0,1)
        LUIE_CCTracker_IconFrame_IconBG:SetColor(0,0,0)
        self:IconHidden(false)
        self:TextHidden(false)
        self:TimerHidden(true)
        self:BreakFreeHidden(true)
        LUIE_CCTracker:SetHidden(false)

    elseif displayType == "stagger" then
        LUIE_CCTracker_TextFrame_Label:SetText(CCT.controlText[ACTION_RESULT_STAGGERED])
        LUIE_CCTracker_TextFrame_Label:SetColor(unpack(CI.SV.cct.colors[ACTION_RESULT_STAGGERED]))
        LUIE_CCTracker_TextFrame_Label:SetFont(CCT_STAGGER_FONT)
        self:TextHidden(false)
        self:IconHidden(true)
        self:TimerHidden(true)
        self:BreakFreeHidden(true)
        LUIE_CCTracker:SetHidden(false)

    elseif displayType == "breakfree" then
        self:IconHidden(true)
        self:TextHidden(true)
        self:TimerHidden(true)
        self:BreakFreeHidden(false)
        LUIE_CCTracker:SetHidden(false)

    elseif displayType == "timer" then
        LUIE_CCTracker_IconFrame_Cooldown:SetHidden(false)
    elseif displayType == "end" then
        LUIE_CCTracker_IconFrame_IconBorderHighlight:SetHidden(false)
        LUIE_CCTracker_IconFrame_Icon:SetTextureCoords(0,1,0,1)
        LUIE_CCTracker_IconFrame_Cooldown:SetHidden(false)
        LUIE_CCTracker_IconFrame_GlobalCooldown:SetHidden(true)
        self:IconHidden(false)
        self:TextHidden(false)
        self:TimerHidden(true)
        self:BreakFreeHidden(true)
        LUIE_CCTracker:SetHidden(false)
    elseif displayType == "endstagger" then
        self:SetupDisplay("end")
        self:IconHidden(true)
    elseif displayType == "proc" then
        LUIE_CCTracker_IconFrame_Icon:SetTextureCoords(0,1,0,1)
        LUIE_CCTracker_IconFrame_IconBorderHighlight:SetHidden(false)
        self:IconHidden(false)
        self:TextHidden(false)
        self:TimerHidden(false)
        self:BreakFreeHidden(true)
        LUIE_CCTracker:SetHidden(false)
    end
end

function CCT:StopDraw(isTextOnly)
    if self.breakFreePlaying and not self.breakFreePlayingDraw then
        -- d("Stop Draw breakfree returned")
        return
    end
    self:VarReset()
    if isTextOnly then self:OnAnimation(LUIE_CCTracker, "endstagger", true)
    else
        self:OnAnimation(LUIE_CCTracker, "end", true)
    end
end

function CCT:StopDrawBreakFree()
    local breakFreeIcon
    local currentCCIcon = CCT_ICON_MISSING
    local currentCC = self.currentCC

    if currentCC ~= 0 and currentCC ~= 4 and currentCC ~= 6 then
        local currentResult = self:CCPriority(currentCC).result
        local currentAbilityId = self:CCPriority(currentCC).abilityId
        local currentColor = CI.SV.cct.colors[currentResult]

        currentCCIcon = GetAbilityIcon(currentAbilityId)

        LUIE_CCTracker_BreakFreeFrame_Left_IconBG:SetColor(unpack(currentColor))
        LUIE_CCTracker_BreakFreeFrame_Right_IconBG:SetColor(unpack(currentColor))
        LUIE_CCTracker_BreakFreeFrame_Left_IconBorder:SetColor(unpack(currentColor))
        LUIE_CCTracker_BreakFreeFrame_Left_IconBorderHighlight:SetColor(unpack(currentColor))
        LUIE_CCTracker_BreakFreeFrame_Right_IconBorder:SetColor(unpack(currentColor))
        LUIE_CCTracker_BreakFreeFrame_Right_IconBorderHighlight:SetColor(unpack(currentColor))
    end

    self:VarReset()
    self.breakFreePlaying = true

    if not currentCCIcon:find(CCT_ICON_MISSING) then
        breakFreeIcon = currentCCIcon
    else
        self:VarReset()
        self.breakFreePlaying = true
        self.breakFreePlayingDraw = true
        zo_callLater(function() self.breakFreePlayingDraw = nil self.breakFreePlaying = nil end, 450)
        LUIE_CCTracker:SetHidden(true)
        return
    end

    if breakFreeIcon == CCT_ZOS_DEFAULT_ICON then
        breakFreeIcon = self:GetDefaultIcon(currentResult)
        LUIE_CCTracker_BreakFreeFrame_Left_Icon:SetColor(unpack(CI.SV.cct.colors[self.controlTypes[currentCC]]))
        LUIE_CCTracker_BreakFreeFrame_Right_Icon:SetColor(unpack(CI.SV.cct.colors[self.controlTypes[currentCC]]))
    else
        LUIE_CCTracker_BreakFreeFrame_Left_Icon:SetColor(1,1,1,1)
        LUIE_CCTracker_BreakFreeFrame_Right_Icon:SetColor(1,1,1,1)
    end
    LUIE_CCTracker_BreakFreeFrame_Left_Icon:SetTexture(breakFreeIcon)
    LUIE_CCTracker_BreakFreeFrame_Left_Icon:SetTextureCoords(0,0.5,0,1)
    LUIE_CCTracker_BreakFreeFrame_Right_Icon:SetTexture(breakFreeIcon)
    LUIE_CCTracker_BreakFreeFrame_Right_Icon:SetTextureCoords(0.5,1,0,1)
    self:OnAnimation(nil, "breakfree", true)
end

function CCT:FindEffectGained(abilityId, sourceUnitId, abilityGraphic)
    local foundValue
    for k, v in pairs (self.effectsGained) do
        if v.abilityId == abilityId and v.sourceUnitId == sourceUnitId and v.abilityGraphic == abilityGraphic then
            foundValue = v
            break
        end
    end
    return foundValue
end

function CCT:CCPriority(ccType)
    local priority
        if ccType == 1 then priority = PriorityOne
        elseif ccType == 2 then priority = PriorityTwo
        elseif ccType == 3 then priority = PriorityThree
        elseif ccType == 4 then priority = PriorityFour
        elseif ccType == 6 then priority = PrioritySix
        end
    return priority
end

function CCT:BreakFreeAnimation()
    if self.currentlyPlaying then
        self.currentlyPlaying:Stop()
    end
    if self.immunePlaying then
        self.immunePlaying:Stop()
    end

    local leftSide, rightSide = LUIE_CCTracker_BreakFreeFrame_Left, LUIE_CCTracker_BreakFreeFrame_Right

    LUIE_CCTracker:SetScale(CI.SV.cct.controlScale)
    leftSide:ClearAnchors()
    leftSide:SetAnchor(RIGHT, LUIE_CCTracker_BreakFreeFrame_Middle, LEFT, 1-20, 0)
    rightSide:ClearAnchors()
    rightSide:SetAnchor(LEFT, LUIE_CCTracker_BreakFreeFrame_Middle, RIGHT, -1+20, 0)
    leftSide:SetAlpha(1)
    rightSide:SetAlpha(1)

    local timeline = animationManager:CreateTimeline()
    local animDuration = 300
    local animDelay = 150

    self:InsertAnimationType(timeline, ANIMATION_SCALE, leftSide, animDelay, 0, ZO_EaseOutCubic, 1.0, 2)
    self:InsertAnimationType(timeline, ANIMATION_SCALE, rightSide, animDelay, 0, ZO_EaseOutCubic, 1.0, 2)
    self:InsertAnimationType(timeline, ANIMATION_SCALE, leftSide, animDuration, animDelay, ZO_EaseOutCubic, 1.8, 0.1)
    self:InsertAnimationType(timeline, ANIMATION_SCALE, rightSide, animDuration, animDelay, ZO_EaseOutCubic, 1.8, 0.1)
    self:InsertAnimationType(timeline, ANIMATION_ALPHA, leftSide, animDuration, animDelay, ZO_EaseInOutQuintic, 1, 0)
    self:InsertAnimationType(timeline, ANIMATION_ALPHA, rightSide, animDuration, animDelay, ZO_EaseInOutQuintic, 1, 0)
    self:InsertAnimationType(timeline, ANIMATION_TRANSLATE, leftSide, animDuration, animDelay, ZO_EaseOutCubic, 0, 0, -550, 0)
    self:InsertAnimationType(timeline, ANIMATION_TRANSLATE, rightSide, animDuration, animDelay, ZO_EaseOutCubic, 0, 0, 550, 0)

    timeline:SetHandler('OnStop', function()
        leftSide:ClearAnchors()
        leftSide:SetAnchor(LEFT, LUIE_CCTracker_BreakFreeFrame, LEFT, 0, 0)
        leftSide:SetScale(1)
        rightSide:ClearAnchors()
        rightSide:SetAnchor(RIGHT, LUIE_CCTracker_BreakFreeFrame, RIGHT, 0, 0)
        rightSide:SetScale(1)
        self.breakFreePlaying = nil
    end)

    timeline:PlayFromStart()

    return timeline
end

function CCT:StartAnimation(control, animType, test)
    if self.currentlyPlaying then
        self.currentlyPlaying:Stop()
    end
    if self.immunePlaying then
        self.immunePlaying:Stop()
    end

    local _, point, relativeTo, relativePoint, offsetX, offsetY = control:GetAnchor()
    control:ClearAnchors()
    control:SetAnchor(point, relativeTo, relativePoint, offsetX, offsetY)

    local timeline = animationManager:CreateTimeline()

    if animType == "proc" then
        if control:GetAlpha() == 0 then
            self:InsertAnimationType(timeline, ANIMATION_ALPHA, control, 100, 0, ZO_EaseInQuadratic, 0, 1)
        else
            control:SetAlpha(1)
        end
        self:InsertAnimationType(timeline, ANIMATION_SCALE, control, 100,   0, ZO_EaseInQuadratic,   1, 2.2, CCT_SET_SCALE_FROM_SV)
        self:InsertAnimationType(timeline, ANIMATION_SCALE, control, 200, 200, ZO_EaseOutQuadratic, 2.2,   1, CCT_SET_SCALE_FROM_SV)

    elseif animType == "end" or animType == "endstagger" then
        local currentAlpha = control:GetAlpha()
        self:InsertAnimationType(timeline, ANIMATION_ALPHA, control, 150,   0, ZO_EaseOutQuadratic,  currentAlpha,   0)

    elseif animType == "silence" then
        if LUIE_CCTracker:GetAlpha() < 1 then
            self:InsertAnimationType(timeline, ANIMATION_ALPHA, LUIE_CCTracker, 100,   0, ZO_EaseInQuadratic,    0,   1)
            self:InsertAnimationType(timeline, ANIMATION_SCALE, control, 100,   0, ZO_EaseInQuadratic,    1, 2.5, CCT_SET_SCALE_FROM_SV)
            self:InsertAnimationType(timeline, ANIMATION_SCALE, control, 200, 200, ZO_EaseOutQuadratic, 2.5,   1, CCT_SET_SCALE_FROM_SV)
        else
            LUIE_CCTracker:SetAlpha(1)
            self:InsertAnimationType(timeline, ANIMATION_SCALE, control, 250,   0, ZO_EaseInQuadratic,    1, 1.5, CCT_SET_SCALE_FROM_SV)
            self:InsertAnimationType(timeline, ANIMATION_SCALE, control, 250, 250, ZO_EaseOutQuadratic, 1.5,   1, CCT_SET_SCALE_FROM_SV)
        end

    elseif animType == "stagger" then
        self:InsertAnimationType(timeline, ANIMATION_ALPHA, control, 50,  0, ZO_EaseInQuadratic,    0,   1)
        self:InsertAnimationType(timeline, ANIMATION_SCALE, control, 50,  0, ZO_EaseInQuadratic,    1, 1.5, CCT_SET_SCALE_FROM_SV)
        self:InsertAnimationType(timeline, ANIMATION_SCALE, control, 50, 100, ZO_EaseOutQuadratic, 1.5,   1, CCT_SET_SCALE_FROM_SV)

    elseif animType == "immune" then
        control:SetScale(CI.SV.cct.controlScale*1)
        self:InsertAnimationType(timeline, ANIMATION_ALPHA, control, 10, 0, ZO_EaseInQuadratic, 0, 0.6)
        self:InsertAnimationType(timeline, ANIMATION_ALPHA, control, CI.SV.cct.immuneDisplayTime, 100, ZO_EaseInOutQuadratic, 0.6, 0)
    end

    timeline:SetHandler('OnStop', function()
        control:SetScale(CI.SV.cct.controlScale)
        control:ClearAnchors()
        control:SetAnchor(point, relativeTo, relativePoint, offsetX, offsetY)
        self.currentlyPlaying = nil
        self.immunePlaying = nil
    end)

    timeline:PlayFromStart()
    return timeline
end

function CCT:InsertAnimationType(animHandler, animType, control, animDuration, animDelay, animEasing, ...)
    if not animHandler then
        return
    end
    if animType == ANIMATION_SCALE then
        local animationScale, startScale, endScale, scaleFromSV = animHandler:InsertAnimation(ANIMATION_SCALE, control, animDelay), ...
        if scaleFromSV then
            startScale = startScale * CI.SV.cct.controlScale
            endScale = endScale * CI.SV.cct.controlScale
        end
        animationScale:SetScaleValues(startScale, endScale)
        animationScale:SetDuration(animDuration)
        animationScale:SetEasingFunction(animEasing)
    elseif animType == ANIMATION_ALPHA then
        local animationAlpha, startAlpha, endAlpha = animHandler:InsertAnimation(ANIMATION_ALPHA, control, animDelay), ...
        animationAlpha:SetAlphaValues(startAlpha, endAlpha)
        animationAlpha:SetDuration(animDuration)
        animationAlpha:SetEasingFunction(animEasing)
    elseif animType == ANIMATION_TRANSLATE then
        local animationTranslate, startX, startY, offsetX, offsetY = animHandler:InsertAnimation(ANIMATION_TRANSLATE, control, animDelay), ...
        animationTranslate:SetTranslateOffsets(startX, startY, offsetX, offsetY)
        animationTranslate:SetDuration(animDuration)
        animationTranslate:SetEasingFunction(animEasing)
    end
end

function CCT:InitControls()
    LUIE_CCTracker:ClearAnchors()
    LUIE_CCTracker:SetAnchor(CENTER, GuiRoot, CENTER, CI.SV.cct.offsetX, CI.SV.cct.offsetY)
    LUIE_CCTracker:SetScale(CI.SV.cct.controlScale)
    LUIE_CCTracker_TextFrame_Label:SetFont(CCT_ICON_FONT)
    if CI.SV.cct.unlocked then
        LUIE_CCTracker_TextFrame_Label:SetText("Unlocked")
    else
        LUIE_CCTracker_TextFrame_Label:SetText("")
    end
    self:TextHidden(false)
    LUIE_CCTracker_IconFrame_IconBorder:SetTexture(CCT_ICONBORDER)
    LUIE_CCTracker_IconFrame_IconBorderHighlight:SetTexture(CCT_ICONBORDER)
    LUIE_CCTracker_IconFrame_IconBorder:SetHidden(false)
    LUIE_CCTracker_IconFrame_IconBorderHighlight:SetHidden(false)
    LUIE_CCTracker_IconFrame_Cooldown:ResetCooldown()
    LUIE_CCTracker_IconFrame_Cooldown:SetHidden(true)
    LUIE_CCTracker_IconFrame_GlobalCooldown:ResetCooldown()
    LUIE_CCTracker_IconFrame_GlobalCooldown:SetHidden(true)
    LUIE_CCTracker_IconFrame_Icon:SetTexture(CCT_DEFAULT_IMMUNE_ICON)
    LUIE_CCTracker_IconFrame_Icon:SetTextureCoords(0.2,0.8,0.2,0.8)
    LUIE_CCTracker_IconFrame_IconBG:SetColor(1,1,1)
    LUIE_CCTracker_IconFrame_Icon:SetColor(1,1,1)
    self:IconHidden(false)
    LUIE_CCTracker_IconFrame_IconBorder:SetColor(1,1,1)
    LUIE_CCTracker_IconFrame_IconBorderHighlight:SetColor(1,1,1)
    LUIE_CCTracker_TextFrame_Label:SetColor(1,1,1)

    LUIE_CCTracker:SetMouseEnabled(CI.SV.cct.unlocked)
    LUIE_CCTracker:SetMovable(CI.SV.cct.unlocked)
    LUIE_CCTracker:SetAlpha(1)

    LUIE_CCTracker_BreakFreeFrame_Left_IconBorder:SetTexture(CCT_ICONBORDER)
    LUIE_CCTracker_BreakFreeFrame_Left_IconBorderHighlight:SetTexture(CCT_ICONBORDER)
    LUIE_CCTracker_BreakFreeFrame_Left_IconBorder:SetTextureCoords(0,0.5,0,1)
    LUIE_CCTracker_BreakFreeFrame_Left_IconBorderHighlight:SetTextureCoords(0,0.5,0,1)
    LUIE_CCTracker_BreakFreeFrame_Right_IconBorder:SetTexture(CCT_ICONBORDER)
    LUIE_CCTracker_BreakFreeFrame_Right_IconBorderHighlight:SetTexture(CCT_ICONBORDER)
    LUIE_CCTracker_BreakFreeFrame_Right_IconBorder:SetTextureCoords(0.5,1,0,1)
    LUIE_CCTracker_BreakFreeFrame_Right_IconBorderHighlight:SetTextureCoords(0.5,1,0,1)
    LUIE_CCTracker_BreakFreeFrame_Left_Icon:SetTexture(CCT_DEFAULT_DISORIENT_ICON)
    LUIE_CCTracker_BreakFreeFrame_Left_Icon:SetTextureCoords(0,0.5,0,1)
    LUIE_CCTracker_BreakFreeFrame_Right_Icon:SetTexture(CCT_DEFAULT_DISORIENT_ICON)
    LUIE_CCTracker_BreakFreeFrame_Right_Icon:SetTextureCoords(0.5,1,0,1)
    self:BreakFreeHidden(true)
    self:TimerHidden(not CI.SV.cct.unlocked)
    LUIE_CCTracker_Timer_Label:SetText("69")
    LUIE_CCTracker_Timer_Label:SetColor(1,1,1,1)
    LUIE_CCTracker:SetHidden(not CI.SV.cct.unlocked)
end

function CCT:FullReset()
    self:VarReset()
    if self.currentlyPlaying then
        self.currentlyPlaying:Stop()
    end

    if self.breakFreePlaying then
        if not self.breakFreePlayingDraw then
            self.breakFreePlaying:Stop() end
        else
            self.breakFreePlayingDraw = nil
            self.breakFreePlaying = nil
        end
    if self.immunePlaying then
        self.immunePlaying:Stop()
    end
    self:InitControls()
end

function CCT:VarReset()
    self.effectsGained = {}
    self.disorientsQueue = {}
    self.fearsQueue = {}
    self.currentCC = 0
    PriorityOne = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
    PriorityTwo = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
    PriorityThree = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
    PriorityFour = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
    PrioritySix = {endTime = 0, abilityId = 0, abilityIcon = "", hitValue = 0, result = 0, abilityName = ""}
    self.Timer = 0
end
