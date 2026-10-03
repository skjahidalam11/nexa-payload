-- NEXA LORD PROTECTED PAYLOAD
-- Loaded only by NEXA_LORD_LOGIN.lua after successful authorization.
local PCall = pcall
local RawRequire = require
local RawImport = import
local RawIsValid = slua and slua.isValid
local function SafeRequire(...) local ok, v = PCall(RawRequire, ...) return ok and v or nil end
local function SafeImport(...) local ok, v = PCall(RawImport, ...) return ok and v or nil end
local function SafeIsValid(v) if v == nil or type(RawIsValid) ~= "function" then return false end local ok, r = PCall(RawIsValid, v) return ok and r == true end
local function HasPanelAuthorization()
    local auth = rawget(_G, "NexaHasPanelAuthorization")
    return type(auth) == "function" and auth() == true
end

-- FEATURE 02: BRPLAYERCHARACTERBASE ENGINE HOOKS AND VEHICLE HANDLING
-- ============================================================

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
local ENetRole = SafeImport("ENetRole")
local EPawnState = SafeImport("EPawnState")
local ESurviveWeaponPropSlot = SafeImport("ESurviveWeaponPropSlot")
local GameplayData = SafeRequire("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = SafeRequire("GameLua.Mod.BaseMod.Common.GamePlayTools")

-- PURPOSE: Current weapon ya weapon data ko detect aur process karta hai.
-- Weapon detection logic moved to ESP section for reliability.

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.04: BRPlayerCharacterBase:ctor
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ctor()
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.05: BRPlayerCharacterBase:_PostConstruct
-- ------------------------------------------------------------
function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.06: BRPlayerCharacterBase:ReceiveBeginPlay
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = SafeImport("CheckFallingDistanceComponent")
    if SafeIsValid(CheckFallingDistanceComponent_C) and not SafeIsValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if SafeIsValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
    self:AddControlEvent(self, "OnAttachedToVehicle", self.HandleOnAttachedToVehicle, self)
    self:AddControlEvent(self, "OnDetachedFromVehicle", self.HandleOnDetachedFromVehicle, self)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

-- PURPOSE: Vehicle/player attachment ya vehicle-related state ko handle karta hai.
-- FEATURE 02.07: BRPlayerCharacterBase:HandleOnAttachedToVehicle
-- ------------------------------------------------------------
function BRPlayerCharacterBase:HandleOnAttachedToVehicle(uVehicle)
  if not SafeIsValid(uVehicle) then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:HandleOnAttachedToVehicle", Game:GetObjName(uVehicle)))
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
    local okAttachTimer, attachTimer = PCall(function()
      return self:AddGameTimer(5, true, 
function()
      if SafeIsValid(self.Object) and SafeIsValid(uVehicle) then
        self:UpdatePlayerAttachToVehicle(uVehicle)
      end
    end)
    end)
    self.nUpdatePlayerAttachToVehicleTimer = okAttachTimer and attachTimer or nil
    local okFixTimer, fixTimer = PCall(function()
      return self:AddGameTimer(3, true, 
function()
      if SafeIsValid(self.Object) and SafeIsValid(uVehicle) then
        self:FixMeshContainerOffsetIfNeeded(uVehicle)
      end
    end)
    end)
    self.nFixMeshContainerTimer = okFixTimer and fixTimer or nil
  end
end

-- PURPOSE: Vehicle/player attachment ya vehicle-related state ko handle karta hai.
-- FEATURE 02.08: BRPlayerCharacterBase:HandleOnDetachedFromVehicle
-- ------------------------------------------------------------
function BRPlayerCharacterBase:HandleOnDetachedFromVehicle(uLastVehicle)
  if not SafeIsValid(uLastVehicle) then
    return
  end
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnDetachedFromVehicle", uLastVehicle)
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    self:ClearAttachToVehicleTimer()
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

-- PURPOSE: Vehicle/player attachment ya vehicle-related state ko handle karta hai.
-- FEATURE 02.09: BRPlayerCharacterBase:UpdatePlayerAttachToVehicle
-- ------------------------------------------------------------
function BRPlayerCharacterBase:UpdatePlayerAttachToVehicle(uVehicle)
  if not SafeIsValid(self.Object) or not SafeIsValid(uVehicle) then
    return
  end
  if not SafeIsValid(self.CapsuleComponent) or not SafeIsValid(self.Mesh) or not SafeIsValid(self.MeshContainer) then
    return
  end
  if not SafeIsValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  if not self.nUpdatePlayerAttachToVehicleCount then
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  local ESTEPoseState = SafeImport("ESTEPoseState")
  local bStand = self.PoseState == ESTEPoseState.Stand
  local uActorRelativeLocation = self.CapsuleComponent:GetRelativeTransform():GetLocation()
  local uMeshRelativeLocation = self.Mesh:GetRelativeTransform():GetLocation()
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  local nCapsuleRadius = self.CapsuleComponent:GetScaledCapsuleRadius()
  local nCapsuleHalfHeight = self.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local nExpectedCapsuleRadius = self.StandRadius
  local nExpectedCapsuleHalfHeight = self.StandHalfHeight
  local uMeshExpectedRL = FVector(0, 0, 0)
  local uActorExpectedRL = FVector(0, 0, self.StandHalfHeight)
  local nTolerance = 1.0
  local bCapsuleRLCorrect = uActorRelativeLocation:Equals(uActorExpectedRL, nTolerance)
  local bMeshRLCorrect = uMeshRelativeLocation:Equals(uMeshExpectedRL, nTolerance)
  local bMeshContainerRLCorrect = nTolerance > math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ)
  local bCapsuleRadiusCorrect = nTolerance > math.abs(nCapsuleRadius - nExpectedCapsuleRadius)
  local bCapsuleHalfHeightCorrect = nTolerance > math.abs(nCapsuleHalfHeight - nExpectedCapsuleHalfHeight)
  local bAllCorrect = bStand and bCapsuleRLCorrect and bMeshRLCorrect and bMeshContainerRLCorrect and bCapsuleRadiusCorrect and bCapsuleHalfHeightCorrect
  if not bAllCorrect then
    self.nUpdatePlayerAttachToVehicleCount = self.nUpdatePlayerAttachToVehicleCount + 1
  else
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:UpdatePlayerAttachToVehicle PlayerKey:%s. bAllCorrect=%s Check Result:%d %d %d %d %d %d, Count:%d", tostring(self.PlayerKey), tostring(bAllCorrect), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, self.nUpdatePlayerAttachToVehicleCount))
  if self.nUpdatePlayerAttachToVehicleCount >= 3 and not bAllCorrect then
    local GameplayData = SafeRequire("GameLua.GameCore.Data.GameplayData")
    local uPlayerController = GameplayData.GetPlayerController()
    if uPlayerController.ReportCrashKitFeature and uPlayerController.ReportCrashKitFeature.ReportCharacterAttachedOnVehicleException then
      local sReportInfo = string.format("VehicleShapeType:%s PlayerKey:%s. Check Result:%d %d %d %d %d %d. Capsule.RelativeLoc:%s Capsule.Radius:%s Capsule.HalfHeight:%s Mesh.RelativeLoc:%s MeshContainer.RelativeLocZ:%s", tostring(uVehicle.VehicleShapeType), tostring(self.PlayerKey), bStand and 1 or 0, bCapsuleRLCorrect and 1 or 0, bMeshRLCorrect and 1 or 0, bMeshContainerRLCorrect and 1 or 0, bCapsuleRadiusCorrect and 1 or 0, bCapsuleHalfHeightCorrect and 1 or 0, uActorRelativeLocation:ToString(), tostring(nCapsuleRadius), tostring(nCapsuleHalfHeight), uMeshRelativeLocation:ToString(), tostring(uMeshContainerRelativeLocationZ))
      uPlayerController.ReportCrashKitFeature:ReportCharacterAttachedOnVehicleException(sReportInfo)
    end
    self.nUpdatePlayerAttachToVehicleCount = 0
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.10: BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded
-- ------------------------------------------------------------
function BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded(uVehicle)
  if not SafeIsValid(self.Object) or not SafeIsValid(uVehicle) then
    return
  end
  if not SafeIsValid(self.MeshContainer) then
    return
  end
  if not SafeIsValid(self:GetCurrentVehicle()) then
    return
  end
  if Game:IsDriver(self.Object) then
    return
  end
  local nTolerance = 1.0
  local uMeshContainerExpectedZ = -1 * self.StandHalfHeight
  local uMeshContainerRelativeLocationZ = self.MeshContainer:GetRelativeTransform():GetLocation().Z
  if nTolerance <= math.abs(uMeshContainerRelativeLocationZ - uMeshContainerExpectedZ) then
    print(bWriteLog and string.format("BRPlayerCharacterBase:FixMeshContainerOffsetIfNeeded PlayerKey:%s. SetMeshContainerOffsetZ from:%s to:%s", tostring(uMeshContainerExpectedZ), tostring(uMeshContainerExpectedZ)))
    self:SetMeshContainerOffsetZ(uMeshContainerExpectedZ)
  end
end

-- PURPOSE: Vehicle/player attachment ya vehicle-related state ko handle karta hai.
-- FEATURE 02.11: BRPlayerCharacterBase:ClearAttachToVehicleTimer
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ClearAttachToVehicleTimer()
  if self.nUpdatePlayerAttachToVehicleTimer then
    self:RemoveGameTimer(self.nUpdatePlayerAttachToVehicleTimer)
    self.nUpdatePlayerAttachToVehicleTimer = nil
  end
  if self.nFixMeshContainerTimer then
    self:RemoveGameTimer(self.nFixMeshContainerTimer)
    self.nFixMeshContainerTimer = nil
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.12: BRPlayerCharacterBase:CharacterAttrChangeEvent
-- ------------------------------------------------------------
function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if SafeIsValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.13: BRPlayerCharacterBase:OnPawnStateChange
-- ------------------------------------------------------------
function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  local EPawnState = SafeImport("EPawnState")
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if SafeIsValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end

end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.14: BRPlayerCharacterBase:HandleFinishedState
-- ------------------------------------------------------------
function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if SafeIsValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfig then
    self.STCharacterMovement:SetDynamicSimpleQueryConfig(false)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.15: BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent
-- ------------------------------------------------------------
function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local EGameModeType = SafeImport("EGameModeType")
    local MatchModeIds = SafeRequire("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.16: BRPlayerCharacterBase:LuaHandleParachuteStateChanged
-- ------------------------------------------------------------
function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  local EParachuteState = SafeImport("EParachuteState")
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if SafeIsValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.17: BRPlayerCharacterBase:OnLanded
-- ------------------------------------------------------------
function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if SafeIsValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.18: BRPlayerCharacterBase:ReceiveEndPlay
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.19: BRPlayerCharacterBase:IsWarGameMode
-- ------------------------------------------------------------
function BRPlayerCharacterBase:IsWarGameMode()
  local GameplayData = SafeRequire("GameLua.GameCore.Data.GameplayData")
  local uGameState = GameplayData:GetGameState()
  local STExtraGameStateBase = SafeImport("STExtraGameStateBase")
  if SafeIsValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    local EGameModeType = SafeImport("EGameModeType")
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.20: BRPlayerCharacterBase:BPOnRecycled
-- ------------------------------------------------------------
function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

-- PURPOSE: Enemy/actor information ko detect, mark ya display karta hai.
-- FEATURE 02.21: BRPlayerCharacterBase:BPOnRespawned
-- ------------------------------------------------------------
function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.22: BRPlayerCharacterBase:ReceiveOnRecycle
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.23: BRPlayerCharacterBase:ReceiveOnSpawn
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.24: BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.25: BRPlayerCharacterBase:HandleOnMovementModeChangedNew
-- ------------------------------------------------------------
function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  local EMovementMode = SafeImport("EMovementMode")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.26: BRPlayerCharacterBase:BPOnMissPlayerDamageRecord
-- ------------------------------------------------------------
function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.28: BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment(Type, Param)
  print(bWriteLog and string.format("BRPlayerCharacterBase:ClientRPC_TriggerHighlightMoment Type = %d, Param = %s", Type, Param))
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_TRIGGER_HIGHLIGHT_MOMENT, Type, Param)
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.29: BRPlayerCharacterBase:ParachuteJump
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if SafeIsValid(uPlayerController) then
    if not self:GetEnsure() then
      local EStateType = SafeImport("EStateType")
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        local ESTEPoseState = SafeImport("ESTEPoseState")
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.30: BRPlayerCharacterBase:OnMovementBaseChangedEvent
-- ------------------------------------------------------------
function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.31: BRPlayerCharacterBase:GetMedievalCraneFromBase
-- ------------------------------------------------------------
function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not SafeIsValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not SafeIsValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.32: BRPlayerCharacterBase:CheckForbidFlaregun
-- ------------------------------------------------------------
function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not SafeIsValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if SafeIsValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.33: BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.34: BRPlayerCharacterBase:HandleNearDeathGiveupRescue
-- ------------------------------------------------------------
function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and SafeIsValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if SafeIsValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.35: BRPlayerCharacterBase:RPC_Server_GmPlayAction
-- ------------------------------------------------------------
function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  local USTExtraBlueprintFunctionLibrary = SafeImport("STExtraBlueprintFunctionLibrary")
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.36: BRPlayerCharacterBase:MulticastRPC_GmPlayAction
-- ------------------------------------------------------------
function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not SafeIsValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = SafeRequire("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, SafeImport("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = SafeRequire("common.asset_util")
  local loadLater = function()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

-- PURPOSE: Visual material, wall effect ya body color ko apply/restore karta hai.
-- FEATURE 02.37: BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall
-- ------------------------------------------------------------
function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if SafeIsValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.38: BRPlayerCharacterBase:OnPlayerEnterCarryBoxState
-- ------------------------------------------------------------
function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.39: BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState
-- ------------------------------------------------------------
function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.40: BRPlayerCharacterBase:ServerRPC_CarryDeadBox
-- ------------------------------------------------------------
function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if SafeIsValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, SafeImport("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.41: BRPlayerCharacterBase:SetAreaID
-- ------------------------------------------------------------
function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.42: BRPlayerCharacterBase:GetAreaID
-- ------------------------------------------------------------
function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.43: BRPlayerCharacterBase:CannotChangeIntoPetSpectator
-- ------------------------------------------------------------
function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.44: BRPlayerCharacterBase:DoModChangeToBT
-- ------------------------------------------------------------
function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.45: BRPlayerCharacterBase:SwitchCameraToParachuteOpening
-- ------------------------------------------------------------
function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.46: BRPlayerCharacterBase:SwitchCameraToParachuteFalling
-- ------------------------------------------------------------
function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

-- PURPOSE: Player character lifecycle, weapon lookup, vehicle attach aur movement events handle hote hain.
-- FEATURE 02.47: BRPlayerCharacterBase:SwitchCameraToNormal
-- ------------------------------------------------------------
function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

-- PURPOSE: Current weapon ya weapon data ko detect aur process karta hai.
-- FEATURE 02.48: BRPlayerCharacterBase:SwitchWeaponCheck
-- ------------------------------------------------------------
function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if SafeIsValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and SafeIsValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ========================================== 
-- ============================================================
-- FEATURE 03: AUTHORIZED PRESENTATION HOOKS
-- ============================================================
-- Authorized phone/broadcast presentation behavior.
-- ==========================================
-- PURPOSE: Authorized presentation wrappers apply karta hai.
-- FEATURE 03.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Visual material, wall effect ya body color ko apply/restore karta hai.
_G.InitializeFeature03PresentationHooks = function()
    if not HasPanelAuthorization() then return false end
    if _G.Feature03PresentationHooksInitialized then return true end

    local initialized = false
    PCall(function()
        local IPS = SafeRequire("GameLua.Mod.Library.Client.UI.IngamePhoneStateUI")
        if IPS and IPS.__inner_impl then
            local originalBattery = IPS.__inner_impl.TickRefreshBatteryInfo
            IPS.__inner_impl.TickRefreshBatteryInfo = function(self, ...)
                if originalBattery then PCall(originalBattery, self, ...) end
                if not HasPanelAuthorization() then return end
                if self.UIRoot and self.UIRoot.ProgressBar_Battery then
                    self.UIRoot.ProgressBar_Battery:SetPercent(1.0)
                    self.UIRoot.ProgressBar_Battery:SetFillColorAndOpacity(FLinearColor(0, 0, 1, 1))
                end
            end

            -- The custom ping-text override was removed. The host's original
            -- SetPingText implementation now remains untouched.
            initialized = true
        end
    end)

    PCall(function()
        local BattleKillBroadcastSubSystem = SafeRequire("GameLua.Mod.BaseMod.Client.BattleKillBroadcast.BattleKillBroadcastSubSystem")
        if not BattleKillBroadcastSubSystem then return end
        local originalCopy = BattleKillBroadcastSubSystem.CopyKillOrPutDownMessageDataUserDataToLuaTable
        BattleKillBroadcastSubSystem.CopyKillOrPutDownMessageDataUserDataToLuaTable = function(self, messageData)
            local msgData = originalCopy and originalCopy(self, messageData) or nil
            if not HasPanelAuthorization() or not (msgData and msgData.bIamCauser) then return msgData end
            local uCharacter = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController() and slua_GameFrontendHUD:GetPlayerController():GetPlayerCharacterSafety()
            if not (uCharacter and SafeIsValid(uCharacter)) then return msgData end
            -- Vehicle, weapon, and outfit skin substitutions are removed.
            -- The original broadcast data continues unchanged.
            return msgData
        end
        initialized = true
    end)

    -- Vehicle-avatar/skin customization hook intentionally removed.

    _G.Feature03PresentationHooksInitialized = initialized
    return initialized
end

-- ==============================================================================
-- ============================ BẮT ĐẦU FULL LOGIC MOD ==========================
-- ==============================================================================

-- PURPOSE: User notification, popup ya message display karta hai.
-- FEATURE 03.03: Notify
-- ------------------------------------------------------------
local function Notify(msg) local s = "[NEXA] " .. tostring(msg)
PCall(function() if _G.LexusNotify then _G.LexusNotify(s) end end)
PCall(function() local sh = SafeImport("ScriptHelperClient") if sh and
sh.AddOnScreenDebugMessage then sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1,
G=1, B=0, A=1}, {X=1.2, Y=1.2}) end end) print(s) end

local _slua = rawget(_G, "slua")

-- PURPOSE: Is function ka kaam login/key ya object validity verify karna hai.
-- FEATURE 03.04: Valid
-- ------------------------------------------------------------
local function Valid(obj)
    if not obj then return false end
    if _slua and _slua.isValid then
        local ok, v = PCall(_slua.isValid, obj)
        if not ok or not v then return false end
    end
    return true
end

-- Cache engine imports used by high-frequency ESP/wall updates. Re-importing
-- them for every enemy and every tick can cause visible latency on mobile.
local CachedLinearColor = rawget(_G, "FLinearColor") or SafeImport("LinearColor")
local CachedKismetSystemLibrary = rawget(_G, "KismetSystemLibrary") or SafeImport("KismetSystemLibrary")

-- ========================================== 
-- ============================================================
-- FEATURE 04: CORE STATE, CACHE, AND CONFIGURATION
-- ============================================================
-- STATIC VARIABLES & GLOBAL CACHE TỐI ƯU HÓA (CHỐNG LAG)
-- ========================================== 
-- PURPOSE: Global cache, runtime state aur common configuration values initialize karta hai.
-- FEATURE 04.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
local C_GREEN = {R=0, G=255, B=0, A=0}
local C_RED = {R=0, G=0, B=0, A=0}
local C_CYAN = {R=0, G=255, B=255, A=0}
local C_YELLOW = {R=0, G=0, B=0, A=0}
-- ESP Type 7 has its own opaque labels so its Bot/Enemy and shared weapon text
-- do not inherit the legacy transparent shared color constants above.
local C_ESP7_BOT_TEXT = {R=0, G=255, B=255, A=255}
local C_ESP7_PLAYER_TEXT = {R=255, G=220, B=0, A=255}
local C_WHITE = {R=0, G=0, B=0, A=0}
-- ESP Type 2 distance text: visible opaque blue.
local C_BLUE_TEXT = {R=0, G=170, B=255, A=255}
local SCALE_COLOR_V2 = {R=0, G=100, B=0, A=0}

_G.FufuModConfig = _G.FufuModConfig or {}
if _G.FufuModConfig.TPPView == nil then
    _G.FufuModConfig.TPPView = false
end

-- ==========================================
-- FORCE TPP CAMERA SYSTEM
-- ==========================================
function ToggleTPPView(enabled)
    if enabled ~= nil then
        _G.FufuModConfig.TPPView = enabled
    else
        _G.FufuModConfig.TPPView = not _G.FufuModConfig.TPPView
    end
    if _G.LexusConfig then
        _G.LexusConfig.TPPView = _G.FufuModConfig.TPPView
    end
    if _G.SaveModSettings then PCall(_G.SaveModSettings) end
    print(string.format("[FufuMod] TPP View: %s", tostring(_G.FufuModConfig.TPPView)))
    if _G.FufuModConfig.TPPView then ApplyTPPView() end
    return _G.FufuModConfig.TPPView
end

function ApplyTPPView()
    if not HasPanelAuthorization() then return end
    if not _G.FufuModConfig or not _G.FufuModConfig.TPPView then return end
    pcall(function()
        local GameplayData = SafeRequire("GameLua.GameCore.Data.GameplayData")
        local pc = GameplayData.GetPlayerController()
        if not SafeIsValid(pc) then return end
        local lp = pc:GetPlayerCharacterSafety()
        if not SafeIsValid(lp) then return end
        
        if type(pc.SwitchCameraMode) == "function" then
            pc:SwitchCameraMode(0, lp, false, true)
        end
        
        if pc.bIsFirstPerson ~= nil then pc.bIsFirstPerson = false end
        if lp.bIsFirstPerson ~= nil then lp.bIsFirstPerson = false end
        if pc.CurCameraMode ~= nil then pc.CurCameraMode = 0 end
        
        local cm = pc.PlayerCameraManager
        if SafeIsValid(cm) and cm.CurCameraMode ~= nil then cm.CurCameraMode = 0 end
        
        local gs = GameplayData.GetGameState()
        if SafeIsValid(gs) then
            if gs.IsFPPGameMode ~= nil then gs.IsFPPGameMode = false end
            if gs.IsCanSwitchFPP ~= nil then gs.IsCanSwitchFPP = true end
            if gs.IsFPPMode ~= nil then gs.IsFPPMode = false end
            if gs.bIsFPPMode ~= nil then gs.bIsFPPMode = false end
            if gs.C_IsFPPMode ~= nil then gs.C_IsFPPMode = false end
        end
    end)
end

function UnlockTPPSwitchButton()
    pcall(function()
        local UIT = SafeRequire("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        if UIT and not UIT.__tpp_unlock then
            UIT.__tpp_unlock = true
            local orig = UIT.IsFPP
            UIT.IsFPP = function(...)
                if _G.FufuModConfig and _G.FufuModConfig.TPPView then return false end
                return orig and orig(...) or false
            end
        end
    end)
end

local GLOBAL_BONE_LIST = {
    "head", "neck_01", "pelvis",
    "upperarm_r", "lowerarm_r", "hand_r",
    "upperarm_l", "lowerarm_l", "hand_l",
    "thigh_l", "calf_l", "foot_l",
    "thigh_r", "calf_r", "foot_r"
}

local GLOBAL_CONNECTIONS = {
    {"neck_01", "pelvis", C_YELLOW},
    {"neck_01", "upperarm_l", C_CYAN}, {"upperarm_l", "lowerarm_l", C_CYAN}, {"lowerarm_l", "hand_l", C_CYAN},
    {"neck_01", "upperarm_r", C_CYAN}, {"upperarm_r", "lowerarm_r", C_CYAN}, {"lowerarm_r", "hand_r", C_CYAN},
    {"pelvis", "thigh_l", C_CYAN}, {"thigh_l", "calf_l", C_CYAN}, {"calf_l", "foot_l", C_CYAN},
    {"pelvis", "thigh_r", C_CYAN}, {"thigh_r", "calf_r", C_CYAN}, {"calf_r", "foot_r", C_CYAN}
}

-- ========================================== 
-- CẤU HÌNH LEXUS CORE + FULL FEATURES VIP 
-- ========================================== 
_G.LexusConfig = _G.LexusConfig or { 
    FakeHWID = false,
    EspDistance = false, 
    EspLoai5 = false, 
    EspLoai7 = false,
    Esp7_SoLuong = true, -- [THÊM MỚI] Bật tắt Số lượng địch
    Esp7_VuKhi = true,   -- [THÊM MỚI] Bật tắt Vũ khí địch
    EspLoai8 = false,
    EspBomMaster = false, 
    EspItemBom = false,   
    EspActiveBom = false, 
    EspVehicle = false,   
    EspVeh_Dacia = true,  
    EspVeh_UAZ = true,    EspVeh_Buggy = true,  
    EspVeh_Coupe = true,  
    EspVeh_Mirado = true, 
    EspVeh_Motor = true,  
    EspVeh_Other = true,  
    EspAntenna = false, 
    UnlockFPS = false, 
    IpadView = false, 
    CustomAimbot = false, 
    CustomAimbotClose = false, 
    LessShake = false, 
    RemoveGrass = false, 
    WallXuyenTuong = false, 
    WallV2_CustomColor = false,
    WallV2_Player = true,
    WallV2_Bot = true,
    EspItem_AR = true,      
    EspItem_Sniper = true,  
    EspItem_SMG = true,     
    EspItem_Shotgun = true, 
    EspItem_LMG = true,       -- [THÊM] Súng máy
    EspItem_Pistol = true,    -- [THÊM] Súng lục
    EspItem_Melee = false,    -- [THÊM] Cận chiến
    MortarAim = false,
    EspItem_Special = true,   -- [THÊM] Vũ khí đặc biệt
    EspItem_Scope = true,
    ADESP_Enable = false,
    ADESP_ShowTags = false,
    ADESP_ShowSnapLines = true,
    ADESP_ShowCounter = false,
    ADESP_ShowWeapon = false,
    TPPView = false,
    EspItem_Grenade = true,   -- [THÊM] Lựu đạn
    Crosshair = false,
    GodMode = false, 
    WallClimb = false,
    BlackSky = false, -- Tích hợp BlackSky
    
    -- Config Mới Cho Aimbot V2 (Aim Touch)
    AimTouchEnable = false,
    AimTouchHipIgKnock = false,
    AimTouchHipIgBot = false,
    AimTouchSGIgKnock = false,
    AimTouchSGIgBot = false,
    AimTouchHipVisCheck = false,
    AimTouchSGVisCheck = false,
    AimTouchHipfire = false,
    AimTouchSG = false,
    AimTouchSGAutoFire = false,
    AimTouchScopeAll = false,
    AimTouchScopeIgKnock = false,
    AimTouchScopeIgBot = false,
    AimTouchScopeVisCheck = false,
    AimTouchScopeSniper = false,
    AimTouchSniperIgKnock = false,
    AimTouchSniperIgBot = false,
    AimTouchSniperVisCheck = false,
    
    
    
    -- Config Glow Súng
    WeaponGlow = false,
    

}
-- Do not force AD ESP sub-toggle values here. Saved settings must remain intact.

-- CHỨA STATE HỆ THỐNG ĐÃ ĐƯỢC TỐI ƯU HÓA HOÀN TOÀN RAM TRỐNG
_G.LexusState = _G.LexusState or { 
    LoopToken = 0, 
    NativeESPReady = false,
    GraphicsUnlocked = false, 
    MenuStep = 0, 
    LastCmdTime = 0,
    TrackedMarks = {},
    EnemyMarks = {},
    LastAimbotCheckTime = 0, 
    CustomTextData = nil,     
    LastAimbotConfigString = "",
    MagicUpdateVersion = 1,
    LastMagicConfigHash = "",
    PrevGraphicsState = {}
}

local limitTime = 0
local currentTime = os.time()
local isExpired = false
if false then -- [BYPASSED LOCAL LIMIT TIME]
    isExpired = false
end

isExpired = false

-- ==============================================================================
-- ============================================================
-- FEATURE 05: SECURITY/BYPASS INITIALIZATION MODULES
-- ============================================================
-- ================== KHỞI TẠO VÀ LOAD BYPASS ĐẦU TIÊN (NEW 2026) ===============
-- ==============================================================================

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.02: nop
-- ------------------------------------------------------------
local function nop() return end

-- PURPOSE: Create a proxy module that prevents crashes when the engine calls missing functions.
-- FEATURE 05.02.1: CreateSafeModule
-- ------------------------------------------------------------

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.03: nopstr
-- ------------------------------------------------------------
local function nopstr() return "" end
-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.04: nopfalse
-- ------------------------------------------------------------
local function nopfalse() return false end
-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.05: noptrue
-- ------------------------------------------------------------
local function noptrue() return true end
-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.06: nopnil
-- ------------------------------------------------------------
local function nopnil() return nil end
-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.07: retFalse
-- ------------------------------------------------------------
local function retFalse() return false end
-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.08: retTrue
-- ------------------------------------------------------------
local function retTrue() return true end

_G.BypassPermissions = {
    SecurityBypass = true,
    AntiCheatBypass = true,
    ReportBypass = true,
    BanBypass = true,
    TelemetryBypass = true,
    NetworkBypass = true,
    MD5Bypass = true,
    SignatureBypass = true,
    DNSBypass = true,
    DeviceBypass = true,
    IPBypass = true,
    MACBypass = true,
    IMEIBypass = true,
    AndroidIDBypass = true,
    
    -- All features permanently enabled
    AllFeaturesEnabled = true,
    NoReports = true,
    NoBan = true,
    NoDetection = true,
    NoTelemetry = true,
    NoCrashReport = true,
    NoAnalytics = true,
    NoMonitor = true,
    NoTrack = true,
    NoScan = true,
    NoVerify = true,
    NoCheck = true,
    NoValidate = true
}

_G.BlockedIPs = {}
_G.AntiCheatBlock = {
    BlockAllAntiCheat = true,
    BlockTSS = true,
    BlockGokuba = true,
    BlockSwiftHawk = true,
    BlockCoronaLab = true,
    BlockHawkEye = true,
    BlockHiggsBoson = true,
    BlockClientBan = true,
    BlockRealTimeBan = true,
    BlockReportSystem = true,
    BlockTLog = true,
    BlockMD5Check = true,
    BlockSignatureVerify = true,
    BlockDeviceFingerprint = true,
    BlockDNSMonitor = true,
    BlockTelemetry = true,
    BlockAnalytics = true,
    BlockCrashReport = true,
    BlockMemoryScan = true,
    BlockSpeedCheck = true,
    BlockWallCheck = true,
    BlockShootVerify = true,
    BlockModifierException = true,
    BlockSimulateLocation = true,
    BlockPlayerSecurity = true,
    BlockCircleFlow = true,
    BlockMrpcsFlow = true,
    BlockKillFlow = true,
    BlockBehaviorScore = true,
    BlockAFKReport = true,
    BlockAvatarException = true,
    BlockFileCheck = true,
    BlockPakVerify = true,
    BlockIntegrityCheck = true,
    BlockRacingAntiCheat = true,
    BlockClientEntry = true,
    BlockNetworkException = true,
    BlockUnrealNet = true,
    BlockReplay = true,
    BlockScreenshot = true,
    BlockDebugLog = true
}

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.09: ClientEntryBypass
-- ------------------------------------------------------------
local function ClientEntryBypass()
    PCall(function()
        if Client then
            Client.SetTssNetworkStatus = nop
            Client.GEMReportEnterLobbyEvent = nop
            Client.TPerforPlatDisconnectReport = nop
            Client.IsConnected = function(NetInterface) return true end
            Client.GetUnrealNetworkStatus = nopstr
            Client.MD5LuaString = function(str) return "BYPASSED_MD5" end
            Client.GetDSVersion = function() return "999.999.999" end
            Client.IsInReplayState = nopfalse
        end
        
        if NetManager then
            NetManager.ProcRespondMsg = nop
            NetManager.isLogMsgAfterLogin = false
            NetManager.logMsgMap = {}
        end
        
        if EventSystem then
            local oldPost = EventSystem.postEvent
            EventSystem.postEvent = function(eventType, eventID, ...)
                if eventID and type(eventID) == "string" then
                    local s = string.upper(eventID)
                    local blocked = {"SECURITY", "CHEAT", "BAN", "REPORT", "FLAG", 
                                    "VIOLATION", "DETECT", "VERIFY", "ANTI", "AC_",
                                    "SUSPICIOUS", "ABNORMAL", "MONITOR", "TRACK",
                                    "TELEMETRY", "ANALYTICS", "CRASH", "DUMP", "TSS", "GOKUBA", "SWIFT", "CORONA", "HAWKEYE", "HIGGS"}
                    for _, be in ipairs(blocked) do
                        if s:find(be) then return end
                    end
                end
                if oldPost then oldPost(eventType, eventID, ...) end
            end
        end
        
        local logFuncs = {"log", "log_warning", "log_error", "log_shipping_client", "log_format", "log_tree", "print"}
        for _, funcName in ipairs(logFuncs) do
            local old = _G[funcName]
            _G[funcName] = function(...)
                local args = {...}
                for _, arg in ipairs(args) do
                    if type(arg) == "string" then
                        local s = string.lower(arg)
                        if s:find("cheat") or s:find("security") or s:find("ban") or
                           s:find("detect") or s:find("verify") or s:find("integrity") or
                           s:find("report") or s:find("violation") or s:find("hack") or
                           s:find("anti") or s:find("ac_") or s:find("suspicious") or
                           s:find("abnormal") or s:find("monitor") or s:find("track") or
                           s:find("tss") or s:find("gokuba") or s:find("hawk") or s:find("higgs") then 
                           return 
                        end
                    end
                end
                if old and funcName == "print" then old(...) end
            end
        end
        
        if LogUtil then
            LogUtil.SetForceLog = nop
            LogUtil.SetLogTreeEnable = nop
            LogUtil.SetWriteLog = nop
        end
        
        if sandbox then 
            sandbox.LogError = nop
            sandbox.LogWarning = nop 
        end

        -- Block suspicious file operations that might be used for detection/logging
        local oldIOOpen = io.open
        io.open = function(path, mode)
            if type(path) == "string" then
                local s = string.lower(path)
                if s:find("log") or s:find("report") or s:find("security") or s:find("cache") then
                    if mode and mode:find("w") then return nil end -- Block writing to logs
                end
            end
            return oldIOOpen(path, mode)
        end
        
        if os and os.remove then
            local oldOSRemove = os.remove
            os.remove = function(path)
                if type(path) == "string" and (path:find("log") or path:find("report")) then return true end
                return oldOSRemove(path)
            end
        end
    end)
    print("[BYPASS] Client Entry bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.10: HiggsBosonBypass
-- ------------------------------------------------------------
local function HiggsBosonBypass()
    PCall(function()
        if CHiggsBosonComponent then
            CHiggsBosonComponent.ReceiveBeginPlay = nop
            CHiggsBosonComponent.StaticShowSecurityAlertInDev = nop
            CHiggsBosonComponent.ShowABCD = nop
            CHiggsBosonComponent._ClientShowSecurityAlertWindow = nop
            CHiggsBosonComponent._ReportChatRobot = nop
            CHiggsBosonComponent.SendAntiDataFlow = nop
            CHiggsBosonComponent.SendHitFireBtnFlow = nop
            CHiggsBosonComponent.OnBattleResult = nop
            CHiggsBosonComponent.SendHisarData = nop
            CHiggsBosonComponent.RPC_Client_ShowSecurityAlertWindow = nop
            CHiggsBosonComponent.RPC_Server_TellServerName = nop
            CHiggsBosonComponent.RecordStrategyTimestampInReplay = nop
            CHiggsBosonComponent.SkipAlertServer = nop
            CHiggsBosonComponent.SetClientAlertWindowEnabled = nop
            CHiggsBosonComponent.IsCharacterOwnerWerewolf = nopfalse
            CHiggsBosonComponent.IsCharacterOwnerButcher = nopfalse
            CHiggsBosonComponent._ProcessReportChatRobotQueue = nop
            CHiggsBosonComponent.LuaNotifySecurityAbnormalJump = nop
            CHiggsBosonComponent.bSkipAlertServer = true
            CHiggsBosonComponent.bMHActive = false
            CHiggsBosonComponent.bCallPreReplication = false
            bIsSkipAlertServer = true
            bSkipUploadNoschat = true
            _nReportNosChatTimerID = nil
            _nReportNosChatMessageID = 0
            _tReportNosChatQueue = {}
            LastTimeHandleAlert = -1
        end
        
        local GameplayData = SafeRequire("GameLua.GameCore.Data.GameplayData")
        if GameplayData then
            local pc = GameplayData.GetPlayerController()
            if Valid(pc) then
                if pc.HiggsBoson then
                    pc.HiggsBoson.bMHActive = false
                    pc.HiggsBoson.bCallPreReplication = false
                end
                if pc.HiggsBosonComponent then
                    pc.HiggsBosonComponent.bMHActive = false
                    pc.HiggsBosonComponent.bCallPreReplication = false
                end
            end
        end
    end)
    print("[BYPASS] HiggsBoson bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.11: HawkEyeBypass
-- ------------------------------------------------------------
local function HawkEyeBypass()
    PCall(function()
        if ClientHawkEyePatrolSubsystem then
            ClientHawkEyePatrolSubsystem._OnHawkSync = nop
            ClientHawkEyePatrolSubsystem._OnHawkReportSuccess = nop
            ClientHawkEyePatrolSubsystem._OnRecvInspectorBroadcastCount = nop
            ClientHawkEyePatrolSubsystem.ReportCheat = nop
            ClientHawkEyePatrolSubsystem.RequestImprison = nop
            ClientHawkEyePatrolSubsystem.SendReportTLog = nop
            ClientHawkEyePatrolSubsystem.IsDuringHawkEyePatrol = nopfalse
            ClientHawkEyePatrolSubsystem._CollectBeWatchedPlayerInfo = nop
            ClientHawkEyePatrolSubsystem.HasReported = noptrue
            ClientHawkEyePatrolSubsystem.GetBeWatchedPlayerInfo = nopnil
            ClientHawkEyePatrolSubsystem._OnPlayerKilledOtherPlayer = nop
            ClientHawkEyePatrolSubsystem._StartFrameUIRefreshTimer = nop
            ClientHawkEyePatrolSubsystem.ExitWatching = nop
            ClientHawkEyePatrolSubsystem.WantMatchNextPatrol = nop
            ClientHawkEyePatrolSubsystem._InitHawkEyePatrolSubsystem = function(self)
                self._bHasInitialized = true
                self._bHasReported = true
            end
            ClientHawkEyePatrolSubsystem._StartHideUITimer = nop
            ClientHawkEyePatrolSubsystem._StartShowDistanceUITimer = nop
            ClientHawkEyePatrolSubsystem._StartCloseBattleEndedTipsTimer = nop
            ClientHawkEyePatrolSubsystem._StartBattleTimeUsageTimer = nop
            ClientHawkEyePatrolSubsystem._StartQuitVoiceRoomTimer = nop
            ClientHawkEyePatrolSubsystem._StartExitGameTimer = nop
            ClientHawkEyePatrolSubsystem._CloseExitGameTimer = nop
            ClientHawkEyePatrolSubsystem._CreateOvertimerTimerForNextPatrol = nop
            ClientHawkEyePatrolSubsystem.ClearNextPatrolOvertimeTimer = nop
            ClientHawkEyePatrolSubsystem.ReturnLobbyAndOpenH5 = nop
            ClientHawkEyePatrolSubsystem.ForceNeverCloseBattleEndedTips = nop
            ClientHawkEyePatrolSubsystem.CheckShowReportedTips = nopfalse
            ClientHawkEyePatrolSubsystem.TryShowReportedTips = nop
            ClientHawkEyePatrolSubsystem.ShowWatchEndedTips = nop
            ClientHawkEyePatrolSubsystem.HasShownWatchEndedTips = noptrue
            ClientHawkEyePatrolSubsystem.OnShowWatchEndedTips = nop
            ClientHawkEyePatrolSubsystem.OnClickLowerLeftExitWatching = nop
            ClientHawkEyePatrolSubsystem.OnClickBottomRightOpenReportWindow = nop
            ClientHawkEyePatrolSubsystem._MarkHasReported = nop
            ClientHawkEyePatrolSubsystem.GetForbidNextPatrolRemainingTimeInSeconds = function() return 0 end
            ClientHawkEyePatrolSubsystem.GetUsedDailyTimeInSeconds = function() return 0 end
            ClientHawkEyePatrolSubsystem.GetInspectorBroadcastCount = function() return -1 end
            ClientHawkEyePatrolSubsystem.GetMaxInspectorBroadcastCount = function() return 0 end
            ClientHawkEyePatrolSubsystem.CanInspectorBroadcast = nopfalse
            ClientHawkEyePatrolSubsystem.IsCharacterLocationShouldDraw = nopfalse
            ClientHawkEyePatrolSubsystem.InitHawkEyePatrolSubsystem = nop
            ClientHawkEyePatrolSubsystem._PostConstruct = function(self)
                self._bHasInitialized = true
                self._bHasReported = true
                self.nInspectorBroadcastCount = -1
            end
            ClientHawkEyePatrolSubsystem.OnRelease = nop
            ClientHawkEyePatrolSubsystem._bHasInitialized = true
            ClientHawkEyePatrolSubsystem._bHasReported = true
            ClientHawkEyePatrolSubsystem._bHasShownWatchEndedTips = true
            ClientHawkEyePatrolSubsystem.bShowBeReportedTips = true
            ClientHawkEyePatrolSubsystem.nInspectorBroadcastCount = -1
        end
        if DSHawkEyePatrolSubsystem then
            DSHawkEyePatrolSubsystem.OnInit = nop
            DSHawkEyePatrolSubsystem.ReportCheat = nop
            DSHawkEyePatrolSubsystem.RequestImprison = nop
        end
    end)
    print("[BYPASS] HawkEye Patrol bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.12: BanLogicBypass
-- ------------------------------------------------------------
local function BanLogicBypass()
    PCall(function()
        if ClientBanLogic then
            ClientBanLogic.ReqBanInfo = nop
            ClientBanLogic.OnVoiceSwitchNotify = nop
            ClientBanLogic.OnVoiceBanNotify = nop
            ClientBanLogic.OnRealTimeVoiceBanNotify = nop
            ClientBanLogic.OnVoiceBanSuccess = nop
            ClientBanLogic.TryOpenVoice = function()
                EventSystem:postEvent(EVENTTYPE_INGAME_BAN, EVENTID_INGAME_BAN_FORBID_VOICE, false)
            end
            ClientBanLogic.IsVoiceReportEnable = nopfalse
            ClientBanLogic.OnSyncMicSuspicious = nop
            ClientBanLogic.OnSyncMicPreFilter = nop
            ClientBanLogic.OnSyncBanInfo = nop
            ClientBanLogic.OnNotifyWarningTips = nop
            ClientBanLogic.VoiceBanEndTime = 0
            ClientBanLogic.bEnableVoiceReport = false
            ClientBanLogic.SuspiciousFlag = 0
            ClientBanLogic.Reason = ""
            ClientBanLogic.IsTranslated = false
        end
        if RealTimeBan then
            RealTimeBan.Init = function() return end
            RealTimeBan.OnPlayerWithRealTimeBan = nop
            RealTimeBan.OnSyncPlayerInfo = nop
            RealTimeBan.HandleEnterGameModeFightingState = nop
            RealTimeBan.ShowAlias = nop
            RealTimeBan.SetOnRankInspectorUID = nop
            RealTimeBan.IsUIDOnRankInspector = nopfalse
            RealTimeBan.GetUIDInspectorRank = function() return -1 end
            RealTimeBan.SetInspectorBroadcastCountUID = nop
            RealTimeBan.GetUIDInspectorBroadcastCount = function() return -1 end
            RealTimeBan.GetTipsIDOffset = function() return 0 end
            RealTimeBan.GetTipsIDOffsetWithUID = function() return 0 end
            RealTimeBan.GetTipsIDOffsetInspector = function() return 0 end
            RealTimeBan.GMShowAlias = nop
            RealTimeBan.tOnRankInspectorUIDSet = {}
            RealTimeBan.tInspectorRankUIDSet = {}
            RealTimeBan.tInspectorBroadcastCountUIDSet = {}
            RealTimeBan.MaxAliasLevel = -1
            RealTimeBan.CurrentAlias = nil
            RealTimeBan.CurrentName = nil
            RealTimeBan.is_onrank_inspector = false
            RealTimeBan.inspector_rank = -1
            RealTimeBan.bHasOldAlias = false
            RealTimeBan.ShowTipsAliasConfig = {}
            RealTimeBan.DelayTime = {}
            RealTimeBan.OldShowTipsAlias = 0
        end
        if BanSystem then
            BanSystem.CheckBan = retFalse
            BanSystem.IsBanned = retFalse
            BanSystem.GetBanReason = function() return "" end
            BanSystem.GetBanTime = function() return 0 end
        end
    end)
    print("[BYPASS] Ban Logic bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.13: ReportSystemBypass
-- ------------------------------------------------------------
local function ReportSystemBypass()
    PCall(function()
        if ClientReportPlayerSubsystem then
            ClientReportPlayerSubsystem.OnInit = nop
            ClientReportPlayerSubsystem._OnPlayerKilledOtherPlayer = nop
            ClientReportPlayerSubsystem._RecordFatalDamager = nop
            ClientReportPlayerSubsystem._RecordMurdererFromDeathReplayData = nop
            ClientReportPlayerSubsystem._OnSyncFatalDamage = nop
            ClientReportPlayerSubsystem._SyncBattleResult = nop
            ClientReportPlayerSubsystem._OnBattleResult = nop
            ClientReportPlayerSubsystem._OnShowQuickReportMutualExclusiveUI = nop
            ClientReportPlayerSubsystem._OnHideQuickReportMutualExclusiveUI = nop
            ClientReportPlayerSubsystem._StartCheckGameModeTypeTimer = nop
            ClientReportPlayerSubsystem._CheckGameModeType = nop
            ClientReportPlayerSubsystem._StartCheckCurrentNotInTeamHistoricalTeammateTimer = nop
            ClientReportPlayerSubsystem._CheckCurrentNotInTeamHistoricalTeammate = nop
            ClientReportPlayerSubsystem._RecordTeammatePlayerInfo = nop
            ClientReportPlayerSubsystem._IsHealthStatusKilled = nopfalse
            ClientReportPlayerSubsystem.GetFatalDamagerMap = function() return {} end
            ClientReportPlayerSubsystem.GetFatalDamagerMapSize = function() return 0 end
            ClientReportPlayerSubsystem.GetName2InfoMap = function() return {} end
            ClientReportPlayerSubsystem.GetCachedTeammateName2InfoMap = function() return {} end
            ClientReportPlayerSubsystem.GetTeammateName2InfoMapDuringBattle = function() return {} end
            ClientReportPlayerSubsystem.GetCurrentNotInTeamHistoricalTeammateMap = function() return {} end
            ClientReportPlayerSubsystem.GetInTeamIndexFromHistoricalTeammateInfo = function() return -1 end
            ClientReportPlayerSubsystem.IsGameModeTypeTeamDeathMatch = nopfalse
            ClientReportPlayerSubsystem.GetGameModeType = function() return -1 end
            ClientReportPlayerSubsystem.GetMainModeID = function() return -1 end
            ClientReportPlayerSubsystem.GetSubModeID = function() return -1 end
            ClientReportPlayerSubsystem.EnableRecordFatalDamage = nop
            ClientReportPlayerSubsystem._tKnockDownerMap = {}
            ClientReportPlayerSubsystem._tMurdererMap = {}
            ClientReportPlayerSubsystem._ds2history = {}
            ClientReportPlayerSubsystem._tMapCurrentNotInTeamHistoricalTeammate = {}
            ClientReportPlayerSubsystem._tTeammateName2InfoMap = {}
            ClientReportPlayerSubsystem._bEnableRecordFatalDamage = false
            ClientReportPlayerSubsystem._bIsGameModeTypeTeamDeathMatch = false
            ClientReportPlayerSubsystem._nGameModeType = -1
            ClientReportPlayerSubsystem._nMainModeID = -1
            ClientReportPlayerSubsystem._nSubModeID = -1
            ClientReportPlayerSubsystem._nCheckTDMGameModeTypeTimer = nil
            ClientReportPlayerSubsystem._nCurrentNotInTeamHistoricalTeammateTimer = nil
        end
        if DSReportPlayerSubsystem then
            DSReportPlayerSubsystem.OnInit = nop
            DSReportPlayerSubsystem._OnNearDeathOrRescued = nop
            DSReportPlayerSubsystem._OnPlayerSettlementStart = nop
            DSReportPlayerSubsystem._OnTeammateDamage = nop
            DSReportPlayerSubsystem._OnCharacterDied = nop
            DSReportPlayerSubsystem._OnPlayerReconnect = nop
            DSReportPlayerSubsystem._RecordFatalDamager = nop
            DSReportPlayerSubsystem._RecordTeammateMurderer = nop
            DSReportPlayerSubsystem._AddMLKillerUIDToBattleResult = nop
            DSReportPlayerSubsystem._AddFatalDamagerMapToBattleResult = nop
            DSReportPlayerSubsystem._AddKnockDownerToBattleResult = nop
            DSReportPlayerSubsystem._AddKillerToBattleResult = nop
            DSReportPlayerSubsystem._AddTeammateMurderToBattleResult = nop
            DSReportPlayerSubsystem._SaveHistoricalTeammateInfo = nop
            DSReportPlayerSubsystem._SyncFatalDamagerMap = nop
            DSReportPlayerSubsystem._AddGameModeTypeToBattleResult = nop
            DSReportPlayerSubsystem._UpdateMLAIUID = nop
            DSReportPlayerSubsystem._AddEnemyMapToBattleResult = nop
            DSReportPlayerSubsystem._OnNoNetStartUpDoor = nop
            DSReportPlayerSubsystem._AssignTeammateInTeamIndex = nop
            DSReportPlayerSubsystem._FindCacheByUID = function(self, nUID, bAddIfNotExists)
                if bAddIfNotExists then return {} end
                return nil
            end
            DSReportPlayerSubsystem._GetFatalDamagerMap = function() return {} end
            DSReportPlayerSubsystem._IsBattleResultTableValid = nopfalse
            DSReportPlayerSubsystem._IsHealthStatusKilled = nopfalse
            DSReportPlayerSubsystem._tUID2InfoMap = {}
            DSReportPlayerSubsystem.nNoStartUpDoorNum = 0
        end
        if ui_complaint then
            ui_complaint.SubmitReportData = function(self) self:CloseWindow(false) return end
            ui_complaint._OnClickReport = function(self) return end
            ui_complaint._AddCommonTypesOfPlayerForReport = function(self) return end
            ui_complaint.AddPlayerForReport = function(self, ...) return end
            ui_complaint.GetSelectedReasonAsArray = function(self) return {} end
            ui_complaint.GetSelectedSubReasonAsArray = function(self) return {} end
            ui_complaint.BlockPlayerChat = function(self) return end
            ui_complaint.IsBlockChatCheck = function(self) return false end
            ui_complaint.CheckBoxBlack = function(self, bCheckState) return end
            ui_complaint.UpdateMatchBlackList = function(self) return end
            ui_complaint._SelectedReasonSet = {}
            ui_complaint._SelectedSubReasonSet = {}
            ui_complaint._SelectedCheatSubReasonSet = {}
            ui_complaint._tPlayerName2InfoMap = {}
            ui_complaint._tPlayerNamesArray = {}
        end
        if LogicComplaint then
            LogicComplaint.Submit = function(...) return end
        end
    end)
    print("[BYPASS] Report System bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.14: TLogBypass
-- ------------------------------------------------------------
local function TLogBypass()
    PCall(function()
        if tlog_report_utils then
            tlog_report_utils.ReportTLogEvent = nop
            tlog_report_utils.IsCanReportLobbyEvent = nopfalse
            tlog_report_utils.IsBusinessReport = nopfalse
            tlog_report_utils.SetMarketStayUpdateEnable = nop
            tlog_report_utils.GetMarketStayUpdateEnable = nopfalse
            tlog_report_utils.SetBusinessReportEnable = nop
            tlog_report_utils.SendTLogReportImmediate = nop
            tlog_report_utils.SetTlogBeginType = nop
            tlog_report_utils.SetTlogEndType = nop
            _G.SendTLogReportImmediate = nop
            _extraTlogReportEnableCfg = {}
            _isCanReportMarketStay = false
            _BusinessReportEnable = false
            _isInitConfig = true
            start_timestamp_map = {}
        end
        if ToolReportUtil then
            ToolReportUtil.GetReportSwitch = nopfalse
            ToolReportUtil.GetPackageInfo = nopnil
            ToolReportUtil.ReParseError = function(error, reportType) return error or "" end
            ToolReportUtil.IsReleaseVersion = noptrue
            ToolReportUtil.IsWhite = nopfalse
            ToolReportUtil.IsXPcallOpenInBattle = nopfalse
            ToolReportUtil.IsClientToolOpen = nopfalse
            MyOpenID = false
            MyUID = false
            VersionInfo = nil
        end
        if DSSecurityTLogSubsystem then
            DSSecurityTLogSubsystem.OnInit = nop
            DSSecurityTLogSubsystem._OnReportServerJumpFlow = nop
            DSSecurityTLogSubsystem._OnDevAlert = nop
            DSSecurityTLogSubsystem._InitWhenEditor = nop
            DSSecurityTLogSubsystem._nInitGameSafeCallbacksTimer = nil
        end
        if _G.TLog then
            _G.TLog.Info = nop
            _G.TLog.Warning = nop
            _G.TLog.Error = nop
            _G.TLog.Debug = nop
            _G.TLog.Report = nop
            _G.TLog.Send = nop
            _G.TLog.Flush = nop
        end
    end)
    print("[BYPASS] TLog Report bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.15: MD5Bypass
-- ------------------------------------------------------------
local function MD5Bypass()
    PCall(function()
        local console = SafeImport("KismetSystemLibrary")
        if console then
            console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
            console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
            console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            console.ExecuteConsoleCommand(nil, "sig.Check 0")
            console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
            console.ExecuteConsoleCommand(nil, "CheatManager.EnableCheat 1")
            console.ExecuteConsoleCommand(nil, "Net.BlockAllAntiCheat 1")
            console.ExecuteConsoleCommand(nil, "AntiCheat.DisableAll 1")
            console.ExecuteConsoleCommand(nil, "t.MaxFPS 165")
        end
        local CMode = SafeImport("CreativeModeBlueprintLibrary")
        if CMode then
            CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
            CMode.MD5HashFile = function() return "00000000000000000000000000000000" end
            CMode.GetContentDiffData = function() return true, "BYPASSED" end
            CMode.VerifyFileIntegrity = retTrue
        end
        if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end end
        if _G.CRC32 then _G.CRC32 = function() return 0 end end
        if _G.SHA1 then _G.SHA1 = function() return "BYPASS" end end
        if _G.FileHashChecker then
            _G.FileHashChecker.CheckFileMD5 = retTrue
            _G.FileHashChecker.VerifyAll = retTrue
            _G.FileHashChecker.GetHash = function() return "BYPASS" end
        end
        if _G.STExtraBlueprintFunctionLibrary then
            _G.STExtraBlueprintFunctionLibrary.CheckMD5 = retTrue
            _G.STExtraBlueprintFunctionLibrary.GetMD5 = function() return "BYPASS" end
            _G.STExtraBlueprintFunctionLibrary.VerifyFile = retTrue
        end
    end)
    print("[BYPASS] MD5 & Signature bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.16: DNSDeviceBypass
-- ------------------------------------------------------------
local function DNSDeviceBypass()
    PCall(function()
        local DeviceID = SafeImport("DeviceID")
        if DeviceID then
            DeviceID.GetDeviceID = function() return "BYPASSED_DEVICE" end
            DeviceID.GetAndroidID = function() return "BYPASSED_ANDROID_ID" end
            DeviceID.GetIMEI = function() return "BYPASSED_IMEI" end
            DeviceID.GetMACAddress = function() return "BYPASSED_MAC" end
            DeviceID.GetUniqueDeviceID = function() return "BYPASSED_UNIQUE" end
            DeviceID.GetDeviceName = function() return "BYPASSED_DEVICE_NAME" end
            DeviceID.GetDeviceModel = function() return "BYPASSED_MODEL" end
            DeviceID.GetDeviceBrand = function() return "BYPASSED_BRAND" end
            DeviceID.GetDeviceManufacturer = function() return "BYPASSED_MANUFACTURER" end
            DeviceID.GetDeviceBoard = function() return "BYPASSED_BOARD" end
            DeviceID.GetDeviceBootloader = function() return "BYPASSED_BOOTLOADER" end
            DeviceID.GetDeviceHardware = function() return "BYPASSED_HARDWARE" end
            DeviceID.GetDeviceHost = function() return "BYPASSED_HOST" end
            DeviceID.GetDeviceFingerprint = function() return "BYPASSED_FINGERPRINT" end
            DeviceID.GetDeviceSerial = function() return "BYPASSED_SERIAL" end
        end
        local DNS = SafeImport("DNS")
        if DNS then
            DNS.Resolve = function() return "127.0.0.1" end
            DNS.GetHostName = function() return "BYPASSED_HOST" end
            DNS.GetIPAddress = function() return "0.0.0.0" end
        end
        local Network = SafeImport("Network")
        if Network then
            Network.GetIPAddress = function() return "0.0.0.0" end
            Network.GetMACAddress = function() return "BYPASSED_MAC" end
            Network.GetSSID = function() return "BYPASSED_SSID" end
            Network.GetBSSID = function() return "BYPASSED_BSSID" end
        end
    end)
    print("[BYPASS] DNS & Device bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.17: GokubaBypass
-- ------------------------------------------------------------
local function GokubaBypass()
    PCall(function()
        local Gokuba = package.loaded["GameLua.Mod.BaseMod.Client.Security.Gokuba"]
        if Gokuba then
            Gokuba.ForwardFeature = function() return {0,0,0,0,0} end
            Gokuba.InitGokubaLogic = nop
            if Gokuba.TimerHandle then
                local time_ticker = SafeRequire("common.time_ticker")
                time_ticker.RemoveTimer(Gokuba.TimerHandle)
                Gokuba.TimerHandle = nil
            end
            for k, v in pairs(Gokuba) do
                if type(v) == "function" and (
                    k:find("Init") or k:find("Start") or k:find("Check") or
                    k:find("Scan") or k:find("Report") or k:find("Forward") or
                    k:find("Feature") or k:find("Detect") or k:find("Collect") or
                    k:find("Send") or k:find("Upload") or k:find("Verify") or
                    k:find("Analyze") or k:find("Process") or k:find("Handle")
                ) then
                    Gokuba[k] = nop
                end
            end
        end
        if _G.GokubaLogic then
            _G.GokubaLogic.ForwardFeature = nop
            _G.GokubaLogic.InitGokubaLogic = nop
        end
    end)
    print("[BYPASS] NEXA bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.18: RacingAntiCheatBypass
-- ------------------------------------------------------------
local function RacingAntiCheatBypass()
    PCall(function()
        if RacingAntiCheatLogic then
            RacingAntiCheatLogic.HandleRacingEnter = nop
            RacingAntiCheatLogic.HandleRacingStart = nop
            RacingAntiCheatLogic.HandleRacingEnd = nop
            RacingAntiCheatLogic.StartDetectTimer = nop
            RacingAntiCheatLogic.StopDetectTimer = nop
            RacingAntiCheatLogic.DetectVehicleFloating = nop
            RacingAntiCheatLogic.HandleFloatingCheat = nop
            RacingAntiCheatLogic.SetIgnoreFloating = nop
            RacingAntiCheatLogic.HandlePlayerPassCheckBelt = nop
            RacingAntiCheatLogic.HandleSpeedCheat = nop
            RacingAntiCheatLogic._CreateVehicleData = function() return {} end
            RacingAntiCheatLogic.vehicleDataMap = {}
            RacingAntiCheatLogic.detectTimer = nil
            RacingAntiCheatLogic.config = {
                FloatingDistLimit = 99999,
                FloatingTimeLimit = 99999,
                CheckPassIntervalLimit = 99999
            }
        end
    end)
    print("[BYPASS] Racing AntiCheat bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.19: CoronaLabBypass
-- ------------------------------------------------------------
local function CoronaLabBypass()
    PCall(function()
        _G.LocalMain = function()
            print("[BYPASS] CoronaLab telemetry timer blocked!")
            return
        end
        local uOuterController = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if SafeIsValid(uOuterController) and uOuterController.AddGameTimer then
            local orig = uOuterController.AddGameTimer
            uOuterController.AddGameTimer = function(interval, bLoop, func, ...)
                if interval == 30 and bLoop == true then
                    return nil
                end
                return orig(interval, bLoop, func, ...)
            end
        end
        if CHiggsBosonComponent then
            CHiggsBosonComponent.SecurityCoronaLabClientDataPointer = function(self) return nil end
            CHiggsBosonComponent.SetFloatValueByName = function(self, name, value) return end
        end
        if _G.CoronaLab then
            _G.CoronaLab.ReportData = nop
            _G.CoronaLab.SendData = nop
            _G.CoronaLab.CollectData = nop
            _G.CoronaLab.Telemetry = nop
        end
        local SubMgr = SafeRequire("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local sub = SubMgr:Get("CoronaLabSubsystem")
            if sub then
                sub.ReportData = nop
                sub.SendToServer = nop
                sub.CollectTelemetry = nop
                sub.StopCollection = nop
            end
        end
    end)
    print("[BYPASS] CoronaLab Telemetry bypassed!")
end

-- PURPOSE: Is function ka kaam login/key ya object validity verify karna hai.
-- FEATURE 05.20: LoginModuleBypass
-- ------------------------------------------------------------
local function LoginModuleBypass()
    PCall(function()
        if login_module then
            login_module["ban-login"] = function() return end
            login_module["idip-kick-out"] = function() return end
            login_module.aq_ban = function() return end
            login_module["device-in-blacklist"] = function() return end
            login_module.device_num_limit = function() return end
            login_module["register-forbidden"] = function() return end
            login_module["low-version"] = function() return end
            login_module["not-in-white-list"] = function() return end
            login_module.Login_Failed = function() return end
            login_module.aas_ban = function() return end
            login_module.PakMonitorStart = function(EnableMode) return end
            login_module.SetupFilenameHideKeywords = function() return end
            login_module.on_login_failed = function(conn_idx, reason, banInfo, banTime, uid, extra_table) return end
            login_module.DelaybanLoginCancelCallback = function() return end
            login_module.CheckBan = retFalse
            login_module.IsBanned = retFalse
        end
    end)
    print("[BYPASS] Login Module bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.21: SwiftHawkBypass
-- ------------------------------------------------------------
local function SwiftHawkBypass()
    PCall(function()
        for _, f in ipairs({"SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams", "SendSwiftHawkData"}) do
            if _G[f] then _G[f] = nop end
            if _G.GameplayCallbacks and _G.GameplayCallbacks[f] then _G.GameplayCallbacks[f] = nop end
        end
        local sub = package.loaded["GameLua.Mod.BaseMod.Client.Security.SwiftHawkSubsystem"]
        if sub then
            sub.ReportData = nop
            sub.SendReport = nop
            sub.CollectTelemetry = nop
        end
    end)
    print("[BYPASS] Swift Hawk bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.22: ShootVerificationBypass
-- ------------------------------------------------------------
local function ShootVerificationBypass()
    PCall(function()
        local sub = SafeRequire("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
        if sub then
            sub.OnShootVerifyFailed = nop
            sub.SendVerifyData = nop
            sub.ReportBulletHit = nop
            sub.UploadHitInfo = nop
            sub.VerifyShot = retTrue
        end
        if _G.BulletHitInfoUploadData then
            _G.BulletHitInfoUploadData.Report = nop
            _G.BulletHitInfoUploadData.Send = nop
            _G.BulletHitInfoUploadData.Upload = nop
        end
    end)
    print("[BYPASS] Shoot Verification bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.23: ModifierExceptionBypass
-- ------------------------------------------------------------
local function ModifierExceptionBypass()
    PCall(function()
        if _G.bReportedModifierException then _G.bReportedModifierException = false end
        local sub = SafeRequire("GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem")
        if sub then
            sub.ReportException = nop
            sub.CheckModifier = retTrue
            sub.ValidateModifier = retTrue
            sub.ReportModifierError = nop
        end
    end)
    print("[BYPASS] Modifier Exception bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.24: SimulateCharacterBypass
-- ------------------------------------------------------------
local function SimulateCharacterBypass()
    PCall(function()
        local sub = SafeRequire("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
        if sub then
            sub.ReportLocation = nop
            sub.SendLocationData = nop
            sub.VerifyLocation = retTrue
        end
    end)
    print("[BYPASS] Simulate Character bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.25: PlayerSecurityBypass
-- ------------------------------------------------------------
local function PlayerSecurityBypass()
    PCall(function()
        for _, c in ipairs({"PlayerSecurityInfoCollector", "PlayerSecurityInfo", "SecurityInfoCollector", "ClientSecurityCollector", "PlayerAntiCheatCollector"}) do
            if _G[c] then
                for k, v in pairs(_G[c]) do
                    if type(v) == "function" and (
                        k:find("Report") or k:find("Collect") or k:find("Send") or
                        k:find("Upload") or k:find("Record") or k:find("Check") or
                        k:find("Verify") or k:find("Validate") or k:find("Scan") or
                        k:find("Analyze") or k:find("Process") or k:find("Handle")
                    ) then
                        _G[c][k] = nop
                    end
                end
            end
        end
        local SecSub = SafeRequire("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
        if SecSub then
            SecSub.ReportData = nop
            SecSub.CheckCheat = retFalse
            SecSub.ValidatePlayer = retTrue
            SecSub.CollectData = nop
            SecSub.SendToServer = nop
        end
    end)
    print("[BYPASS] Player Security bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.26: ClientFlowBypass
-- ------------------------------------------------------------
local function ClientFlowBypass()
    PCall(function()
        for _, name in ipairs({"ClientSecMrpcsFlow", "MrpcsFlow", "MrpcsData", "ClientCircleFlowSubsystem", "ClientKillFlowSubsystem", "ClientSecPlayerKillFlow"}) do
            local sub = package.loaded[name] or _G[name]
            if sub then
                for k, v in pairs(sub) do
                    if type(v) == "function" and (
                        k:find("Report") or k:find("Send") or k:find("Flow") or
                        k:find("Record") or k:find("Process") or k:find("Upload") or
                        k:find("Track") or k:find("Monitor") or k:find("Analyze")
                    ) then
                        PCall(function() sub[k] = nop end)
                    end
                end
            end
        end
    end)
    print("[BYPASS] Client Flow bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.27: GameplayCallbackBypass
-- ------------------------------------------------------------
local function GameplayCallbackBypass()
    PCall(function()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        if _G.GameplayCallbacks.IsBypassed then return end
        local GC = _G.GameplayCallbacks
        
        local reports = {
            "ReportAttackFlow", "ReportSecAttackFlow", "ReportFireArms", 
            "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior", 
            "ReportTeammatHurt", "ReportMisKillByTeammate", "ReportForbitPick", 
            "ReportPlayerMoveRoute", "ReportPlayerPosition", "ReportVehicleMoveFlow", 
            "ReportSecTgameMovingFlow", "ReportParachuteData", "SendTssSdkAntiDataToLobby", 
            "ReportEquipmentFlow", "ReportAimFlow", "ReportPlayersPing", 
            "ReportPlayerIP", "ReportPlayerFramePingRecord", "OnDSConnectionSaturated", 
            "ReportDSNetSaturation", "ReportNetContinuousSaturate", "ReportDSNetRate", 
            "SendClientStats", "SendServerAvgTickDelta", "ReportCircleFlow", 
            "ClientSecMrpcsFlow", "SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams",
            "ReportSecurityViolation", "ReportIntegrityCheck", "ReportSignatureVerify",
            "ReportAntiCheat", "ReportAC", "ReportSuspicious", "ReportAbnormal"
        }
        for _, f in ipairs(reports) do GC[f] = nop end
        
        GC.CheckReportSecAttackFlowWithAttackFlow = retFalse
        GC.CheckReportSecAttackFlow = retFalse
        
        local origState = GC.OnDSPlayerStateChanged
        GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
            local s = State and string.lower(tostring(State)) or ""
            local blocked = {
                ["cheatdetected"]=1, ["connectionlost"]=1, ["connectiontimeout"]=1, 
                ["connectionexception"]=1, ["netdrivererror"]=1, ["banned"]=1, 
                ["kicked"]=1, ["suspended"]=1, ["violationdetected"]=1, 
                ["integrityfailure"]=1, ["securityviolation"]=1, ["report"]=1,
                ["ban"]=1, ["detect"]=1, ["flag"]=1, ["hack"]=1,
                ["anti"]=1, ["ac_"]=1, ["beacon"]=1, ["monitor"]=1
            }
            if blocked[s] then return end
            if origState then PCall(origState, UID, State, bPure, bSafe, Param) end
        end
        
        GC.OnPlayerNetConnectionClosed = nop
        GC.OnPlayerActorChannelError = nop
        GC.OnPlayerRPCValidateFailed = nop
        GC.OnPlayerSpectateException = nop
        GC.OnShutdownAfterError = nop
        GC.IsBypassed = true
    end)
    print("[BYPASS] Gameplay Callback bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.28: KillAllSubsystems
-- ------------------------------------------------------------
local function KillAllSubsystems()
    PCall(function()
        local SubMgr = SafeRequire("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubMgr then
            local toKill = {
                "CoronaLabSubsystem", "PlayerSecurityInfoSubsystem", "ClientCircleFlowSubsystem",
                "ModifierExceptionSubsystem", "SimulateCharacterSubsystem", "ShootVerifySubSystemClient",
                "HiggsBosonComponent", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem",
                "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem", "ClientDataStatistcsSubsystem",
                "AFKReportorSubsystem", "BehaviorScoreSubsystem", "FileCheckSubsystem",
                "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem",
                "AvatarExceptionSubsystem", "GameReportSubsystem", "ClientSecMrpcsFlowSubsystem",
                "MrpcsFlowSubsystem", "CircleFlowSubsystem", "SwiftHawkSubsystem",
                "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
                "MD5CheckSubsystem", "PakVerifySubsystem", "DNSMonitorSubsystem",
                "DeviceFingerprintSubsystem", "ReplayMonitorSubsystem", "TelemetrySubsystem",
                "GokubaSubsystem", "RacingAntiCheatSubsystem", "ClientBanSubsystem",
                "RealTimeBanSubsystem", "TLogSubsystem", "ReportSubsystem",
                "SecurityMonitorSubsystem", "CheatDetectionSubsystem", "ViolationMonitorSubsystem",
                "SuspiciousActivitySubsystem", "AbnormalBehaviorSubsystem", "NetworkMonitorSubsystem",
                "AnalyticsSubsystem", "CrashReportSubsystem", "PerformanceMonitorSubsystem"
            }
            for _, name in ipairs(toKill) do
                local sub = SubMgr:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and (
                            k:find("Report") or k:find("Send") or k:find("Upload") or
                            k:find("Verify") or k:find("Check") or k:find("Validate") or
                            k:find("Scan") or k:find("Detect") or k:find("Collect") or
                            k:find("Flow") or k:find("Heartbeat") or k:find("Monitor") or
                            k:find("Track") or k:find("Record") or k:find("Log") or
                            k:find("Alert") or k:find("Notify") or k:find("Ban") or
                            k:find("Kick") or k:find("Suspend") or k:find("Flag") or
                            k:find("Anti") or k:find("AC") or k:find("Analyze") or
                            k:find("Process") or k:find("Handle") or k:find("Evaluate")
                        ) then PCall(function() sub[k] = nop end) end
                    end
                    if sub.timer then PCall(function() sub:RemoveGameTimer(sub.timer) end) end
                    if sub.heartbeatTimer then PCall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
                    if sub.reportTimer then PCall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
                    if sub.checkTimer then PCall(function() sub:RemoveGameTimer(sub.checkTimer) end) end
                    if sub.monitorTimer then PCall(function() sub:RemoveGameTimer(sub.monitorTimer) end) end
                    if sub.scanTimer then PCall(function() sub:RemoveGameTimer(sub.scanTimer) end) end
                end
            end
        end
    end)
    print("[BYPASS] All subsystems killed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.29: SLUABypass
-- ------------------------------------------------------------
local function SLUABypass()
    PCall(function()
        if slua and slua.getSignature then slua.getSignature = function() return 0xDEADBEEF end end
        local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
        if loader then
            loader.verifyBytecode = retTrue
            loader.checkIntegrity = retTrue
            if loader.disableSignatureCheck then loader.disableSignatureCheck = retTrue end
        end
        local slua_serialize = package.loaded["slua.serialize"]
        if slua_serialize then
            slua_serialize.check = retTrue
            slua_serialize.verify = retTrue
        end
        if _G.slua_verify then _G.slua_verify = retTrue end
        if _G.check_slua_integrity then _G.check_slua_integrity = retTrue end
        if _G.slua_loader then
            _G.slua_loader.verifyBytecode = retTrue
            _G.slua_loader.checkIntegrity = retTrue
        end
    end)
    print("[BYPASS] SLUA bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.30: ReplayTelemetryBypass
-- ------------------------------------------------------------
local function ReplayTelemetryBypass()
    PCall(function()
        if _G.Replay then
            _G.Replay.Record = nop
            _G.Replay.StopRecord = nop
            _G.Replay.Save = nop
            _G.Replay.Upload = nop
            _G.Replay.Report = nop
        end
        if _G.Telemetry then
            _G.Telemetry.Send = nop
            _G.Telemetry.Report = nop
            _G.Telemetry.Track = nop
            _G.Telemetry.Log = nop
        end
        if _G.Analytics then
            _G.Analytics.Send = nop
            _G.Analytics.Report = nop
            _G.Analytics.Track = nop
        end
        if _G.Firebase then
            _G.Firebase.logEvent = nop
            _G.Firebase.trackEvent = nop
            _G.Firebase.setEnabled = retFalse
            _G.Firebase.sendEvent = nop
            _G.Firebase.report = nop
        end
        if _G.Adjust then
            _G.Adjust.logEvent = nop
            _G.Adjust.trackEvent = nop
            _G.Adjust.setEnabled = retFalse
            _G.Adjust.sendEvent = nop
        end
        if _G.AppsFlyer then
            _G.AppsFlyer.logEvent = nop
            _G.AppsFlyer.trackEvent = nop
            _G.AppsFlyer.setEnabled = retFalse
            _G.AppsFlyer.sendEvent = nop
        end
    end)
    print("[BYPASS] Replay & Telemetry bypassed!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.31: FinalProtection
-- ------------------------------------------------------------
local function FinalProtection()
    PCall(function()
        for _, flag in ipairs({
            "ENABLE_REPORT", "ENABLE_ANTI_CHEAT", "ENABLE_SECURITY", 
            "ENABLE_TELEMETRY", "ENABLE_ANALYTICS", "ENABLE_CRASH_REPORT", 
            "ENABLE_PERFORMANCE_REPORT", "ENABLE_MONITOR", "ENABLE_TRACK",
            "ENABLE_DETECT", "ENABLE_VERIFY", "ENABLE_CHECK", "ENABLE_SCAN",
            "ENABLE_AC", "ENABLE_BEACON", "ENABLE_SDK", "ENABLE_TSS",
            "ENABLE_SWIFT_HAWK", "ENABLE_GOKUBA", "ENABLE_HIGGS",
            "ENABLE_CORONA", "ENABLE_HAWKEYE", "ENABLE_BAN",
            "ENABLE_VALIDATE", "ENABLE_AUTHENTICATE", "ENABLE_SIGNATURE"
        }) do
            if _G[flag] then _G[flag] = false end
        end
        
        local origReq = require
        local blocked = {
            "HiggsBosonComponent", "PlayerSecurityInfoSubsystem", "CoronaLabSubsystem",
            "ClientCircleFlowSubsystem", "ModifierExceptionSubsystem", "ShootVerifySubSystemClient",
            "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem", "Gokuba",
            "SwiftHawkSubsystem", "ClientBanLogic", "RealTimeBan", "RacingAntiCheatLogic",
            "SecurityMonitorSubsystem", "CheatDetectionSubsystem", "ViolationMonitorSubsystem",
            "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
            "TssSdk", "TssManager", "AntiCheatManager", "ACManager",
            "DeviceFingerprintSubsystem", "DNSMonitorSubsystem", "FileCheckSubsystem",
            "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem",
            "AvatarExceptionSubsystem", "GameReportSubsystem", "BehaviorScoreSubsystem",
            "AFKReportorSubsystem", "ClientDataStatistcsSubsystem", "ReplayMonitorSubsystem",
            "TelemetrySubsystem", "AnalyticsSubsystem", "CrashReportSubsystem"
        }
        _G.require = function(m)
            for _, b in ipairs(blocked) do
                if m:find(b) then return {} end
            end
            return origReq(m)
        end
        
        if _G.BypassPermissions then
            for k, v in pairs(_G.BypassPermissions) do
                _G.BypassPermissions[k] = true
            end
        end
        
        if _G.AntiCheatBlock then
            for k, v in pairs(_G.AntiCheatBlock) do
                _G.AntiCheatBlock[k] = true
            end
        end
    end)
    print("[BYPASS] Final Protection activated!")
end

-- PURPOSE: Security/bypass-related modules ko safely initialize aur control karta hai.
-- FEATURE 05.32: InitializeAllBypass
-- ------------------------------------------------------------
local function InitializeAllBypass()
    PCall(function()
        print("[ULTIMATE BYPASS] Starting initialization...")
        ClientEntryBypass()
        HiggsBosonBypass()
        HawkEyeBypass()
        BanLogicBypass()
        ReportSystemBypass()
        TLogBypass()
        MD5Bypass()
        DNSDeviceBypass()
        GokubaBypass()
        RacingAntiCheatBypass()
        CoronaLabBypass()
        LoginModuleBypass()
        SwiftHawkBypass()
        ShootVerificationBypass()
        ModifierExceptionBypass()
        SimulateCharacterBypass()
        PlayerSecurityBypass()
        ClientFlowBypass()
        GameplayCallbackBypass()
        KillAllSubsystems()
        SLUABypass()
        ReplayTelemetryBypass()
        FinalProtection()
        print("[ULTIMATE BYPASS] Complete - All Security Systems Disabled")
    end)
end

-- ========================================== 
-- ============================================================
-- FEATURE 06: MAP-MARK CLEANUP AND ENEMY IDENTITY HELPERS
-- ============================================================
-- HÀM QUẢN LÝ DỌN RÁC MAP MARK (CHỐNG LAG/HIỂN THỊ ẢO KHI ĐỊCH CHẾT)
-- ========================================== 
-- PURPOSE: Map marks cleanup aur enemies ke liye stable unique identity maintain karta hai.
-- FEATURE 06.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Enemy/actor information ko detect, mark ya display karta hai.
-- FEATURE 06.02: SafeAddMark
-- ------------------------------------------------------------
local function SafeAddMark(id, pos, z, str, size, actor)
    local mark = nil
    PCall(function()
        local InGameMarkTools = SafeRequire("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.ClientAddMapMark then
            mark = InGameMarkTools.ClientAddMapMark(id, pos, z, str, size, actor)
            if mark then _G.LexusState.TrackedMarks[mark] = true end
        end
    end)
    return mark
end

-- PURPOSE: Enemy/actor information ko detect, mark ya display karta hai.
-- FEATURE 06.03: SafeRemoveMark
-- ------------------------------------------------------------
local function SafeRemoveMark(mark)
    if not mark then return end
    PCall(function()
        local InGameMarkTools = SafeRequire("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.HideMapMark then
            InGameMarkTools.HideMapMark(mark)
        end
        if InGameMarkTools and InGameMarkTools.RemoveMapMark then
            InGameMarkTools.RemoveMapMark(mark)
        end
    end)
    _G.LexusState.TrackedMarks[mark] = nil
end

-- ========================================== 
-- TẠO ID DUY NHẤT VÀ VĨNH VIỄN CHO MỖI KẺ ĐỊCH (SỬA LỖI GIẬT LAG KHI SLUA TẠO WRAPPER MỚI)
-- ==========================================
-- PURPOSE: Enemy/actor information ko detect, mark ya display karta hai.
-- FEATURE 06.04: GetSafeEnemyKey
-- ------------------------------------------------------------
local function GetSafeEnemyKey(enemy)
    if Valid(enemy) then
        if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
        if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
    end
    return tostring(enemy)
end

-- ========================================== 
-- ============================================================
-- FEATURE 07: AI/PLAYER DETECTION
-- ============================================================
-- KIỂM TRA PHÂN BIỆT AI (BOT) / REAL PLAYER - OPTIMIZED
-- ==========================================
-- PURPOSE: AI/bot aur real player ko identify karne mein help karta hai.
-- FEATURE 07.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: AI/bot aur real player ko identify karne mein help karta hai.
-- FEATURE 07.02: CheckIsAI
-- ------------------------------------------------------------
local function CheckIsAI(pawn, markData)
    if markData and markData.AK_IS_BOT ~= nil and markData.AK_BOT_CHECKED_ACTOR == pawn then 
        return markData.AK_IS_BOT, true 
    end

    if not SafeIsValid(pawn) then return false, false end
    
    local isAI = false
    PCall(function()
        if pawn.IsAIPawn and type(pawn.IsAIPawn) == "function" then
            isAI = pawn:IsAIPawn()
        elseif Game and Game.IsAI and type(Game.IsAI) == "function" then
            isAI = Game:IsAI(pawn)
        elseif pawn.bIsAI == true or pawn.IsAI == true or pawn.bIsABot == true or pawn.bIsBot == true then
            isAI = true
        elseif type(pawn.IsBot) == "function" and pawn:IsBot() then
            isAI = true
        else
            local pState = pawn.PlayerState or (type(pawn.GetPlayerState) == "function" and pawn:GetPlayerState())
            if SafeIsValid(pState) then
                if pState.bIsABot == true or pState.bIsBot == true or pState.bIsAI == true then
                    isAI = true
                elseif type(pState.IsBot) == "function" and pState:IsBot() then
                    isAI = true
                end
            end
        end

        if not isAI and pawn.GetController then
            local controller = pawn:GetController()
            if SafeIsValid(controller) then
                local cName = tostring(controller:GetName() or "")
                if cName:find("AI") or cName:find("Bot") then
                    isAI = true
                end
            end
        end
    end)
    
    if markData then
        markData.AK_IS_BOT = isAI
        markData.AK_BOT_CHECKED_ACTOR = pawn
    end
    return isAI, true
end

-- ==============================================================================
-- ============================================================
-- FEATURE 10: POPUP/COUNT AND LEFT-PANEL UI LOGIC
-- ============================================================
-- LOGIC 1: CHỈ MỞ KHÓA BỘ ĐẾM POP-UP MÀN HÌNH VÀ ÉP ẨN CHỮ "COUNT" Ở Ô SÚNG
-- =========================================================================
-- PURPOSE: Popup, count text aur left-side UI behavior customize karta hai.
-- FEATURE 10.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Popup, count text aur left-side UI behavior customize karta hai.
-- FEATURE 10.02: ForceEnableKillCounterUI
-- ------------------------------------------------------------
_G.ForceEnableKillCounterUI = function()
    if not HasPanelAuthorization() then return end
    PCall(function()
        local KillCounterUISubsystem = package.loaded["GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem"] or SafeRequire("GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem")
        if KillCounterUISubsystem and KillCounterUISubsystem.__inner_impl and not _G.KCUISystemHacked2 then
            local kcImpl = KillCounterUISubsystem.__inner_impl
            kcImpl.CheckSupportKCUI = function() return true end
            kcImpl.CheckNeedMainKillCounterUI = function(self, PlayerWeapon, PlayerID)
                if SafeIsValid(PlayerWeapon) then
                    local WeaponID = PlayerWeapon:GetWeaponID()
                    self:UpdateMainKillCounterUI(true, WeaponID, WeaponID)
                else self:UpdateMainKillCounterUI(false) end
            end
            _G.KCUISystemHacked2 = true
        end

        local ModuleManager = SafeRequire("client.module_framework.ModuleManager")
        if ModuleManager and not _G.KCLogicHacked2 then
            local LogicKillCounter = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.LogicKillCounter)
            if LogicKillCounter then
                LogicKillCounter.CheckSupportKC = function() return true end
                LogicKillCounter.CheckSupportKillCounterAvatar = function() return true end
                LogicKillCounter.CheckHasWeaponKillCounter = function() return true end
                LogicKillCounter.GetBaseKillCounterIdByWeaponId = function() return 2100004 end
                LogicKillCounter.GetEquipedKillCounterId = function() return 2100004 end
                LogicKillCounter.GetMyEquipedKillCounterId = function() return 2100004 end
                LogicKillCounter.GetOneWeaponKillCountInBattle = function(self, uid, weaponId) return _G.TDFTDeKillCounts[weaponId] or 0 end
                LogicKillCounter.GetWeaponKillCountByUid = function(self, uid, weaponId) return _G.TDFTDeKillCounts[weaponId] or 0 end
                _G.KCLogicHacked2 = true
            end
        end

        -- [FIX CHỮ COUNT]: Ép ẩn hoàn toàn Icon và Chữ đếm trên mọi giao diện ô súng
        local ESlateVisibility = SafeImport("ESlateVisibility")
        local SwitchModes = {
            "GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode1",
            "GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode2",
            "GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode3",
            "GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotBase"
        }
        for _, modePath in ipairs(SwitchModes) do
            local s, mode = PCall(require, modePath)
            if s and mode and mode.__inner_impl and not mode.__inner_impl._KCIconHidden then
                mode.__inner_impl.CheckShowKCIcon = function(self)
                    if SafeIsValid(self.KillCounterImg) then 
                        self.KillCounterImg:SetVisibility(ESlateVisibility.Collapsed) 
                    end
                    if SafeIsValid(self.KillCounterText) then 
                        self.KillCounterText:SetVisibility(ESlateVisibility.Collapsed) 
                    end
                end
                mode.__inner_impl._KCIconHidden = true
            end
        end
    end)
end

-- =========================================================================
-- LOGIC 2: GÓC TRÁI CỦA BẠN & TÍCH HỢP TOÁN TỬ GỌI BẢNG ĐIỆN TỬ
-- =========================================================================
-- PURPOSE: Popup, count text aur left-side UI behavior customize karta hai.
-- FEATURE 10.03: ForceEnableKillMessage
-- ------------------------------------------------------------
_G.ForceEnableKillMessage = function()
    if not HasPanelAuthorization() then return end
    PCall(function()
        local killInfoPath = "GameLua.Mod.BaseMod.Client.KillInfoTips.KillInfo"
        local KillInfo = package.loaded[killInfoPath] or SafeRequire(killInfoPath)
        
        if KillInfo and KillInfo.__inner_impl and not _G.KillMessageHacked then
            local originalFileItem = KillInfo.__inner_impl.FileItem
            KillInfo.__inner_impl.FileItem = function(self, DamageRecordData)
                PCall(function()
                    local LocalPlayer = SafeRequire("GameLua.GameCore.Data.GameplayData").GetPlayerCharacter()
                    if SafeIsValid(LocalPlayer) and DamageRecordData.Causer == LocalPlayer:GetPlayerNameSafety() then 
                        local currentWeapon = LocalPlayer:GetCurrentWeapon()
                        if SafeIsValid(currentWeapon) then
                            local weaponID = currentWeapon:GetWeaponID()

                           -- [LOGIC BỘ ĐẾM]: Cập nhật và gọi Pop-up Bảng điện tử chớp trên màn hình
                            if DamageRecordData.ResultHealthStatus == 2 then 
                                _G.TDFTDeKillCounts[weaponID] = (_G.TDFTDeKillCounts[weaponID] or 0) + 1
                                
                                -- [FIX LỖI SKIN HÒM XÁC]: Kích hoạt biến đếm thời gian quét hòm xác khi địch chết
                                _G.NeedCheckDeadBoxTimer = 15
                                
                                if not CACHED_UI_Manager then CACHED_UI_Manager = SafeRequire("client.slua_ui_framework.manager") end
                                local uiMainKillCounter = CACHED_UI_Manager.GetUI(CACHED_UI_Manager.UI_Config_InGame.MainKillCounter)
                                
                                if uiMainKillCounter and uiMainKillCounter.UpdateWeaponID then
                                    local counterAvatarID = weaponID
                                    uiMainKillCounter:UpdateWeaponID(weaponID, counterAvatarID)
                                    
                                    local ModuleManager = SafeRequire("client.module_framework.ModuleManager")
                                    if ModuleManager then
                                        local kcModule = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.LogicKillCounter)
                                        if kcModule then
                                            local kcItemID = kcModule:GetEquipedKillCounterId(0, counterAvatarID)
                                            uiMainKillCounter:SetKillCounterItemShowWithNum(kcItemID, _G.TDFTDeKillCounts[weaponID], counterAvatarID)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end)
                
                if originalFileItem then return originalFileItem(self, DamageRecordData) end
            end
            _G.KillMessageHacked = true
        end
    end)
end

-- FEATURE 11: SETTINGS SAVE/LOAD AND AUTOSAVE LOOP
-- ============================================================
-- HỆ THỐNG LƯU VÀ TẢI SETTING MENU VIP (TỰ ĐỘNG)
-- ========================================== 
-- PURPOSE: Settings save/load aur background autosave process handle karta hai.
-- FEATURE 11.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- HÀM LƯU CONFIG (RAM ONLY)
-- FEATURE 11.03: SaveModSettings
-- ------------------------------------------------------------
_G.SaveModSettings = function()
    if not HasPanelAuthorization() then return false end
    _G.LexusConfig = _G.LexusConfig or {}
    _G.LexusState = _G.LexusState or {}
    _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {}
    -- Settings already live in _G.LexusConfig and _G.LexusState.CustomTextData.
    -- No file is created, read, or written.
    return true
end

-- HÀM TẢI CONFIG (RAM ONLY)
-- FEATURE 11.04: LoadModSettings
-- ------------------------------------------------------------
_G.LoadModSettings = function()
    if not HasPanelAuthorization() then return false end
    _G.LexusConfig = _G.LexusConfig or {}
    _G.LexusState = _G.LexusState or {}
    _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {}
    _G.ModConfigLoaded = true
    return true
end

-- AutoSaveLoop removed: RAM state needs no periodic disk save.
_G.ModConfigAutoSaveStarted = true

-- DƯ THỪA ĐỂ KHÔNG BỊ LỖI VÒNG LẶP CŨ CỦA BẠN
-- PURPOSE: Menu/settings configuration ko create, load ya update karta hai.
-- FEATURE 11.06: ReadLiveConfig
-- ------------------------------------------------------------
_G.ReadLiveConfig = function()
    if not HasPanelAuthorization() then return false end
    return _G.LexusConfig, _G.LexusState and _G.LexusState.CustomTextData
end

-- ========================================== 
-- ============================================================
-- FEATURE 12: NATIVE VIP MENU
-- ============================================================
-- HỆ THỐNG MENU VIP NATIVE (CHẠY TRỰC TIẾP TỪ SETTING GAME)
-- ========================================== 

-- PURPOSE: Native VIP menu controls, menu entries aur callbacks define karta hai.
-- FEATURE 12.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Menu/settings configuration ko create, load ya update karta hai.
-- FEATURE 12.02: _G.InitModMenuTab
-- ------------------------------------------------------------
function _G.InitModMenuTab()
    if not HasPanelAuthorization() then
        _G.MenuInitialized = false
        return false
    end
    -- Load settings before menu controls read their values. Without this
    -- authorized one-time load, the initialized defaults were shown again
    -- even though SaveModSettings had already written a config file.
    if not _G.ModSettingsLoaded then
        if _G.LoadModSettings then _G.LoadModSettings() end
        _G.ModSettingsLoaded = true
    end
    if _G.ModMenuInitialized then return end
    _G.ModMenuInitialized = true

    _G.LexusState.CustomTextData = _G.LexusState.CustomTextData or {
        OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0, HRecoil = 0.3, VRecoil = 0.3, MagicHead = 1.0, MagicBody = 1.0, MagicLegs = 1.0, IpadViewFOV = 120,
        AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
        AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
        AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchScopePred = 0, AimTouchScopeRecoil = 0,
        AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400, AimTouchSniperPred = 0,
        BugManRatio = 133,
        WeaponGlowThickness = 3, WeaponGlowColor = 5,
        ColorV3Hidden = 1, ColorV3Visible = 2, ColorV3Thickness = 4, OutlineColor = 4
    }

    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = SafeRequire("client.common.LocUtil")
    end
    
    -- 1. CREATE VIRTUAL ID TABLE WITH NEW TEXT
    local FakeTextMap = {
        [999000] = "MOD MENU NEXA",
        [999001] = "ESP TELE @NEXALORD",
        [999002] = "AIMBOT & MAGIC BULLET TELE @NEXALORD",
        [999003] = "ROYAL AIMBOT - CUSTOM (Close Range - Scope)",
        [999004] = "SUPPORT & GRAPHICS TELE @NEXALORD",
        [999005] = "KILL COUNTER TELE @NEXALORD",
        [999010] = "AD ESP TELE @NEXALORD",
    }

    -- 2. HOOK ALL GAME TEXT READING FUNCTIONS (FIXES EMPTY TAB ISSUE)
    if LocUtil and not LocUtil._IsModMenuHooked_V2 then
        local hookFuncs = {"GetLocalizeResStr", "GetText", "GetTextByID", "GetLocalText", "GetLocalizeStr"}
        for _, funcName in ipairs(hookFuncs) do
            if LocUtil[funcName] then
                local old_func = LocUtil[funcName]
                LocUtil[funcName] = function(id)
                    if FakeTextMap[id] then
                        return FakeTextMap[id]
                    end
                    if type(id) == "string" and not tonumber(id) then
                        return id
                    end
                    if old_func then
                        return old_func(id)
                    end
                    return ""
                end
            end
        end
        LocUtil._IsModMenuHooked_V2 = true
    end

    -- Ensure AD ESP state is clean but respect the loaded toggle
    if _G.LexusConfig and _G.LexusConfig.ADESP_Enable then
        _G.ADESP_Running = false -- Force re-init in MainLoop
    end

    local SettingPageDefine = nil
    PCall(function() SettingPageDefine = SafeRequire("client.logic.NewSetting.SettingPageDefine") end)
    local SettingCatalog = nil
    PCall(function() SettingCatalog = SafeRequire("client.logic.NewSetting.SettingCatalog") end)
    
    if SettingPageDefine and not SettingPageDefine.ModMenu then
        local AliasMap = SafeRequire("client.slua.umg.NewSetting.Item.AliasMap")
        
        local StackADESP = {
            { Key = "ModMenu_ADESP_Master", UI = AliasMap.TitleSwitcher, Text = "▶ Enable AD ESP (Advanced Stable Tags)", ExpandIndex = 0, GetFunc = function() return _G.NexaLoginPanel.IsAuthorized() and _G.LexusConfig.ADESP_Enable == true end, SetFunc = function(c,v) if not _G.NexaLoginPanel.IsAuthorized() then return false end _G.LexusConfig.ADESP_Enable = v; if not v and _G.ClearAllADESPWidgets then _G.ClearAllADESPWidgets() end if _G.SaveModSettings then _G.SaveModSettings() end return true end },
            { Key = "ModMenu_ADESP_Tags", UI = AliasMap.Switcher, Text = "   Show Stable Tags & HP Bar", ExpandHandle = "ModMenu_ADESP_Master", GetFunc = function() return _G.NexaLoginPanel.IsAuthorized() and _G.LexusConfig.ADESP_ShowTags == true end, SetFunc = function(c,v) if not _G.NexaLoginPanel.IsAuthorized() then return false end _G.LexusConfig.ADESP_ShowTags = v; if not v and _G.ClearAllADESPWidgets then _G.ClearAllADESPWidgets() end if _G.SaveModSettings then _G.SaveModSettings() end return true end },
            { Key = "ModMenu_ADESP_SnapLines", UI = AliasMap.Switcher, Text = "   Show SnapLines", ExpandHandle = "ModMenu_ADESP_Master", GetFunc = function() return _G.NexaLoginPanel.IsAuthorized() and _G.LexusConfig.ADESP_ShowSnapLines == true end, SetFunc = function(c,v) if not _G.NexaLoginPanel.IsAuthorized() then return false end _G.LexusConfig.ADESP_ShowSnapLines = v; PlayerMapMarker.bUseSnapLines = v == true; if not v and PlayerMapMarker.ClearAllSnapLines then PlayerMapMarker.ClearAllSnapLines() end if _G.SaveModSettings then _G.SaveModSettings() end return true end },
            { Key = "ModMenu_ADESP_Counter", UI = AliasMap.Switcher, Text = "   Show Top Enemy Counter", ExpandHandle = "ModMenu_ADESP_Master", GetFunc = function() return _G.NexaLoginPanel.IsAuthorized() and _G.LexusConfig.ADESP_ShowCounter == true end, SetFunc = function(c,v) if not _G.NexaLoginPanel.IsAuthorized() then return false end _G.LexusConfig.ADESP_ShowCounter = v; _G.ADESP_LastCounterText = ""; if not v and _G.RemoveCounterVisualLayers then _G.RemoveCounterVisualLayers() end if _G.SaveModSettings then _G.SaveModSettings() end return true end },
            { Key = "ModMenu_ADESP_Weapon", UI = AliasMap.Switcher, Text = "   Show Enemy Weapon Icon", ExpandHandle = "ModMenu_ADESP_Master", GetFunc = function() return _G.NexaLoginPanel.IsAuthorized() and _G.LexusConfig.ADESP_ShowWeapon == true end, SetFunc = function(c,v) if not _G.NexaLoginPanel.IsAuthorized() then return false end _G.LexusConfig.ADESP_ShowWeapon = v; if _G.SaveModSettings then _G.SaveModSettings() end return true end },

        }
        local StackESP = {
            { Key = "ModMenu_ESP2", UI = AliasMap.Switcher, Text = "ESP Type 2 (Distance in meters) tele @NEXALORD", GetFunc = function() return _G.LexusConfig.EspDistance end, SetFunc = function(c,v) _G.LexusConfig.EspDistance = v return true end },
            { Key = "ModMenu_ESP5", UI = AliasMap.Switcher, Text = "ESP Type 5 (Box) tele NEXALORD", GetFunc = function() return _G.LexusConfig.EspLoai5 end, SetFunc = function(c,v) _G.LexusConfig.EspLoai5 = v return true end },
            { Key = "ModMenu_ESP7_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ESP Type 7 (Detailed Info) tele NEXALORD", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.EspLoai7 end, SetFunc = function(c,v) _G.LexusConfig.EspLoai7 = v return true end },
            { Key = "ModMenu_ESP7_SoLuong", UI = AliasMap.Switcher, Text = "   Show Enemy Count", ExpandHandle = "ModMenu_ESP7_Ex", GetFunc = function() return _G.LexusConfig.Esp7_SoLuong end, SetFunc = function(c,v) _G.LexusConfig.Esp7_SoLuong = v return true end },
            { Key = "ModMenu_ESP7_VuKhi", UI = AliasMap.Switcher, Text = "   Show Enemy Weapon", ExpandHandle = "ModMenu_ESP7_Ex", GetFunc = function() return _G.LexusConfig.Esp7_VuKhi end, SetFunc = function(c,v) _G.LexusConfig.Esp7_VuKhi = v return true end },
            { Key = "ModMenu_ESP8", UI = AliasMap.Switcher, Text = "ESP Type 8 (Head HP Bar) tele NEXALORD", GetFunc = function() return _G.LexusConfig.EspLoai8 end, SetFunc = function(c,v) _G.LexusConfig.EspLoai8 = v return true end },
            { Key = "ModMenu_ESPBom_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Grenade Warnings & Location tele NEXA", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.EspBomMaster end, SetFunc = function(c,v) _G.LexusConfig.EspBomMaster = v return true end },
            { Key = "ModMenu_ESPItemBom", UI = AliasMap.Switcher, Text = "   Locate Grenades on the Ground", ExpandHandle = "ModMenu_ESPBom_Ex", GetFunc = function() return _G.LexusConfig.EspItemBom end, SetFunc = function(c,v) _G.LexusConfig.EspItemBom = v return true end },
            { Key = "ModMenu_ESPActiveBom", UI = AliasMap.Switcher, Text = "   Warn when Enemy Holds or Throws", ExpandHandle = "ModMenu_ESPBom_Ex", GetFunc = function() return _G.LexusConfig.EspActiveBom end, SetFunc = function(c,v) _G.LexusConfig.EspActiveBom = v return true end },
            
            { Key = "ModMenu_ESPVehicle_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Vehicle ESP (Detailed) tele NEXA", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.EspVehicle end, SetFunc = function(c,v) _G.LexusConfig.EspVehicle = v return true end },
            { Key = "ModMenu_ESPVeh_Dacia", UI = AliasMap.Switcher, Text = "   Show Dacia", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.LexusConfig.EspVeh_Dacia end, SetFunc = function(c,v) _G.LexusConfig.EspVeh_Dacia = v return true end },
            { Key = "ModMenu_ESPVeh_UAZ", UI = AliasMap.Switcher, Text = "   Show UAZ (Jeep)", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.LexusConfig.EspVeh_UAZ end, SetFunc = function(c,v) _G.LexusConfig.EspVeh_UAZ = v return true end },
            { Key = "ModMenu_ESPVeh_Buggy", UI = AliasMap.Switcher, Text = "   Show Buggy", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.LexusConfig.EspVeh_Buggy end, SetFunc = function(c,v) _G.LexusConfig.EspVeh_Buggy = v return true end },
            { Key = "ModMenu_ESPVeh_Coupe", UI = AliasMap.Switcher, Text = "   Show Coupe RB", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.LexusConfig.EspVeh_Coupe end, SetFunc = function(c,v) _G.LexusConfig.EspVeh_Coupe = v return true end },
            { Key = "ModMenu_ESPVeh_Mirado", UI = AliasMap.Switcher, Text = "   Show Mirado", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.LexusConfig.EspVeh_Mirado end, SetFunc = function(c,v) _G.LexusConfig.EspVeh_Mirado = v return true end },
            { Key = "ModMenu_ESPVeh_Motor", UI = AliasMap.Switcher, Text = "   Show Motor/Scooter", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.LexusConfig.EspVeh_Motor end, SetFunc = function(c,v) _G.LexusConfig.EspVeh_Motor = v return true end },
            { Key = "ModMenu_ESPVeh_Other", UI = AliasMap.Switcher, Text = "   Show Other (Boat/BRDM...)", ExpandHandle = "ModMenu_ESPVehicle_Ex", GetFunc = function() return _G.LexusConfig.EspVeh_Other end, SetFunc = function(c,v) _G.LexusConfig.EspVeh_Other = v return true end },
            
            { Key = "ModMenu_ESPAntenna", UI = AliasMap.Switcher, Text = "ESP Antenna tele NEXALORD", GetFunc = function() return _G.LexusConfig.EspAntenna end, SetFunc = function(c,v) _G.LexusConfig.EspAntenna = v return true end }
        }

        local StackAimbot = {
            { Key = "ModMenu_Aimbot_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Custom Long-Range Aimbot", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.CustomAimbot end, SetFunc = function(c,v) _G.LexusConfig.CustomAimbot = v return true end },
            { Key = "ModMenu_Aimbot_Speed", UI = AliasMap.Slider, Text = "   Long-Range Aimbot Speed", ExpandHandle = "ModMenu_Aimbot_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.OuterSpeed end, SetFunc = function(c,v) _G.LexusState.CustomTextData.OuterSpeed = v return true end },
            { Key = "ModMenu_Aimbot_Recoil", UI = AliasMap.Slider, Text = "   Compensate Recoil (New)", ExpandHandle = "ModMenu_Aimbot_Ex", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.LexusState.CustomTextData.OuterRecoil or 0 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.OuterRecoil = v return true end },

            { Key = "ModMenu_AimbotClose_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Custom Close-Range Aimbot", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.CustomAimbotClose end, SetFunc = function(c,v) _G.LexusConfig.CustomAimbotClose = v return true end },
            { Key = "ModMenu_AimbotClose_Speed", UI = AliasMap.Slider, Text = "   Close-Range Aimbot Speed", ExpandHandle = "ModMenu_AimbotClose_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.InnerSpeed end, SetFunc = function(c,v) _G.LexusState.CustomTextData.InnerSpeed = v return true end },
            { Key = "ModMenu_LessShake", UI = AliasMap.Switcher, Text = "Reduce Scope Shake (if toggled off, drop and pick up gun)", GetFunc = function() return _G.LexusConfig.LessShake end, SetFunc = function(c,v) _G.LexusConfig.LessShake = v return true end },
            { Key = "ModMenu_Crosshair", UI = AliasMap.Switcher, Text = "Small Crosshair (if toggled off, drop and pick up gun)", GetFunc = function() return _G.LexusConfig.Crosshair end, SetFunc = function(c,v) _G.LexusConfig.Crosshair = v return true end },
            { Key = "ModMenu_GodMode", UI = AliasMap.Switcher, Text = "Rapid Fire (Extremely Fast) (if toggled off, drop and pick up gun)", GetFunc = function() return _G.LexusConfig.GodMode end, SetFunc = function(c,v) _G.LexusConfig.GodMode = v return true end },
            { Key = "ModMenu_MortarAim", UI = AliasMap.Switcher, Text = "Mortar Auto Aim (Standalone)", GetFunc = function() return _G.LexusConfig.MortarAim end, SetFunc = function(c,v) _G.LexusConfig.MortarAim = v return true end }
        }

        local StackAimbotV2 = {
            { Key = "ModMenu_AT_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Enable Royal Aimbot & Custom", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.AimTouchEnable end, SetFunc = function(c,v) _G.LexusConfig.AimTouchEnable = v return true end },
            
            -- HIPFIRE
            { Key = "ModMenu_AT_Hip_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Hipfire Aimbot (White Crosshair)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.AimTouchHipfire end, SetFunc = function(c,v) _G.LexusConfig.AimTouchHipfire = v return true end },
            { Key = "ModMenu_AT_Hip_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked Enemies", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.LexusConfig.AimTouchHipIgKnock end, SetFunc = function(c,v) _G.LexusConfig.AimTouchHipIgKnock = v return true end },
            { Key = "ModMenu_AT_Hip_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.LexusConfig.AimTouchHipIgBot end, SetFunc = function(c,v) _G.LexusConfig.AimTouchHipIgBot = v return true end },
            { Key = "ModMenu_AT_Hip_Vis", UI = AliasMap.Switcher, Text = "      Check Visibility (VisCheck)", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.LexusConfig.AimTouchHipVisCheck end, SetFunc = function(c,v) _G.LexusConfig.AimTouchHipVisCheck = v return true end },
            { Key = "ModMenu_AT_Hip_Prio", UI = AliasMap.Slider, Text = "      Priority (1:Crosshair 2:Distance 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchHipPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.LexusState.CustomTextData.AimTouchHipPrio = val return true end },
            { Key = "ModMenu_AT_Hip_Bone", UI = AliasMap.Slider, Text = "      Target Bone (1:Head 2:Chest 3:Stomach 4:Waist)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchHipBone or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.LexusState.CustomTextData.AimTouchHipBone = val return true end },
            { Key = "ModMenu_AT_Hip_Cond", UI = AliasMap.Slider, Text = "      Condition (1:Aim on Fire 2:Always Aim)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchHipCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.LexusState.CustomTextData.AimTouchHipCond = val return true end },
            { Key = "ModMenu_AT_Hip_Spd", UI = AliasMap.Slider, Text = "      Smoothness / Speed (1-100)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchHipSpeed or 50 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchHipSpeed = v return true end },
            { Key = "ModMenu_AT_Hip_FOV", UI = AliasMap.Slider, Text = "      FOV Radius (1-100)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchHipFOV or 30 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchHipFOV = v return true end },
            { Key = "ModMenu_AT_Hip_Dist", UI = AliasMap.Slider, Text = "      Max Distance (1-500m)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.LexusState.CustomTextData.AimTouchHipDist or 250) / 5) end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchHipDist = v * 5 return true end },

            -- AIMBOT SHOTGUN
            { Key = "ModMenu_AT_SG_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Shotgun Aimbot (Works with Shotgun only)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.AimTouchSG end, SetFunc = function(c,v) _G.LexusConfig.AimTouchSG = v return true end },
            { Key = "ModMenu_AT_SG_AutoFire", UI = AliasMap.Switcher, Text = "      Auto Fire (tap fire to register damage, auto-fire avoids damage bugs)", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.LexusConfig.AimTouchSGAutoFire end, SetFunc = function(c,v) _G.LexusConfig.AimTouchSGAutoFire = v return true end },
            { Key = "ModMenu_AT_SG_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked Enemies", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.LexusConfig.AimTouchSGIgKnock end, SetFunc = function(c,v) _G.LexusConfig.AimTouchSGIgKnock = v return true end },
            { Key = "ModMenu_AT_SG_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.LexusConfig.AimTouchSGIgBot end, SetFunc = function(c,v) _G.LexusConfig.AimTouchSGIgBot = v return true end },
            { Key = "ModMenu_AT_SG_Vis", UI = AliasMap.Switcher, Text = "      Check Visibility (VisCheck)", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.LexusConfig.AimTouchSGVisCheck end, SetFunc = function(c,v) _G.LexusConfig.AimTouchSGVisCheck = v return true end },
            { Key = "ModMenu_AT_SG_Prio", UI = AliasMap.Slider, Text = "      Priority (1:Crosshair 2:Distance 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSGPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.LexusState.CustomTextData.AimTouchSGPrio = val return true end },
            { Key = "ModMenu_AT_SG_Bone", UI = AliasMap.Slider, Text = "      Target Bone (1:Head 2:Chest 3:Stomach 4:Waist)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSGBone or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.LexusState.CustomTextData.AimTouchSGBone = val return true end },
            { Key = "ModMenu_AT_SG_Cond", UI = AliasMap.Slider, Text = "      Condition (1:Aim on Fire 2:Always Aim)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSGCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.LexusState.CustomTextData.AimTouchSGCond = val return true end },
            { Key = "ModMenu_AT_SG_Spd", UI = AliasMap.Slider, Text = "      Smoothness / Speed (1-100)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSGSpeed or 80 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchSGSpeed = v return true end },
            { Key = "ModMenu_AT_SG_FOV", UI = AliasMap.Slider, Text = "      FOV Radius (1-100)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSGFOV or 40 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchSGFOV = v return true end },
            { Key = "ModMenu_AT_SG_Dist", UI = AliasMap.Slider, Text = "      Max Distance (1-100m)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSGDist or 30 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchSGDist = v return true end },
            
            -- SCOPE ALL (REGULAR GUNS WHEN SCOPED)
            { Key = "ModMenu_AT_ScopeAll_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Scoped Aimbot (Easy to mis-aim, toggle off and on scope to fix)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.AimTouchScopeAll end, SetFunc = function(c,v) _G.LexusConfig.AimTouchScopeAll = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked Enemies", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.LexusConfig.AimTouchScopeIgKnock end, SetFunc = function(c,v) _G.LexusConfig.AimTouchScopeIgKnock = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.LexusConfig.AimTouchScopeIgBot end, SetFunc = function(c,v) _G.LexusConfig.AimTouchScopeIgBot = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Vis", UI = AliasMap.Switcher, Text = "      Check Visibility (VisCheck)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.LexusConfig.AimTouchScopeVisCheck end, SetFunc = function(c,v) _G.LexusConfig.AimTouchScopeVisCheck = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Prio", UI = AliasMap.Slider, Text = "      Priority (1:Crosshair 2:Distance 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchScopePrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.LexusState.CustomTextData.AimTouchScopePrio = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Bone", UI = AliasMap.Slider, Text = "      Target Bone (1:Head 2:Chest 3:Stomach 4:Waist)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchScopeBone or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.LexusState.CustomTextData.AimTouchScopeBone = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Cond", UI = AliasMap.Slider, Text = "      Condition (1:Aim on Fire 2:Always Aim)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchScopeCond or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.LexusState.CustomTextData.AimTouchScopeCond = val return true end },
            { Key = "ModMenu_AT_ScopeAll_Spd", UI = AliasMap.Slider, Text = "      Smoothness / Speed (1-100)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchScopeSpeed or 40 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchScopeSpeed = v return true end },
            { Key = "ModMenu_AT_ScopeAll_FOV", UI = AliasMap.Slider, Text = "      FOV Radius (1-100)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchScopeFOV or 20 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchScopeFOV = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Dist", UI = AliasMap.Slider, Text = "      Max Distance (1-500m)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.LexusState.CustomTextData.AimTouchScopeDist or 300) / 5) end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchScopeDist = v * 5 return true end },
            { Key = "ModMenu_AT_ScopeAll_Pred", UI = AliasMap.Slider, Text = "      Prediction for Moving Targets", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchScopePred or 0 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchScopePred = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Recoil", UI = AliasMap.Slider, Text = "      Auto Recoil Compensation (set ~3%-4% for best effect)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchScopeRecoil or 0 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchScopeRecoil = v return true end },

            -- SCOPE SNIPER
            { Key = "ModMenu_AT_Sniper_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ Scoped Aimbot (Snipers/DMRs)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.AimTouchScopeSniper end, SetFunc = function(c,v) _G.LexusConfig.AimTouchScopeSniper = v return true end },
            { Key = "ModMenu_AT_Sniper_IgKnock", UI = AliasMap.Switcher, Text = "      Ignore Knocked Enemies", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.LexusConfig.AimTouchSniperIgKnock end, SetFunc = function(c,v) _G.LexusConfig.AimTouchSniperIgKnock = v return true end },
            { Key = "ModMenu_AT_Sniper_IgBot", UI = AliasMap.Switcher, Text = "      Ignore Bots", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.LexusConfig.AimTouchSniperIgBot end, SetFunc = function(c,v) _G.LexusConfig.AimTouchSniperIgBot = v return true end },
            { Key = "ModMenu_AT_Sniper_Vis", UI = AliasMap.Switcher, Text = "      Check Visibility (VisCheck)", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.LexusConfig.AimTouchSniperVisCheck end, SetFunc = function(c,v) _G.LexusConfig.AimTouchSniperVisCheck = v return true end },
            { Key = "ModMenu_AT_Sniper_Prio", UI = AliasMap.Slider, Text = "      Priority (1:Crosshair 2:Distance 3:HP 4:HP%)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSniperPrio or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.LexusState.CustomTextData.AimTouchSniperPrio = val return true end },
            { Key = "ModMenu_AT_Sniper_Bone", UI = AliasMap.Slider, Text = "      Target Bone (1:Head 2:Chest 3:Stomach 4:Waist)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 4, min = 1, max = 4, Min = 1, Max = 4, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSniperBone or 1 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 4 then val = 4 end; _G.LexusState.CustomTextData.AimTouchSniperBone = val return true end },
            { Key = "ModMenu_AT_Sniper_Cond", UI = AliasMap.Slider, Text = "      Condition (1:Aim on Fire 2:Always Aim)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 2, min = 1, max = 2, Min = 1, Max = 2, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSniperCond or 2 end, SetFunc = function(c,v) local val = math.floor(v+0.5); if val < 1 then val = 1 end; if val > 2 then val = 2 end; _G.LexusState.CustomTextData.AimTouchSniperCond = val return true end },
            { Key = "ModMenu_AT_Sniper_Spd", UI = AliasMap.Slider, Text = "      Smoothness / Speed (1-100)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSniperSpeed or 30 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchSniperSpeed = v return true end },
            { Key = "ModMenu_AT_Sniper_FOV", UI = AliasMap.Slider, Text = "      FOV Radius (1-100)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSniperFOV or 20 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchSniperFOV = v return true end },
            { Key = "ModMenu_AT_Sniper_Dist", UI = AliasMap.Slider, Text = "      Max Distance (1-500m)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.LexusState.CustomTextData.AimTouchSniperDist or 400) / 5) end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchSniperDist = v * 5 return true end },
            { Key = "ModMenu_AT_Sniper_Pred", UI = AliasMap.Slider, Text = "      Prediction for Moving Targets", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.LexusState.CustomTextData.AimTouchSniperPred or 0 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.AimTouchSniperPred = v return true end }
        }

        local StackCombat = {
            { Key = "ModMenu_FakeHWID", UI = AliasMap.Switcher, Text = "Fake HWID (Anti-Device ID Ban)", GetFunc = function() return _G.LexusConfig.FakeHWID end, SetFunc = function(c,v) _G.LexusConfig.FakeHWID = v return true end },
            { Key = "ModMenu_Ipad_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ iPad View", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.IpadView end, SetFunc = function(c,v) _G.LexusConfig.IpadView = v return true end },
            { Key = "ModMenu_Ipad_FOV", UI = AliasMap.Slider, Text = "   FOV Slider", ExpandHandle = "ModMenu_Ipad_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return (_G.LexusState.CustomTextData.IpadViewFOV or 120) - 90 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.IpadViewFOV = 90 + v return true end },
            { Key = "ModMenu_TPPView", UI = AliasMap.Switcher, Text = "TPP View (Force Third Person)", GetFunc = function() return _G.NexaLoginPanel.IsAuthorized() and _G.FufuModConfig.TPPView end, SetFunc = function(c,v) if not _G.NexaLoginPanel.IsAuthorized() then return false end ToggleTPPView(v) return true end },



            { Key = "ModMenu_165FPS", UI = AliasMap.Switcher, Text = "Unlock 165 FPS (if toggled off, it will only turn off next match)", GetFunc = function() return _G.LexusConfig.UnlockFPS end, SetFunc = function(c,v) _G.LexusConfig.UnlockFPS = v; if v then _G.LexusState.GraphicsUnlocked = false end return true end },
            
            -- WALL V2 CUSTOM COLOUR MENU
            { Key = "ModMenu_WallXuyenTuong", UI = AliasMap.TitleSwitcher, Text = "▶ Wallhack V2 (Custom Glowing Colors)", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.WallXuyenTuong end, SetFunc = function(c,v) _G.LexusConfig.WallXuyenTuong = v return true end },
            { Key = "ModMenu_V2CustomColor", UI = AliasMap.Switcher, Text = "   Use Custom Colors (Off = Normal)", ExpandHandle = "ModMenu_WallXuyenTuong", GetFunc = function() return _G.LexusConfig.WallV2_CustomColor end, SetFunc = function(c,v) _G.LexusConfig.WallV2_CustomColor = v return true end },
            { Key = "ModMenu_V2Player", UI = AliasMap.Switcher, Text = "   Enable for Players", ExpandHandle = "ModMenu_WallXuyenTuong", GetFunc = function() return _G.LexusConfig.WallV2_Player end, SetFunc = function(c,v) _G.LexusConfig.WallV2_Player = v return true end },
            { Key = "ModMenu_PL_OpenR", UI = AliasMap.Slider, Text = "      Player Open R (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.PlayerOpenR or 1 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerOpenR = v return true end },
            { Key = "ModMenu_PL_OpenG", UI = AliasMap.Slider, Text = "      Player Open G (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.PlayerOpenG or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerOpenG = v return true end },
            { Key = "ModMenu_PL_OpenB", UI = AliasMap.Slider, Text = "      Player Open B (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.PlayerOpenB or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerOpenB = v return true end },
            { Key = "ModMenu_PL_OpenA", UI = AliasMap.Slider, Text = "      Player Open A (Alpha 0-255)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 255, min = 0, max = 255, GetFunc = function() return _G.LexusState.CustomTextData.PlayerOpenA or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerOpenA = v return true end },
            { Key = "ModMenu_PL_OpenL", UI = AliasMap.Slider, Text = "      Player Open L (Flow/Glow 0-50)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.LexusState.CustomTextData.PlayerOpenL or 10 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerOpenL = v return true end },
            { Key = "ModMenu_PL_BehindR", UI = AliasMap.Slider, Text = "      Player Behind R (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.PlayerBehindR or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerBehindR = v return true end },
            { Key = "ModMenu_PL_BehindG", UI = AliasMap.Slider, Text = "      Player Behind G (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.PlayerBehindG or 1 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerBehindG = v return true end },
            { Key = "ModMenu_PL_BehindB", UI = AliasMap.Slider, Text = "      Player Behind B (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.PlayerBehindB or 1 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerBehindB = v return true end },
            { Key = "ModMenu_PL_BehindA", UI = AliasMap.Slider, Text = "      Player Behind A (Alpha 0-255)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 255, min = 0, max = 255, GetFunc = function() return _G.LexusState.CustomTextData.PlayerBehindA or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerBehindA = v return true end },
            { Key = "ModMenu_PL_BehindL", UI = AliasMap.Slider, Text = "      Player Behind L (Flow/Glow 0-50)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.LexusState.CustomTextData.PlayerBehindL or 10 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.PlayerBehindL = v return true end },
            { Key = "ModMenu_V2Bot", UI = AliasMap.Switcher, Text = "   Enable for Bots", ExpandHandle = "ModMenu_WallXuyenTuong", GetFunc = function() return _G.LexusConfig.WallV2_Bot end, SetFunc = function(c,v) _G.LexusConfig.WallV2_Bot = v return true end },
            { Key = "ModMenu_BT_OpenR", UI = AliasMap.Slider, Text = "      Bot Open R (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.BotOpenR or 20 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotOpenR = v return true end },
            { Key = "ModMenu_BT_OpenG", UI = AliasMap.Slider, Text = "      Bot Open G (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.BotOpenG or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotOpenG = v return true end },
            { Key = "ModMenu_BT_OpenB", UI = AliasMap.Slider, Text = "      Bot Open B (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.BotOpenB or 1 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotOpenB = v return true end },
            { Key = "ModMenu_BT_OpenA", UI = AliasMap.Slider, Text = "      Bot Open A (Alpha 0-255)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 255, min = 0, max = 255, GetFunc = function() return _G.LexusState.CustomTextData.BotOpenA or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotOpenA = v return true end },
            { Key = "ModMenu_BT_OpenL", UI = AliasMap.Slider, Text = "      Bot Open L (Flow/Glow 0-50)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.LexusState.CustomTextData.BotOpenL or 10 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotOpenL = v return true end },
            { Key = "ModMenu_BT_BehindR", UI = AliasMap.Slider, Text = "      Bot Behind R (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.BotBehindR or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotBehindR = v return true end },
            { Key = "ModMenu_BT_BehindG", UI = AliasMap.Slider, Text = "      Bot Behind G (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.BotBehindG or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotBehindG = v return true end },
            { Key = "ModMenu_BT_BehindB", UI = AliasMap.Slider, Text = "      Bot Behind B (0-300)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 300, min = 0, max = 300, GetFunc = function() return _G.LexusState.CustomTextData.BotBehindB or 1 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotBehindB = v return true end },
            { Key = "ModMenu_BT_BehindA", UI = AliasMap.Slider, Text = "      Bot Behind A (Alpha 0-255)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 255, min = 0, max = 255, GetFunc = function() return _G.LexusState.CustomTextData.BotBehindA or 255 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotBehindA = v return true end },
            { Key = "ModMenu_BT_BehindL", UI = AliasMap.Slider, Text = "      Bot Behind L (Flow/Glow 0-50)", ExpandHandle = "ModMenu_WallXuyenTuong", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.LexusState.CustomTextData.BotBehindL or 10 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.BotBehindL = v return true end },



            { Key = "ModMenu_BlackSky", UI = AliasMap.Switcher, Text = "Black Sky", GetFunc = function() return _G.LexusConfig.BlackSky end, SetFunc = function(c,v) _G.LexusConfig.BlackSky = v return true end },
            { Key = "ModMenu_RemoveGrass", UI = AliasMap.Switcher, Text = "Remove Grass (if toggled off, it will only turn off next match)", GetFunc = function() return _G.LexusConfig.RemoveGrass end, SetFunc = function(c,v) _G.LexusConfig.RemoveGrass = v return true end },
            { Key = "ModMenu_WallClimb", UI = AliasMap.Switcher, Text = "Wall Climb", GetFunc = function() return _G.LexusConfig.WallClimb end, SetFunc = function(c,v) _G.LexusConfig.WallClimb = v return true end },


            -- [NEW] WEAPON GLOW MENU (EXPANDABLE)
            { Key = "ModMenu_WeaponGlow_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ Weapon Glow (HDR Brightness)", ExpandIndex = 0, GetFunc = function() return _G.LexusConfig.WeaponGlow end, SetFunc = function(c,v) _G.LexusConfig.WeaponGlow = v return true end },
            { Key = "ModMenu_WeaponGlowColor", UI = AliasMap.Slider, Text = "   Weapon Color (1:Red 2:Green 3:Blue 4:Yellow 5:Rainbow)", ExpandHandle = "ModMenu_WeaponGlow_Ex", MinValue = 1, MaxValue = 5, GetFunc = function() return _G.LexusState.CustomTextData.WeaponGlowColor or 5 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.WeaponGlowColor = v return true end },
            { Key = "ModMenu_WeaponGlowThick", UI = AliasMap.Slider, Text = "   Weapon Glow Thickness", ExpandHandle = "ModMenu_WeaponGlow_Ex", MinValue = 1, MaxValue = 15, GetFunc = function() return _G.LexusState.CustomTextData.WeaponGlowThickness or 3 end, SetFunc = function(c,v) _G.LexusState.CustomTextData.WeaponGlowThickness = v return true end }
        }

        -- Defense in depth: every generated menu control refuses reads and
        -- writes unless canonical panel authorization is currently active.
        local function GuardMenuStack(stack)
            for _, item in ipairs(stack) do
                local originalGet = item.GetFunc
                local originalSet = item.SetFunc
                item.GetFunc = function(...)
                    if not HasPanelAuthorization() then return false end
                    if type(originalGet) == "function" then return originalGet(...) end
                    return false
                end
                item.SetFunc = function(...)
                    if not HasPanelAuthorization() then return false end
                    if type(originalSet) == "function" then
                        local changed = originalSet(...)
                        -- Most standard menu setters update only their in-memory
                        -- config value. Persist every successful toggle or slider
                        -- change here so settings survive the next menu/session.
                        if changed ~= false and _G.SaveModSettings then _G.SaveModSettings() end
                        return changed
                    end
                    return false
                end
            end
        end
        GuardMenuStack(StackADESP)
        GuardMenuStack(StackESP)
        GuardMenuStack(StackAimbot)
        GuardMenuStack(StackAimbotV2)
        GuardMenuStack(StackCombat)

        -- FIX: PASS NUMERIC ID INSTEAD OF TEXT, CHANGE "loc" TO "Text"
        SettingPageDefine.ModMenu = {
            Key = "ModMenu",
            Text = 999000, 
            UIKey = "Setting_Page_Privacy", 
            Category = {
                { Key = "Cat_ADESP", Text = 999010, Stack = StackADESP },
                { Key = "Cat_ESP", Text = 999001, Stack = StackESP },
                { Key = "Cat_Aimbot", Text = 999002, Stack = StackAimbot },
                { Key = "Cat_AimbotV2", Text = 999003, Stack = StackAimbotV2 },
                { Key = "Cat_Combat", Text = 999004, Stack = StackCombat },
            }
        }
        
        table.insert(SettingCatalog, 1, SettingPageDefine.ModMenu) -- Insert at index 1 to make the menu appear first
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._IsModMenuHooked then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...) 
            
            -- [FIX MISSING OPTIONS BUTTON] - Only inject VIP Menu into main Setting, block custom UI settings
            if config and config.keyName then
                local lowerKeyName = string.lower(config.keyName)
                if string.find(lowerKeyName, "setting_main") and not string.find(lowerKeyName, "custom") then
                    local catalog = args[1]
                    -- Check if args[1] is the main Setting Catalog
                    if type(catalog) == "table" and catalog[1] and type(catalog[1]) == "table" and catalog[1].Key then
                        local isAuth = HasPanelAuthorization()
                        local hasModMenu = false
                        local modMenuIdx = nil
                        for i, page in ipairs(catalog) do
                            if type(page) == "table" and page.Key == "ModMenu" then
                                hasModMenu = true
                                modMenuIdx = i
                                break
                            end
                        end
                        if isAuth then
                            if not hasModMenu then
                                table.insert(catalog, 1, SettingPageDefine.ModMenu)
                            end
                        else
                            -- If not authorized, strip out ModMenu completely from settings catalog!
                            if hasModMenu and modMenuIdx then
                                table.remove(catalog, modMenuIdx)
                            end
                        end
                    end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._IsModMenuHooked = true
    end
end

-- PURPOSE: Menu/settings configuration ko create, load ya update karta hai.
-- FEATURE 12.03: ShowLexusVIPMenu
-- ------------------------------------------------------------
local function ShowLexusVIPMenu() 
    if not HasPanelAuthorization() then return end
    if _G.LexusMenuAlreadyShown then return end
    if _G.LexusState.MenuStep ~= 0 then return end

    PCall(function()
        local Msg = SafeRequire("client.slua.logic.common.logic_common_msg_box")
        if not Msg or not Msg.Show then return end

        local function Step_ScamAlert()
            Msg.Show(1, "SCAM MOD WARNING", "Join my Telegram to avoid those who sell free mods", function() local Web = SafeRequire("client.slua.logic.url.logic_webview_sdk"); if Web and Web.OpenURL then Web:OpenURL("https://t.me/NEXALORD") end end, function() end, "NEXA")
            _G.LexusState.MenuStep = 99
            _G.LexusMenuAlreadyShown = true
        end

        local function Step_Welcome()
            Msg.Show(1, "WELCOME", "I am NEXA. You don't need external combos or configs anymore because now there is a NEXA MENU in the Game Settings!\n BUT LISTEN TO ME, ENABLE FEW FEATURES, IT LAGS A LOT. I DON'T WANT YOUR PHONE TO CRASH. ALSO, AIM CAREFULLY AND YOU'LL BE SAFE", 
            function() 
                _G.InitModMenuTab()
                Notify("'NEXA MOD MENU' HAS BEEN ADDED TO THE GAME SETTINGS!\nOpen Settings (Gear) -> NEXA MOD MENU to toggle features and adjust sliders in real-time during the match!")
                Step_ScamAlert()
            end, 
            function() end, "OPEN IN-GAME MENU", "NEXA")
        end

        _G.LexusState.MenuStep = 1
        Step_Welcome() 
    end)
end-- ========================================== 
-- ============================================================
-- FEATURE 13: GRAPHICS UNLOCK AND IPAD VIEW
-- ============================================================
-- LOGIC MỞ KHÓA 165 FPS VÀ UI IPAD VIEW 
-- ========================================== 
-- PURPOSE: FPS unlock, graphics options aur iPad-view related settings apply karta hai.
-- FEATURE 13.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: FPS unlock, graphics options aur iPad-view related settings apply karta hai.
-- FEATURE 13.02: InitializeGraphicsUnlock
-- ------------------------------------------------------------
local function InitializeGraphicsUnlock() 
    -- if false then -- [BYPASSED] return end -- [BYPASSED]
    -- if _G.LexusState.GraphicsUnlocked or false -- [STRIPPED] then return end

    PCall(function()
        local SettingCfg = SafeRequire("client.logic.setting.setting_config")
        local GraphicSettingDB = SafeRequire("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        if SettingCfg then
            if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 160 end
            if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 160 end
        end
        if GraphicSettingDB then
            if GraphicSettingDB.TpViewValue then GraphicSettingDB.TpViewValue.max = 160 end
        end
    end)

    PCall(function()
        local logic_setting_graphics = SafeRequire("client.slua.logic.setting.logic_setting_graphics")
        local GSC_FPS = SafeRequire("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        local GSC_FPSFT = SafeRequire("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        local GraphicSettingDB = SafeRequire("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        
        local KismetMathLibrary = SafeImport("KismetMathLibrary") or _G.KismetMathLibrary
        local FLinearColor = SafeImport("LinearColor") or _G.FLinearColor

        if logic_setting_graphics then
            local old_SetFPS = logic_setting_graphics.SetFPS
            function logic_setting_graphics.SetFPS(gameInstance, FPSLevel)
                if old_SetFPS then old_SetFPS(gameInstance, FPSLevel) end
                if FPSLevel == 8 then 
                    gameInstance:ExecuteCMD("t.MaxFPS", "165")
                    gameInstance:ExecuteCMD("r.FrameRateLimit", "165")
                end
            end
        end

        if GSC_FPS and GSC_FPS.__inner_impl then
            local fps_impl = GSC_FPS.__inner_impl
            function fps_impl:GetMaxFPSLevel() return 8, 8 end
            function fps_impl:InitRealSupportFPS()
                local RealSupportFPS = {}
                for i = 1, 8 do RealSupportFPS[i] = {true, true} end
                if GraphicSettingDB then GraphicSettingDB:UpdateUIData(GraphicSettingDB.RealSupportFPS, RealSupportFPS, false) end
                return RealSupportFPS
            end
            function fps_impl:UpdateSelectedFPSState(selectedLevel)
                if not SafeIsValid(self.UIRoot) then return end
                for level = 2, 8 do
                    local name = "NodeFps" .. (({[2]=20,[3]=25,[4]=30,[5]=40,[6]=60,[7]=90,[8]=120})[level] or 120)
                    local widget = self.UIRoot[name]
                    if SafeIsValid(widget) then
                        widget:SetIsEnabled(true) 
                        PCall(function() widget:SetRenderOpacity(1.0) end)
                        local switcher = self.UIRoot["WidgetSwitcher_" .. level]
                        if SafeIsValid(switcher) then 
                            switcher:SetActiveWidgetIndex(level == selectedLevel and 0 or 1) 
                        end
                    end
                end
            end
        end

        if GSC_FPSFT and GSC_FPSFT.__inner_impl then
            local ft_impl = GSC_FPSFT.__inner_impl
            local NMinFPS, NStep = 90, 5
            local function clamp(value, min, max)
                if value < min then return min end
                if max < value then return max end
                return value
            end
            local function lerp(a, b, t) return a + (b - a) * t end
            local function _getColorByPercent(start, finish, percent)
                if not FLinearColor then return nil end
                return FLinearColor(lerp(start.R, finish.R, percent), lerp(start.G, finish.G, percent), lerp(start.B, finish.B, percent), lerp(start.A, finish.A, percent))
            end
            
            ft_impl.ShowOrHide = function(self)
                self:SelfHitTestInvisible()
                if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end
            end

            ft_impl.InitFPSFTSwitch = function(self)
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                if self.UIRoot.Setting_Switch then self.UIRoot.Setting_Switch:SetSwitcherEnable2(FPSFineTuneSwitch, true) end
                if self.UIRoot.CanvasPanel_8 then self:SetWidgetVisible(self.UIRoot.CanvasPanel_8, FPSFineTuneSwitch) end
                if self.UIRoot.WidgetSwitcher_0 then self.UIRoot.WidgetSwitcher_0:SetActiveWidgetIndex(2) end
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
            end

            ft_impl.InitFPSFTValue165 = function(self)
                local itemRoot = self.UIRoot
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                local FPSFineTuneNum = 165
                if FPSFineTuneSwitch then
                    FPSFineTuneNum = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneNum) or 165
                    itemRoot.Slider_screen3:SetLocked(false)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 1.0, 1.0, 1.0))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 1.0, 1.0, 1.0))
                    end
                else
                    itemRoot.Slider_screen3:SetLocked(true)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 0.625, 0.6, 1))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 0.625, 0.6, 1.0))
                    end
                end
                local FPSFineTunePer = (FPSFineTuneNum - NMinFPS) / (165 - NMinFPS)
                
                itemRoot.Veihclescreen3:SetText(tostring(FPSFineTuneNum))
                itemRoot.Slider_screen3:SetValue(FPSFineTunePer)
                itemRoot.ProgressBar_screen3:SetPercent(FPSFineTunePer)
                
                if FLinearColor then
                    local startColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
                    local midColor = FLinearColor(1.0, 0.54, 0.11, 1.0)
                    local endColor = FLinearColor(1.0, 0.23, 0.15, 1.0)
                    local sliderColor = FPSFineTunePer < 0.4 and startColor or _getColorByPercent(midColor, endColor, (FPSFineTunePer - 0.4) / 0.6)
                    itemRoot.Slider_screen3:SetSliderHandleColor(sliderColor)
                end
            end

            ft_impl.OnFPSFTValueChange3 = function(self, FPSFineTuneNum)
                GraphicSettingDB:UpdateUIData(GraphicSettingDB.FPSFineTuneNum, FPSFineTuneNum)
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
                if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
                local gameInstance = GraphicSettingDB.GetGameInstance and GraphicSettingDB.GetGameInstance()
                if gameInstance then
                    gameInstance:ExecuteCMD("t.MaxFPS", tostring(FPSFineTuneNum))
                    gameInstance:ExecuteCMD("r.FrameRateLimit", tostring(FPSFineTuneNum))
                end
            end

            ft_impl.OnFPSFTSliderValueChange3 = function(self, value)
                if GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch) and KismetMathLibrary then
                    local FPSFineTuneNum = KismetMathLibrary.FCeil(value * (165 - NMinFPS) / NStep) * NStep + NMinFPS
                    self:OnFPSFTValueChange3(clamp(FPSFineTuneNum, NMinFPS, 165))
                end
            end
            
            ft_impl.OnFPSFTAdd = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTAdd2 = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus2 = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTSliderValueChange = ft_impl.OnFPSFTSliderValueChange3
            ft_impl.OnFPSFTSliderValueChange2 = ft_impl.OnFPSFTSliderValueChange3
        end
    end)
    _G.LexusState.GraphicsUnlocked = true
    Notify("Graphics & FPS 165Hz Unlocked (Upgraded Version)")
end

-- ========================================== 
-- ============================================================
-- FEATURE 14: ESP INITIALIZATION AND RENDERING
-- ============================================================
-- KHỞI TẠO HỆ THỐNG ESP (GỐC)
-- ========================================== 
-- PURPOSE: ESP system initialize karke actors/targets ka visual display manage karta hai.
-- FEATURE 14.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Enemy/actor information ko detect, mark ya display karta hai.
-- FEATURE 14.02: InitializeNativeESP
-- ------------------------------------------------------------
local function InitializeNativeESP() 
    if _G.LexusState.NativeESPReady then return end
    PCall(function() 
        local GamePlayTools = SafeRequire("GameLua.Mod.BaseMod.Common.GamePlayTools") 
        local currentMarkCfg = GamePlayTools.GetCurrentConfig("ScreenMarkConfig") 
        local function ApplyCfg(cfg)
            if not cfg then return end 
            if cfg[1006] then 
                cfg[1006].bBindBlocked = true;
                cfg[1006].bBindOutScreen = true; 
                cfg[1006].MaxWidgetNum = 99
                cfg[1006].MaxShowDistance = 6000000; 
                cfg[1006].bScaleByDistance = false
                cfg[1006].BindSocketName = "root"; 
                cfg[1006].bUseLuaWorldSocketName = true
                cfg[1006].WorldPositionOffset = FVector(0, 0, -30) 
            end 
            -- [FIX ESP LOẠI 4] Thay vì dùng 1003 dễ bị game xóa, ta tạo ID độc quyền 8888
            cfg[8888] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true,     -- Bắt buộc phải có để bám theo địch
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 30),
                bNeedPreLoad = true,        -- Bắt buộc có để load sẵn UI (chống lỗi)
                Priority = 2 
            } 
            cfg[9999] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true, 
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 50),
                bNeedPreLoad = true, 
                Priority = 2 
            } 
        end 
        ApplyCfg(currentMarkCfg) 
        for k, cfg in pairs(package.loaded) do 
            if type(k) == "string" and string.find(k, "ScreenMarkConfig") and type(cfg) == "table" then 
                ApplyCfg(cfg) 
            end 
        end 
    end)
    _G.LexusState.NativeESPReady = true 
    Notify("Native ESP System Initialized") 
end

-- ========================================== 
-- LOCAL FUNCTIONS CHO LOGIC NEW ESP - OPTIMIZED
-- ========================================== 
-- PURPOSE: ESP system initialize karke actors/targets ka visual display manage karta hai.
-- FEATURE 14.03: GetAllSkeletalMeshes
-- ------------------------------------------------------------
local function GetAllSkeletalMeshes(enemy, markData)
    local curTime = os.clock()
    if markData and markData.CachedMeshes and markData.CachedMeshTime and (curTime - markData.CachedMeshTime < 3.0) then
        local validMeshes = {}
        for _, cachedMesh in ipairs(markData.CachedMeshes) do
            if Valid(cachedMesh) then table.insert(validMeshes, cachedMesh) end
        end
        markData.CachedMeshes = validMeshes
        return validMeshes
    end

    local meshes = {}
    if Valid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
    PCall(function()
        local SkeletalMeshClass = SafeImport("SkeletalMeshComponent")
        if SkeletalMeshClass and type(enemy.GetComponentsByClass) == "function" then
            local childs = enemy:GetComponentsByClass(SkeletalMeshClass)
            if childs then
                local count = type(childs.Num) == "function" and childs:Num() or #childs
                for i = 1, count do
                    local comp = type(childs.Get) == "function" and childs:Get(i-1) or childs[i]
                    if Valid(comp) and comp ~= enemy.Mesh then
                        table.insert(meshes, comp)
                    end
                end
            end
        end
    end)
    if markData then
        markData.CachedMeshes = meshes
        markData.CachedMeshTime = curTime
    end
    return meshes
end

-- ========================================== 
-- ============================================================
-- FEATURE 15: WALL-THROUGH AND BODY-COLOR SYSTEMS
-- ============================================================
-- HÀM XUYÊN TƯỜNG & RESTORE GỐC
-- ==========================================
-- PURPOSE: Wall/body visual effects apply aur restore karne ka logic rakhta hai.
-- FEATURE 15.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Visual material, wall effect ya body color ko apply/restore karta hai.
-- FEATURE 15.02: UndoWallXuyenTuong
-- ------------------------------------------------------------
local function UndoWallXuyenTuong(enemy, markData)
    PCall(function()
        if markData.WallhackApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    PCall(function() if type(mesh.SetRenderCustomDepth) == "function" then mesh:SetRenderCustomDepth(false) end end)
                    for i = 0, 10 do 
                        local matInterface = mesh:GetMaterial(i)
                        if Valid(matInterface) then
                            local baseMat = matInterface:GetBaseMaterial()
                            if Valid(baseMat) then baseMat.bDisableDepthTest = false end
                        end
                    end
                end
            end
            markData.WallhackApplied = false
        end
    end)
end

-- PURPOSE: Visual material, wall effect ya body color ko apply/restore karta hai.
-- FEATURE 15.03: ApplyWallXuyenTuong (Color-coded for Players: Pink/Red, Bots: Green/Yellow)
-- ------------------------------------------------------------
local function ApplyWallXuyenTuong(enemy, pc, markData)
    PCall(function()
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        if #meshes == 0 then return end
        
        -- Make visibility check much more responsive (0.05s) to eliminate state mixing/delay
        local curTime = os.clock()
        if markData.LastWallVisCheckTime == nil or (curTime - markData.LastWallVisCheckTime) > 0.50 then
            markData.LastWallVisCheckTime = curTime
            local isHidden = true
            PCall(function()
                if Valid(pc) and type(pc.LineOfSightTo) == "function" then
                    if pc:LineOfSightTo(enemy) then isHidden = false else isHidden = true end
                end
            end)
            markData.CachedWallHidden = isHidden
        end
        
        local hidden = markData.CachedWallHidden
        if hidden == nil then hidden = true end
        
        local isBot = CheckIsAI(enemy, markData)
        if isBot and not _G.LexusConfig.WallV2_Bot then return end
        if not isBot and not _G.LexusConfig.WallV2_Player then return end
        
        local FLinearColor = CachedLinearColor or rawget(_G, "FLinearColor") or SafeImport("LinearColor")
        if not FLinearColor then return end
        
        -- Execute required console commands for Dyeing Chams like 7.lua
        PCall(function()
            local KSL = CachedKismetSystemLibrary or rawget(_G, "KismetSystemLibrary") or SafeImport("KismetSystemLibrary")
            local world = slua.getWorld()
            if KSL and world then
                KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
                KSL.ExecuteConsoleCommand(world, "r.CustomDepth 3")
                KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
            end
        end)
        
        local customText = _G.LexusState and _G.LexusState.CustomTextData or {}
        local visColor, occColor
        if _G.LexusConfig.WallV2_CustomColor then
            if isBot then
                local openL = customText.BotOpenL or 10
                local behindL = customText.BotBehindL or 10
                visColor = FLinearColor(((customText.BotOpenR or 20) / 255.0) * (openL / 10), ((customText.BotOpenG or 255) / 255.0) * (openL / 10), ((customText.BotOpenB or 1) / 255.0) * (openL / 10), (customText.BotOpenA or 255) / 255.0)
                occColor = FLinearColor(((customText.BotBehindR or 255) / 255.0) * (behindL / 10), ((customText.BotBehindG or 255) / 255.0) * (behindL / 10), ((customText.BotBehindB or 1) / 255.0) * (behindL / 10), (customText.BotBehindA or 255) / 255.0)
            else
                local openL = customText.PlayerOpenL or 10
                local behindL = customText.PlayerBehindL or 10
                visColor = FLinearColor(((customText.PlayerOpenR or 1) / 255.0) * (openL / 10), ((customText.PlayerOpenG or 255) / 255.0) * (openL / 10), ((customText.PlayerOpenB or 255) / 255.0) * (openL / 10), (customText.PlayerOpenA or 255) / 255.0)
                occColor = FLinearColor(((customText.PlayerBehindR or 255) / 255.0) * (behindL / 10), ((customText.PlayerBehindG or 1) / 255.0) * (behindL / 10), ((customText.PlayerBehindB or 1) / 255.0) * (behindL / 10), (customText.PlayerBehindA or 255) / 255.0)
            end
        elseif isBot then
            visColor = FLinearColor(0, 300, 0, 1)
            occColor = FLinearColor(300, 300, 0, 1)
        else
            visColor = FLinearColor(0, 300, 300, 1)
            occColor = FLinearColor(300, 0, 0, 1)
        end
        
        for _, mesh in ipairs(meshes) do
            if Valid(mesh) then
                PCall(function()
                    mesh:SetDrawDyeing(true)
                    mesh:SetDrawDyeingMode(1)
                    mesh:SetVisibleDyeingColor(visColor)
                    mesh:SetOccludedDyeingColor(occColor)
                    mesh:SetDyeingColorFadeDistance(99999.0)
                    mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
                    
                    mesh:SetDrawHighlight(true)
                    mesh:OverrideHighlightColor(visColor)
                    mesh:SetHighlightCanBeOccluded(false)
                    
                    mesh:SetRenderCustomDepth(true)
                    mesh:SetCustomDepthStencilValue(0)
                end)
            end
        end
    end)
end





-- ========================================== 
-- ============================================================
-- FEATURE 16: AIMBOT SYSTEM
-- ============================================================
-- HỆ THỐNG AIMBOT V2 TÍCH HỢP MỚI (UPDATE KISMET SMOOTH)
-- ========================================== 
-- PURPOSE: Target selection, aim control aur aimbot-related calculations handle karta hai.
-- FEATURE 16.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Target selection aur aiming behavior ko control karta hai.
-- FEATURE 16.02: GetEnemyTargetsFromActors
-- ------------------------------------------------------------
_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    if not HasPanelAuthorization() then return result end
    local player = GameplayData.GetPlayerCharacter()

    if not SafeIsValid(player) then
        return result
    end

    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
    end

    local myTeam = player:GetTeamID()

    for _, actor in pairs(allCharacters) do
        if SafeIsValid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
            if actor:GetTeamID() ~= myTeam then
                local dist = player:GetDistanceTo(actor)
                if dist <= radius then
                    table.insert(result, actor)
                end
            end
        end
    end
    return result
end

-- PURPOSE: Target selection aur aiming behavior ko control karta hai.
-- FEATURE 16.03: AimTouch
-- ------------------------------------------------------------
_G.AimTouch = function()
    if not HasPanelAuthorization() then return end
    PCall(function()
        if not _G.LexusConfig.AimTouchEnable then return end
        
        local player = GameplayData.GetPlayerCharacter()
        if not SafeIsValid(player) then return end
        
        local pc = player:GetPlayerControllerSafety()
        if not SafeIsValid(pc) then return end
        
        local isFiring = player.bIsWeaponFiring
        local isADS = player.bIsGunADS
        
        -- CHECK WEAPON & AMMO
        local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(player.GetCurrentShootWeapon) == "function" then
            weapon = player:GetCurrentShootWeapon()
        end
        
        local isShotgun = false
        local isSniper = false
        local currentAmmo = 1
        
        if SafeIsValid(weapon) then
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then 
                isShotgun = true 
            end
            
            if wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                isSniper = true
            end
            
            if type(weapon.GetCurrentAmmo) == "function" then
                currentAmmo = weapon:GetCurrentAmmo()
            elseif weapon.ShootWeaponComponent and type(weapon.ShootWeaponComponent.GetCurrentAmmo) == "function" then
                currentAmmo = weapon.ShootWeaponComponent:GetCurrentAmmo()
            elseif weapon.CurrentAmmo ~= nil then
                currentAmmo = weapon.CurrentAmmo
            end
        end

        -- LOGIC NHẢ CÒ SÚNG NẾU MẤT MỤC TIÊU / ĐỊCH CHẾT HOẶC SHOTGUN HẾT ĐẠN
        if _G.LexusState.IsAutoFiring then
            PCall(function()
                player.bIsWeaponFiring = false
                if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(false) end
                if SafeIsValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(false) end
                local wepMgr = player.WeaponManagerComponent
                if SafeIsValid(wepMgr) then wepMgr.bIsWeaponFiring = false end
            end)
            _G.LexusState.IsAutoFiring = false
        end

        -- SHOTGUN HẾT ĐẠN NGƯNG AIM ĐỂ GAME NẠP ĐẠN
        if isShotgun and currentAmmo <= 0 then
            return
        end

        local cond = 2
        local prioMode = 1
        local boneIdx = 1
        local speedVal = 50
        local fovVal = 30
        local maxDistMeters = 50
        local useVisCheck = false
        local igKnock = false
        local igBot = false
        
        -- Logic thêm vào: Dự đoán và Bù giật
        local predVal = 0 
        local recoilCompVal = 0 

        -- PHÂN LOẠI CẤU HÌNH THEO TRẠNG THÁI HIỆN TẠI
        if isShotgun and _G.LexusConfig.AimTouchSG then
            cond = _G.LexusState.CustomTextData.AimTouchSGCond or 1
            if _G.LexusConfig.AimTouchSGAutoFire then cond = 2 end
            if cond == 1 and not isFiring then return end
            prioMode = _G.LexusState.CustomTextData.AimTouchSGPrio or 1
            boneIdx = _G.LexusState.CustomTextData.AimTouchSGBone or 2
            speedVal = _G.LexusState.CustomTextData.AimTouchSGSpeed or 80
            fovVal = _G.LexusState.CustomTextData.AimTouchSGFOV or 40
            maxDistMeters = _G.LexusState.CustomTextData.AimTouchSGDist or 30
            useVisCheck = _G.LexusConfig.AimTouchSGVisCheck
            igKnock = _G.LexusConfig.AimTouchSGIgKnock
            igBot = _G.LexusConfig.AimTouchSGIgBot
            
        elseif isADS then
            if isSniper and _G.LexusConfig.AimTouchScopeSniper then
                cond = _G.LexusState.CustomTextData.AimTouchSniperCond or 2
                if cond == 1 and not isFiring then return end
                prioMode = _G.LexusState.CustomTextData.AimTouchSniperPrio or 1
                boneIdx = _G.LexusState.CustomTextData.AimTouchSniperBone or 1
                speedVal = _G.LexusState.CustomTextData.AimTouchSniperSpeed or 30
                fovVal = _G.LexusState.CustomTextData.AimTouchSniperFOV or 20
                maxDistMeters = _G.LexusState.CustomTextData.AimTouchSniperDist or 400
                useVisCheck = _G.LexusConfig.AimTouchSniperVisCheck
                igKnock = _G.LexusConfig.AimTouchSniperIgKnock
                igBot = _G.LexusConfig.AimTouchSniperIgBot
                predVal = _G.LexusState.CustomTextData.AimTouchSniperPred or 0 -- Lấy giá trị dự đoán Sniper
            elseif _G.LexusConfig.AimTouchScopeAll then
                cond = _G.LexusState.CustomTextData.AimTouchScopeCond or 1
                if cond == 1 and not isFiring then return end
                prioMode = _G.LexusState.CustomTextData.AimTouchScopePrio or 1
                boneIdx = _G.LexusState.CustomTextData.AimTouchScopeBone or 2
                speedVal = _G.LexusState.CustomTextData.AimTouchScopeSpeed or 40
                fovVal = _G.LexusState.CustomTextData.AimTouchScopeFOV or 20
                maxDistMeters = _G.LexusState.CustomTextData.AimTouchScopeDist or 300
                useVisCheck = _G.LexusConfig.AimTouchScopeVisCheck
                igKnock = _G.LexusConfig.AimTouchScopeIgKnock
                igBot = _G.LexusConfig.AimTouchScopeIgBot
                predVal = _G.LexusState.CustomTextData.AimTouchScopePred or 0 -- Lấy giá trị dự đoán Súng thường
                recoilCompVal = _G.LexusState.CustomTextData.AimTouchScopeRecoil or 0 -- Lấy giá trị bù giật
            else
                return
            end
        else
            if not _G.LexusConfig.AimTouchHipfire then return end
            cond = _G.LexusState.CustomTextData.AimTouchHipCond or 1
            if cond == 1 and not isFiring then return end 
            prioMode = _G.LexusState.CustomTextData.AimTouchHipPrio or 1
            boneIdx = _G.LexusState.CustomTextData.AimTouchHipBone or 1
            speedVal = _G.LexusState.CustomTextData.AimTouchHipSpeed or 50
            fovVal = _G.LexusState.CustomTextData.AimTouchHipFOV or 30
            maxDistMeters = _G.LexusState.CustomTextData.AimTouchHipDist or 250
            useVisCheck = _G.LexusConfig.AimTouchHipVisCheck
            igKnock = _G.LexusConfig.AimTouchHipIgKnock
            igBot = _G.LexusConfig.AimTouchHipIgBot
        end

        local currentMaxDist = maxDistMeters * 100 

        local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
        if not enemies or #enemies == 0 then return end
        
        local FVector2D = SafeImport("Vector2D")
        local UGameplayStatics = SafeImport("GameplayStatics")
        local KismetMathLibrary = SafeImport("KismetMathLibrary")
        
        local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
        if not SafeIsValid(camManager) then return end
        
        local camLoc = camManager:GetCameraLocation()
        if not camLoc then return end
        
        local ui_util = SafeRequire("client.common.ui_util")
        if not ui_util then return end
        
        local viewportSize = ui_util.GetViewportSize()
        if not viewportSize then return end
        
        local centerX = viewportSize.X * 0.5
        local centerY = viewportSize.Y * 0.5
        
        local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)
        
        local bestTarget = nil
        local bestScore = 99999999 
        
        local selBoneName = "head"
        if boneIdx == 1 then selBoneName = "head"
        elseif boneIdx == 2 then selBoneName = "spine_03"
        elseif boneIdx == 3 then selBoneName = "spine_01"
        elseif boneIdx == 4 then selBoneName = "pelvis" end

        for i, target in ipairs(enemies) do
            if not SafeIsValid(target) then goto continue end
            
            PCall(function()
                if SafeIsValid(target.Mesh) then
                    target.Mesh.MeshComponentUpdateFlag = 0
                end
            end)
            
            if igKnock and target.HealthStatus == 1 then goto continue end
            
            if igBot then
                local tIsBot = false
                if target.bIsAI == true or target.IsAI == true then tIsBot = true end
                local pState = target.PlayerState
                if SafeIsValid(pState) and (pState.bIsABot or pState.bIsBot) then tIsBot = true end
                if tIsBot then goto continue end
            end
            
            -- [FIX TỤT FPS]: Khóa tia Raycast check tường, chỉ quét 0.2s một lần (Đủ mượt mà không cháy CPU)
            if useVisCheck then
                local curTime = os.clock()
                local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
                _G.AimTouchVisCache = _G.AimTouchVisCache or {}
                if not _G.AimTouchVisCache[tId] or (curTime - _G.AimTouchVisCache[tId].time) > 0.2 then
                    local isHidden = true
                    PCall(function() if pc:LineOfSightTo(target) then isHidden = false end end)
                    _G.AimTouchVisCache[tId] = { hidden = isHidden, time = curTime }
                end
                if _G.AimTouchVisCache[tId].hidden then goto continue end
            end
            
            local tPos = target:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.GetSocketLocation) == "function" then
                    tPos = target:GetSocketLocation(selBoneName)
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.K2_GetActorLocation) == "function" then
                    tPos = target:K2_GetActorLocation()
                    if tPos then
                        if boneIdx == 1 then tPos.Z = tPos.Z + 70
                        elseif boneIdx == 2 then tPos.Z = tPos.Z + 40
                        elseif boneIdx == 3 then tPos.Z = tPos.Z + 20 end
                    end
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then goto continue end
            
            local screen = FVector2D()
            local success = pc:ProjectWorldLocationToScreen(tPos, screen, false)
            if not success or screen.X <= 0 or screen.Y <= 0 then goto continue end
            
            local dx = screen.X - centerX
            local dy = screen.Y - centerY
            local distScreen = math.sqrt(dx*dx + dy*dy)
            
            if distScreen > FOV_RADIUS then goto continue end
            
            local currentScore = distScreen
            if prioMode == 2 then currentScore = player:GetDistanceTo(target)
            elseif prioMode == 3 then currentScore = target.Health or 100
            elseif prioMode == 4 then 
                local hp = target.Health or 100
                local maxhp = target.HealthMax or 100
                if maxhp <= 0 then maxhp = 100 end
                currentScore = hp / maxhp
            end
            
            if currentScore < bestScore then
                bestScore = currentScore
                bestTarget = target
            end
            
            ::continue::
        end
        
        if not SafeIsValid(bestTarget) then return end
        
        local finalBonePos = bestTarget:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.GetSocketLocation) == "function" then
                finalBonePos = bestTarget:GetSocketLocation(selBoneName)
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.K2_GetActorLocation) == "function" then
                finalBonePos = bestTarget:K2_GetActorLocation()
                if finalBonePos then
                    if boneIdx == 1 then finalBonePos.Z = finalBonePos.Z + 70
                    elseif boneIdx == 2 then finalBonePos.Z = finalBonePos.Z + 40
                    elseif boneIdx == 3 then finalBonePos.Z = finalBonePos.Z + 20 end
                end
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then return end
        
        -- LOGIC 1: PREDICTION (DỰ ĐOÁN HƯỚNG CHẠY)
        if predVal > 0 then
            PCall(function()
                local tVelocity = nil
                -- Unreal Engine Lấy vector di chuyển của địch
                if type(bestTarget.GetVelocity) == "function" then
                    tVelocity = bestTarget:GetVelocity()
                end
                
                -- Nếu địch đang di chuyển
                if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                    local distToEnemy = player:GetDistanceTo(bestTarget) / 100.0 -- Khoảng cách mét
                    
                    -- Tính toán thời gian đạn bay (Time-Of-Flight) tỉ lệ thuận với khoảng cách và biến truyền vào
                    -- Hệ số 800.0 đại diện cho tốc độ đạn rơi giả lập, 50.0 là mức trung bình slider
                    local ToF = (distToEnemy / 800.0) * (predVal / 50.0) 
                    
                    -- Dịch chuyển toạ độ Aim lên trước hướng chạy
                    finalBonePos.X = finalBonePos.X + (tVelocity.X * ToF)
                    finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * ToF)
                end
            end)
        end

        local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos)
        if not rot then return end
        
        local currentRot = pc:GetControlRotation()
        if not currentRot then return end
        
        local deltaYaw = rot.Yaw - currentRot.Yaw
        local deltaPitch = rot.Pitch - currentRot.Pitch
        
        -- [BẮT ĐẦU FIX] Bù trừ chênh lệch Camera khi mở ống ngắm (ADS) để không bị lệch tâm
        if isADS then
            local camRot = nil
            if type(camManager.GetCameraRotation) == "function" then
                camRot = camManager:GetCameraRotation()
            end
            if camRot then
                deltaYaw = deltaYaw - (camRot.Yaw - currentRot.Yaw)
                deltaPitch = deltaPitch - (camRot.Pitch - currentRot.Pitch)
            end
        end
        -- [KẾT THÚC FIX]

        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
        if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
        if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
        if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
        
        local smoothFactor = 0.0
        if speedVal >= 100 then
            smoothFactor = 1.0
        else
            smoothFactor = (speedVal / 100.0) * 0.3
            if smoothFactor < 0.01 then smoothFactor = 0.01 end
        end
        
        local finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor)
        local finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
        
        -- LOGIC 2: RECOIL COMPENSATION (ÉP TÂM / BÙ GIẬT TRÁNH BẮN QUÁ ĐẦU)
        -- Chỉ ép tâm khi súng đang bắn và giá trị Recoil > 0 (Dùng cho Súng thường)
        if recoilCompVal > 0 and isFiring then
            -- Trong UE4, kéo Pitch xuống (nhỏ đi) tương đương với việc ghìm tâm màn hình xuống
            -- Slider recoilCompVal (0-50), mỗi frame bù một lượng dựa trên độ giật
            local pullDownForce = (recoilCompVal / 50.0) * 1.5 -- Điều chỉnh nhân tố 1.5 tuỳ ý để ép gắt hơn
            finalPitch = finalPitch - pullDownForce
        end

        local finalRot = { Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }
        pc:SetControlRotation(finalRot, "AimTouch")
        
        if isShotgun and _G.LexusConfig.AimTouchSGAutoFire then
            PCall(function()
                local distToTarget = player:GetDistanceTo(bestTarget) / 100
                if distToTarget <= maxDistMeters then
                    player.bIsWeaponFiring = true
                    if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(true) end
                    if SafeIsValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(true) end
                    local wepMgr = player.WeaponManagerComponent
                    if SafeIsValid(wepMgr) then wepMgr.bIsWeaponFiring = true end
                    
                    local currentWep = player:GetCurrentWeapon()
                    if SafeIsValid(currentWep) and type(currentWep.StartFire) == "function" then 
                        currentWep:StartFire() 
                    end
                    _G.LexusState.IsAutoFiring = true
                end
            end)
        end

    end)
end

-- ========================================== 
-- ============================================================
-- FEATURE 17: VEHICLE-WALL SYSTEM
-- ============================================================
-- HỆ THỐNG WALL PHƯƠNG TIỆN SIÊU MƯỢT (ĐÃ XÓA ITEM ESP)
-- ========================================== 
-- ============================================================
-- FEATURE 18: MAIN LOOP AND RUNTIME SCHEDULER
-- ============================================================
-- VÒNG LẶP CHÍNH (MAIN LOOP) TỐI ƯU CỰC MẠNH
-- ========================================== 
-- PURPOSE: Main runtime loop, periodic updates aur feature scheduler chalata hai.
-- FEATURE 18.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
-- PURPOSE: Repeated runtime update ya scheduled task execute karta hai.
-- FEATURE 18.02: MainLoop
-- ------------------------------------------------------------
-- ========================================================================

-- WIDGET ENEMY COUNTER (native UI pinned top-center, multi-match safe)
-- ========================================================================
local GK_WIDGET_PATHS = {
    "/Game/UMG/UI_BP/Common/BaseComponent/CommonBaseComponent_TextButton_UIBP.CommonBaseComponent_TextButton_UIBP",
    "/Game/UMG/UI_BP/Common/BaseComponent/CommonBaseComponent_TextButton_UIBP.CommonBaseComponent_TextButton_UIBP_C",
}
local function GK_DestroyWidget()
    if _G.GK_WIDGET and SafeIsValid(_G.GK_WIDGET) then
        pcall(function() _G.GK_WIDGET:RemoveFromParent() end)
    end
    _G.GK_WIDGET = nil
    _G.GK_WIDGET_LAST_TEXT = ""
    _G.GK_WIDGET_OK = false
end
local function GK_GetOrCreateWidget()
    if _G.GK_WIDGET and SafeIsValid(_G.GK_WIDGET) then return _G.GK_WIDGET end
    GK_DestroyWidget()
    
    for _, bp in ipairs(GK_WIDGET_PATHS) do
        if _G.GK_WIDGET then break end
        pcall(function()
            local btn = slua.loadUI(bp)
            if not btn or not SafeIsValid(btn) then return end
            -- Try Method 1: UIContainers.Top
            pcall(function()
                local hm = package.loaded["game_frontend_hud"] or SafeRequire("game_frontend_hud")
                if hm and hm.AddToContainer and UIContainers and UIContainers.Top then
                    hm.AddToContainer(UIContainers.Top, btn, 10800)
                    _G.GK_WIDGET_OK = true
                end
            end)
            -- Try Method 2: AddToViewport fallback
            if not _G.GK_WIDGET_OK then
                pcall(function()
                    if btn.AddToViewport then btn:AddToViewport(100); _G.GK_WIDGET_OK = true end
                end)
            end
            if btn.RichText_Content then
                btn.RichText_Content:SetText("NEXA  LOADING...")
                local fi = btn.RichText_Content.Font
                if fi then fi.Size = 15; btn.RichText_Content:SetFont(fi) end
            end
            local WLL = SafeImport("WidgetLayoutLibrary")
            if WLL then
                local slot = WLL.SlotAsCanvasSlot(btn)
                if slot then
                    slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0))
                    slot:SetAlignment(FVector2D(0.5, 0))
                    slot:SetPosition(FVector2D(0, 12))
                    slot:SetSize(FVector2D(340, 40))
                end
            end
            pcall(function()
                if UEnums and UEnums.ESlateVisibility then
                    btn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                end
            end)
            _G.GK_WIDGET = btn
        end)
    end
    return _G.GK_WIDGET
end
local function GK_UpdateWidget(enemyCount, botCount)
    
    local newText
    if enemyCount == 0 and botCount == 0 then
        newText = " ZONE CLEAR  |  @NEXA"
    elseif enemyCount > 0 and botCount > 0 then
        newText = "NEXA  " .. enemyCount .. " ENEMY  |  " .. botCount .. " BOT  |  @NEXA"
    elseif enemyCount > 0 then
        newText = "NEXA  " .. enemyCount .. " ENEMY  |  @NEXA"
    else
        newText = "NEXA  " .. botCount .. " BOT  |  @NEXA"
    end
    if newText == _G.GK_WIDGET_LAST_TEXT then return end
    _G.GK_WIDGET_LAST_TEXT = newText
    local w = GK_GetOrCreateWidget()
    if w and SafeIsValid(w) and w.RichText_Content then
        pcall(function() w.RichText_Content:SetText("") end)
        pcall(function() w.RichText_Content:SetText(newText) end)
    end
end


function _G.InitializeADESPSystem()
    if not HasPanelAuthorization() then return end
    if _G.ADESP_Initialized then return end
    -- AD ESP SYSTEM (INTEGRATED)
    -- ==========================================
    local HEAD_WIDGET_BP = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP"
    
    local EnemyCounterWidget = nil
    local EnemyCounterRunning = false
    local EnemyCounterTimer = nil
    _G.ADESP_LastCounterText = ""
    
    -- Per-entity native head widgets from the verified V4 flow.
    local EntityHeadWidgets = {}
    
    -- V5-derived stable CanvasPanel boxes. These contain only the V2 name/BOT
    -- content and black background; the existing native widget remains available
    -- for its verified health bar and fallback path.
    local StableEntityBoxes = {}
    local StableESPCanvas = nil
    local StableCanvasScaleX = 1.0
    local StableCanvasScaleY = 1.0
    local StableCanvasOffsetX = 0.0
    local StableCanvasOffsetY = 0.0
    
    -- ==========================================
    -- SECTION 1: CONFIGURATION
    -- ==========================================
    
    -- Type 7-style lightweight cadence and bounded scan distance.
    -- The timer may tick faster, but the actual AD ESP work is throttled.
    local ADESP_UPDATE_INTERVAL = 0.20
    -- Keep the B Point closer to the target during swipe or gyro motion while
    -- preserving the existing nearest-target cap and the 20 Hz AD ESP scan.
    local ADESP_MAX_DISTANCE_M = 400
    local ADESP_WEAPON_CACHE_INTERVAL = 1.5
    local ADESP_STALE_CLEANUP_INTERVAL = 0.50
    local ADESP_LAST_UPDATE_TIME = 0
    local ADESP_LAST_STALE_CLEANUP_TIME = 0
    local ADESP_ACTIVE_PC = nil
    local ADESP_TIMER_GENERATION = 0
    
    local ESP_TEXT_LIFETIME = 0.06
    
    -- World-space offsets preserve the Base health-bar behavior and keep all
    -- actor-attached text above the body.
    local DISTANCE_OFFSET = {X = 0, Y = 0, Z = 145}
    local HEAD_LABEL_OFFSET = {X = 0, Y = 0, Z = 115}
    local HEALTH_BAR_OFFSET = {X = 0, Y = 0, Z = 85}
    
    -- Compact box sizing. The final width is based on RichText_Content's
    -- desired size, with only a small padding allowance.
    local BOX_MIN_WIDTH = 24
    local BOX_MIN_HEIGHT = 20
    local BOX_HORIZONTAL_PADDING = 8
    local BOX_VERTICAL_PADDING = 4
    -- Stable screen-space tag layout. The low-pass filter dampens camera shake
    -- while still following real target movement.
    local TAG_BOX_HEIGHT = 27
    local TAG_HEALTH_TRACK_HEIGHT = 5
    local TAG_HEALTH_TRACK_Y = 25
    -- Adaptive screen-space stabilization. Small changes are filtered;
    -- fast swipes use a high alpha; large projection jumps snap immediately.
    local TAG_PIXEL_QUANTIZE = 1.0
    -- All ESP elements use this verified head-bone point. The small lift keeps
    -- the label above the head while preserving one shared world anchor.
    local HEAD_BONE_VERTICAL_LIFT = 46
    local NAME_MAX_LENGTH = 27
    
    -- ==========================================
    -- SECTION 2: HELPER FUNCTIONS
    -- ==========================================
    
    local function SafeToString(value)
        if value == nil then return "" end
        if type(value) == "string" or type(value) == "number" then
            return tostring(value)
        end
    
        local ok, result = pcall(function()
            if value.ToString and type(value.ToString) == "function" then
                return value:ToString()
            end
            if value.GetString and type(value.GetString) == "function" then
                return value:GetString()
            end
            return tostring(value)
        end)
    
        if ok and result ~= nil then return tostring(result) end
        return ""
    end
    
    local function CleanPlayerName(value)
        local name = SafeToString(value)
        name = name:gsub("[\r\n]", " ")
        name = name:gsub("%s+", " ")
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
    
        if #name > NAME_MAX_LENGTH then
            name = name:sub(1, NAME_MAX_LENGTH - 3) .. "..."
        end
    
        return name
    end
    
    local function GetActualPlayerName(pawn)
        if not SafeIsValid(pawn) then return "PLAYER" end
    
        -- Verified in V3/PlayerHeadUIBP.lua.
        if pawn.GetPlayerNameSafety and type(pawn.GetPlayerNameSafety) == "function" then
            local ok, value = pcall(function()
                return pawn:GetPlayerNameSafety()
            end)
            if ok then
                local name = CleanPlayerName(value)
                if name ~= "" then return name end
            end
        end
    
        return "PLAYER"
    end
    
    local function IsAIPawn(pawn)
        if not SafeIsValid(pawn) then return false end
    
        local ok, result = pcall(function()
            if pawn.IsAIPawn and type(pawn.IsAIPawn) == "function" then
                return pawn:IsAIPawn()
            end
            if Game.IsAI and type(Game.IsAI) == "function" then
                return Game:IsAI(pawn)
            end
            if pawn.GetController and type(pawn.GetController) == "function" then
                local controller = pawn:GetController()
                if SafeIsValid(controller) then
                    local cName = tostring(controller:GetName() or "")
                    if cName:find("AI") or cName:find("Bot") then
                        return true
                    end
                end
            end
            return false
        end)
    
        return ok and result == true
    end
    
    local function IsPawnAlive(pawn)
        if not SafeIsValid(pawn) then return false end
    
        local ok, result = pcall(function()
            if pawn.HealthStatus then
                local SecurityCommonUtils = SafeRequire("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
                return SecurityCommonUtils.IsHealthStatusAlive(pawn.HealthStatus)
            end
            return (tonumber(pawn.Health) or 0) > 0
        end)
    
        return ok and result == true
    end
    
    -- V5 reference uses HealthStatus == 1 for the knocked/down state.
    local function IsPawnKnocked(pawn)
        return SafeIsValid(pawn) and tonumber(pawn.HealthStatus) == 1
    end
    
    local function IsPawnRenderable(pawn)
        return IsPawnKnocked(pawn) or IsPawnAlive(pawn)
    end
    
    local function GetHPString(pct)
        local n = math.floor((pct * 4) + 0.5)
        local s = ""
        for i = 1, 4 do
            s = s .. (i <= n and "▁" or " ")
        end
        return s
    end
    
    local function GetDynamicScale(distM)
        local scale = 1.0 - (math.min(distM, 200) / 400)
        return math.max(0.65, scale)
    end
    
    -- ==========================================
    -- SECTION 3: VERIFIED PROJECTION HELPER
    -- ==========================================
    
    local function GetHeadWorldPosition(enemy)
        if not SafeIsValid(enemy) then return nil end
        local headPos = nil
        local boneOK = false
        pcall(function()
            if enemy.GetBonePos and type(enemy.GetBonePos) == "function" then
                local candidate = enemy:GetBonePos("head", {X = 0, Y = 0, Z = 0})
                if candidate and (candidate.X ~= 0 or candidate.Y ~= 0 or candidate.Z ~= 0) then
                    headPos = FVector(candidate.X, candidate.Y, candidate.Z + HEAD_BONE_VERTICAL_LIFT)
                    boneOK = true
                end
            end
        end)
        if boneOK then return headPos end
        -- Safe fallback only for runtimes where the head bone is unavailable.
        local actorPos = nil
        pcall(function() actorPos = enemy:K2_GetActorLocation() end)
        if actorPos then
            return FVector(actorPos.X, actorPos.Y, actorPos.Z + 100)
        end
        return nil
    end
    -- ==========================================
    -- SECTION 4: EXISTING TEXT HEALTH BAR / DISTANCE
    -- ==========================================
    
    local function AddDebugTextSafe(hud, text, enemy, offset, color, scale)
        if not SafeIsValid(hud) or not hud.AddDebugText or not SafeIsValid(enemy) then
            return false
        end
    
        local ok = pcall(function()
            hud:AddDebugText(
                text,
                enemy,
                ESP_TEXT_LIFETIME,
                offset,
                offset,
                color,
                true, false, true, nil,
                scale,
                true
            )
        end)
    
        return ok
    end
    
    local function GetHeadRelativeOffset(enemy, headLoc, fallbackOffset)
        local offset = fallbackOffset
        pcall(function()
            local actorLoc = enemy and enemy:K2_GetActorLocation()
            if actorLoc and headLoc then
                offset = {
                    X = headLoc.X - actorLoc.X,
                    Y = headLoc.Y - actorLoc.Y,
                    Z = headLoc.Z - actorLoc.Z
                }
            end
        end)
        return offset
    end
    local function UpdateDistanceText(pc, enemy, distM, scale, headLoc)
        pcall(function()
            local hud = pc and pc.MyHUD
            if not SafeIsValid(hud) then return end
    
            AddDebugTextSafe(
                hud,
                string.format("[%dm]", distM),
                enemy,
                GetHeadRelativeOffset(enemy, headLoc, DISTANCE_OFFSET),
                {R = 255, G = 255, B = 255, A = 255},
                scale
            )
        end)
    end
    
    local function UpdateHealthBar(pc, enemy, scale, headLoc)
        pcall(function()
            local hud = pc and pc.MyHUD
            if not SafeIsValid(hud) then return end
    
            local hp = tonumber(enemy.Health) or 0
            local max = tonumber(enemy.HealthMax) or 100
            local pct = (max > 0) and (hp / max) or 0
            pct = math.max(0, math.min(1, pct))
    
            local color = (pct < 0.3)
                and {R = 255, G = 0, B = 0, A = 255}
                or ((pct < 0.7)
                    and {R = 255, G = 255, B = 0, A = 255}
                    or  {R = 0, G = 255, B = 0, A = 255})
    
            AddDebugTextSafe(
                hud,
                GetHPString(pct),
                enemy,
                GetHeadRelativeOffset(enemy, headLoc, HEALTH_BAR_OFFSET),
                color,
                scale
            )
        end)
    end
    
    -- ==========================================
    -- SECTION 5: V4 NATIVE HEAD WIDGET
    -- ==========================================
    
    local function SetNativeColor(widget, color)
        pcall(function()
            local slateColor = FSlateColor(FLinearColor(
                color.R / 255,
                color.G / 255,
                color.B / 255,
                color.A / 255
            ))
    
            if widget.TextBlock_PlayerName then
                widget.TextBlock_PlayerName:SetColorAndOpacity(slateColor)
            end
            if widget.Text_PlayerName then
                widget.Text_PlayerName:SetColorAndOpacity(slateColor)
            end
    
            -- Visual-only change: solid black name plate for maximum contrast.
            -- Bot/Player text colors remain unchanged.
            local bgColor = FLinearColor(0.005, 0.005, 0.008, 1.0)
            if widget.Image_Name_BG then
                widget.Image_Name_BG:SetColorAndOpacity(bgColor)
            end
            if widget.Image_TeamBG then
                widget.Image_TeamBG:SetColorAndOpacity(bgColor)
            end
        end)
    end
    
    local function SetNativeText(widget, text)
        if widget.TextBlock_PlayerName then
            widget.TextBlock_PlayerName:SetText(text)
        end
        if widget.Text_PlayerName then
            widget.Text_PlayerName:SetText(text)
        end
    end
    
    local function SetNativeHealth(widget, enemy)
        local hp = tonumber(enemy.Health) or 0
        local maxHp = tonumber(enemy.HealthMax) or 100
        if maxHp <= 0 then maxHp = 100 end
    
        local hpPercent = math.max(0, math.min(1, hp / maxHp))
        local hpColor = (hpPercent < 0.3)
            and FLinearColor(1, 0, 0, 1)
            or ((hpPercent < 0.7)
                and FLinearColor(1, 1, 0, 1)
                or  FLinearColor(0, 1, 0, 1))
    
        if widget.ProgressBar_HP then
            widget.ProgressBar_HP:SetPercent(hpPercent)
            widget.ProgressBar_HP:SetFillColorAndOpacity(hpColor)
            widget.ProgressBar_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end
        if widget.ProgressBar_0 then
            widget.ProgressBar_0:SetPercent(hpPercent)
            widget.ProgressBar_0:SetFillColorAndOpacity(hpColor)
            widget.ProgressBar_0:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end
    end
    
    local function GetStableESPCanvas()
        if StableESPCanvas and SafeIsValid(StableESPCanvas) then return StableESPCanvas end
    
        local tools = nil
        pcall(function() tools = SafeRequire("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
        if not tools or not tools.GetMainControlBaseUI then return nil end
    
        local mainUI = nil
        pcall(function() mainUI = tools.GetMainControlBaseUI() end)
        if not mainUI or not SafeIsValid(mainUI) then return nil end
    
        pcall(function()
            if mainUI.CanvasPanel_0 and SafeIsValid(mainUI.CanvasPanel_0) then
                StableESPCanvas = mainUI.CanvasPanel_0
            elseif mainUI.CanvasPanel_42 and SafeIsValid(mainUI.CanvasPanel_42) then
                StableESPCanvas = mainUI.CanvasPanel_42
            end
        end)
        return StableESPCanvas
    end
    
    local function UpdateStableCanvasTransform(pc, canvas)
        if not canvas or not SafeIsValid(canvas) then return end
        local success = false
        pcall(function()
            local SBL = SafeImport("SlateBlueprintLibrary")
            local geometry = canvas:GetCachedGeometry()
            if SBL and SBL.AbsoluteToLocal and geometry then
                local p0 = SBL.AbsoluteToLocal(geometry, FVector2D(0, 0))
                local p1 = SBL.AbsoluteToLocal(geometry, FVector2D(100, 100))
                if p0 and p1 then
                    StableCanvasScaleX = (p1.X - p0.X) / 100
                    StableCanvasScaleY = (p1.Y - p0.Y) / 100
                    StableCanvasOffsetX = p0.X
                    StableCanvasOffsetY = p0.Y
                    success = true
                end
            end
        end)
        if not success then
            pcall(function()
                local WLL = SafeImport("WidgetLayoutLibrary")
                local geometry = canvas:GetCachedGeometry()
                if WLL and WLL.ScreenToWidgetLocal and geometry then
                    local p0 = FVector2D(0, 0)
                    local p1 = FVector2D(0, 0)
                    WLL.ScreenToWidgetLocal(pc, geometry, FVector2D(0, 0), p0)
                    WLL.ScreenToWidgetLocal(pc, geometry, FVector2D(100, 100), p1)
                    StableCanvasScaleX = (p1.X - p0.X) / 100
                    StableCanvasScaleY = (p1.Y - p0.Y) / 100
                    StableCanvasOffsetX = p0.X
                    StableCanvasOffsetY = p0.Y
                    success = true
                end
            end)
        end
        if not success then
            local scale = 1.0
            pcall(function() scale = SafeImport("WidgetLayoutLibrary").GetViewportScale(pc) or 1.0 end)
            StableCanvasScaleX = 1.0 / scale
            StableCanvasScaleY = 1.0 / scale
            StableCanvasOffsetX = 0.0
            StableCanvasOffsetY = 0.0
        end
    end
    
    local function ProjectToStableCanvas(pc, worldLoc, canvas)
        if not pc or not worldLoc or not canvas then return nil end
        local screenPos = FVector2D(0, 0)
        local projected = false
        pcall(function() projected = pc:ProjectWorldLocationToScreen(worldLoc, screenPos, true) end)
        if not projected and (screenPos.X == 0 and screenPos.Y == 0) then return nil end
        UpdateStableCanvasTransform(pc, canvas)
        return FVector2D(
            screenPos.X * StableCanvasScaleX + StableCanvasOffsetX,
            screenPos.Y * StableCanvasScaleY + StableCanvasOffsetY
        )
    end
    
    local function AK_GetFirstWeaponInBackpack(WeaponManager)
        if not SafeIsValid(WeaponManager) then return nil, nil end
        local slots = {
            ESurviveWeaponPropSlot.SWPS_MainShootWeapon1,
            ESurviveWeaponPropSlot.SWPS_MainShootWeapon2,
            ESurviveWeaponPropSlot.SWPS_SubShootWeapon
        }
        for _, slot in ipairs(slots) do
            local w = WeaponManager:GetInventoryWeaponByPropSlot(slot)
            if SafeIsValid(w) then return w, slot end
        end
        return nil, nil
    end

    local function AK_GetCharacterWeapon(Character)
        if not SafeIsValid(Character) or not Character.GetWeaponManager then return nil, nil, 0, "" end
        local uWeaponManager = Character:GetWeaponManager()
        if not SafeIsValid(uWeaponManager) then return nil, nil, 0, "" end
        local curWeaponSlot = uWeaponManager:GetCurrentUsingPropSlot()
        local TargetWeapon = nil
        local bIsActiveHand = true
        if curWeaponSlot == ESurviveWeaponPropSlot.SWPS_None then
            TargetWeapon = AK_GetFirstWeaponInBackpack(uWeaponManager)
            bIsActiveHand = false
        else
            TargetWeapon = uWeaponManager:GetInventoryWeaponByPropSlot(curWeaponSlot)
        end
        if not SafeIsValid(TargetWeapon) or not TargetWeapon.GetItemDefineID then return nil, bIsActiveHand, 0, "" end
        local ItemDefineID = TargetWeapon:GetItemDefineID()
        if not ItemDefineID or not ItemDefineID.TypeSpecificID then return nil, bIsActiveHand, 0, "" end
        local TargetID = ItemDefineID.TypeSpecificID
        if TargetWeapon.IsUsingGrenadeLaunch and TargetWeapon:IsUsingGrenadeLaunch() then TargetID = 202100 end
        local TableData = CDataTable.GetTableData("Item", TargetID)
        if not TableData then return nil, bIsActiveHand, TargetID, "" end
        local itemIconPath = TableData.ItemWhiteIcon
        local itemName = TableData.ItemName or ""
        if type(itemName) == "number" then
            local LocUtil = _G.LocUtil or (package.loaded["client.common.LocUtil"] and SafeRequire("client.common.LocUtil"))
            if LocUtil and LocUtil.GetTextByID then itemName = LocUtil.GetTextByID(itemName) end
        end
        return itemIconPath, bIsActiveHand, TargetID, tostring(itemName)
    end

    local function StableBoxWidth(text)
        -- Reduced multiplier from 8 to 6 for smaller font size 10
        local width = 12 + (#tostring(text or "") * 6)
        return math.max(40, math.min(200, width))
    end
    
    local function QuantizeTagCoordinate(value)
        local step = TAG_PIXEL_QUANTIZE
        if not step or step <= 0 then return value end
        return math.floor((value / step) + 0.5) * step
    end
    
    local function GetExactTagPosition(entry, targetPos)
        -- Follow the current projected head position directly. Only pixel
        -- quantization remains, matching ESP Type 8's stable native anchor.
        -- No deadzone, interpolation, cached trail, or snake-like smoothing.
        if not targetPos then return nil end
        local x = QuantizeTagCoordinate(targetPos.X)
        local y = QuantizeTagCoordinate(targetPos.Y)
        entry.positionInitialized = true
        entry.smoothedX = x
        entry.smoothedY = y
        return FVector2D(x, y)
    end
    
    local function CreateStableEntityBox(enemy)
        local id = tostring(enemy)
        local cached = StableEntityBoxes[id]
        if cached and cached.root and SafeIsValid(cached.root) then return cached end
    
        local canvas = GetStableESPCanvas()
        if not canvas or not CGame or not CGame.NewObjectFromPath then return nil end
    
        local root = nil
        pcall(function() root = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
        if not root or not SafeIsValid(root) then return nil end
        local rootSlot = nil
        pcall(function() rootSlot = canvas:AddChildToCanvas(root) end)
        if not rootSlot or not SafeIsValid(rootSlot) then return nil end
    
        local border = nil
        pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", root) end)
        if not border or not SafeIsValid(border) then return nil end
        pcall(function()
            border:SetBrushColor(FLinearColor(0.005, 0.005, 0.008, 0.4))
            border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        local borderSlot = nil
        pcall(function() borderSlot = root:AddChildToCanvas(border) end)
        if not borderSlot or not SafeIsValid(borderSlot) then return nil end
        pcall(function() borderSlot:SetPosition(FVector2D(0, 0)); borderSlot:SetZOrder(0) end)
    
        local weaponIcon = nil
        pcall(function() weaponIcon = CGame:NewObjectFromPath("/Script/UMG.Image", root) end)
        local weaponIconSlot = nil
        if weaponIcon and SafeIsValid(weaponIcon) then
            pcall(function() weaponIconSlot = root:AddChildToCanvas(weaponIcon) end)
            if weaponIconSlot and SafeIsValid(weaponIconSlot) then
                pcall(function()
                    weaponIconSlot:SetSize(FVector2D(50, 30))
                    weaponIconSlot:SetZOrder(15)
                    weaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                end)
            end
        end

        local textBlock = nil
        pcall(function() textBlock = CGame:NewObjectFromPath("/Script/UMG.TextBlock", root) end)
        if not textBlock or not SafeIsValid(textBlock) then return nil end
        local textSlot = nil
        pcall(function() textSlot = root:AddChildToCanvas(textBlock) end)
        if not textSlot or not SafeIsValid(textSlot) then return nil end
        pcall(function()
            textSlot:SetAutoSize(true)
            textSlot:SetAlignment(FVector2D(0.5, 0.5))
            textSlot:SetZOrder(10)
            textBlock:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            if textBlock.Font then
                local font = textBlock.Font
                font.Size = 10
                textBlock:SetFont(font)
            end
        end)
    
        -- The track and fill are children of the same CanvasPanel as the tag,
        -- so the health bar stays attached to the bottom of the box.
        local healthTrack = nil
        pcall(function() healthTrack = CGame:NewObjectFromPath("/Script/UMG.Border", root) end)
        if healthTrack and SafeIsValid(healthTrack) then
            pcall(function()
                healthTrack:SetBrushColor(FLinearColor(0.03, 0.03, 0.03, 1.0))
                healthTrack:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
        end
        local healthTrackSlot = nil
        if healthTrack and SafeIsValid(healthTrack) then
            pcall(function() healthTrackSlot = root:AddChildToCanvas(healthTrack) end)
        end
    
        local healthBar = nil
        pcall(function() healthBar = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", root) end)
        if healthBar and SafeIsValid(healthBar) then
            pcall(function()
                healthBar:SetPercent(1.0)
                healthBar:SetFillColorAndOpacity(FLinearColor(0.0, 1.0, 0.0, 1.0))
                healthBar:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
        end
        local healthBarSlot = nil
        if healthBar and SafeIsValid(healthBar) then
            pcall(function() healthBarSlot = root:AddChildToCanvas(healthBar) end)
        end
    
        pcall(function()
            rootSlot:SetAlignment(FVector2D(0.5, 1.0))
            rootSlot:SetAutoSize(false)
            rootSlot:SetZOrder(10750)
            root:SetRenderTransformPivot(FVector2D(0.5, 1.0))
            root:SetRenderScale(FVector2D(1.0, 1.0))
            root:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end)
        cached = {
            root = root, rootSlot = rootSlot, border = border, borderSlot = borderSlot,
            text = textBlock, textSlot = textSlot,
            weaponIcon = weaponIcon, weaponIconSlot = weaponIconSlot,
            healthTrack = healthTrack, healthTrackSlot = healthTrackSlot,
            healthBar = healthBar, healthBarSlot = healthBarSlot,
            lastText = "", lastColor = "", lastHealth = -1, lastWeapon = "",
            lastWidth = 0, lastX = nil, lastY = nil, cachedPos = FVector2D(0, 0),
            smoothedX = 0, smoothedY = 0, positionInitialized = false,
            cachedBaseName = nil, cachedWeaponIconPath = nil, cachedWeaponName = "",
            lastWeaponCheck = 0
        }
        StableEntityBoxes[id] = cached
        return cached
    end
    
    local function UpdateStableEntityBox(pc, enemy, isBot, isKnocked, headLoc, distM)
        local entry = CreateStableEntityBox(enemy)
        if not entry then return false end
        local canvas = GetStableESPCanvas()
        local localPos = ProjectToStableCanvas(pc, headLoc, canvas)
        if not localPos then
            entry.root:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            return false
        end

        -- Cache slow-changing identity and weapon data. This follows Type 7's
        -- 1.5-second weapon cache instead of querying weapon objects every tick.
        local now = os.clock()
        local weaponIconPath, weaponName = nil, nil
        if _G.LexusConfig.ADESP_ShowWeapon then
            if entry.lastWeaponCheck == 0 or (now - entry.lastWeaponCheck) >= ADESP_WEAPON_CACHE_INTERVAL then
                local okWeapon, iconPath, _, _, name = pcall(function()
                    return AK_GetCharacterWeapon(enemy)
                end)
                if okWeapon then
                    entry.cachedWeaponIconPath = iconPath
                    entry.cachedWeaponName = (name and tostring(name)) or ""
                else
                    entry.cachedWeaponIconPath = nil
                    entry.cachedWeaponName = ""
                end
                entry.lastWeaponCheck = now
            end
            weaponIconPath = entry.cachedWeaponIconPath
            weaponName = entry.cachedWeaponName
        else
            entry.cachedWeaponIconPath = nil
            entry.cachedWeaponName = ""
            entry.lastWeaponCheck = now
        end

        local baseName = entry.cachedBaseName
        if not baseName then
            baseName = isBot and "BOT" or GetActualPlayerName(enemy)
            entry.cachedBaseName = baseName
        end
        local displayName = isKnocked and ("[KNOCK] " .. baseName) or baseName
        local weaponSuffix = (weaponName and weaponName ~= "") and (" | " .. tostring(weaponName)) or ""
        local distanceText = string.format("%s  [%dm]%s", displayName, math.max(0, math.floor(tonumber(distM) or 0)), weaponSuffix)
        -- Requested tag colors: Bot = cyan, Player = yellow, Knocked = red.
        local color = isBot and {R=0, G=255, B=255, A=255}
            or (isKnocked and {R=255, G=0, B=0, A=255} or {R=255, G=255, B=0, A=255})
        local colorKey = string.format("%d:%d:%d", color.R, color.G, color.B)
        
        local width = StableBoxWidth(distanceText)
        
        local stablePos = GetExactTagPosition(entry, localPos)
    
        local hp = tonumber(enemy.Health) or 0
        local maxHp = tonumber(enemy.HealthMax) or 100
        if maxHp <= 0 then maxHp = 100 end
        local hpPercent = math.max(0, math.min(1, hp / maxHp))
        local hpColor = (hpPercent < 0.3)
            and FLinearColor(1.0, 0.0, 0.0, 1.0)
            or ((hpPercent < 0.7)
                and FLinearColor(1.0, 1.0, 0.0, 1.0)
                or FLinearColor(0.0, 1.0, 0.0, 1.0))
    
        pcall(function()
            if entry.lastWidth ~= width then
                entry.rootSlot:SetSize(FVector2D(width, TAG_BOX_HEIGHT))
                entry.borderSlot:SetSize(FVector2D(width, TAG_BOX_HEIGHT))
                
                -- Text is always centered in the box now
                entry.textSlot:SetPosition(FVector2D(width * 0.5, 10))

                if entry.healthTrackSlot then
                    entry.healthTrackSlot:SetPosition(FVector2D(3, TAG_HEALTH_TRACK_Y))
                    entry.healthTrackSlot:SetSize(FVector2D(width - 6, TAG_HEALTH_TRACK_HEIGHT))
                    entry.healthTrackSlot:SetZOrder(11)
                end
                if entry.healthBarSlot then
                    entry.healthBarSlot:SetPosition(FVector2D(3, TAG_HEALTH_TRACK_Y))
                    entry.healthBarSlot:SetSize(FVector2D(width - 6, TAG_HEALTH_TRACK_HEIGHT))
                    entry.healthBarSlot:SetZOrder(12)
                end
                entry.lastWidth = width
            end

            -- Update Weapon Icon
            if entry.weaponIcon and entry.weaponIconSlot then
                if weaponIconPath and weaponIconPath ~= "" then
                    if entry.lastWeapon ~= weaponIconPath then
                        pcall(function()
                            local tex = slua.loadObject(weaponIconPath)
                            if tex then
                                if entry.weaponIcon.SetBrushFromTexture then
                                    entry.weaponIcon:SetBrushFromTexture(tex)
                                elseif entry.weaponIcon.SetBrushResourceObject then
                                    entry.weaponIcon:SetBrushResourceObject(tex)
                                end
                            end
                        end)
                        entry.lastWeapon = weaponIconPath
                    end
                    entry.weaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    -- Positioned centered ABOVE the tag box with a small gap.
                    entry.weaponIconSlot:SetPosition(FVector2D((width - 50) * 0.5, -23))
                else
                    entry.weaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                end
            end
            local tagVisibility = _G.LexusConfig.ADESP_ShowTags and UEnums.ESlateVisibility.SelfHitTestInvisible or UEnums.ESlateVisibility.Collapsed
            entry.border:SetWidgetVisibility(tagVisibility)
            entry.text:SetWidgetVisibility(tagVisibility)
            
            if _G.LexusConfig.ADESP_ShowTags then
                if entry.lastText ~= distanceText then
                    entry.text:SetText(distanceText)
                    entry.lastText = distanceText
                end
                if entry.lastColor ~= colorKey then
                    entry.text:SetColorAndOpacity(FSlateColor(FLinearColor(color.R/255, color.G/255, color.B/255, 1.0)))
                    entry.lastColor = colorKey
                end
                if entry.healthBar and entry.lastHealth ~= hpPercent then
                    entry.healthBar:SetPercent(hpPercent)
                    entry.healthBar:SetFillColorAndOpacity(hpColor)
                    entry.healthBar:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    entry.lastHealth = hpPercent
                end
                if entry.healthTrack then
                    entry.healthTrack:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                end
            else
                if entry.healthBar then entry.healthBar:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                if entry.healthTrack then entry.healthTrack:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
            end
            if entry.lastX ~= stablePos.X or entry.lastY ~= stablePos.Y then
                entry.cachedPos.X = stablePos.X
                entry.cachedPos.Y = stablePos.Y
                entry.rootSlot:SetPosition(entry.cachedPos)
                entry.lastX = stablePos.X
                entry.lastY = stablePos.Y
            end
            entry.root:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        return true
    end
    local function RemoveStableEntityBox(id, entry)
        if entry and entry.root and SafeIsValid(entry.root) then
            pcall(function()
                entry.root:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                if entry.root.RemoveFromParent then entry.root:RemoveFromParent() end
            end)
        end
        StableEntityBoxes[id] = nil
    end
    
    local function HideNativeLabelControls(widget)
        if not widget then return end
        local collapsed = UEnums.ESlateVisibility.Collapsed
        pcall(function()
            if widget.TextBlock_PlayerName then widget.TextBlock_PlayerName:SetWidgetVisibility(collapsed) end
            if widget.Text_PlayerName then widget.Text_PlayerName:SetWidgetVisibility(collapsed) end
            if widget.Image_Name_BG then widget.Image_Name_BG:SetWidgetVisibility(collapsed) end
            if widget.Image_TeamBG then widget.Image_TeamBG:SetWidgetVisibility(collapsed) end
        end)
    end
    
    local function CreateOrGetNativeHeadWidget(enemy)
        local id = tostring(enemy)
        local entry = EntityHeadWidgets[id]
        if entry and entry.widget and SafeIsValid(entry.widget) then
            return entry
        end
    
        local widget = nil
        local ok = pcall(function()
            widget = slua.loadUI(HEAD_WIDGET_BP)
            if not widget or not SafeIsValid(widget) then
                widget = nil
                return
            end
    
            -- Exact verified V4 container path and widget asset.
            SafeRequire("game_frontend_hud").AddToContainer(UIContainers.Top, widget, 10700)
            widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
        end)
    
        if not ok or not widget then
            return nil
        end
    
        entry = {
            widget = widget,
            lastText = "",
            lastColor = "",
            lastX = nil,
            lastY = nil
        }
        EntityHeadWidgets[id] = entry
        return entry
    end
    
    local function UpdateNativeHeadWidget(pc, enemy, isBot, isKnocked, headLoc, screenPos, distM)
        local entry = CreateOrGetNativeHeadWidget(enemy)
        if not entry then return false end
    
        local widget = entry.widget
        local labelColor
        if isBot then
            labelColor = {R = 0, G = 255, B = 255, A = 255} -- cyan
        elseif isKnocked then
            labelColor = {R = 255, G = 0, B = 0, A = 255} -- red
        else
            labelColor = {R = 255, G = 255, B = 0, A = 255} -- yellow
        end
        local baseName = isBot and "BOT" or GetActualPlayerName(enemy)
        -- Verified V5 convention for the downed state.
        local displayName = isKnocked and ("[KNOCK] " .. baseName) or baseName
    
        local ok = pcall(function()
            local slot = SafeImport("WidgetLayoutLibrary").SlotAsCanvasSlot(widget)
            if not slot then return end
    
            -- Verified V4 contract: one ProjectWorldLocationToScreen result,
            -- then one CanvasSlot position/alignment for the native head widget.
            -- Explicit fixed anchors prevent the widget from inheriting a stale
            -- parent-relative anchor while the camera moves.
            slot:SetAnchors(FAnchors(0, 0, 0, 0))
            -- Bottom-center alignment matches the ESP Base head-top placement.
            slot:SetAlignment(FVector2D(0.5, 1.0))
    
            -- Keep the verified native blueprint dimensions. The previous
            -- distance-dependent SetSize/RenderScale combination changed the
            -- widget geometry and produced side drift at range.
            local x = math.floor(screenPos.X + 0.5)
            local y = math.floor(screenPos.Y + 0.5)
            if entry.lastX ~= x or entry.lastY ~= y then
                slot:SetPosition(FVector2D(x, y))
                entry.lastX = x
                entry.lastY = y
            end
    
            -- Keep one fixed widget scale so the CanvasSlot remains centered on
            -- the same ESP Base head projection at every distance.
            widget:SetRenderScale(FVector2D(1.0, 1.0))
            SetNativeText(widget, displayName)
            SetNativeColor(widget, labelColor)
            SetNativeHealth(widget, enemy)
            widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            entry.lastText = displayName
        end)
    
        return ok and entry.lastText == displayName
    end
    
    local function RemoveNativeHeadWidget(id, entry)
        if entry and entry.widget and SafeIsValid(entry.widget) then
            pcall(function()
                entry.widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                if entry.widget.RemoveFromParent then
                    entry.widget:RemoveFromParent()
                end
            end)
        end
        EntityHeadWidgets[id] = nil
    end
    
    -- ==========================================
    -- SECTION 6: REFERENCE-STYLE COUNTER
    -- ==========================================
    
        -- The old BTN_BP and native head-widget roots are intentionally not used
        -- here. The counter uses dedicated UMG Border/TextBlock layers so it can
        -- never inherit enemy name-tag rendering.
    local CounterBackgroundWidgets = {}
    local CounterBorderRoot = nil
    local CounterBorderSlot = nil
    local CounterBorderLayers = {}
    local CounterTextBlock = nil
    local CounterTextSlot = nil
    -- Counter geometry used by the dedicated counter overlay.
    local CounterAnchorX = nil
    local CounterAnchorY = nil
    local COUNTER_TEXT_SHIFT_X = 12
    local COUNTER_GLOBAL_SHIFT_X = -148
    -- Reference-style banner: solid center behind the full text, with
    -- progressively fading ends and a restrained dark/neon outer edge.
    local COUNTER_Y = 46
    local COUNTER_HEIGHT = 30
    local COUNTER_LAYERS = {
        {width = 290, height = 36, r = 0.005, g = 0.005, b = 0.01, a = 0.75, z = 10490}
    }
    
    local function SetCounterChildVisibility(widget, childName, visibility)
        pcall(function()
            local child = widget and widget[childName]
            if child and child.SetWidgetVisibility then
                child:SetWidgetVisibility(visibility)
            end
        end)
    end
    
    local function HideCounterNonBackgroundControls(widget)
        local collapsed = UEnums.ESlateVisibility.Collapsed
        SetCounterChildVisibility(widget, "TextBlock_PlayerName", collapsed)
        SetCounterChildVisibility(widget, "Text_PlayerName", collapsed)
        SetCounterChildVisibility(widget, "ProgressBar_HP", collapsed)
        SetCounterChildVisibility(widget, "ProgressBar_0", collapsed)
        SetCounterChildVisibility(widget, "Image_WeaponIcon", collapsed)
        SetCounterChildVisibility(widget, "Image_Weapon", collapsed)
        SetCounterChildVisibility(widget, "TextBlock_TeamID", collapsed)
        SetCounterChildVisibility(widget, "TextBlock_PlayerTeamID", collapsed)
    end
    
    local function SetCounterBackgroundColor(widget, color)
        pcall(function()
            -- These are the verified image/brush controls used by V4/V5.
            if widget.Image_Name_BG then
                widget.Image_Name_BG:SetColorAndOpacity(color)
            end
            if widget.Image_TeamBG then
                widget.Image_TeamBG:SetColorAndOpacity(color)
            end
        end)
    end
    
    local function ShowCounterTextControls(widget)
        local visible = UEnums.ESlateVisibility.SelfHitTestInvisible
        -- Use one native text alias only during positioning verification.
        if widget.TextBlock_PlayerName then
            SetCounterChildVisibility(widget, "TextBlock_PlayerName", visible)
            SetCounterChildVisibility(widget, "Text_PlayerName", UEnums.ESlateVisibility.Collapsed)
        elseif widget.Text_PlayerName then
            SetCounterChildVisibility(widget, "Text_PlayerName", visible)
            SetCounterChildVisibility(widget, "TextBlock_PlayerName", UEnums.ESlateVisibility.Collapsed)
        end
    end
    
    local function ApplyCounterTextAppearance(widget)
        pcall(function()
            local textColor = FSlateColor(FLinearColor(1.0, 1.0, 1.0, 1.0))
            if widget.TextBlock_PlayerName then
                widget.TextBlock_PlayerName:SetColorAndOpacity(textColor)
                local fontInfo = widget.TextBlock_PlayerName.Font
                if fontInfo then
                    fontInfo.Size = 15
                    widget.TextBlock_PlayerName:SetFont(fontInfo)
                end
                if widget.TextBlock_PlayerName.SetRenderTranslation then
                    widget.TextBlock_PlayerName:SetRenderTranslation(FVector2D(COUNTER_TEXT_SHIFT_X, 0))
                end
            end
            if widget.Text_PlayerName then
                widget.Text_PlayerName:SetColorAndOpacity(textColor)
                local fontInfo = widget.Text_PlayerName.Font
                if fontInfo then
                    fontInfo.Size = 15
                    widget.Text_PlayerName:SetFont(fontInfo)
                end
                if widget.Text_PlayerName.SetRenderTranslation then
                    widget.Text_PlayerName:SetRenderTranslation(FVector2D(COUNTER_TEXT_SHIFT_X, 0))
                end
            end
        end)
    end
    
    local function StretchCounterBackground(widget)
        -- Keep the native brush at its own width. Each widget is already a full
        -- canvas layer; scaling the child image caused the red strip to cross the
        -- text. The width/fade is controlled by the separate layer widgets.
        pcall(function()
            local identityScale = FVector2D(1.0, 1.0)
            if widget.Image_Name_BG and widget.Image_Name_BG.SetRenderScale then
                widget.Image_Name_BG:SetRenderScale(identityScale)
            end
            if widget.Image_TeamBG and widget.Image_TeamBG.SetRenderScale then
                widget.Image_TeamBG:SetRenderScale(identityScale)
            end
        end)
    end
    
    local function PositionCounterLayer(widget, width, height)
        local slot = SafeImport("WidgetLayoutLibrary").SlotAsCanvasSlot(widget)
        if not slot then return false end
    
        slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0))
        slot:SetAlignment(FVector2D(0.5, 0))
        slot:SetPosition(FVector2D(COUNTER_GLOBAL_SHIFT_X, COUNTER_Y))
        slot:SetSize(FVector2D(width, height))
        widget:SetRenderScale(FVector2D(1.0, 1.0))
        return true
    end
    
    local function CreateCounterBackgroundLayer(layer)
        local widget = nil
        local ok = pcall(function()
            widget = slua.loadUI(HEAD_WIDGET_BP)
            if not widget or not SafeIsValid(widget) then
                widget = nil
                return
            end
    
            SafeRequire("game_frontend_hud").AddToContainer(UIContainers.Top, widget, layer.z)
            HideCounterNonBackgroundControls(widget)
            SetCounterBackgroundColor(widget, FLinearColor(layer.r, layer.g, layer.b, layer.a))
            StretchCounterBackground(widget)
            if not PositionCounterLayer(widget, layer.width, layer.height) then
                widget = nil
                return
            end
            widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    
        if ok and widget then return widget end
        return nil
    end
    
    local function SetCounterText(widget, text)
        if not widget or not SafeIsValid(widget) then return false end
    
        if widget == CounterTextBlock then
            local directOK = pcall(function()
                widget:SetText(text)
            end)
            return directOK
        end
    
        local ok = pcall(function()
            -- Keep the text layer independent from every red background layer.
            SetCounterBackgroundColor(widget, FLinearColor(0, 0, 0, 0))
            ShowCounterTextControls(widget)
            if widget.TextBlock_PlayerName then
                widget.TextBlock_PlayerName:SetText(text)
            end
            if not widget.TextBlock_PlayerName and widget.Text_PlayerName then
                widget.Text_PlayerName:SetText(text)
            end
            ApplyCounterTextAppearance(widget)
        end)
        return ok
    end
    
    local function CreateCounterTextLayer()
        local widget = nil
        local ok = pcall(function()
            widget = slua.loadUI(HEAD_WIDGET_BP)
            if not widget or not SafeIsValid(widget) then
                widget = nil
                return
            end
    
            SafeRequire("game_frontend_hud").AddToContainer(UIContainers.Top, widget, 10500)
            HideCounterNonBackgroundControls(widget)
            PositionCounterLayer(widget, 320, COUNTER_HEIGHT)
            widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            -- The first real Player/Bot/Dist string is written by UpdateAllESP;
            -- do not display hardcoded bootstrap counts.
            SetCounterText(widget, "")
        end)
    
        if ok and widget then return widget end
        return nil
    end
    
    local function RemoveCounterBorderOverlay()
        pcall(function()
            if CounterBorderRoot and SafeIsValid(CounterBorderRoot) then
                CounterBorderRoot:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                if CounterBorderRoot.RemoveFromParent then CounterBorderRoot:RemoveFromParent() end
            end
        end)
        CounterBorderRoot = nil
        CounterBorderSlot = nil
        CounterBorderLayers = {}
        CounterTextBlock = nil
        CounterTextSlot = nil
    end
    
    local function UpdateCounterVisualEffects(realCount, botCount)
        if not CounterBorderRoot or not SafeIsValid(CounterBorderRoot) then return end
        
        pcall(function()
            -- Dynamic color based on threat level
            local r, g, b = 0.0, 1.0, 0.0 -- Zone Clear (Green)
            
            if realCount > 0 or botCount > 0 then
                r, g, b = 1.0, 0.0, 0.0 -- Enemy/Bot Counter (Red)
            end
            
            -- Keep all counter text white for clear contrast. The status color
            -- is applied only to the background border below.
            if CounterTextBlock and SafeIsValid(CounterTextBlock) then
                CounterTextBlock:SetColorAndOpacity(FSlateColor(FLinearColor(1.0, 1.0, 1.0, 1.0)))
            end
            
            -- Apply status color only to the background border
            for _, item in ipairs(CounterBorderLayers) do
                if item.border and SafeIsValid(item.border) then
                    item.border:SetBrushColor(FLinearColor(r, g, b, 0.6))
                end
            end
        end)
    end

    local function UpdateCounterBorderOverlay(pc)
        if not CounterBorderRoot or not SafeIsValid(CounterBorderRoot) then return false end
        local canvas = GetStableESPCanvas()
        if not canvas or not SafeIsValid(canvas) then return false end
        local width, height = 0, 0
        pcall(function()
            local geometry = canvas:GetCachedGeometry()
            if geometry and geometry.GetLocalSize then
                local size = geometry:GetLocalSize()
                if size then width, height = size.X, size.Y end
            end
        end)
        if width <= 200 then
            pcall(function()
                local size = SafeImport("WidgetLayoutLibrary").GetViewportSize(pc)
                if size then width, height = size.X, size.Y end
            end)
        end
        if width <= 200 then return false end
    
        -- Use the actual banner center-bottom in the stable ESP canvas, not the
        -- viewport center or the text slot's shifted position.
        CounterAnchorX = (width * 0.5) + COUNTER_GLOBAL_SHIFT_X
        CounterAnchorY = COUNTER_Y + COUNTER_HEIGHT
    
        pcall(function()
            CounterBorderSlot:SetPosition(FVector2D(0, 0))
            CounterBorderSlot:SetSize(FVector2D(width, height))
            for _, item in ipairs(CounterBorderLayers) do
                local x = ((width - item.width) * 0.5) + COUNTER_GLOBAL_SHIFT_X
                item.slot:SetPosition(FVector2D(x, COUNTER_Y))
                item.slot:SetSize(FVector2D(item.width, item.height))
            end
            if CounterTextSlot and SafeIsValid(CounterTextSlot) then
                CounterTextSlot:SetPosition(FVector2D((width * 0.5) + COUNTER_GLOBAL_SHIFT_X + COUNTER_TEXT_SHIFT_X, COUNTER_Y + (COUNTER_HEIGHT * 0.5)))
            end
        end)
        return true
    end
    
    local function CreateCounterBorderOverlay(pc)
        if CounterBorderRoot and SafeIsValid(CounterBorderRoot) then
            UpdateCounterBorderOverlay(pc)
            return true
        end
        local canvas = GetStableESPCanvas()
        if not canvas or not CGame or not CGame.NewObjectFromPath then return false end
    
        local root = nil
        pcall(function() root = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas) end)
        if not root or not SafeIsValid(root) then return false end
        local rootSlot = nil
        pcall(function() rootSlot = canvas:AddChildToCanvas(root) end)
        if not rootSlot or not SafeIsValid(rootSlot) then return false end
        pcall(function()
            rootSlot:SetAlignment(FVector2D(0, 0))
            rootSlot:SetZOrder(10480)
            root:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    
        local layers = {}
        for _, layer in ipairs(COUNTER_LAYERS) do
            local border = nil
            pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", root) end)
            if border and SafeIsValid(border) then
                pcall(function()
                    border:SetBrushColor(FLinearColor(layer.r, layer.g, layer.b, layer.a))
                    border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                end)
                local slot = nil
                pcall(function() slot = root:AddChildToCanvas(border) end)
                if slot and SafeIsValid(slot) then
                    pcall(function() slot:SetZOrder(layer.z - 10480) end)
                    table.insert(layers, {slot = slot, border = border, width = layer.width, height = layer.height})
                end
            end
        end
    
        local textBlock = nil
        local textSlot = nil
        pcall(function() textBlock = CGame:NewObjectFromPath("/Script/UMG.TextBlock", root) end)
        if textBlock and SafeIsValid(textBlock) then
            pcall(function() textSlot = root:AddChildToCanvas(textBlock) end)
            if textSlot and SafeIsValid(textSlot) then
                pcall(function()
                    textSlot:SetAutoSize(true)
                    textSlot:SetAlignment(FVector2D(0.5, 0.5))
                    textSlot:SetZOrder(1000)
                    textBlock:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    textBlock:SetColorAndOpacity(FSlateColor(FLinearColor(1.0, 1.0, 1.0, 1.0)))
                    if textBlock.Font then
                        local font = textBlock.Font
                        font.Size = 15
                        textBlock:SetFont(font)
                    end
                end)
            else
                textBlock = nil
                textSlot = nil
            end
        end
    
        CounterBorderRoot = root
        CounterBorderSlot = rootSlot
        CounterBorderLayers = layers
        CounterTextBlock = textBlock
        CounterTextSlot = textSlot
        return UpdateCounterBorderOverlay(pc)
    end
    
    function _G.RemoveCounterVisualLayers()
        RemoveCounterBorderOverlay()
        pcall(function()
            if EnemyCounterWidget and SafeIsValid(EnemyCounterWidget) then
                EnemyCounterWidget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                if EnemyCounterWidget.RemoveFromParent then
                    EnemyCounterWidget:RemoveFromParent()
                end
            end
            EnemyCounterWidget = nil
    
            for _, widget in pairs(CounterBackgroundWidgets) do
                if widget and SafeIsValid(widget) then
                    widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    if widget.RemoveFromParent then widget:RemoveFromParent() end
                end
            end
            CounterBackgroundWidgets = {}
        end)
    end
    
    local function CreateEnemyCounterWidget()
        if EnemyCounterWidget and SafeIsValid(EnemyCounterWidget) then
            return EnemyCounterWidget
        end
    
        RemoveCounterVisualLayers()
    
        -- The counter must use only its dedicated CanvasPanel. Do not fall back
        -- to the native head-widget blueprint: that blueprint is an enemy name
        -- tag and can cover the screen during warning/state changes.
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        local borderOK = CreateCounterBorderOverlay(pc)
        if not borderOK or not CounterTextBlock or not SafeIsValid(CounterTextBlock) then
            RemoveCounterVisualLayers()
            return nil
        end

        -- The text block is a child of the dedicated counter canvas.
        EnemyCounterWidget = CounterTextBlock
        if not EnemyCounterWidget or not SafeIsValid(EnemyCounterWidget) then
            RemoveCounterVisualLayers()
            return nil
        end
    
        return EnemyCounterWidget
    end
    
    -- ==========================================
    -- SECTION 8: MAIN LOOP
    -- ==========================================
    
    local GameplayData = SafeRequire("GameLua.GameCore.Data.GameplayData")
    local StartEnemyCounter
    local function UpdateAllESP()
        if not HasPanelAuthorization() then
            return
        end
        
        if not _G.LexusConfig or not _G.LexusConfig.ADESP_Enable then 
            return 
        end
        pcall(function()
            local pc = GameplayData and GameplayData.GetPlayerController()
            if not SafeIsValid(pc) then return end

            local now = os.clock()
            if (now - ADESP_LAST_UPDATE_TIME) < ADESP_UPDATE_INTERVAL then return end
            ADESP_LAST_UPDATE_TIME = now
            -- A new match normally supplies a new controller. Soft-reset only
            -- Lua references and collapse old widgets; do not mass-remove them
            -- while the lobby/loading screen is active.
            if ADESP_ACTIVE_PC and ADESP_ACTIVE_PC ~= pc then
                ADESP_TIMER_GENERATION = ADESP_TIMER_GENERATION + 1
                for _, entry in pairs(EntityHeadWidgets) do
                    if entry and entry.widget and SafeIsValid(entry.widget) then
                        pcall(function() entry.widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                    end
                end
                for _, entry in pairs(StableEntityBoxes) do
                    if entry and entry.root and SafeIsValid(entry.root) then
                        pcall(function() entry.root:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                    end
                end
                EntityHeadWidgets = {}
                StableEntityBoxes = {}
                StableESPCanvas = nil
                _G.ADESP_LastCounterText = ""
                EnemyCounterRunning = false
                EnemyCounterTimer = nil
            end
            ADESP_ACTIVE_PC = pc
            if not EnemyCounterRunning and StartEnemyCounter then
                StartEnemyCounter()
            end

            local localPlayer = pc:GetPlayerCharacterSafety()
            if not SafeIsValid(localPlayer) then return end
            -- Bind SnapLine to the existing stable ESP canvas and helpers.
            if PlayerMapMarker then
                PlayerMapMarker.ESPCanvas = StableESPCanvas or GetStableESPCanvas()
                PlayerMapMarker.ScreenPixelToCanvasLocal = function(screenPC, pixel)
                    local canvas = PlayerMapMarker.ESPCanvas
                    if not canvas or not pixel then return FVector2D(0, 0) end
                    UpdateStableCanvasTransform(screenPC, canvas)
                    return FVector2D(pixel.X * StableCanvasScaleX + StableCanvasOffsetX,
                        pixel.Y * StableCanvasScaleY + StableCanvasOffsetY)
                end
                PlayerMapMarker.IsAI = function(character)
                    return IsAIPawn(character)
                end
            end
    
            local allChars = {}
            local okChars, rawChars = pcall(function()
                if GameplayData.GetAllPlayerCharacters then
                    return GameplayData.GetAllPlayerCharacters()
                end
                return nil
            end)
            if okChars and type(rawChars) == "table" then
                allChars = rawChars
            elseif GameplayData.GameCharacters then
                pcall(function()
                    for _, char in pairs(GameplayData.GameCharacters) do
                        table.insert(allChars, char)
                    end
                end)
            end
            
            local myTeamId = localPlayer.TeamID or 0
            local myLoc = localPlayer:K2_GetActorLocation()
    
            local botCount, realCount = 0, 0
            local nearestDist = 9999
            local activeIDs = {}
            local WLL = SafeImport("WidgetLayoutLibrary")
            local viewportSize = WLL.GetViewportSize(pc)
            local centerX = viewportSize.X / 2
    
            local activeSnapLines = {}
            local snapFromX, snapFromY = nil, nil
            if PlayerMapMarker and PlayerMapMarker.bUseSnapLines and PlayerMapMarker.ESPCanvas then
                snapFromX, snapFromY = PlayerMapMarker.GetSnapLineStartPos(pc)
            end

            for _, enemy in pairs(allChars) do
                if SafeIsValid(enemy) and enemy ~= localPlayer then
                    local enemyTeamId = enemy.TeamID or 0
    
                    if enemyTeamId ~= myTeamId and IsPawnRenderable(enemy) then
                        local loc = enemy:K2_GetActorLocation()
                        local distRaw = FVector.Dist(myLoc, loc)
                        local distM = math.floor(distRaw / 100)
                        if distM <= ADESP_MAX_DISTANCE_M then
                            local isBot = IsAIPawn(enemy)
                        local isKnocked = IsPawnKnocked(enemy)
                        local id = tostring(enemy)
    
                        if isBot then
                            botCount = botCount + 1
                        else
                            realCount = realCount + 1
                        end
    
                        if distRaw < nearestDist then
                            nearestDist = distRaw
                        end
    
                        -- One shared head-bone anchor drives the name tag, distance,
                        -- and health bar.
                        local headLoc = GetHeadWorldPosition(enemy)
                        if not headLoc then
                            headLoc = FVector(loc.X, loc.Y, loc.Z + 100)
                        end
                        local projected = FVector2D(0, 0)
    
                        local projectionOK = false
                        pcall(function() projectionOK = pc:ProjectWorldLocationToScreen(headLoc, projected) end)
    
                        if projectionOK then
                            local visible = projected
                                and projected.X >= 0
                                and projected.Y >= 0
                                and projected.X <= viewportSize.X
                                and projected.Y <= viewportSize.Y
    
                            if visible then
                                if PlayerMapMarker and PlayerMapMarker.bUseSnapLines and snapFromX and snapFromY then
                                    local snapKey = tostring(enemy)
                                    activeSnapLines[snapKey] = true
                                    local canvasPos = PlayerMapMarker.ScreenPixelToCanvasLocal(pc, projected)
                                    PlayerMapMarker.UpdateSnapLine(snapKey, canvasPos, true, snapFromX, snapFromY, enemy, pc)
                                end
                            end
                            if visible and (_G.LexusConfig.ADESP_ShowTags or _G.LexusConfig.ADESP_ShowWeapon) then
                                activeIDs[id] = true
                                -- Name and distance share one smoothed screen-space tag.
                                -- This removes the second world-space label that shakes.
                                local stableBoxOK = UpdateStableEntityBox(pc, enemy, isBot, isKnocked, headLoc, distM)
                                if stableBoxOK then
                                    local nativeEntry = EntityHeadWidgets[id]
                                    if nativeEntry and nativeEntry.widget then
                                        nativeEntry.widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                                    end
                                else
                                    -- Fallback only when the stable CanvasPanel is unavailable.
                                    UpdateNativeHeadWidget(pc, enemy, isBot, isKnocked, headLoc, projected, distM)
                                    UpdateDistanceText(pc, enemy, distM, GetDynamicScale(distM), headLoc)
                                    UpdateHealthBar(pc, enemy, GetDynamicScale(distM), headLoc)
                                end
                            end
                        end
                        end
                    end
                end
            end

            if PlayerMapMarker and PlayerMapMarker.bUseSnapLines then
                for snapKey in pairs(PlayerMapMarker.SnapLineWidgets or {}) do
                    if not activeSnapLines[snapKey] then PlayerMapMarker.RemoveSnapLine(snapKey) end
                end
            elseif PlayerMapMarker and PlayerMapMarker.ClearAllSnapLines then
                PlayerMapMarker.ClearAllSnapLines()
            end

            if _G.LexusConfig.ADESP_ShowCounter then
                UpdateCounterBorderOverlay(pc)
                UpdateCounterVisualEffects(realCount, botCount)
                
                -- The loop already refreshes at 20 Hz. Keep one decimal metre so
                -- close movement is visible instead of appearing frozen until a
                -- full metre boundary is crossed.
                local nearest = (nearestDist == 9999) and 0 or (math.floor(nearestDist / 10) / 10)
                local newText = ""
                if realCount == 0 and botCount == 0 then
                    newText = " ZONE CLEAR  |  @NEXA"
                else
                    newText = string.format("Player: %d   Bot: %d   Dist: %.1fm", realCount, botCount, nearest)
                end
                
                local textChanged = newText ~= _G.ADESP_LastCounterText
                if textChanged then
                    _G.ADESP_LastCounterText = newText
                end
                -- Retry creation if the UI was not ready during a lobby/match
                -- transition, and apply the status colour after creation so the
                -- first warning frame is red instead of the default dark banner.
                local widget = nil
                if textChanged or not EnemyCounterWidget or not SafeIsValid(EnemyCounterWidget) then
                    widget = CreateEnemyCounterWidget()
                    if widget and SafeIsValid(widget) then
                        SetCounterText(widget, newText)
                    end
                end
                UpdateCounterVisualEffects(realCount, botCount)
            else
                _G.RemoveCounterVisualLayers()
            end

            -- Stale cleanup is throttled and intentionally limited to a small
            -- batch, matching Type 7's non-aggressive lifecycle behavior.
            if (now - ADESP_LAST_STALE_CLEANUP_TIME) >= ADESP_STALE_CLEANUP_INTERVAL then
                ADESP_LAST_STALE_CLEANUP_TIME = now
                local cleanupBudget = 4
                for id, entry in pairs(EntityHeadWidgets) do
                    if not activeIDs[id] then
                        RemoveNativeHeadWidget(id, entry)
                        cleanupBudget = cleanupBudget - 1
                        if cleanupBudget <= 0 then break end
                    end
                end
                cleanupBudget = 4
                for id, entry in pairs(StableEntityBoxes) do
                    if not activeIDs[id] then
                        RemoveStableEntityBox(id, entry)
                        cleanupBudget = cleanupBudget - 1
                        if cleanupBudget <= 0 then break end
                    end
                end
            end
        end)
    end
    
    -- ==========================================
    -- SECTION 8: START
    -- ==========================================
    
    StartEnemyCounter = function()
        if EnemyCounterRunning then return end
        EnemyCounterRunning = true
        local timerGeneration = ADESP_TIMER_GENERATION
    
        local function initTimer()
            if timerGeneration ~= ADESP_TIMER_GENERATION then return end
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if SafeIsValid(pc) and pc.AddGameTimer then
                -- The timer only schedules work; UpdateAllESP itself is
                -- throttled to the Type 7-style interval.
                local timer_ok, timer_handle = PCall(function()
                    return pc:AddGameTimer(ADESP_UPDATE_INTERVAL, true, function()
                    if timerGeneration == ADESP_TIMER_GENERATION then
                        UpdateAllESP()
                    end
                    end)
                end)
                EnemyCounterTimer = timer_ok and timer_handle or nil
            else
                local fb = slua_GameFrontendHUD or Game
                if fb and SafeIsValid(fb) and fb.AddGameTimer then
                    PCall(function() fb:AddGameTimer(1.0, false, initTimer) end)
                else
                    EnemyCounterRunning = false
                end
            end
        end
    
        initTimer()
    end
    

    _G.ADESP_Initialized = true
    
    -- Export cleanup function to handle match transitions
    _G.ClearAllADESPWidgets = function()
        pcall(function()
            -- In this environment the controller owns the repeating timer.
            -- Invalidate its generation so an old-match callback becomes a
            -- no-op instead of touching lobby objects.
            ADESP_TIMER_GENERATION = ADESP_TIMER_GENERATION + 1
            EnemyCounterTimer = nil
            EnemyCounterRunning = false
            ADESP_ACTIVE_PC = nil
            
            -- Remove all active widgets
            for id, entry in pairs(EntityHeadWidgets) do
                RemoveNativeHeadWidget(id, entry)
            end
            for id, entry in pairs(StableEntityBoxes) do
                RemoveStableEntityBox(id, entry)
            end
            
            -- Do not remove the shared canvas during a transition; collapsing
            -- children is safer and prevents lobby-loading freezes.
            StableESPCanvas = nil
            
            _G.RemoveCounterVisualLayers()
            _G.ADESP_LastCounterText = ""
            
            EntityHeadWidgets = {}
            StableEntityBoxes = {}
            _G.ADESP_Initialized = false
            _G.ADESP_Running = false
        end)
    end

    if _G.LexusConfig and _G.LexusConfig.ADESP_Enable then
        if StartEnemyCounter then StartEnemyCounter() end
    end
end

function MainLoop() 
    local isAuthorized = HasPanelAuthorization()

    -- Single fail-closed runtime gate: no feature loop, visual work, hook work,
    -- or menu re-entry may continue until the canonical panel has authorized.
    if not isAuthorized then
        -- Keep persisted preferences intact during lobby/match revalidation.
        -- The early return below still blocks all feature work until authorization.
        if _G.ADESP_Running then
            if _G.ClearAllADESPWidgets then _G.ClearAllADESPWidgets() end
            _G.ADESP_Running = false
        end
        if _G.HideModMenuTab then PCall(_G.HideModMenuTab) end
        return
    end


    if _G.LexusConfig and _G.LexusConfig.ADESP_Enable then
        if not _G.ADESP_Running then
            if _G.InitializeADESPSystem then _G.InitializeADESPSystem() end
            _G.ADESP_Running = true
        end
    else
        if _G.ADESP_Running then
            if _G.ClearAllADESPWidgets then _G.ClearAllADESPWidgets() end
            _G.ADESP_Running = false
        end
    end

    PCall(function() if ApplyTPPView then ApplyTPPView() end end)
    -- if false then -- [BYPASSED] return end -- [BYPASSED]

    -- =====================================================================
    -- HỆ THỐNG LẤY HWID GỐC & ĐỔI HWID ẢO (SPOOFER) CHỐNG BAN
    -- =====================================================================
    PCall(function()
        local SystemLib = SafeImport("KismetSystemLibrary")
        if SystemLib and not _G.FakeHWID_Hooked then
            -- Lưu lại hàm lấy HWID gốc
            _G.Original_GetDeviceId = SystemLib.GetDeviceId

            -- Ghi đè hàm của game
            SystemLib.GetDeviceId = function(...)
                if _G.LexusConfig.FakeHWID then
                    if not _G.FakeHWID_String then
                        -- Tạo ngẫu nhiên một HWID ảo 32 ký tự
                        local chars = "0123456789abcdef"
                        local hwid = ""
                        for i = 1, 32 do 
                            hwid = hwid .. chars:sub(math.random(1, 16), math.random(1, 16)) 
                        end
                        _G.FakeHWID_String = hwid
                    end
                    -- Trả về HWID ảo
                    return _G.FakeHWID_String
                end
                
                -- Nếu tắt Fake HWID thì trả về HWID thật
                if _G.Original_GetDeviceId then return _G.Original_GetDeviceId(...) end
                return "UNKNOWN"
            end
            _G.FakeHWID_Hooked = true
        end
    end)

    -- Hàm độc lập để bạn lấy HWID Gốc (nếu sau này cần hiển thị)
    _G.GetOriginalHWID = function()
        if _G.Original_GetDeviceId then
            return tostring(_G.Original_GetDeviceId())
        end
        local SystemLib = SafeImport("KismetSystemLibrary")
        if SystemLib and type(SystemLib.GetDeviceId) == "function" then
            return tostring(SystemLib.GetDeviceId())
        end
        return "UNKNOWN_DEVICE"
    end
    -- =====================================================================

    if _G.LexusState.CustomTextData == nil then 
        _G.LexusState.CustomTextData = {OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, MagicHead = 1.0, MagicBody = 1.0, MagicLegs = 1.0, IpadViewFOV = 120, AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250, AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30, AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400}
    end

    local okData, GameplayData = PCall(require, "GameLua.GameCore.Data.GameplayData") 
    if not okData or not GameplayData then return end 
    local pc = GameplayData.GetPlayerController() 
    local localPlayer = nil
    if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end 

    -- XÓA SẠCH SÀNH SANH RÁC KHỎI RAM KHI BẠN CHẾT, ĐỔI MAP, VÀO SẢNH
    if not Valid(localPlayer) then 
        if _G.LexusState.TrackedMarks then
            for markId, _ in pairs(_G.LexusState.TrackedMarks) do
                SafeRemoveMark(markId)
            end
        end
        _G.LexusState.TrackedMarks = {} 
        
        -- Dọn sạch object UE4 MIDs để giải phóng RAM tối đa qua nhiều trận
        for key, data in pairs(_G.LexusState.EnemyMarks) do
            if data and data.MIDs then
                for meshStr, midTable in pairs(data.MIDs) do
                    for k, _ in pairs(midTable) do midTable[k] = nil end
                end
                data.MIDs = nil
            end
            if data and data.MIDs_V3 then
                for meshStr, midTable in pairs(data.MIDs_V3) do
                    for k, _ in pairs(midTable) do midTable[k] = nil end
                end
                data.MIDs_V3 = nil
            end
        end
        
        _G.LexusState.EnemyMarks = {}
        _G.AK_OrigHitboxes = {}
        _G.AK_ModdedPhysAssets = {}
        _G.LexusState.PrevGraphicsState = {}
        
        -- Cleanup logic removed for stability.
        
        return 
    end

    local Cached_SecurityCommonUtils = nil
    PCall(function() Cached_SecurityCommonUtils = SafeRequire("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils") end)
    local Cached_MyHUD = pc and pc.MyHUD or nil

    if _G.LexusConfig.UnlockFPS then InitializeGraphicsUnlock() end
    InitializeNativeESP()
    ShowLexusVIPMenu()
    
    
    -- HOÀN TRẢ GÓC NHÌN NGAY LẬP TỨC NẾU TẮT IPAD VIEW
    if _G.LexusConfig.IpadView and _G.LexusState.CustomTextData then
        PCall(function()
            local targetTPP = _G.LexusState.CustomTextData.IpadViewFOV or 120
            local uTPPCam = localPlayer.ThirdPersonCameraComponent
            if Valid(uTPPCam) and not localPlayer.bIsWeaponAiming then
                if uTPPCam.FieldOfView ~= targetTPP then uTPPCam.FieldOfView = targetTPP end
            end
        end)
    else
        PCall(function()
            local uTPPCam = localPlayer.ThirdPersonCameraComponent
            if Valid(uTPPCam) and not localPlayer.bIsWeaponAiming then
                if uTPPCam.FieldOfView ~= 90 then uTPPCam.FieldOfView = 90 end
            end
        end)
    end

    -- ========================================================
    -- LOGIC AIMBOT V2 ROYAL/CUSTOM
    -- ========================================================
    if _G.LexusConfig.AimTouchEnable then
        _G.AimTouch()
    end

    if _G.LexusConfig.MortarAim then
        if type(_G.MortarAimTick) == "function" then
            _G.MortarAimTick()
        end
    end
    


    -- Combined Gun Info + AI/Player Info Hook for ESP
    if _G.LexusConfig.Esp7_VuKhi then
        PCall(function()
            local enemies = GameplayData.GetCharacterList and GameplayData.GetCharacterList()
            if enemies then
                for _, enemy in pairs(enemies) do
                    if SafeIsValid(enemy) and enemy ~= localPlayer then
                        -- 1. Gun Info & Icon
                        local iconPath, activeHand, targetID = _G.AK_GetCharacterWeapon(enemy)
                        if targetID and targetID > 0 then
                            enemy.CachedWeaponID = targetID
                            enemy.CachedWeaponIcon = iconPath
                            enemy.CachedWeaponActiveHand = activeHand
                        end
                        
                        -- 2. AI / Player Info
                        local markData = enemy.AK_MarkData or {}
                        enemy.AK_MarkData = markData
                        local isBot = CheckIsAI(enemy, markData)
                        enemy.CachedPlayerType = isBot and "BOT" or "ENEMY"
                        
                        -- Combined Display Info String for ESP renderer
                        local typeLabel = isBot and "BOT " or "ENEMY "
                        local weaponInfoStr = (targetID and targetID > 0) and tostring(targetID) or "---"
                        enemy.CachedESPInfo = string.format("%s | Gun: %s", typeLabel, weaponInfoStr)
                    end
                end
            end
        end)
    end

    -- [THÊM MỚI] LOGIC GLOW SÚNG (ĐỘC LẬP & SIÊU MƯỢT 0.5s/Lần - ĐẢM BẢO 0% DROP FPS)
    if not _G.LastGlowTime or (os.clock() - _G.LastGlowTime) > 0.5 then
        _G.LastGlowTime = os.clock()
        if _G.ApplyWeaponGlow then _G.ApplyWeaponGlow(localPlayer) end
    end

    -- ========================================================
    -- LOGIC BÙ GIẬT (GHÌM TÂM) CHỈ DÀNH RIÊNG CHO AIMBOT GỐC (ĐÃ FIX LAG ĐÔNG NGƯỜI)
    -- ========================================================
    PCall(function()
        if _G.LexusConfig.CustomAimbot and localPlayer.bIsWeaponFiring and localPlayer.bIsGunADS then
            local outerRecoilVal = _G.LexusState.CustomTextData.OuterRecoil or 0
            if outerRecoilVal > 0 then
                local curTime = os.clock()
                
                -- [FIX CPU CỰC MẠNH]: Quét mục tiêu 0.2s/lần thay vì 100 lần/giây để tránh quá tải máy khi check FOV
                if not _G.RecoilTargetCacheTime or (curTime - _G.RecoilTargetCacheTime) > 0.2 then
                    _G.RecoilTargetCacheTime = curTime
                    _G.HasRecoilTargetCached = false
                    
                    local ui_util = SafeRequire("client.common.ui_util")
                    if ui_util then
                        local viewportSize = ui_util.GetViewportSize()
                        if viewportSize then
                            local centerX = viewportSize.X * 0.5
                            local centerY = viewportSize.Y * 0.5
                            local FOV_RADIUS = (6 / 100.0) * (viewportSize.X / 2.0) 
                            
                            local enemies = _G.GetEnemyTargetsFromActors(40000) 
                            if enemies and #enemies > 0 then
                                local FVector2D = SafeImport("Vector2D")
                                for _, target in ipairs(enemies) do
                                    if SafeIsValid(target) and target.HealthStatus ~= 1 then 
                                        local tPos = type(target.K2_GetActorLocation) == "function" and target:K2_GetActorLocation() or nil
                                        if tPos then
                                            local screen = FVector2D()
                                            if pc:ProjectWorldLocationToScreen(tPos, screen, false) and screen.X > 0 and screen.Y > 0 then
                                                local dx = screen.X - centerX
                                                local dy = screen.Y - centerY
                                                if math.sqrt(dx*dx + dy*dy) <= FOV_RADIUS then
                                                    _G.HasRecoilTargetCached = true
                                                    break 
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if _G.HasRecoilTargetCached then
                    local currentRot = pc:GetControlRotation()
                    if currentRot then
                        local pullDownForce = (outerRecoilVal / 50.0) * 1.5
                        currentRot.Pitch = currentRot.Pitch - pullDownForce
                        pc:SetControlRotation(currentRot, "CustomAimbotRecoil")
                    end
                end
            end
        else
            _G.HasRecoilTargetCached = false
        end
    end)
    
    -- CHẶN HIGGSBOSON THEO THỜI GIAN THỰC LÀM AN TOÀN TUYỆT ĐỐI MÀ KHÔNG GÂY VĂNG GAME
    PCall(function()
        if Valid(pc) then
            if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false end
            if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent.bCallPreReplication = false end
        end
    end)

    if _G.LexusConfig.WallClimb then
        PCall(function()
            local charMove = localPlayer.CharacterMovement
            if Valid(charMove) then
                if not _G.LexusState.WallClimbOriginals then
                    _G.LexusState.WallClimbOriginals = { WalkableFloorAngle = charMove.WalkableFloorAngle, MaxStepHeight = charMove.MaxStepHeight }
                end
                charMove.WalkableFloorAngle = 199.0
                charMove.MaxStepHeight = 999.0
                _G.LexusState.WallClimbApplied = true
            end
        end)
    elseif _G.LexusState.WallClimbApplied then
        PCall(function()
            local charMove = localPlayer.CharacterMovement
            if Valid(charMove) and _G.LexusState.WallClimbOriginals then
                charMove.WalkableFloorAngle = _G.LexusState.WallClimbOriginals.WalkableFloorAngle or 50.0
                charMove.MaxStepHeight = _G.LexusState.WallClimbOriginals.MaxStepHeight or 45.0
            end
        end)
        _G.LexusState.WallClimbApplied = false
    end

    -- HOÀN TRẢ ĐỒ HỌA NGAY LẬP TỨC NẾU TẮT (TẮT LÀ TẮT LIỀN)
    local now = os.clock()
    PCall(function()
        local lsg = SafeRequire("client.slua.logic.setting.logic_setting_graphics")
        local gi = lsg.GetGameInstance()
        if gi then
            if _G.LexusConfig.RemoveGrass and not _G.LexusState.PrevGraphicsState.RemoveGrass then
                gi:ExecuteCMD("grass.DensityScale", "0")
                gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
                _G.LexusState.PrevGraphicsState.RemoveGrass = true
            elseif not _G.LexusConfig.RemoveGrass and _G.LexusState.PrevGraphicsState.RemoveGrass then
                gi:ExecuteCMD("grass.DensityScale", "1")
                gi:ExecuteCMD("grass.DiscardDataOnLoad", "0")
                _G.LexusState.PrevGraphicsState.RemoveGrass = false
            end

            -- LOGIC BLACKSKY
            if _G.LexusConfig.BlackSky and not _G.LexusState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "9999")
                _G.LexusState.PrevGraphicsState.BlackSky = true
            elseif not _G.LexusConfig.BlackSky and _G.LexusState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "0000")
                _G.LexusState.PrevGraphicsState.BlackSky = false
            end
        end
    end)

    PCall(function()
        local weapon = nil
        PCall(function()
            local weaponManager = localPlayer.WeaponManagerComponent
            if Valid(weaponManager) and type(weaponManager.GetCurrentWeapon) == "function" then
                weapon = weaponManager:GetCurrentWeapon()
            end
        end)
        if not Valid(weapon) then
            if type(localPlayer.GetCurrentShootWeapon) == "function" then weapon = localPlayer:GetCurrentShootWeapon()
            elseif type(localPlayer.GetCurrentWeapon) == "function" then weapon = localPlayer:GetCurrentWeapon() end
        end

        if Valid(weapon) then
            local entities = {}
            if Valid(weapon.ShootWeaponEntity_GEN_VARIABLE) then table.insert(entities, weapon.ShootWeaponEntity_GEN_VARIABLE) end
            if Valid(weapon.ShootWeaponEntity) then table.insert(entities, weapon.ShootWeaponEntity) end
            if Valid(weapon.ShootWeaponComponent) and Valid(weapon.ShootWeaponComponent.ShootWeaponEntityComponent) then 
                table.insert(entities, weapon.ShootWeaponComponent.ShootWeaponEntityComponent) 
            end

            for _, entity in ipairs(entities) do
                local anyWeaponModOn = _G.LexusConfig.LessShake or _G.LexusConfig.Crosshair or _G.LexusConfig.GodMode or _G.LexusConfig.CustomAimbot or _G.LexusConfig.CustomAimbotClose or _G.LexusConfig.AimbotMode ~= "None" or _G.LexusConfig.LessRecoil or _G.LexusConfig.VerticalRecoil

                if anyWeaponModOn then
                    if not entity.OriginalStatsCached then
                        entity.OriginalStatsCached = {
                            GameDeviationFactor = entity.GameDeviationFactor,
                            GameDeviationAccuracy = entity.GameDeviationAccuracy,
                            BulletFireSpeed = entity.BulletFireSpeed,
                            ShootInterval = entity.ShootInterval,
                            BaseDamage = entity.BaseDamage,
                            AccessoriesHRecoilFactor = entity.AccessoriesHRecoilFactor,
                            AccessoriesVRecoilFactor = entity.AccessoriesVRecoilFactor,
                            RecoilKick = entity.RecoilKick,
                            RecoilKickADS = entity.RecoilKickADS,
                            AnimationKick = entity.AnimationKick
                        }
                    end
                    
                    
                    
                    if _G.LexusConfig.LessShake then entity.RecoilKick = 0.0; entity.RecoilKickADS = 0.0; entity.AnimationKick = 0.0 end
                    if _G.LexusConfig.Crosshair then entity.GameDeviationFactor = 0.0 end
                    if _G.LexusConfig.GodMode then entity.BulletFireSpeed = 500000.0; entity.ShootInterval = 0.001; entity.BaseDamage = 60000.0 end
                    
                    if entity.AutoAimingConfig then
                        if not entity.OriginalAutoAimCached then
                            entity.OriginalAutoAimCached = {
                                OuterSpeed = entity.AutoAimingConfig.OuterRange and entity.AutoAimingConfig.OuterRange.Speed,
                                InnerSpeed = entity.AutoAimingConfig.InnerRange and entity.AutoAimingConfig.InnerRange.Speed
                            }
                        end
                        
                        
                        if _G.LexusConfig.CustomAimbot then
                            local speed = _G.LexusState.CustomTextData.OuterSpeed or 10
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = speed
                                entity.AutoAimingConfig.OuterRange.RangeRate = 4.5
                                entity.AutoAimingConfig.OuterRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.OuterRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.OuterRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.OuterRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.OuterRange.ProneRate = 1.0
                                entity.AutoAimingConfig.OuterRange.DyingRate = 0.0
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = speed
                                entity.AutoAimingConfig.InnerRange.RangeRate = 4.5
                                entity.AutoAimingConfig.InnerRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.InnerRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.InnerRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.InnerRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.InnerRange.ProneRate = 1.0
                                entity.AutoAimingConfig.InnerRange.DyingRate = 0.0
                            end
                        elseif _G.LexusConfig.CustomAimbotClose or _G.LexusConfig.AimbotMode == "Close" then
                            local speed = _G.LexusState.CustomTextData.InnerSpeed or 10
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = speed
                                entity.AutoAimingConfig.OuterRange.DyingRate = 0.0
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = speed
                                entity.AutoAimingConfig.InnerRange.DyingRate = 0.0
                            end
                        elseif _G.LexusConfig.AimbotMode == "Far" then
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = 5
                                entity.AutoAimingConfig.OuterRange.RangeRate = 0.7
                                entity.AutoAimingConfig.OuterRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.OuterRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.OuterRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.OuterRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.OuterRange.ProneRate = 1
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = 5
                                entity.AutoAimingConfig.InnerRange.RangeRate = 0.7
                                entity.AutoAimingConfig.InnerRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.InnerRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.InnerRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.InnerRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.InnerRange.ProneRate = 1
                            end
                        end
                    end
                    
                    entity.LexusWeaponModsActive = true

                elseif entity.LexusWeaponModsActive then
                    if entity.OriginalStatsCached then
                        local orig = entity.OriginalStatsCached
                        entity.GameDeviationFactor = orig.GameDeviationFactor
                        entity.GameDeviationAccuracy = orig.GameDeviationAccuracy
                        entity.BulletFireSpeed = orig.BulletFireSpeed
                        entity.ShootInterval = orig.ShootInterval
                        entity.BaseDamage = orig.BaseDamage
                        entity.AccessoriesHRecoilFactor = orig.AccessoriesHRecoilFactor
                        entity.AccessoriesVRecoilFactor = orig.AccessoriesVRecoilFactor
                        entity.RecoilKick = orig.RecoilKick
                        entity.RecoilKickADS = orig.RecoilKickADS
                        entity.AnimationKick = orig.AnimationKick
                    end
                    if entity.AutoAimingConfig and entity.OriginalAutoAimCached then
                        PCall(function() entity.AutoAimingConfig.Bones = { "Spine_01", "Pelvis", "Head" } end)
                        if entity.AutoAimingConfig.OuterRange and entity.OriginalAutoAimCached.OuterSpeed then
                            entity.AutoAimingConfig.OuterRange.Speed = entity.OriginalAutoAimCached.OuterSpeed
                        end
                        if entity.AutoAimingConfig.InnerRange and entity.OriginalAutoAimCached.InnerSpeed then
                            entity.AutoAimingConfig.InnerRange.Speed = entity.OriginalAutoAimCached.InnerSpeed
                        end
                    end
                    entity.LexusWeaponModsActive = false
                end
            end
        end
    end)



    PCall(function()
        local allCharacters = {}
        if GameplayData.GetAllPlayerCharacters then allCharacters = GameplayData.GetAllPlayerCharacters()
        elseif GameplayData.GameCharacters then for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end end
        
        local currentValidKeys = {}
        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer then
                currentValidKeys[GetSafeEnemyKey(enemy)] = true
            end
        end
        
        for key, data in pairs(_G.LexusState.EnemyMarks) do
            if not currentValidKeys[key] then
                SafeRemoveMark(data.radarMark)
                SafeRemoveMark(data.hpMark)
                SafeRemoveMark(data.distMark)
                
                -- [FIX RAM]: Dọn rác AimTouch VisCheck của địch đã chết hoặc văng quá xa
                if _G.AimTouchVisCache and _G.AimTouchVisCache[key] then
                    _G.AimTouchVisCache[key] = nil
                end
                
                if data.MIDs then
                    for meshStr, midTable in pairs(data.MIDs) do
                        for k, _ in pairs(midTable) do
                            midTable[k] = nil
                        end
                    end
                    data.MIDs = nil
                end
                if data.MIDs_V3 then
                    for meshStr, midTable in pairs(data.MIDs_V3) do
                        for k, _ in pairs(midTable) do
                            midTable[k] = nil
                        end
                    end
                    data.MIDs_V3 = nil
                end
                
                data.enemy = nil
                data.CachedMeshes = nil
                _G.LexusState.EnemyMarks[key] = nil
            end
        end

        local realCount = 0
        local aiCount = 0

        local function GetFirstElemSafe(elemArray)
            if elemArray and type(elemArray.Num) == "function" and elemArray:Num() > 0 then
                if type(elemArray.Get) == "function" then return elemArray:Get(0) end
            elseif elemArray and type(elemArray) == "table" and #elemArray > 0 then
                return elemArray[1]
            end
            return nil
        end

        local BoneScaleMap = {
            ["head"] = mHead_Global, ["neck_01"] = mHead_Global,
            ["pelvis"] = mBody_Global, ["spine_01"] = mBody_Global, ["spine_02"] = mBody_Global, ["spine_03"] = mBody_Global,
            ["thigh_l"] = mLegs_Global, ["thigh_r"] = mLegs_Global, 
            ["calf_l"] = mLegs_Global, ["calf_r"] = mLegs_Global,   
            ["foot_l"] = mLegs_Global, ["foot_r"] = mLegs_Global    
        }
        
        local mLoc = nil
        PCall(function() if type(localPlayer.K2_GetActorLocation) == "function" then mLoc = localPlayer:K2_GetActorLocation() end end)

        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                local bIsReallyDead = false
                PCall(function()
                    if type(enemy.IsDead) == "function" then bIsReallyDead = enemy:IsDead()
                    elseif enemy.bIsDead ~= nil then bIsReallyDead = enemy.bIsDead
                    elseif enemy.bIsDeadFlag ~= nil then bIsReallyDead = enemy.bIsDeadFlag end
                    if enemy.HealthStatus ~= nil and enemy.HealthStatus == 2 then bIsReallyDead = true end
                end)

                local eKey = GetSafeEnemyKey(enemy)
                _G.LexusState.EnemyMarks[eKey] = _G.LexusState.EnemyMarks[eKey] or { enemy = enemy }
                local markData = _G.LexusState.EnemyMarks[eKey]
                markData.enemy = enemy 

                if not bIsReallyDead then
                    -- [GK_COUNTER]: Always count living enemies for the widget
                    local distForCount = 0
                    PCall(function() distForCount = localPlayer:GetDistanceTo(enemy) / 100 end)
                    if distForCount <= 600 then
                        local isBotForCount = CheckIsAI(enemy, markData)
                        if isBotForCount then aiCount = aiCount + 1 else realCount = realCount + 1 end
                    end

                    -- [FIX LỖI MẤT MÁU KHI NHẢY DÙ/HỒI SINH]: Kiểm tra xem địch có bị đổi Actor (nhân vật mới) không.
                    -- Nếu có, xóa toàn bộ Marker (UI) bị kẹt ở xác cũ để code bên dưới vẽ lại lên nhân vật mới.
                    if markData.lastEnemyActor ~= enemy then
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end -- Xóa luôn rác của ESP 8
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                        if markData.radarMark then SafeRemoveMark(markData.radarMark); markData.radarMark = nil end
                        
                        markData.lastEnemyActor = enemy
                        markData.LastUIComp = nil
                        markData.LastFrameUIState = nil
                    end
                    
                    local eMesh = nil
                    PCall(function() eMesh = enemy.Mesh or (type(enemy.getAvatarComponent2) == "function" and enemy:getAvatarComponent2() or nil) end)
                    local aLoc = nil
                    PCall(function() if type(enemy.K2_GetActorLocation) == "function" then aLoc = enemy:K2_GetActorLocation() end end)
                    
                    local isBotResult, isStateLoaded = CheckIsAI(enemy, markData)
                    local isBot = markData.AK_IS_BOT or false

                    local currentMeshCount = 0
                    if Valid(eMesh) then
                        local tempMeshes = GetAllSkeletalMeshes(enemy, markData)
                        currentMeshCount = #tempMeshes
                    end
                    local isMeshChanged = (markData.LastMeshCountWall ~= currentMeshCount)

                    -- ĐÃ TỐI ƯU CỰC KỲ: Chỉ Apply khi thật sự cần
                    if _G.LexusConfig.WallXuyenTuong then
                        ApplyWallXuyenTuong(enemy, pc, markData)
                    else
                        UndoWallXuyenTuong(enemy, markData)
                    end







                    local distM = 0
                    PCall(function() distM = localPlayer:GetDistanceTo(enemy) / 100 end)

                    local currentHp, maxHp = 100, 100
                    -- When the stable AD ESP head box is active, suppress the
                    -- native Replay frame so two independently positioned
                    -- health/name widgets cannot overlap or jitter together.
                    local stableADESPActive = _G.LexusConfig.ADESP_ShowTags == true or _G.LexusConfig.ADESP_ShowWeapon == true
                    local showFrameUI = _G.LexusConfig.EspLoai5 and not stableADESPActive
                    
                    if showFrameUI then
                        PCall(function()
                            if enemy.Health then currentHp = enemy.Health elseif type(enemy.GetHealth) == "function" then currentHp = enemy:GetHealth() end
                            if enemy.HealthMax then maxHp = enemy.HealthMax elseif type(enemy.GetHealthMax) == "function" then maxHp = enemy:GetHealthMax() end
                        end)
                        if maxHp <= 0 then maxHp = 100 end
                    end
                    local hpRatio = currentHp / maxHp

                    if _G.LexusConfig.EspAntenna then
                        PCall(function()
                            local MyHUD = Cached_MyHUD
                            if Valid(MyHUD) and type(MyHUD.AddDebugText) == "function" and distM <= 400 then
                                -- Use an explicit opaque color: the shared legacy C_GREEN table has A=0.
                                local antennaColor = {R=0, G=255, B=0, A=255}
                                local loopCount = 8  
                                local zStep = 1000     
                                local baseZ = 105     
                                local topZ = baseZ + (loopCount * zStep)
                                for i = 1, loopCount do
                                    local zOffset = baseZ + (i * zStep)
                                    MyHUD:AddDebugText("|", enemy, 0.06,
                                        {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset},
                                        antennaColor, true, false, true, nil, 1.2, true)
                                end
                                MyHUD:AddDebugText("I", enemy, 0.06,
                                    {X=0, Y=0, Z=topZ + 60}, {X=0, Y=0, Z=topZ + 60},
                                    antennaColor, true, false, true, nil, 1.5, true)
                            end
                        end)
                    end

                    if _G.LexusConfig.EspLoai7 then
                        PCall(function()
                            local MyHUD = Cached_MyHUD
                            if Valid(MyHUD) then
                                -- Counted above
                                
                                if distM <= 400 then
                                    local stateText = ""
                                    
                                    -- Weapon display remains; the removed posture/state display is not retained.
                                    -- Xử lý Vũ Khí
                                    if _G.LexusConfig.Esp7_VuKhi then
                                        local curTime = os.clock()
                                        if markData.AK_LAST_WEP_TIME == nil or curTime > markData.AK_LAST_WEP_TIME + 1.5 then
                                            local eWeapon = nil
                                            if enemy.CurrentWeapon then eWeapon = enemy.CurrentWeapon
                                            elseif type(enemy.GetCurrentWeapon) == "function" then eWeapon = enemy:GetCurrentWeapon()
                                            elseif enemy.WeaponManagerComponent then eWeapon = enemy.WeaponManagerComponent.CurrentWeaponReplicated end
                                            
                                            local weaponName = "---"
                                            if Valid(eWeapon) then if type(eWeapon.GetWeaponName) == "function" then weaponName = eWeapon:GetWeaponName() end end
                                            markData.AK_CACHED_WEP_NAME = tostring(weaponName)
                                            markData.AK_LAST_WEP_TIME = curTime
                                        end

                                        if stateText ~= "" then
                                            stateText = stateText .. " - " .. (markData.AK_CACHED_WEP_NAME or "---")
                                        else
                                            stateText = (markData.AK_CACHED_WEP_NAME or "---")
                                        end
                                    end

                                    -- 3. Prepend Bot / Enemy Tag to stateText
                                    local botPlayerTag = isBot and "BOT " or "ENEMY "
                                    stateText = botPlayerTag .. stateText

                                    -- 4. Vẽ lên màn hình nếu có bật 1 trong 2
                                    if stateText ~= "" then
                                        -- Weapon info is part of this label and intentionally uses
                                        -- the same visible Bot/Player color as its prefix.
                                        local textColor = isBot and C_ESP7_BOT_TEXT or C_ESP7_PLAYER_TEXT
                                        local dynamicScale = math.max(0.5, 0.8 - (distM / 400))
                                        MyHUD:AddDebugText(stateText, enemy, 0.06, {X=0, Y=0, Z=100}, {X=0, Y=0, Z=100}, textColor, true, false, true, nil, dynamicScale, true)
                                    end
                                end
                            end
                        end)
                    end

                    -- ĐÃ TỐI ƯU CỰC KỲ: Chỉ SetVisibility cho UI khung máu khi thật sự cần
                    if showFrameUI then
                        PCall(function()
                            local SecurityCommonUtils = Cached_SecurityCommonUtils
                            local show = true
                            if enemy.HealthStatus and SecurityCommonUtils and SecurityCommonUtils.IsHealthStatusAlive then 
                                if not SecurityCommonUtils.IsHealthStatusAlive(enemy.HealthStatus) then show = false end
                            end
                            if show and mLoc then
                                if aLoc and SecurityCommonUtils and SecurityCommonUtils.IsVector then
                                    if SecurityCommonUtils.IsVector(aLoc) and SecurityCommonUtils.IsVector(mLoc) then
                                        if aLoc.Z >= 150000 or FVector.Dist2D(mLoc, aLoc) > 50000 then show = false end
                                    end
                                end
                            end
                            if show then
                                if enemy.Replay_IsEnemyFrameUIExisted and not enemy:Replay_IsEnemyFrameUIExisted() then enemy:Replay_CreateEnemyFrameUI(true, true) end
                                if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(true) end
                                if enemy.Replay_UpdateEnemyFrameUI then enemy:Replay_UpdateEnemyFrameUI(hpRatio) end
                                
                                local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if markData.LastFrameUIState ~= "VISIBLE" then
                                        if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(0) end
                                        if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(false) end
                                        markData.LastFrameUIState = "VISIBLE"
                                    end
                                end
                            end
                        end)
                    else
                        PCall(function()
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end
                            local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                            if Valid(uiComp) then
                                if markData.LastFrameUIState ~= "HIDDEN" then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                    markData.LastFrameUIState = "HIDDEN"
                                end
                            end
                        end)
                    end

                    if _G.LexusConfig.EspDistance then
                        PCall(function()
                            local hud = Cached_MyHUD
                            if Valid(hud) and hud.AddDebugText then
                                if distM <= 400 then
                                    local dynamicScale = math.max(0.55, 0.95 - (distM / 400))
                                    hud:AddDebugText(string.format("[%dm]", math.floor(distM)), enemy, 0.06, {X=0, Y=115, Z=20}, {X=0, Y=115, Z=20}, C_BLUE_TEXT, true, false, true, nil, dynamicScale * 1.5, true)
                                end
                            end
                        end)
                    end

                    -- [ESP LOẠI 8 ĐỘC LẬP (Đã Fix Lỗi)]: Copy logic thanh máu ESP 1, nhưng chạy biến hpMark8 riêng biệt
                    if _G.LexusConfig.EspLoai8 then
                        if markData.hpMark8 == nil then markData.hpMark8 = SafeAddMark(1006, FVector(0,0,0), 0, "", 4, enemy) end
                    else
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end
                    end
                    
                else
                    if not markData.IsCleanedUp then
                        SafeRemoveMark(markData.radarMark)
                        markData.radarMark = nil
                        SafeRemoveMark(markData.hpMark)
                        markData.hpMark = nil
                        SafeRemoveMark(markData.hpMark8) -- Dọn dẹp ESP 8
                        markData.hpMark8 = nil
                        SafeRemoveMark(markData.distMark)
                        markData.distMark = nil
                        
                        if markData.MIDs then
                            for meshStr, midTable in pairs(markData.MIDs) do
                                for k, _ in pairs(midTable) do midTable[k] = nil end
                            end
                            markData.MIDs = nil
                        end
                        
                        if markData.MIDs_V3 then
                            for meshStr, midTable in pairs(markData.MIDs_V3) do
                                for k, _ in pairs(midTable) do midTable[k] = nil end
                            end
                            markData.MIDs_V3 = nil
                        end
                        
                        PCall(function()
                            local eObj = markData.enemy
                            if Valid(eObj) then 
                                if eObj.Replay_SetVisiableOfFrameUI then eObj:Replay_SetVisiableOfFrameUI(false) end
                                local uiComp = eObj.EnemyFrameUI or (type(eObj.GetEnemyFrameUI) == "function" and eObj:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end 
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                end
                            end
                            
                        end)

                        markData.IsCleanedUp = true
                    end
                end
            end
        end

                if _G.LexusConfig.EspLoai7 and _G.LexusConfig.Esp7_SoLuong then
            GK_UpdateWidget(realCount, aiCount)
        else
            GK_DestroyWidget()
        end

        -- ==========================================================
        -- [LOGIC ESP BOM VVIP] - OPTIMIZED WITH WEAK CACHE (100% GỐC, KHÔNG LAG)
        -- ==========================================================
        if _G.LexusConfig.EspBomMaster and (_G.LexusConfig.EspItemBom or _G.LexusConfig.EspActiveBom) then
            PCall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = SafeImport("GameplayStatics") end
                    if not _G.CachedActorClass_ForBomb then _G.CachedActorClass_ForBomb = SafeImport("Actor") end 
                    if not _G.CachedProjArray then _G.CachedProjArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForBomb) end
                    
                    -- Khởi tạo Cache sử KHALED Weak Table để game tự xóa rác, không tràn RAM
                    if not _G.ActorBombCacheInit then
                        _G.NonBombCache = setmetatable({}, { __mode = "k" })
                        _G.BombCache = setmetatable({}, { __mode = "k" })
                        _G.ActorBombCacheInit = true
                    end
                    
                    local ui_util = SafeRequire("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()
                        
                        -- LUỒNG QUÉT DỮ LIỆU NẶNG: Chạy 0.5s/lần thay vì mỗi frame
                        if not _G.LastBombScanTime or (curTime - _G.LastBombScanTime) > 0.5 then
                            _G.LastBombScanTime = curTime
                            local allActors = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForBomb, _G.CachedProjArray)
                            
                            local activeBombs = {}
                            local itemBombs = {}
                            
                            if allActors then
                                for _, actor in pairs(allActors) do
                                    if SafeIsValid(actor) and not actor.bHidden and not actor.bTearOff then
                                        
                                        -- 1. KIỂM TRA BỘ NHỚ ĐỆM (CACHE) SIÊU TỐC
                                        -- Nếu actor này đã từng quét và KHÔNG PHẢI BOM -> Bỏ qua lập tức (Giảm 99% Lag)
                                        if not _G.NonBombCache[actor] then
                                            local bType = 0
                                            local isItem = false
                                            local isKnownBomb = _G.BombCache[actor]
                                            
                                            if isKnownBomb then
                                                bType = isKnownBomb.type
                                                isItem = isKnownBomb.isItem
                                            else
                                                -- Lần đầu tiên thấy Actor này, tiến hành kiểm tra tên (Rất ít khi xảy ra)
                                                local nameLower = nil
                                                PCall(function() nameLower = string.lower(type(actor.GetName) == "function" and actor:GetName() or tostring(actor)) end)
                                                
                                                if nameLower then
                                                    if string.find(nameLower, "m79") or string.find(nameLower, "launcher") then bType = 5
                                                    elseif string.find(nameLower, "smoke") then bType = 2
                                                    elseif string.find(nameLower, "burn") or string.find(nameLower, "molotov") then bType = 3
                                                    elseif string.find(nameLower, "flash") or string.find(nameLower, "stun") then bType = 4
                                                    elseif string.find(nameLower, "grenade") then bType = 1 end
                                                    
                                                    if bType > 0 then
                                                        if string.find(nameLower, "projectile") or string.find(nameLower, "thrown") then
                                                            isItem = false
                                                        else
                                                            isItem = true
                                                            local shouldAdd = true
                                                            if bType == 3 and not (string.find(nameLower, "pickup") or string.find(nameLower, "wrapper") or string.find(nameLower, "weapon")) then
                                                                shouldAdd = false
                                                            elseif bType == 5 then
                                                                local attachParent = nil
                                                                PCall(function() if type(actor.GetAttachParentActor) == "function" then attachParent = actor:GetAttachParentActor() end end)
                                                                if SafeIsValid(attachParent) then
                                                                    local isHolding = false
                                                                    PCall(function()
                                                                        local curWeapon = type(attachParent.GetCurrentWeapon) == "function" and attachParent:GetCurrentWeapon() or attachParent.CurrentWeapon
                                                                        if curWeapon == actor then isHolding = true end
                                                                    end)
                                                                    if not isHolding then shouldAdd = false end
                                                                end
                                                            end
                                                            if not shouldAdd then bType = 0 end
                                                        end
                                                    end
                                                end
                                                
                                                -- Lưu kết quả vào Cache
                                                if bType > 0 then
                                                    _G.BombCache[actor] = { type = bType, isItem = isItem }
                                                else
                                                    _G.NonBombCache[actor] = true
                                                end
                                            end
                                            
                                            -- Nếu là Bom hợp lệ (từ Cache hoặc vừa tìm ra)
                                            if bType > 0 then
                                                local isPendingKill = false
                                                PCall(function() if type(actor.IsPendingKill) == "function" then isPendingKill = actor:IsPendingKill() end end)
                                                
                                                if not isPendingKill then
                                                    if isItem then
                                                        table.insert(itemBombs, {act = actor, type = bType})
                                                    else
                                                        table.insert(activeBombs, {act = actor, type = bType})
                                                    end
                                                else
                                                    -- Xóa khỏi cache nếu bomb đã nổ/biến mất
                                                    _G.BombCache[actor] = nil
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            _G.CachedActiveBombs = activeBombs
                            _G.CachedItemBombs = itemBombs
                        end

                        local curGameTime = 0
                        PCall(function() curGameTime = _G.CachedGameplayStatics.GetTimeSeconds(gameInstance) end)

                        local function DrawBombs(bombList, isItem, maxDist)
                            if not bombList then return end
                            for _, item in ipairs(bombList) do
                                local bomb = item.act
                                local bType = item.type
                                
                                if SafeIsValid(bomb) and not bomb.bHidden then
                                    local distM = 0
                                    PCall(function() distM = localPlayer:GetDistanceTo(bomb) / 100 end)
                                    
                                    if distM > 0 and distM <= maxDist then
                                        local displayName = ""
                                        local bombColor = C_WHITE
                                        local zOffset = isItem and 15 or 25
                                        
                                        if bType == 1 then displayName = "Boom"; bombColor = isItem and {R=255, G=100, B=100, A=255} or C_RED
                                        elseif bType == 2 then displayName = "KHÓI"; bombColor = isItem and {R=200, G=200, B=200, A=255} or C_WHITE
                                        elseif bType == 3 then displayName = "LỬA"; bombColor = isItem and {R=255, G=160, B=50, A=255} or {R=255, G=100, B=0, A=255}
                                        elseif bType == 4 then displayName = "MÙ"; bombColor = isItem and {R=150, G=255, B=255, A=255} or C_CYAN
                                        elseif bType == 5 then displayName = "ĐẠN KHÓI"; bombColor = isItem and {R=150, G=255, B=150, A=255} or {R=100, G=255, B=100, A=255} end
                                        
                                        local text = string.format("%s [%dm]", displayName, math.floor(distM))
                                        local shouldTimerRun = not isItem 
                                        
                                        if isItem then PCall(function() if bomb.bIsPinPulled or bomb.bPinPulled or (type(bomb.IsPinPulled) == "function" and bomb:IsPinPulled()) then shouldTimerRun = true end end) end

                                        if shouldTimerRun and curGameTime > 0 then
                                            local timeLeft = -1
                                            PCall(function() if bomb.ExplosionTime then timeLeft = bomb.ExplosionTime - curGameTime elseif bomb.ExplodeTime then timeLeft = bomb.ExplodeTime - curGameTime end end)
                                            
                                            if timeLeft == -1 or timeLeft > 100 then
                                                _G.ActiveBombTimers = _G.ActiveBombTimers or {}
                                                local bombId = tostring(bomb)
                                                if not _G.ActiveBombTimers[bombId] then _G.ActiveBombTimers[bombId] = curGameTime end
                                                local elapsed = curGameTime - _G.ActiveBombTimers[bombId]
                                                local maxTime = (bType == 1 and 7.0) or (bType == 2 and 45.0) or (bType == 3 and 12.0) or (bType == 4 and 5.0) or 45.0
                                                timeLeft = maxTime - elapsed
                                            end
                                            
                                            if timeLeft < 0 then timeLeft = 0 end
                                            if timeLeft > 0.1 then text = string.format("%s (%.1fs)", text, timeLeft) end
                                        end
                                        
                                        local dynamicScale = math.max(0.6, 1.1 - (distM / maxDist))
                                        MyHUD:AddDebugText(text, bomb, 0.06, {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset}, bombColor, true, false, true, nil, dynamicScale, true)
                                    end
                                end
                            end
                        end
                        
                        if not _G.LastClearTimer or (curTime - _G.LastClearTimer) > 1.0 then
                            _G.LastClearTimer = curTime
                            PCall(function() if _G.ActiveBombTimers then for k, v in pairs(_G.ActiveBombTimers) do if (curGameTime - v) > 60.0 then _G.ActiveBombTimers[k] = nil end end end end)
                        end

                        if _G.LexusConfig.EspItemBom then DrawBombs(_G.CachedItemBombs, true, 50) end
                        if _G.LexusConfig.EspActiveBom then DrawBombs(_G.CachedActiveBombs, false, 150) end
                    end
                end
            end)
        end

        -- ==========================================================
        -- [LOGIC ESP XE - VEHICLE ESP VVIP] - OPTIMIZED
        -- ==========================================================
        -- ==========================================================
        -- [LOGIC ESP XE - VEHICLE ESP VVIP] - OPTIMIZED KHÔNG MÁU (SIÊU NHẸ)
        -- ==========================================================
        if _G.LexusConfig.EspVehicle then
            PCall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = SafeImport("GameplayStatics") end
                    if not _G.CachedActorClass_ForVehicle then _G.CachedActorClass_ForVehicle = SafeImport("STExtraVehicleBase") end 
                    if not _G.CachedVehicleArray then _G.CachedVehicleArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForVehicle) end
                    
                    local ui_util = SafeRequire("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()

                        -- LUỒNG QUÉT CHÍNH: 1.0s quét 1 lần.
                        if not _G.LastVehicleScanTime or (curTime - _G.LastVehicleScanTime) > 1.0 then
                            _G.LastVehicleScanTime = curTime
                            local allVehicles = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForVehicle, _G.CachedVehicleArray)
                            
                            local activeVehicles = {}
                            if allVehicles then
                                for _, veh in pairs(allVehicles) do
                                    if SafeIsValid(veh) and not veh.bHidden and not veh.bTearOff then
                                        local isPendingKill = false
                                        PCall(function() if type(veh.IsPendingKill) == "function" then isPendingKill = veh:IsPendingKill() end end)
                                        
                                        if not isPendingKill then
                                            local vehName = "Xe"
                                            local hasDriver = false
                                            
                                            PCall(function()
                                                if type(veh.GetVehicleName) == "function" then vehName = veh:GetVehicleName() elseif veh.VehicleName then vehName = veh.VehicleName end
                                                local driver = type(veh.GetDriver) == "function" and veh:GetDriver() or nil
                                                if SafeIsValid(driver) then hasDriver = true end
                                            end)
                                            
                                            local nameLower = string.lower(tostring(vehName) .. tostring(veh))
                                            local displayName = "Xe"
                                            if string.find(nameLower, "uaz") then displayName = "UAZ"
                                            elseif string.find(nameLower, "dacia") then displayName = "Dacia"
                                            elseif string.find(nameLower, "buggy") then displayName = "Buggy"
                                            elseif string.find(nameLower, "mirado") then displayName = "Mirado"
                                            elseif string.find(nameLower, "bike") or string.find(nameLower, "motor") then displayName = "Motor"
                                            elseif string.find(nameLower, "scooter") then displayName = "Scooter"
                                            elseif string.find(nameLower, "coupe") then displayName = "Coupe RB"
                                            elseif string.find(nameLower, "brdm") then displayName = "BRDM"
                                            elseif string.find(nameLower, "boat") or string.find(nameLower, "aquarail") then displayName = "Thuyền"
                                            elseif string.find(nameLower, "glider") then displayName = "Tàu lượn"
                                            else displayName = "Xe (" .. string.sub(vehName, 1, 8) .. ")" end

                                            table.insert(activeVehicles, {act = veh, name = displayName, hasDriver = hasDriver})
                                        end
                                    end
                                end
                            end
                            _G.CachedVehicles = activeVehicles
                        end

                        if _G.CachedVehicles then
                            for _, item in ipairs(_G.CachedVehicles) do
                                local veh = item.act
                                if SafeIsValid(veh) and not veh.bHidden then
                                    local isShow = false
                                    if item.name == "Dacia" then isShow = _G.LexusConfig.EspVeh_Dacia
                                    elseif item.name == "UAZ" then isShow = _G.LexusConfig.EspVeh_UAZ
                                    elseif item.name == "Buggy" then isShow = _G.LexusConfig.EspVeh_Buggy
                                    elseif item.name == "Coupe RB" then isShow = _G.LexusConfig.EspVeh_Coupe
                                    elseif item.name == "Mirado" then isShow = _G.LexusConfig.EspVeh_Mirado
                                    elseif item.name == "Motor" or item.name == "Scooter" then isShow = _G.LexusConfig.EspVeh_Motor
                                    else isShow = _G.LexusConfig.EspVeh_Other end

                                    if isShow then
                                        local distM = 0
                                        PCall(function() distM = localPlayer:GetDistanceTo(veh) / 100 end)
                                        
                                        if distM > 0 and distM <= 300 then
                                            local text = string.format("%s [%dm]", item.name, math.floor(distM))
                                            local vehColor = item.hasDriver and {R=255, G=50, B=50, A=255} or {R=0, G=255, B=150, A=255}
                                            local dynamicScale = math.max(0.6, 1.1 - (distM / 500))
                                            
                                            MyHUD:AddDebugText(text, veh, 0.06, {X=0, Y=0, Z=50}, {X=0, Y=0, Z=50}, vehColor, true, false, true, nil, dynamicScale, true)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end

    end)
end

_G.LexusState.LoopToken = (_G.LexusState.LoopToken or 0) + 1 
local myToken = _G.LexusState.LoopToken

-- PURPOSE: Repeated runtime update ya scheduled task execute karta hai.
-- FEATURE 18.03: ExpiredTick
-- ------------------------------------------------------------
local function ExpiredTick()
    if not _G.LexusNotifiedPopup then
        PCall(function()
            local Msg = SafeRequire("client.slua.logic.common.logic_common_msg_box")
            if Msg and Msg.Show then
                Msg.Show(1, "MOD EXPIRED", "YOUR MOD VERSION HAS EXPIRED!\nPLEASE CONTACT ADMIN TO RENEW.\nInbox Tele @NEXALORD To Buy. If Someone Else Sold This To You, Congratulations, You've Been Scammed", 
                function() 
                    local Web = SafeRequire("client.slua.logic.url.logic_webview_sdk")
                    if Web and Web.OpenURL then Web:OpenURL("https://t.me/NEXALORD") end 
                end, 
                function() end, "CONTACT NOW", "NEXA")
                _G.LexusNotifiedPopup = true 
            end
        end)
        
        if not _G.LexusNotifiedPopup then
            local okTicker, ticker = PCall(require, "common.time_ticker") 
            if okTicker and ticker and ticker.AddTimerOnce then 
                ticker.AddTimerOnce(2.0, ExpiredTick) 
            end
        end
    end
end

-- PURPOSE: Repeated runtime update ya scheduled task execute karta hai.
-- FEATURE 18.04: FastTick
-- ------------------------------------------------------------
local function FastTick() 
    if false then -- [BYPASSED] 
        if not _G.LexusNotifiedExpire then
            Notify("MOD HAS EXPIRED! PLEASE CONTACT ADMIN TO RENEW!\nInbox Tele @NEXALORD To Buy. If Someone Else Sold This To You, Congratulations, You've Been Scammed")
            _G.LexusNotifiedExpire = true
            ExpiredTick() 
        end
        return 
    end

    if myToken ~= _G.LexusState.LoopToken then return end
    PCall(MainLoop) 
    local okTicker, ticker = PCall(require, "common.time_ticker") 
    if okTicker and ticker and ticker.AddTimerOnce then 
        ticker.AddTimerOnce(0.02, FastTick) 
    end 
end

if true then -- [BYPASSED]
    FastTick() 
    Notify("You Are Using My Vvip Mod 4. If You Don't Have A Key, Inbox Tele @NEXALORD To Buy. If Someone Else Sold This To You, Congratulations, You've Been Scammed")
else
    FastTick() 
end

-- ===================================================================================
-- ============================================================
-- FEATURE 19: SYSTEM HOOKS AND MORTAR AIM INTEGRATION
-- ============================================================
-- SYSTEM HOOKS TỪ BYPASS MỚI
-- ===================================================================================
-- ============================================================
-- MORTAR AIMBOT INTEGRATION
-- ============================================================
-- PURPOSE: System hooks aur mortar aiming integration ka additional logic rakhta hai.
-- FEATURE 19.01: INITIALIZATION / STATE
-- ------------------------------------------------------------
local MortarAim = {
    Config = {
        AimInterval = 0.03,
        MaxRange = 600.0,
        FOV = 40.0,
        BaseGravity = 980.0,
        SwipeBreakAngle = 3.5,
        PitchWeight = 0.3
    },
    lockedTarget = nil,
    lastAimRotation = nil,
    aimActive = false
}

-- PURPOSE: User notification, popup ya message display karta hai.
-- FEATURE 19.02: MortarNotify
-- ------------------------------------------------------------
local function MortarNotify(message)
    local fn = rawget(_G, "TrnDravix") or rawget(_G, "TrnDravix_log") or _G.Notify
    if type(fn) == "function" then
        PCall(fn, "[Mortar] " .. tostring(message))
    end
end

-- PURPOSE: Is function ka kaam login/key ya object validity verify karna hai.
-- FEATURE 19.03: MortarValid
-- ------------------------------------------------------------
local function MortarValid(value)
    if value == nil then return false end
    local slua = rawget(_G, "slua")
    if slua and type(slua.isValid) == "function" then
        local ok, result = PCall(slua.isValid, value)
        return ok and result == true
    end
    return true
end

-- PURPOSE: System hooks aur mortar aiming integration ka additional logic rakhta hai.
-- FEATURE 19.04: MortarNormalizeAngle
-- ------------------------------------------------------------
local function MortarNormalizeAngle(angle)
    while angle > 180.0 do angle = angle - 360.0 end
    while angle < -180.0 do angle = angle + 360.0 end
    return angle
end

-- PURPOSE: System hooks aur mortar aiming integration ka additional logic rakhta hai.
-- FEATURE 19.05: MortarAtan2
-- ------------------------------------------------------------
local function MortarAtan2(y, x)
    if x > 0 then return math.atan(y / x)
    elseif x < 0 and y >= 0 then return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then return math.pi / 2
    elseif x == 0 and y < 0 then return -math.pi / 2
    end
    return 0
end

-- PURPOSE: System hooks aur mortar aiming integration ka additional logic rakhta hai.
-- FEATURE 19.06: MortarSolveBallisticPitch
-- ------------------------------------------------------------
local function MortarSolveBallisticPitch(horizontal, vertical, velocity, gravity)
    local velocity2 = velocity * velocity
    local velocity4 = velocity2 * velocity2
    local discriminant = velocity4 - gravity * gravity * horizontal * horizontal
    discriminant = discriminant - 2.0 * gravity * vertical * velocity2
    if discriminant < 0 then return 45.0 end
    local root = math.sqrt(discriminant)
    local denominator = gravity * horizontal
    local angle = denominator == 0 and 90.0 or math.atan((velocity2 + root) / denominator) * (180.0 / math.pi)
    if angle < 45.0 then angle = 45.0 end
    if angle > 88.0 then angle = 88.0 end
    return angle
end

-- PURPOSE: System hooks aur mortar aiming integration ka additional logic rakhta hai.
-- FEATURE 19.07: MortarReverseMapPitch
-- ------------------------------------------------------------
local function MortarReverseMapPitch(ballistic_pitch)
    local value = (ballistic_pitch - 45.0) * 2.0930232558139537 - 60.0
    if value < -60.0 then value = -60.0 end
    if value > 30.0 then value = 30.0 end
    return value
end

-- PURPOSE: Target selection aur aiming behavior ko control karta hai.
-- FEATURE 19.08: MortarGetBallistics
-- ------------------------------------------------------------
local function MortarGetBallistics(weapon)
    local state, velocity, gravity_scale
    PCall(function() state = weapon and weapon.MortarAimState end)
    PCall(function()
        if weapon and type(weapon.GetBulletFireSpeedFromEntity) == "function" then
            velocity = tonumber(weapon:GetBulletFireSpeedFromEntity())
        end
    end)
    if not velocity or velocity <= 0 then velocity = state == 1 and 12520.0 or 9070.0 end
    PCall(function()
        local entity = weapon and weapon.ShootWeaponEntity
        if MortarValid(entity) and entity.LaunchGravityScale then
            gravity_scale = tonumber(entity.LaunchGravityScale)
        end
    end)
    if not gravity_scale or gravity_scale <= 0 then gravity_scale = state == 1 and 4.0 or 2.8 end
    return velocity, MortarAim.Config.BaseGravity * gravity_scale
end

-- PURPOSE: Current weapon ya weapon data ko detect aur process karta hai.
-- FEATURE 19.09: IsMortarWeapon
-- ------------------------------------------------------------
local function IsMortarWeapon(weapon)
    if not MortarValid(weapon) then return false end
    local state
    PCall(function() state = weapon.MortarState end)
    if state ~= nil and tonumber(state) ~= 2 then return false end
    local name = ""
    PCall(function() name = string.lower(tostring(weapon)) end)
    return string.find(name, "mortar", 1, true) ~= nil or state == 2
end

-- PURPOSE: Target selection aur aiming behavior ko control karta hai.
-- FEATURE 19.10: _G.MortarAimTick
-- ------------------------------------------------------------
function _G.MortarAimTick()
    if not HasPanelAuthorization() then return end
    if not _G.LexusConfig.MortarAim then return end
    
    local okData, GameplayData = PCall(require, "GameLua.GameCore.Data.GameplayData")
    if not okData or not GameplayData then return end
    
    local pc = GameplayData.GetPlayerController()
    local player = pc and pc:GetPlayerCharacterSafety()
    if not MortarValid(player) or not MortarValid(pc) then return end
    
    local camera = pc.PlayerCameraManager
    if not MortarValid(camera) then return end
    
    local camera_rotation
    PCall(function() camera_rotation = camera:GetCameraRotation() end)
    if not camera_rotation then return end
    
    local weapon = player.CurrentWeapon
    if not weapon and type(player.GetCurrentWeapon) == "function" then
        weapon = player:GetCurrentWeapon()
    end
    
    if not IsMortarWeapon(weapon) then
        if MortarAim.aimActive then
            MortarAim.aimActive = false
            MortarAim.lockedTarget = nil
            MortarAim.lastAimRotation = nil
            MortarNotify("Auto Aim OFF")
        end
        return
    end
    
    if not MortarAim.aimActive then
        MortarAim.aimActive = true
        MortarNotify("Mortar Deployed - AIM ON")
    end
    
    if MortarAim.lockedTarget and MortarAim.lastAimRotation then
        local yaw_delta = math.abs(MortarNormalizeAngle(camera_rotation.Yaw - MortarAim.lastAimRotation.Yaw))
        local pitch_delta = math.abs(MortarNormalizeAngle(camera_rotation.Pitch - MortarAim.lastAimRotation.Pitch))
        if yaw_delta > MortarAim.Config.SwipeBreakAngle or pitch_delta > MortarAim.Config.SwipeBreakAngle then
            MortarAim.lockedTarget = nil
            MortarAim.lastAimRotation = nil
            MortarNotify("Target Unlocked (Swiped)")
        end
    end
    
    if MortarAim.lockedTarget then
        local isEnemy = true
        PCall(function()
            local lpTeam = player.TeamID or (player.PlayerState and player.PlayerState.TeamNum)
            local tTeam = MortarAim.lockedTarget.TeamID or (MortarAim.lockedTarget.PlayerState and MortarAim.lockedTarget.PlayerState.TeamNum)
            if lpTeam == tTeam then isEnemy = false end
        end)
        local isDead = MortarAim.lockedTarget.bDead or MortarAim.lockedTarget.bIsDead or MortarAim.lockedTarget.bIsDeadFlag
        if not isEnemy or isDead or not MortarValid(MortarAim.lockedTarget) then
            MortarAim.lockedTarget = nil
        end
    end
    
    if not MortarAim.lockedTarget then
        local camera_location = camera:GetCameraLocation()
        local best_score = MortarAim.Config.FOV
        local characters = {}
        PCall(function() characters = GameplayData.GetAllPlayerCharacters() end)
        
        for _, actor in pairs(characters or {}) do
            if MortarValid(actor) and actor ~= player then
                local isEnemy = true
                PCall(function()
                    local lpTeam = player.TeamID or (player.PlayerState and player.PlayerState.TeamNum)
                    local tTeam = actor.TeamID or (actor.PlayerState and actor.PlayerState.TeamNum)
                    if lpTeam == tTeam then isEnemy = false end
                end)
                local isDead = actor.bDead or actor.bIsDead or actor.bIsDeadFlag
                
                if isEnemy and not isDead then
                    local location = type(actor.K2_GetActorLocation) == "function" and actor:K2_GetActorLocation()
                    if location then
                        local dx = location.X - camera_location.X
                        local dy = location.Y - camera_location.Y
                        local dz = location.Z - camera_location.Z
                        local horizontal = math.sqrt(dx * dx + dy * dy)
                        local distance = horizontal / 100.0
                        
                        if distance <= MortarAim.Config.MaxRange then
                            local yaw = MortarAtan2(dy, dx) * (180.0 / math.pi)
                            local pitch = MortarAtan2(dz, horizontal) * (180.0 / math.pi)
                            local yaw_delta = math.abs(MortarNormalizeAngle(yaw - camera_rotation.Yaw))
                            local pitch_delta = math.abs(MortarNormalizeAngle(pitch - camera_rotation.Pitch))
                            
                            if yaw_delta <= MortarAim.Config.FOV then
                                local score = math.sqrt(yaw_delta * yaw_delta + (pitch_delta * MortarAim.Config.PitchWeight) ^ 2)
                                if score < best_score then
                                    best_score = score
                                    MortarAim.lockedTarget = actor
                                end
                            end
                        end
                    end
                end
            end
        end
        if MortarAim.lockedTarget then MortarNotify("Target Locked!") end
    end
    
    if not MortarAim.lockedTarget then
        MortarAim.lastAimRotation = nil
        return
    end
    
    local origin = type(player.K2_GetActorLocation) == "function" and player:K2_GetActorLocation()
    local target = type(MortarAim.lockedTarget.K2_GetActorLocation) == "function" and MortarAim.lockedTarget:K2_GetActorLocation()
    
    if not origin or not target then
        MortarAim.lockedTarget = nil
        return
    end
    
    local dx, dy, dz = target.X - origin.X, target.Y - origin.Y, target.Z - origin.Z
    local horizontal = math.sqrt(dx * dx + dy * dy)
    local velocity, gravity = MortarGetBallistics(weapon)
    local ballistic_pitch = MortarSolveBallisticPitch(horizontal, dz, velocity, gravity)
    local pitch = MortarReverseMapPitch(ballistic_pitch)
    local yaw = MortarAtan2(dy, dx) * (180.0 / math.pi)
    -- Humanize: Add slight randomness to prevent server-side robotic detection
    local humanPitch = pitch + (math.random() * 0.4 - 0.2)
    local humanYaw = yaw + (math.random() * 0.4 - 0.2)
    local rotation = FRotator(humanPitch, humanYaw, 0)
    
    PCall(function()
        camera.bLimitViewPitch = false
        camera.bLimitViewYaw = false
        camera.ViewPitchMin = -89.9
        camera.ViewPitchMax = 89.9
        if type(player.K2_SetActorRotation) == "function" and type(FRotator) == "function" then
            player:K2_SetActorRotation(FRotator(0, humanYaw, 0), false)
        end
        player.BaseAimRotation = rotation
        pc.ControlRotation = rotation
    end)
    MortarAim.lastAimRotation = rotation
end

-- PURPOSE: Starts the Mortar Aimbot timer loop.
-- FEATURE 19.10.1: MortarAim.Start
-- ------------------------------------------------------------
function MortarAim.Start()
    if MortarAim.started then return end
    local okTicker, ticker = PCall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerLoop then
        ticker.AddTimerLoop(0, _G.MortarAimTick, -1, MortarAim.Config.AimInterval)
        MortarAim.started = true
        MortarNotify("System Started")
    end
end

-- PURPOSE: System hooks aur mortar aiming integration ka additional logic rakhta hai.
-- FEATURE 19.11: InitAllModSystems
-- ------------------------------------------------------------
local function InitAllModSystems()
    if not HasPanelAuthorization() then
        print("[NEXA] Access Blocked: Menu and features are OFF (Not Authorized)")
        return
    end
    -- if false then -- [BYPASSED] return end -- [BYPASSED] 

    PCall(function()
        if _G.StartBypass_VIP_v3 then _G.StartBypass_VIP_v3() end
        if _G.InitializeFeature03PresentationHooks then _G.InitializeFeature03PresentationHooks() end
        if MortarAim.Start then MortarAim.Start() end
        if UnlockTPPSwitchButton then UnlockTPPSwitchButton() end
    end)

    local GameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or SafeRequire("GameLua.GameCore.Data.GameplayData")
    if not GameplayData then return end

    PCall(function()
        local LocalPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
        if SafeIsValid(LocalPlayer) then
            if LocalPlayer.bHasShownDevNotice == nil then
                LocalPlayer.bHasShownDevNotice = false 
                LocalPlayer.bHasShownExpiredNotice = false 
                LocalPlayer.bIsDeadFlag = false
            end
        end
    end)
end

-- DisableAllModSystems removed for stability.

-- Mod initialization is now handled by CheckLoginAndInit after successful verification.
-- InitAllModSystems is defined as a local function but we need it accessible for the callback.
_G.InitAllModSystems = InitAllModSystems

-- ==============================================================================
-- ================== PHẦN RETURN ĐƯỢC GIỮ NGUYÊN TỪ CODE GỐC ===================
-- ==============================================================================

-- ==========================================
local class = SafeRequire("class")
local CCharacterBase = SafeRequire("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
-- =========================
-- SNAPLINE ONLY (ADDED)
-- =========================
PlayerMapMarker = PlayerMapMarker or {}

-- =========================
-- SNAPLINE ONLY
-- =========================

PlayerMapMarker.bUseSnapLines = (_G.LexusConfig and _G.LexusConfig.ADESP_ShowSnapLines) ~= false
PlayerMapMarker.SnapLineThickness = 1.0
PlayerMapMarker.SnapLineOriginY = 76
PlayerMapMarker.SnapLineOriginOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetX = 0
PlayerMapMarker.SnapLineHeadOffsetY = -14
PlayerMapMarker.SnapLineColor =
    FLinearColor and FLinearColor(0.6, 0.0, 0.0, 1.0)
    or {R=150, G=0, B=0, A=255}
PlayerMapMarker.SnapLineOpacity = 0.7

PlayerMapMarker.SnapLineWidgets =
    PlayerMapMarker.SnapLineWidgets or {}

function PlayerMapMarker.CreateSnapLine()
    if not PlayerMapMarker.ESPCanvas
        or not SafeIsValid(PlayerMapMarker.ESPCanvas) then
        return nil
    end

    local Border = nil

    pcall(function()
        Border = CGame:NewObjectFromPath(
            "/Script/UMG.Border",
            PlayerMapMarker.ESPCanvas
        )
    end)

    if not Border or not SafeIsValid(Border) then
        return nil
    end

    local color = PlayerMapMarker.SnapLineColor
        or (FLinearColor and
            FLinearColor(
                1.0, 1.0, 1.0,
                PlayerMapMarker.SnapLineOpacity or 0.7
            )
            or {
                R=1,G=1,B=1,
                A=PlayerMapMarker.SnapLineOpacity or 0.7
            })

    pcall(function()
        Border:SetBrushColor(color)
    end)

    pcall(function()
        Border:SetWidgetVisibility(
            UEnums.ESlateVisibility.SelfHitTestInvisible
        )
    end)

    pcall(function()
        Border.RenderTransformPivot =
            FVector2D and FVector2D(0.0, 0.5)
            or {X=0,Y=0.5}

        Border:SetRenderTransformPivot(
            FVector2D and FVector2D(0.0, 0.5)
            or {X=0,Y=0.5}
        )
    end)

    local Slot = nil

    pcall(function()
        Slot = PlayerMapMarker.ESPCanvas:AddChildToCanvas(Border)

        if Slot then
            Slot:SetAutoSize(false)
            Slot:SetZOrder(1)
        end
    end)

    return {
        Widget = Border,
        Slot = Slot
    }
end


function PlayerMapMarker.GetSnapLineStartPos(PC)

    local screenPixelW = 0
    local screenPixelH = 0
    local scale = 1.0

    pcall(function()
        if PC and PC.GetViewportSize then

            local vs =
                FVector2D and FVector2D(0, 0)
                or {X=0,Y=0}

            PC:GetViewportSize(vs)

            if vs and vs.X and vs.X > 200 then
                screenPixelW = vs.X
                screenPixelH = vs.Y
            end
        end
    end)

    if screenPixelW <= 200 then
        pcall(function()

            local WLL = SafeImport("WidgetLayoutLibrary")

            if WLL and WLL.GetViewportSize then

                local vs = WLL.GetViewportSize(PC)

                if vs and vs.X and vs.X > 200 then
                    screenPixelW = vs.X
                    screenPixelH = vs.Y
                end
            end
        end)
    end

    pcall(function()

        local WLL = SafeImport("WidgetLayoutLibrary")

        if WLL and WLL.GetViewportScale then

            local s = WLL.GetViewportScale(PC)

            if s and type(s) == "number" and s > 0 then
                scale = s
            end
        end
    end)

    if screenPixelW <= 200 then
        screenPixelW =
            (PlayerMapMarker._cachedViewportW or 1920) * scale

        screenPixelH =
            (PlayerMapMarker._cachedViewportH or 1080) * scale
    end

    if not PlayerMapMarker._CachedTopCenterPixel then
        PlayerMapMarker._CachedTopCenterPixel =
            FVector2D and FVector2D(0, 0)
            or {X=0,Y=0}
    end

    PlayerMapMarker._CachedTopCenterPixel.X =
        screenPixelW / 2.0

    PlayerMapMarker._CachedTopCenterPixel.Y =
        (PlayerMapMarker.SnapLineOriginY or 50) * scale

    local fromCanvasPos =
        PlayerMapMarker.ScreenPixelToCanvasLocal(
            PC,
            PlayerMapMarker._CachedTopCenterPixel
        )

    local fromX =
        fromCanvasPos.X +
        (PlayerMapMarker.SnapLineOriginOffsetX or 0)

    local fromY = fromCanvasPos.Y

    return fromX, fromY
end


function PlayerMapMarker.UpdateSnapLine(
    KeyStr,
    CanvasPos,
    bOnScreen,
    fromX,
    fromY,
    Character,
    PC
)

    if not PlayerMapMarker.bUseSnapLines then
        return
    end

    if not PlayerMapMarker.ESPCanvas
        or not SafeIsValid(PlayerMapMarker.ESPCanvas) then
        return
    end

    local LineData =
        PlayerMapMarker.SnapLineWidgets[KeyStr]

    if not bOnScreen
        or not CanvasPos
        or not (slua and slua.isValid and SafeIsValid(Character))
        or not (slua and slua.isValid and SafeIsValid(PC)) then

        if LineData
            and LineData.Widget
            and SafeIsValid(LineData.Widget) then

            pcall(function()
                LineData.Widget:SetWidgetVisibility(
                    UEnums.ESlateVisibility.Collapsed
                )
            end)
        end

        return
    end

    local bIsNew = false

    if not LineData then

        LineData =
            PlayerMapMarker.CreateSnapLine()

        if not LineData
            or not LineData.Widget
            or not LineData.Slot then
            return
        end

        PlayerMapMarker.SnapLineWidgets[KeyStr] =
            LineData

        bIsNew = true
    end

    local Widget = LineData.Widget
    local Slot = LineData.Slot

    pcall(function()
        Widget:SetWidgetVisibility(
            UEnums.ESlateVisibility.SelfHitTestInvisible
        )
    end)

    if not LineData._PivotSet then

        pcall(function()
            Widget.RenderTransformPivot =
                FVector2D and FVector2D(0.0, 0.5)
                or {X=0,Y=0.5}

            Widget:SetRenderTransformPivot(
                FVector2D and FVector2D(0.0, 0.5)
                or {X=0,Y=0.5}
            )
        end)

        LineData._PivotSet = true
    end

    local bIsBot =
        PlayerMapMarker.IsAI(Character)

    local lineColor =
        bIsBot
        and FLinearColor(1.0, 0.0, 0.0, 0.95)
        or FLinearColor(0.0, 1.0, 0.0, 0.95)

    local currentLineColorHash =
        bIsBot and "bot" or "player"

    if LineData._cachedColorHash
        ~= currentLineColorHash then

        pcall(function()
            Widget:SetBrushColor(lineColor)
        end)

        LineData._cachedColorHash =
            currentLineColorHash
    end

    local toX =
        CanvasPos.X +
        (PlayerMapMarker.SnapLineHeadOffsetX or 0)

    local toY =
        CanvasPos.Y +
        (PlayerMapMarker.SnapLineHeadOffsetY or 0)

    local dx = toX - fromX
    local dy = toY - fromY

    local length =
        math.sqrt(dx * dx + dy * dy)

    local thickness =
        PlayerMapMarker.SnapLineThickness or 1.5

    local angle_rad =
        (math.atan2 and math.atan2(dy, dx))
        or math.atan(dy, dx)

    local angle =
        angle_rad * 57.29577951308232

    local threshold = 2.0

    LineData.lastToX =
        LineData.lastToX or -999

    LineData.lastToY =
        LineData.lastToY or -999

    if math.abs(toX - LineData.lastToX) > threshold
        or math.abs(toY - LineData.lastToY) > threshold then

        LineData.lastToX = toX
        LineData.lastToY = toY

        if not LineData._CachedPosVec then

            LineData._CachedPosVec =
                FVector2D
                and FVector2D(
                    fromX,
                    fromY - thickness / 2.0
                )
                or {
                    X=fromX,
                    Y=fromY - thickness / 2.0
                }

            LineData._CachedSizeVec =
                FVector2D
                and FVector2D(length, thickness)
                or {
                    X=length,
                    Y=thickness
                }

        else

            LineData._CachedPosVec.X =
                fromX

            LineData._CachedPosVec.Y =
                fromY - thickness / 2.0

            LineData._CachedSizeVec.X =
                length

            LineData._CachedSizeVec.Y =
                thickness
        end

        pcall(function()

            Slot:SetPosition(
                LineData._CachedPosVec
            )

            Slot:SetSize(
                LineData._CachedSizeVec
            )

            if bIsNew then
                Slot:SetZOrder(1)
            end
        end)

        pcall(function()
            Widget:SetRenderAngle(angle)
        end)
    end
end


function PlayerMapMarker.RemoveSnapLine(KeyStr)

    local LineData =
        PlayerMapMarker.SnapLineWidgets[KeyStr]

    if LineData
        and LineData.Widget
        and SafeIsValid(LineData.Widget) then

        pcall(function()
            LineData.Widget:RemoveFromParent()
            LineData.Widget:ConditionalBeginDestroy()
        end)

        PlayerMapMarker.SnapLineWidgets[KeyStr] = nil
    end
end


function PlayerMapMarker.ClearAllSnapLines()

    for KeyStr, LineData in
        pairs(PlayerMapMarker.SnapLineWidgets) do

        if LineData
            and LineData.Widget
            and SafeIsValid(LineData.Widget) then

            pcall(function()
                LineData.Widget:RemoveFromParent()
                LineData.Widget:ConditionalBeginDestroy()
            end)
        end
    end

    PlayerMapMarker.SnapLineWidgets = {}
end

return SafeRequire("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"
  },
  {
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"
  },
  {
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"
  },
  {
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"
  },
  {
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"
  },
  {
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"
  },
  {
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"
  },
  {
    BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  }
}, "BRPlayerCharacterBase")
