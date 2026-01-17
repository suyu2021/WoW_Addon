if not BrAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

-- Lua APIs
local tinsert, tremove, wipe = table.insert, table.remove, wipe
local pairs, type, error = pairs, type, error
local _G = _G

-- WoW APIs
local GetScreenWidth, GetScreenHeight, CreateFrame, UnitName
  = GetScreenWidth, GetScreenHeight, CreateFrame, UnitName
local StaticPopup_Show, StaticPopup_FindVisible, ReloadUI = StaticPopup_Show, StaticPopup_FindVisible, ReloadUI


local AceGUI = LibStub("AceGUI-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

-- =======================
-- Narrow layout tuning
-- Targets (allow small visual tweaks via margins, keep panel widths stable)
local BRA_LEFT_PANEL_WIDTH = 210
local BRA_RIGHT_PANEL_WIDTH = 260
local BRA_FRAME_MARGIN_LEFT = 10
local BRA_FRAME_MARGIN_RIGHT = 10

-- Right panel anchors use the right margin inset.
local BRA_RIGHT_PANEL_LEFT_OFFSET = -(BRA_FRAME_MARGIN_RIGHT + BRA_RIGHT_PANEL_WIDTH)

-- =======================
-- Docking to BanruoUI (right side)
--
-- The bordered templates used by BanruoUI and BrA Options have transparent/inner padding.
-- Anchoring outer frames edge-to-edge leaves a visible gap between the *drawn* borders.
-- We compensate by intentionally overlapping the frames on X.
local BRA_DOCK_TO_BANRUOUI = true
local BRA_DOCK_VISUAL_X = -24  -- tuned for UI-DialogBox-Border inset(11/12) + BrA BG inset(11/12)
local BRA_DOCK_VISUAL_Y = 0

local function BrA_DockToBanruoUIRight(frame)
  if not BRA_DOCK_TO_BANRUOUI or not frame or not frame.ClearAllPoints then return end
  local ban = _G and _G.BanruoUI_MainFrame
  if not ban or not ban.IsShown or not ban:IsShown() then return end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", ban, "TOPRIGHT", BRA_DOCK_VISUAL_X, BRA_DOCK_VISUAL_Y)
end



-- =======================
-- Narrow layout hotfix: force right-side controls into a single column after rebuild
-- Goal: prevent 2-column Flow assumptions from breaking at narrow widths.
local function BrA_ForceSingleColumn(widget, depth)
  if not widget then return end
  depth = depth or 0
  if depth > 8 then return end

  -- Prefer vertical list layout on containers
  if widget.SetLayout then
    pcall(widget.SetLayout, widget, "List")
  end
  if widget.SetFullWidth then
    pcall(widget.SetFullWidth, widget, true)
  end
  if widget.SetRelativeWidth then
    pcall(widget.SetRelativeWidth, widget, 1.0)
  end

  local children = widget.children
  if type(children) == "table" then
    for _, child in pairs(children) do
      if child then
        if child.SetFullWidth then pcall(child.SetFullWidth, child, true) end
        if child.SetRelativeWidth then pcall(child.SetRelativeWidth, child, 1.0) end
        -- If child is also a container, force it vertical too
        if child.SetLayout then pcall(child.SetLayout, child, "List") end
        if child.children then BrA_ForceSingleColumn(child, depth + 1) end
      end
    end
  end

  if widget.DoLayout then
    pcall(widget.DoLayout, widget)
  end
end


-- =========================
-- v2.6.2: Reload prompt when closing Options
-- - No polling/ticker; triggers only on Options frame hide (after first show)
-- =========================
local BRAURAS_RELOAD_POPUP_KEY = "BRAURAS_RELOAD_ON_OPTIONS_CLOSE"

if not StaticPopupDialogs[BRAURAS_RELOAD_POPUP_KEY] then
  StaticPopupDialogs[BRAURAS_RELOAD_POPUP_KEY] = {
    text = "|cFF8800FFBrAuras|r\n需要重载界面 (/reload) 才能完全生效。\n现在重载吗？",
    button1 = RELOADUI or "Reload",
    button2 = CANCEL,
    OnAccept = function()
      ReloadUI()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
  }
end

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")
local SharedMedia = LibStub("LibSharedMedia-3.0")

---@class BrAuras
local BrAuras = BrAuras
local L = BrAuras.L

local displayButtons = OptionsPrivate.displayButtons
local tempGroup = OptionsPrivate.tempGroup
local aceOptions = {}
local function ForceSingleColumn(container)
  if not container or not container.children then return end
  if container.SetLayout then
    container:SetLayout("List")
  end
  for _, child in pairs(container.children) do
    if child.SetFullWidth then
      child:SetFullWidth(true)
    end
    if child.children then
      ForceSingleColumn(child)
    end
  end
end


local function CreateFrameSizer(frame, callback, position)
  callback = callback or (function() end)

  local left, right, top, bottom, xOffset1, yOffset1, xOffset2, yOffset2
  if position == "BOTTOMLEFT" then
    left, right, top, bottom = 1, 0, 0, 1
    xOffset1, yOffset1 = 1, 1
    xOffset2, yOffset2 = 0, 0
  elseif position == "BOTTOMRIGHT" then
    left, right, top, bottom = 0, 1, 0, 1
    xOffset1, yOffset1 = 0, 1
    xOffset2, yOffset2 = -1, 0
  elseif position == "TOPLEFT" then
    left, right, top, bottom = 1, 0, 1, 0
    xOffset1, yOffset1 = 1, 0
    xOffset2, yOffset2 = 0, -1
  elseif position == "TOPRIGHT" then
    left, right, top, bottom = 0, 1, 1, 0
    xOffset1, yOffset1 = 0, 0
    xOffset2, yOffset2 = -1, -1
  end

  local handle = CreateFrame("Button", nil, frame)
  handle:SetPoint(position, frame)
  handle:SetSize(25, 25)
  handle:EnableMouse()

  handle:SetScript("OnMouseDown", function()
    frame:StartSizing(position)
  end)

  handle:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    callback()
  end)

  local normal = handle:CreateTexture(nil, "OVERLAY")
  normal:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  normal:SetTexCoord(left, right, top, bottom)
  normal:SetPoint("BOTTOMLEFT", handle, xOffset1, yOffset1)
  normal:SetPoint("TOPRIGHT", handle, xOffset2, yOffset2)
  handle:SetNormalTexture(normal)

  local pushed = handle:CreateTexture(nil, "OVERLAY")
  pushed:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  pushed:SetTexCoord(left, right, top, bottom)
  pushed:SetPoint("BOTTOMLEFT", handle, xOffset1, yOffset1)
  pushed:SetPoint("TOPRIGHT", handle, xOffset2, yOffset2)
  handle:SetPushedTexture(pushed)

  local highlight = handle:CreateTexture(nil, "OVERLAY")
  highlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  highlight:SetTexCoord(left, right, top, bottom)
  highlight:SetPoint("BOTTOMLEFT", handle, xOffset1, yOffset1)
  highlight:SetPoint("TOPRIGHT", handle, xOffset2, yOffset2)
  handle:SetHighlightTexture(highlight)

  return handle
end

-- v2.6.2.33: narrow layout target width
local defaultWidth = BRA_FRAME_MARGIN_LEFT + BRA_LEFT_PANEL_WIDTH + BRA_RIGHT_PANEL_WIDTH + BRA_FRAME_MARGIN_RIGHT
local defaultHeight = 665
local minWidth = defaultWidth
local minHeight = 240



function OptionsPrivate.CreateFrame()
  LibDD:Create_UIDropDownMenu("BrAuras_DropDownMenu", nil)
  local frame
  local db = OptionsPrivate.savedVars.db
  local odb = OptionsPrivate.savedVars.odb

  frame = CreateFrame("Frame", "BrAurasOptions", UIParent, "PortraitFrameTemplate")
  local color = CreateColorFromHexString("ff120d08") -- PANEL_BACKGROUND_COLOR
  local r, g, b = color:GetRGB()
  -- v2.6.2.19: Keep the template Bg very subtle so BanruoUI-style skin layers are the primary look.
  -- This avoids double-darkening / muddying when our custom textures are present.
  frame.Bg:SetColorTexture(r, g, b, 0.08)
  frame.Bg.colorTexture = {r, g, b, 0.08}

  -- ===== BanruoUI-style background (overlay, non-interactive) =====
  local function ApplyBanruoBackground()

local function SafeVerticalGradient(tex, r1,g1,b1,a1, r2,g2,b2,a2)
  if not tex then return end
  if tex.SetGradientAlpha then
    tex:SetGradientAlpha("VERTICAL", r1,g1,b1,a1, r2,g2,b2,a2)
  elseif tex.SetGradient and CreateColor then
            -- Some clients expose SetGradient but not SetGradientAlpha
            tex:SetGradient("VERTICAL",
              CreateColor(r1,g1,b1,a1),
              CreateColor(r2,g2,b2,a2)
            )
  else
    -- Fallback: no gradient support, use a flat overlay closer to the darker end
    tex:SetColorTexture(r2,g2,b2, math.max(a1, a2))
  end
end
    if not frame then return end

    -- Create once (textures only, no overlay frame to avoid covering content)
    if not frame.BanruoMainBG then
      -- Main warm dark panel background (avoid title bar area)
      local main = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
      -- Match BanruoUI's "UI-DialogBox-Background-Dark" feel (dark-warm material, not pure black)
      main:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
      main:SetHorizTile(true)
      main:SetVertTile(true)
      -- Keep a similar inset thickness to BanruoUI (L11/R12/B11); top is limited by the PortraitFrame title bar.
      main:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -24)
      main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 11)
      main:SetVertexColor(1, 1, 1, 0.92)
      frame.BanruoMainBG = main

      -- Subtle vertical vignette / depth
      local shade = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
      shade:SetAllPoints(main)
      shade:SetColorTexture(0, 0, 0, 1)
      -- Depth: subtle top, stronger bottom
      SafeVerticalGradient(shade, 0,0,0,0.14,  0,0,0,0.48)
      frame.BanruoShadeBG = shade

      -- Top warmth hint (very subtle)
      local warm = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
      warm:SetAllPoints(main)
      warm:SetColorTexture(0.35, 0.20, 0.08, 1)
      -- Warm hint: extremely restrained (edge/specular feel)
      SafeVerticalGradient(warm, 0.35,0.20,0.08,0.06,  0.35,0.20,0.08,0.00)
      frame.BanruoWarmBG = warm
    else
      -- Keep anchored points stable if template/layout changed anything
      local main = frame.BanruoMainBG
      if main then
        main:ClearAllPoints()
        main:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -24)
        main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 11)
      end
    end
  end



  function OptionsPrivate.SetTitle(title)
    local text = "BrAuras " .. BrAuras.versionString
    if title and title ~= "" then
      text = ("%s - %s"):format(text, title)
    end
    BrAurasOptionsTitleText:SetText(text)
  end

  tinsert(UISpecialFrames, frame:GetName())
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(minWidth, minHeight)
  frame:SetFrameStrata("DIALOG")
  -- Workaround classic issue

  local serverTime = C_DateAndTime.GetServerTimeLocal()
  if serverTime >= 1748736000 -- June 1.
     and serverTime <= 1751328000 -- July 1.
  then
    BrAurasOptionsPortrait:SetTexture([[Interface\AddOns\BrAuras\Media\Textures\logo_256_round_pride.tga]])
  else
    BrAurasOptionsPortrait:SetTexture([[Interface\AddOns\BrAuras\Media\Textures\logo_256_round.tga]])
  end


  -- v2.6.2.x: Hide WA portrait logo + ring (PortraitFrameTemplate parts)
  if _G.BrAurasOptionsPortrait then _G.BrAurasOptionsPortrait:Hide() end
  if _G.BrAurasOptionsPortraitFrame then _G.BrAurasOptionsPortraitFrame:Hide() end
  if _G.BrAurasOptionsPortraitBorder then _G.BrAurasOptionsPortraitBorder:Hide() end
  if frame.Portrait then frame.Portrait:Hide() end
  if frame.PortraitFrame then frame.PortraitFrame:Hide() end
  if frame.PortraitBorder then frame.PortraitBorder:Hide() end
  if frame.PortraitContainer then frame.PortraitContainer:Hide() end

  local function BrAurasOptions_HidePortraitBits(f)
    -- Keep portrait/logo ring hidden even if the Blizzard template tries to re-show it on layout.
    if type(ButtonFrameTemplate_HidePortrait) == "function" then
      pcall(ButtonFrameTemplate_HidePortrait, f)
    end
    if _G.BrAurasOptionsPortrait then _G.BrAurasOptionsPortrait:Hide() end
    if _G.BrAurasOptionsPortraitFrame then _G.BrAurasOptionsPortraitFrame:Hide() end
    if _G.BrAurasOptionsPortraitBorder then _G.BrAurasOptionsPortraitBorder:Hide() end
    if f.Portrait then f.Portrait:Hide() end
    if f.PortraitFrame then f.PortraitFrame:Hide() end
    if f.PortraitBorder then f.PortraitBorder:Hide() end
    if f.PortraitContainer then f.PortraitContainer:Hide() end
  end

  if frame.TitleBg then frame.TitleBg:Hide() end -- remove leftover circular title art (if any)
  frame.window = "default"

  local xOffset, yOffset

  if db.frame then
    -- Convert from old settings to new
    odb.frame = db.frame
    if odb.frame.xOffset and odb.frame.yOffset then
      odb.frame.xOffset = odb.frame.xOffset + GetScreenWidth() - (odb.frame.width or defaultWidth) / 2
      odb.frame.yOffset = odb.frame.yOffset + GetScreenHeight()
    end
    db.frame = nil
  end

  if odb.frame then
    xOffset, yOffset = odb.frame.xOffset, odb.frame.yOffset
  end

  if not (xOffset and yOffset) then
    xOffset = GetScreenWidth() / 2
    yOffset = GetScreenHeight() - defaultHeight / 2
  end

  frame:SetPoint("TOP", UIParent, "BOTTOMLEFT", xOffset, yOffset)
  if BRA_DOCK_TO_BANRUOUI and C_Timer and C_Timer.After then
    C_Timer.After(0, function() BrA_DockToBanruoUIRight(frame) end)
  elseif BRA_DOCK_TO_BANRUOUI then
    BrA_DockToBanruoUIRight(frame)
  end
  frame:Hide()

  -- v2.6.2: mark that options has been shown at least once
  frame._braurasShownOnce = false
  frame:HookScript("OnShow", function()
    frame._braurasShownOnce = true
    BrAurasOptions_HidePortraitBits(frame)
    ApplyBanruoBackground()
    if BRA_DOCK_TO_BANRUOUI and C_Timer and C_Timer.After then
      C_Timer.After(0, function() BrA_DockToBanruoUIRight(frame) end)
    elseif BRA_DOCK_TO_BANRUOUI then
      BrA_DockToBanruoUIRight(frame)
    end

    -- v2.6.2.18 (B-verify): Keep CloseButton above the draggable TitleContainer
    -- so hover/click are not eaten by TitleContainer.
    if frame.CloseButton and frame.TitleContainer then
      frame.CloseButton:SetFrameLevel(frame.TitleContainer:GetFrameLevel() + 2)
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function() BrAurasOptions_HidePortraitBits(frame) end)
    end

  frame:HookScript("OnSizeChanged", function()
    ApplyBanruoBackground()
  end)
  end)

  frame:SetScript("OnHide", function()
    local suspended = OptionsPrivate.Private.PauseAllDynamicGroups()

    OptionsPrivate.Private.ClearFakeStates()

    for id, data in pairs(OptionsPrivate.Private.regions) do
      if data.region then
        data.region:Collapse()
        data.region:OptionsClosed()
        if OptionsPrivate.Private.clones[id] then
          for _, cloneRegion in pairs(OptionsPrivate.Private.clones[id]) do
            cloneRegion:Collapse()
            cloneRegion:OptionsClosed()
          end
        end
      end
    end

    OptionsPrivate.Private.ResumeAllDynamicGroups(suspended)
    OptionsPrivate.Private.Resume()

    if OptionsPrivate.Private.mouseFrame then
      OptionsPrivate.Private.mouseFrame:OptionsClosed()
    end

    if OptionsPrivate.Private.personalRessourceDisplayFrame then
      OptionsPrivate.Private.personalRessourceDisplayFrame:OptionsClosed()
    end

    if frame.dynamicTextCodesFrame  then
      frame.dynamicTextCodesFrame:Hide()
    end

    if frame.moversizer then
      frame.moversizer:OptionsClosed()
    end

    -- v2.6.2: prompt /reload when closing options (after the frame has been shown at least once)
    if frame._braurasShownOnce and not StaticPopup_FindVisible(BRAURAS_RELOAD_POPUP_KEY) then
      StaticPopup_Show(BRAURAS_RELOAD_POPUP_KEY)
    end
  end)

  local width, height

  if odb.frame then
    width, height = odb.frame.width, odb.frame.height
  end

  -- v2.6.2.33: enforce a narrow default on load (stored widths from older wide layouts are ignored)
  if width and width > defaultWidth then
    width = defaultWidth
  end

  if not (width and height) then
    width, height = defaultWidth, defaultHeight
  end

  width = max(width, minWidth)
  height = max(height, minHeight)
  frame:SetWidth(width)
  frame:SetHeight(height)


  OptionsPrivate.SetTitle()

  local function commitWindowChanges()
    if not frame.minimized then
      local xOffset = frame:GetRight()-(frame:GetWidth()/2)
      local yOffset = frame:GetTop()
      odb.frame = odb.frame or {}
      odb.frame.xOffset = xOffset
      odb.frame.yOffset = yOffset
      odb.frame.width = frame:GetWidth()
      odb.frame.height = frame:GetHeight()
    end
  end

  if not frame.TitleContainer then
    frame.TitleContainer = CreateFrame("Frame", nil, frame)
    frame.TitleContainer:SetAllPoints(frame.TitleBg)
  end

  frame.TitleContainer:SetScript("OnMouseDown", function()
    frame:StartMoving()
  end)
  frame.TitleContainer:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    commitWindowChanges()
  end)

  -- v2.6.2.18 (B-verify): Raise CloseButton above TitleContainer so it remains clickable.
  if frame.CloseButton and frame.TitleContainer then
    frame.CloseButton:SetFrameLevel(frame.TitleContainer:GetFrameLevel() + 2)
  end
  -- [v2.6.2.9] Fixed-size Step1: removed bottom-right resizer creation (disable manual resizing)
  frame.UpdateFrameVisible = function(self)
    self.tipPopup:Hide()
    if self.minimized then
      BrAurasOptionsTitleText:Hide()
      self.buttonsContainer.frame:Hide()
      for _, fn in ipairs({"TexturePicker", "IconPicker", "ModelPicker", "ImportExport", "TextEditor", "CodeReview", "UpdateFrame", "DebugLog"}) do
        local obj = OptionsPrivate[fn](self, true)
        if obj then
          obj.frame:Hide()
        end
      end
      if self.newView then
        self.newView.frame:Hide()
      end
      self.container.frame:Hide()

      self.loadProgress:Hide()
      self.toolbarContainer:Hide()
      self.filterInput:Hide();
      self.tipFrame:Hide()
      self:HideTip()
self.dynamicTextCodesFrame:Hide()
    else
      BrAurasOptionsTitleText:Show()
if self.window == "default" then
        OptionsPrivate.SetTitle()
        self.buttonsContainer.frame:Show()
        self.container.frame:Show()
        self:ShowTip()
      else
        self.buttonsContainer.frame:Hide()
        self.container.frame:Hide()
        self.dynamicTextCodesFrame:Hide()
        self:HideTip()
      end
      local widgets = {
        { window = "texture",      title = L["Texture Picker"],       fn = "TexturePicker" },
        { window = "icon",         title = L["Icon Picker"],          fn = "IconPicker" },
        { window = "model",        title = L["Model Picker"],         fn = "ModelPicker" },
        { window = "importexport", title = L["Import / Export"],      fn = "ImportExport" },
        { window = "texteditor",   title = L["Code Editor"],          fn = "TextEditor" },
        { window = "codereview",   title = L["Custom Code Viewer"],   fn = "CodeReview" },
        { window = "debuglog",     title = L["Debug Log"],            fn = "DebugLog" },
        { window = "update",       title = L["Update"],               fn = "UpdateFrame" },
      }

      for _, widget in ipairs(widgets) do
        local obj = OptionsPrivate[widget.fn](self, true)
        if self.window == widget.window then
          OptionsPrivate.SetTitle(widget.title)
          if obj then
            obj.frame:Show()
          end
        else
          if obj then
            obj.frame:Hide()
          end
        end
      end

      if self.window == "newView" then
        OptionsPrivate.SetTitle(L["New Template"])
        self.newView.frame:Show()
      else
        if self.newView then
          self.newView.frame:Hide()
        end
      end
      if self.window == "default" then
        if self.loadProgessVisible then
          self.loadProgress:Show()
          self.toolbarContainer:Hide()
          self.filterInput:Hide();
        else
          self.loadProgress:Hide()
          self.toolbarContainer:Show()
          self.filterInput:Show();
          --self.filterInputClear:Show();
        end
      else
        self.loadProgress:Hide()
        self.toolbarContainer:Hide()
        self.filterInput:Hide();
      end
    end
  end



  local minimizebutton = CreateFrame("Button", nil, frame, "MaximizeMinimizeButtonFrameTemplate")
  minimizebutton:SetFrameLevel(frame.TitleContainer:GetFrameLevel() + 1)
  minimizebutton:SetPoint("RIGHT", frame.CloseButton, "LEFT", BrAuras.IsClassicOrWrathOrCataOrMists() and 10 or 0, 0)
  minimizebutton:SetOnMaximizedCallback(function()
    frame.minimized = false
    local right, top = frame:GetRight(), frame:GetTop()
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    if BRA_DOCK_TO_BANRUOUI then BrA_DockToBanruoUIRight(frame) end
    frame:SetHeight(odb.frame and odb.frame.height or defaultHeight)
    frame:SetWidth(odb.frame and odb.frame.width or defaultWidth)
    frame.buttonsScroll:DoLayout()
    frame:UpdateFrameVisible()
  end)
  minimizebutton:SetOnMinimizedCallback(function()
    commitWindowChanges()
    frame.minimized = true
    local right, top = frame:GetRight(), frame:GetTop()
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    if BRA_DOCK_TO_BANRUOUI then BrA_DockToBanruoUIRight(frame) end
    frame:SetHeight(75)
    frame:SetWidth(160)
    frame:UpdateFrameVisible()
  end)

  local tipFrame = CreateFrame("Frame", nil, frame)
  tipFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 17, 30)
  tipFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BRA_FRAME_MARGIN_RIGHT, 10)
  tipFrame:Hide()
  frame.tipFrame = tipFrame

  local tipPopup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  tipPopup:SetFrameStrata("FULLSCREEN")
  tipPopup:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  tipPopup:SetBackdropColor(0, 0, 0, 0.8)
  --tipPopup:SetHeight(100)
  tipPopup:Hide()
  frame.tipPopup = tipPopup

  local tipPopupTitle = tipPopup:CreateFontString(nil, "BACKGROUND", "GameFontNormalLarge")
  tipPopupTitle:SetPoint("TOPLEFT", tipPopup, "TOPLEFT", 10, -10)
  tipPopupTitle:SetPoint("TOPRIGHT", tipPopup, "TOPRIGHT", -10, -10)
  tipPopupTitle:SetJustifyH("LEFT")
  tipPopupTitle:SetJustifyV("TOP")

  local tipPopupLabel = tipPopup:CreateFontString(nil, "BACKGROUND", "GameFontWhite")
  local fontPath = SharedMedia:Fetch("font", "Fira Sans Medium")
  if (fontPath) then
    tipPopupLabel:SetFont(fontPath, 12)
  end
  tipPopupLabel:SetPoint("TOPLEFT", tipPopupTitle, "BOTTOMLEFT", 0, -6)
  tipPopupLabel:SetPoint("TOPRIGHT", tipPopupTitle, "BOTTOMRIGHT", 0, -6)
  tipPopupLabel:SetJustifyH("LEFT")
  tipPopupLabel:SetJustifyV("TOP")

  local tipPopupLabelCJ = tipPopup:CreateFontString(nil, "BACKGROUND", "GameFontWhite")
  tipPopupLabelCJ:SetFont("Fonts\\ARKai_T.ttf", 12)
  tipPopupLabelCJ:SetPoint("TOPLEFT", tipPopupLabel, "BOTTOMLEFT", 0, 0)
  tipPopupLabelCJ:SetPoint("TOPRIGHT", tipPopupLabel, "BOTTOMRIGHT", 0, 0)
  tipPopupLabelCJ:SetJustifyH("LEFT")
  tipPopupLabelCJ:SetJustifyV("TOP")

  local tipPopupLabelK = tipPopup:CreateFontString(nil, "BACKGROUND", "GameFontWhite")
  tipPopupLabelK:SetFont("Fonts\\K_Pagetext.TTF", 12)
  tipPopupLabelK:SetPoint("TOPLEFT", tipPopupLabelCJ, "BOTTOMLEFT", 0, 0)
  tipPopupLabelK:SetPoint("TOPRIGHT", tipPopupLabelCJ, "BOTTOMRIGHT", 0, 0)
  tipPopupLabelK:SetJustifyH("LEFT")
  tipPopupLabelK:SetJustifyV("TOP")

  local urlWidget = CreateFrame("EditBox", nil, tipPopup, "InputBoxTemplate")
  urlWidget:SetFont(STANDARD_TEXT_FONT, 12, "")
  urlWidget:SetPoint("TOPLEFT", tipPopupLabelK, "BOTTOMLEFT", 6, 0)
  urlWidget:SetPoint("TOPRIGHT", tipPopupLabelK, "BOTTOMRIGHT", 0, 0)
  urlWidget:SetScript("OnChar", function() urlWidget:SetText(urlWidget.text); urlWidget:HighlightText(); end);
  urlWidget:SetScript("OnMouseUp", function() urlWidget:HighlightText(); end);
  urlWidget:SetScript("OnEscapePressed", function() tipPopup:Hide() end)
  urlWidget:SetHeight(34)

  local tipPopupCtrlC = tipPopup:CreateFontString(nil, "BACKGROUND", "GameFontWhite")
  tipPopupCtrlC:SetPoint("TOPLEFT", urlWidget, "BOTTOMLEFT", -6, 0)
  tipPopupCtrlC:SetPoint("TOPRIGHT", urlWidget, "BOTTOMRIGHT", 0, 0)
  tipPopupCtrlC:SetJustifyH("LEFT")
  tipPopupCtrlC:SetJustifyV("TOP")
  tipPopupCtrlC:SetText(L["Press Ctrl+C to copy the URL"])

  --- @type fun(referenceWidget: frame, title: string, texture: string, url: string, description: string, descriptionCJ: string?, descriptionK: string?, rightAligned: boolean?, width: number?)
  local function ToggleTip(referenceWidget, url, title, description, descriptionCJ, descriptionK, rightAligned, width)
    width = width or 400
    if tipPopup:IsVisible() and urlWidget.text == url then
      tipPopup:Hide()
      return
    end
    urlWidget.text = url
    urlWidget:SetText(url)
    tipPopupTitle:SetText(title)
    tipPopupLabel:SetText(description)
    tipPopupLabelCJ:SetText(descriptionCJ)
    tipPopupLabelK:SetText(descriptionK)
    urlWidget:HighlightText()

    tipPopup:ClearAllPoints();
    if rightAligned then
      tipPopup:SetPoint("BOTTOMRIGHT", referenceWidget, "TOPRIGHT", 6, 4)
    else
      tipPopup:SetPoint("BOTTOMLEFT", referenceWidget, "TOPLEFT", -6, 4)
    end

    tipPopup:SetWidth(width)
    tipPopup:Show()
    tipPopup:SetHeight(26 + tipPopupTitle:GetHeight() + tipPopupLabel:GetHeight() + tipPopupLabelCJ:GetHeight() + tipPopupLabelK:GetHeight()
                       + urlWidget:GetHeight() + tipPopupCtrlC:GetHeight())
    -- This does somehow fix an issue where the first popup after a game restart doesn't show up.
    -- This isn't reproducable after a simple ui reload, so no idea what goes wrong, but with this line here,
    -- it seems to work.
    tipPopupLabel:GetRect()
    tipPopupLabelCJ:GetRect()
    tipPopupLabelK:GetRect()
  end

  OptionsPrivate.ToggleTip = ToggleTip

  --- @type fun(title: string, texture: string, url: string, description: string, descriptionCJ: string?, descriptionK: string?, rightAligned: boolean?, width: number?)
  local addFooter = function(title, texture, url, description, descriptionCJ, descriptionK, rightAligned, width)
    local button = AceGUI:Create("BrAurasToolbarButton")
    button:SetSmallFont(true)
    button:SetText(title)
    button:SetTexture(texture)
    button:SetCallback("OnClick", function()
      ToggleTip(button.frame, url, title, description, descriptionCJ, descriptionK, rightAligned, width)
    end)
    button.frame:Show()
    return button.frame
  end

  local function lineWrapDiscordList(list)
    local patreonLines = {}
    local lineLength = 0
    local currentLine = {}
    for _, patreon in ipairs(list) do
      if lineLength + #patreon + 2 > 130 then
        tinsert(patreonLines, table.concat(currentLine, ", ") .. ", ")
        currentLine = {}
        tinsert(currentLine, patreon)
        lineLength = #patreon + 2
      else
        lineLength = lineLength + #patreon + 2
        tinsert(currentLine, patreon)
      end
    end
    if #currentLine > 0 then
      tinsert(patreonLines, table.concat(currentLine, ", "))
    end
    return table.concat(patreonLines, "\n")
  end

  local thanksList = L["We thank"] .. "\n"
                     .. L["All maintainers of the libraries we use, especially:"] .. "\n"
                     .. "• " .. L["Ace: Funkeh, Nevcairiel"] .. "\n"
                     .. "• " .. L["LibCompress: Galmok"]  .. "\n"
                     .. "• " .. L["LibCustomGlow: Dooez"] .. "\n"
                     .. "• " .. L["LibDeflate: Yoursafety"] .. "\n"
                     .. "• " .. L["LibDispel: Simpy"] .. "\n"
                     .. "• " .. L["LibSerialize: Sanjo"] .. "\n"
                     .. "• " .. L["LibSpecialization: Funkeh"] .. "\n"
                     .. "• " .. L["Our translators (too many to name)"] .. "\n"
                     .. "• " .. L["And our Patreons, Discord Regulars and Subscribers, and Friends of the Addon:"] .. "\n"

  thanksList = thanksList .. lineWrapDiscordList(OptionsPrivate.Private.DiscordList)

  local footerSpacing = 4
  local thanksListCJ = lineWrapDiscordList(OptionsPrivate.Private.DiscordListCJ)
  local thanksListK = lineWrapDiscordList(OptionsPrivate.Private.DiscordListK)

  local discordButton = addFooter(L["Discord"], [[Interface\AddOns\BrAuras\Media\Textures\discord.tga]], "https://discord.gg/weakauras",
            L["Chat with BrAuras experts on our Discord server."])
  discordButton:SetParent(tipFrame)
  discordButton:SetPoint("LEFT", tipFrame, "LEFT")

  local documentationButton = addFooter(L["Documentation"], [[Interface\AddOns\BrAuras\Media\Textures\GitHub.tga]], "https://github.com/BrAuras/BrAuras2/wiki",
            L["Check out our wiki for a large collection of examples and snippets."])
  documentationButton:SetParent(tipFrame)
  documentationButton:SetPoint("LEFT", discordButton, "RIGHT", footerSpacing, 0)

  local thanksButton = addFooter(L["Thanks"], [[Interface\AddOns\BrAuras\Media\Textures\waheart.tga]],
                                 "https://www.patreon.com/BrAuras", thanksList, thanksListCJ, thanksListK, nil, 800)
  thanksButton:SetParent(tipFrame)
  thanksButton:SetPoint("LEFT", documentationButton, "RIGHT", footerSpacing, 0)

  if OptionsPrivate.changelog then
    local changelog
    if OptionsPrivate.changelog.highlightText then
      changelog = L["Highlights"] .. "\n" .. OptionsPrivate.changelog.highlightText
    else
      changelog = OptionsPrivate.changelog.commitText
    end

    local changelogButton = addFooter(L["Changelog"], "", OptionsPrivate.changelog.fullChangeLogUrl,
                                      changelog, nil, nil, false, 800)
    changelogButton:SetParent(tipFrame)
    changelogButton:SetPoint("LEFT", thanksButton, "RIGHT", footerSpacing, 0)
  end

  local reportbugButton = addFooter(L["Found a Bug?"], [[Interface\AddOns\BrAuras\Media\Textures\bug_report.tga]], "https://github.com/BrAuras/BrAuras2/issues/new?template=bug_report.yml",
            L["Report bugs on our issue tracker."], nil, nil, true)
  reportbugButton:SetParent(tipFrame)
  reportbugButton:SetPoint("RIGHT", tipFrame, "RIGHT")

  local wagoButton = addFooter(L["Find Auras"], [[Interface\AddOns\BrAuras\Media\Textures\wago.tga]], "https://wago.io",
            L["Browse Wago, the largest collection of auras."], nil, nil, true)
  wagoButton:SetParent(tipFrame)
  wagoButton:SetPoint("RIGHT", reportbugButton, "LEFT", -footerSpacing, 0)

  local companionButton
  if not OptionsPrivate.Private.CompanionData.slugs then
    companionButton = addFooter(L["Update Auras"], [[Interface\AddOns\BrAuras\Media\Textures\wagoupdate_refresh.tga]], "https://weakauras.wtf",
            L["Keep your Wago imports up to date with the Companion App."])
    companionButton:SetParent(tipFrame)
    companionButton:SetPoint("RIGHT", wagoButton, "LEFT", -footerSpacing, 0)
  end

  frame.ShowTip = function(self)
    -- v2.6.2.x: hide footer bar permanently
    self.tipFrame:Hide()
  end

  frame.HideTip = function(self)
    self.tipFrame:Hide()
    self.buttonsContainer.frame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", BRA_FRAME_MARGIN_LEFT, 12)
    self.container.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BRA_FRAME_MARGIN_RIGHT, 10)
  end

  -- Right Side Container
  local container = AceGUI:Create("InlineGroup")
  container.frame:SetParent(frame)
  container.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BRA_FRAME_MARGIN_RIGHT, 10)
  container.frame:SetPoint("TOPLEFT", frame, "TOPRIGHT", BRA_RIGHT_PANEL_LEFT_OFFSET, 0)
  container.frame:Show()
  container.frame:SetClipsChildren(true)
  container.titletext:Hide()
  -- Hide the border
  container.content:GetParent():SetBackdrop(nil)
  container.content:SetPoint("TOPLEFT", 0, -28)
  container.content:SetPoint("BOTTOMRIGHT", 0, 0)
  frame.container = container
  frame.moversizer, frame.mover = OptionsPrivate.MoverSizer(frame)

  -- Left Side Container
  local buttonsContainer = AceGUI:Create("InlineGroup")
  -- v2.6.2.33: left panel fixed width
  buttonsContainer:SetWidth(BRA_LEFT_PANEL_WIDTH)
  buttonsContainer.frame:SetParent(frame)
  buttonsContainer.frame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", BRA_FRAME_MARGIN_LEFT, 12)
  buttonsContainer.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", BRA_FRAME_MARGIN_LEFT, -67)
  buttonsContainer.frame:Show()
  frame.buttonsContainer = buttonsContainer


  -- filter line
  local filterInput = CreateFrame("EditBox", "BrAurasFilterInput", frame, "SearchBoxTemplate")
  filterInput:SetScript("OnTextChanged", function(self)
    SearchBoxTemplate_OnTextChanged(self)
    OptionsPrivate.SortDisplayButtons(filterInput:GetText())
  end)
  filterInput:SetHeight(15)
  filterInput:SetPoint("TOP", frame, "TOP", 0, -65)
  filterInput:SetPoint("LEFT", frame, "LEFT", BRA_FRAME_MARGIN_LEFT + 7, 0)
  filterInput:SetPoint("RIGHT", buttonsContainer.frame, "RIGHT", -6, 0)
  filterInput:SetFont(STANDARD_TEXT_FONT, 10, "")
  frame.filterInput = filterInput
  filterInput:Hide()

  -- Toolbar
  local toolbarContainer = CreateFrame("Frame", nil, buttonsContainer.frame)
  toolbarContainer:SetParent(buttonsContainer.frame)
  -- toolbarContainer:Hide()
  toolbarContainer:SetPoint("TOPLEFT", buttonsContainer.frame, "TOPLEFT", 30, 30)
  toolbarContainer:SetPoint("BOTTOMRIGHT", buttonsContainer.frame, "TOPRIGHT", 0, 0)

  local undo = AceGUI:Create("BrAurasToolbarButton")
  undo:SetText(L["Undo"])
  undo:SetTexture("Interface\\AddOns\\BrAuras\\Media\\Textures\\upleft")
  undo:SetCallback("OnClick", function()
    OptionsPrivate.Private.TimeMachine:StepBackward()
    frame:FillOptions()
  end)
  undo.frame:SetParent(toolbarContainer)
  undo.frame:SetShown(OptionsPrivate.Private.Features:Enabled("undo"))
  undo:SetPoint("LEFT")
  undo.frame:SetCollapsesLayout(true)

  local redo = AceGUI:Create("BrAurasToolbarButton")
  redo:SetText(L["Redo"])
  redo:SetTexture("Interface\\AddOns\\BrAuras\\Media\\Textures\\upright")
  redo:SetCallback("OnClick", function()
    OptionsPrivate.Private.TimeMachine:StepForward()
    frame:FillOptions()
  end)
  redo.frame:SetParent(toolbarContainer)
  redo.frame:SetShown(OptionsPrivate.Private.Features:Enabled("undo"))
  redo:SetPoint("LEFT", undo.frame, "RIGHT", 10, 0)
  redo.frame:SetEnabled(OptionsPrivate.Private.TimeMachine:DescribeNext() ~= nil)
  redo.frame:SetCollapsesLayout(true)
  OptionsPrivate.Private.Features:Subscribe("undo",
    function()
      undo.frame:Show()
      redo.frame:Show()
    end,
    function()
      undo.frame:Hide()
      redo.frame:Hide()
    end
  )

  local tmControls = {
    undo = undo,
    redo = redo,
  }

  function tmControls:Step()
    -- slightly annoying workaround
    -- Buttons behave in a strange way if they are disabled inside of the OnClick handler
    -- where the pushed texture refuses to vanish until the button is enabled & user clicks it again
    -- so, just disable the button after next frame draw, so it's imperceptible to the user but we're not in the OnClick handler
    C_Timer.After(0, function()
      self.undo:SetDisabled(OptionsPrivate.Private.TimeMachine:DescribePrevious() == nil)
      self.redo:SetDisabled(OptionsPrivate.Private.TimeMachine:DescribeNext() == nil)
    end)
  end
  tmControls:Step()
  OptionsPrivate.Private.TimeMachine.sub:AddSubscriber("Step", tmControls)

  local newButton = AceGUI:Create("BrAurasToolbarButton")
  newButton:SetText(L["New Aura"])
  newButton:SetTexture("Interface\\AddOns\\BrAuras\\Media\\Textures\\newaura")
  newButton.frame:SetParent(toolbarContainer)
  newButton.frame:Hide() -- v2.6.2.x hide New button
  newButton:SetPoint("LEFT", redo.frame, "RIGHT", 10, 0)
  frame.toolbarContainer = toolbarContainer

  newButton:SetCallback("OnClick", function()
    frame:NewAura()
  end)

  local importButton = AceGUI:Create("BrAurasToolbarButton")
  importButton:SetText(L["Import"])
  importButton:SetTexture("Interface\\AddOns\\BrAuras\\Media\\Textures\\importsmall")
  importButton:SetCallback("OnClick", OptionsPrivate.ImportFromString)
  importButton.frame:SetParent(toolbarContainer)
  importButton.frame:Hide() -- v2.6.2.x hide Import button
  importButton:SetPoint("LEFT", newButton.frame, "RIGHT", 10, 0)

  local lockButton = AceGUI:Create("BrAurasToolbarButton")
  lockButton:SetText(L["Lock Positions"])
  lockButton:SetTexture("Interface\\AddOns\\BrAuras\\Media\\Textures\\lockPosition")
  lockButton:SetCallback("OnClick", function(self)
    if BrAurasOptionsSaved.lockPositions then
      lockButton:SetStrongHighlight(false)
      lockButton:UnlockHighlight()
      BrAurasOptionsSaved.lockPositions = false
    else
      lockButton:SetStrongHighlight(true)
      lockButton:LockHighlight()
      BrAurasOptionsSaved.lockPositions = true
    end
  end)
  if BrAurasOptionsSaved.lockPositions then
    lockButton:LockHighlight()
  end
  lockButton.frame:SetParent(toolbarContainer)
  lockButton.frame:Show()
  lockButton:SetPoint("LEFT", importButton.frame, "RIGHT", 10, 0)

  local magnetButton = AceGUI:Create("BrAurasToolbarButton")
  magnetButton:SetText(L["Magnetically Align"])
  magnetButton:SetTexture("Interface\\AddOns\\BrAuras\\Media\\Textures\\magnetic")
  magnetButton:SetCallback("OnClick", function(self)
    if BrAurasOptionsSaved.magnetAlign then
      magnetButton:SetStrongHighlight(false)
      magnetButton:UnlockHighlight()
      BrAurasOptionsSaved.magnetAlign = false
    else
      magnetButton:SetStrongHighlight(true)
      magnetButton:LockHighlight()
      BrAurasOptionsSaved.magnetAlign = true
    end
  end)

  if BrAurasOptionsSaved.magnetAlign then
    magnetButton:LockHighlight()
  end
  magnetButton.frame:SetParent(toolbarContainer)
  magnetButton.frame:Show()
  magnetButton:SetPoint("LEFT", lockButton.frame, "RIGHT", 10, 0)


  local loadProgress = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  loadProgress:SetPoint("TOP", buttonsContainer.frame, "TOP", 0, -4)
  loadProgress:SetText(L["Creating options: "].."0/0")
  frame.loadProgress = loadProgress

  frame.SetLoadProgressVisible = function(self, visible)
    self.loadProgessVisible = visible
    self:UpdateFrameVisible()
  end

  local buttonsScroll = AceGUI:Create("ScrollFrame")
  buttonsScroll:SetLayout("ButtonsScrollLayout")
  buttonsScroll.width = "fill"
  buttonsScroll.height = "fill"
  buttonsContainer:SetLayout("fill")
  buttonsContainer:AddChild(buttonsScroll)
  buttonsScroll.DeleteChild = function(self, delete)
    for index, widget in ipairs(buttonsScroll.children) do
      if widget == delete then
        tremove(buttonsScroll.children, index)
      end
    end
    delete:OnRelease()
    buttonsScroll:DoLayout()
  end
  frame.buttonsScroll = buttonsScroll

  function buttonsScroll:GetScrollPos()
    local status = self.status or self.localstatus
    return status.offset, status.offset + self.scrollframe:GetHeight()
  end

  -- override SetScroll to make children visible as needed
  local oldSetScroll = buttonsScroll.SetScroll
  buttonsScroll.SetScroll = function(self, value)
    oldSetScroll(self, value)
    self.LayoutFunc(self.content, self.children, true)
  end

  function buttonsScroll:SetScrollPos(top, bottom)
    local status = self.status or self.localstatus
    local viewheight = self.scrollframe:GetHeight()
    local height = self.content:GetHeight()
    local move

    local viewtop = -1 * status.offset
    local viewbottom = -1 * (status.offset + viewheight)
    if top > viewtop then
      move = top - viewtop
    elseif bottom < viewbottom then
      move = bottom - viewbottom
    else
      move = 0
    end

    status.offset = status.offset - move

    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", 0, status.offset)
    self.content:SetPoint("TOPRIGHT", 0, status.offset)

    status.scrollvalue = status.offset / ((height - viewheight) / 1000.0)
  end

  -- Ready to Install section
  local pendingInstallButton = AceGUI:Create("BrAurasLoadedHeaderButton")
  pendingInstallButton:SetText(L["Ready for Install"])
  pendingInstallButton:Disable()
  pendingInstallButton:EnableExpand()
  pendingInstallButton.frame.view:Hide()
  if odb.pendingImportCollapse then
    pendingInstallButton:Collapse()
  else
    pendingInstallButton:Expand()
  end
  pendingInstallButton:SetOnExpandCollapse(function()
    if pendingInstallButton:GetExpanded() then
      odb.pendingImportCollapse = nil
    else
      odb.pendingImportCollapse = true
    end
    OptionsPrivate.SortDisplayButtons()
  end)
  pendingInstallButton:SetExpandDescription(L["Expand all pending Import"])
  pendingInstallButton:SetCollapseDescription(L["Collapse all pending Import"])
  frame.pendingInstallButton = pendingInstallButton

  -- Ready for update section
  local pendingUpdateButton = AceGUI:Create("BrAurasLoadedHeaderButton")
  pendingUpdateButton:SetText(L["Ready for Update"])
  pendingUpdateButton:Disable()
  pendingUpdateButton:EnableExpand()
  pendingUpdateButton.frame.view:Hide()
  if odb.pendingUpdateCollapse then
    pendingUpdateButton:Collapse()
  else
    pendingUpdateButton:Expand()
  end
  pendingUpdateButton:SetOnExpandCollapse(function()
    if pendingUpdateButton:GetExpanded() then
      odb.pendingUpdateCollapse = nil
    else
      odb.pendingUpdateCollapse = true
    end
    OptionsPrivate.SortDisplayButtons()
  end)
  pendingUpdateButton:SetExpandDescription(L["Expand all pending Import"])
  pendingUpdateButton:SetCollapseDescription(L["Collapse all pending Import"])
  frame.pendingUpdateButton = pendingUpdateButton

  -- Loaded section
  local loadedButton = AceGUI:Create("BrAurasLoadedHeaderButton")
  loadedButton:SetText(L["Loaded/Standby"])
  loadedButton:Disable()
  loadedButton:EnableExpand()
  if odb.loadedCollapse then
    loadedButton:Collapse()
  else
    loadedButton:Expand()
  end
  loadedButton:SetOnExpandCollapse(function()
    if loadedButton:GetExpanded() then
      odb.loadedCollapse = nil
    else
      odb.loadedCollapse = true
    end
    OptionsPrivate.SortDisplayButtons()
  end)
  loadedButton:SetExpandDescription(L["Expand all loaded displays"])
  loadedButton:SetCollapseDescription(L["Collapse all loaded displays"])
  loadedButton:SetViewClick(function()
    local suspended = OptionsPrivate.Private.PauseAllDynamicGroups()

    if loadedButton.view.visibility == 2 then
      for _, child in ipairs(loadedButton.childButtons) do
        if child:IsLoaded() then
          child:PriorityHide(2)
        end
      end
      loadedButton:PriorityHide(2)
    else
      for _, child in ipairs(loadedButton.childButtons) do
        if child:IsLoaded() then
          child:PriorityShow(2)
        end
      end
      loadedButton:PriorityShow(2)
    end
    OptionsPrivate.Private.ResumeAllDynamicGroups(suspended)
  end)
  loadedButton.RecheckVisibility = function(self)
    local none, all = true, true
    for _, child in ipairs(loadedButton.childButtons) do
      if child:GetVisibility() ~= 2 then
        all = false
      end
      if child:GetVisibility() ~= 0 then
        none = false
      end
    end
    local newVisibility
    if all then
      newVisibility = 2
    elseif none then
      newVisibility = 0
    else
      newVisibility = 1
    end
    if newVisibility ~= self.view.visibility then
      self.view.visibility = newVisibility
      self:UpdateViewTexture()
    end
  end
  loadedButton:SetViewDescription(L["Toggle the visibility of all loaded displays"])
  loadedButton.childButtons = {}
  frame.loadedButton = loadedButton

  -- Not Loaded section
  local unloadedButton = AceGUI:Create("BrAurasLoadedHeaderButton")
  unloadedButton:SetText(L["Not Loaded"])
  unloadedButton:Disable()
  unloadedButton:EnableExpand()
  if odb.unloadedCollapse then
    unloadedButton:Collapse()
  else
    unloadedButton:Expand()
  end
  unloadedButton:SetOnExpandCollapse(function()
    if unloadedButton:GetExpanded() then
      odb.unloadedCollapse = nil
    else
      odb.unloadedCollapse = true
    end
    OptionsPrivate.SortDisplayButtons()
  end)
  unloadedButton:SetExpandDescription(L["Expand all non-loaded displays"])
  unloadedButton:SetCollapseDescription(L["Collapse all non-loaded displays"])
  unloadedButton:SetViewClick(function()
    local suspended = OptionsPrivate.Private.PauseAllDynamicGroups()
    if unloadedButton.view.visibility == 2 then
      for _, child in ipairs(unloadedButton.childButtons) do
        child:PriorityHide(2)
      end
      unloadedButton:PriorityHide(2)
    else
      for _, child in ipairs(unloadedButton.childButtons) do
        child:PriorityShow(2)
      end
      unloadedButton:PriorityShow(2)
    end
    OptionsPrivate.Private.ResumeAllDynamicGroups(suspended)
  end)
  unloadedButton.RecheckVisibility = function(self)
    local none, all = true, true
    for _, child in ipairs(unloadedButton.childButtons) do
      if child:GetVisibility() ~= 2 then
        all = false
      end
      if child:GetVisibility() ~= 0 then
        none = false
      end
    end
    local newVisibility
    if all then
      newVisibility = 2
    elseif none then
      newVisibility = 0
    else
      newVisibility = 1
    end
    if newVisibility ~= self.view.visibility then
      self.view.visibility = newVisibility
      self:UpdateViewTexture()
    end
  end
  unloadedButton:SetViewDescription(L["Toggle the visibility of all non-loaded displays"])
  unloadedButton.childButtons = {}
  frame.unloadedButton = unloadedButton

  -- Sidebar used for Dynamic Text Replacements
  local sidegroup = AceGUI:Create("BrAurasInlineGroup")
  sidegroup.frame:SetParent(frame)
  sidegroup.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", BRA_FRAME_MARGIN_LEFT, -63);
  sidegroup.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BRA_FRAME_MARGIN_RIGHT, 46);
  sidegroup.frame:Show()
  sidegroup:SetLayout("flow")

  local dynamicTextCodesFrame = CreateFrame("Frame", "BrAurasTextReplacements", sidegroup.frame, "PortraitFrameTemplate")
  dynamicTextCodesFrame.Bg:SetColorTexture(unpack(frame.Bg.colorTexture))
  ButtonFrameTemplate_HidePortrait(dynamicTextCodesFrame)
  dynamicTextCodesFrame:SetPoint("TOPLEFT", sidegroup.frame, "TOPRIGHT", 20, 0)
  dynamicTextCodesFrame:SetPoint("BOTTOMLEFT", sidegroup.frame, "BOTTOMRIGHT", 20, 0)
  dynamicTextCodesFrame:SetWidth(250)
  dynamicTextCodesFrame:SetScript("OnHide", function()
    OptionsPrivate.currentDynamicTextInput = nil
  end)
  frame.dynamicTextCodesFrame = dynamicTextCodesFrame

  local dynamicTextCodesFrameTitle
  if dynamicTextCodesFrame.TitleContainer and dynamicTextCodesFrame.TitleContainer.TitleText then
    dynamicTextCodesFrameTitle = dynamicTextCodesFrame.TitleContainer.TitleText
  elseif dynamicTextCodesFrame.TitleText then
    dynamicTextCodesFrameTitle = dynamicTextCodesFrame.TitleText
  end
  if dynamicTextCodesFrameTitle then
    dynamicTextCodesFrameTitle:SetText("Dynamic Text Replacements")
    dynamicTextCodesFrameTitle:SetJustifyH("CENTER")
    dynamicTextCodesFrameTitle:SetPoint("LEFT", dynamicTextCodesFrame, "TOPLEFT")
    dynamicTextCodesFrameTitle:SetPoint("RIGHT", dynamicTextCodesFrame, "TOPRIGHT", -10, 0)
  end

  local dynamicTextCodesLabel = AceGUI:Create("Label")
  dynamicTextCodesLabel:SetText(L["Insert text replacement codes to make text dynamic."])
  dynamicTextCodesLabel:SetFontObject(GameFontNormal)
  dynamicTextCodesLabel:SetPoint("TOP", dynamicTextCodesFrame, "TOP", 0, -35)
  dynamicTextCodesLabel:SetFontObject(GameFontNormalSmall2)
  dynamicTextCodesLabel.frame:SetParent(dynamicTextCodesFrame)
  dynamicTextCodesLabel.frame:Show()

  local dynamicTextCodesScrollContainer = AceGUI:Create("SimpleGroup")
  dynamicTextCodesScrollContainer.frame:SetParent(dynamicTextCodesFrame)
  dynamicTextCodesScrollContainer.frame:SetPoint("TOP", dynamicTextCodesLabel.frame, "BOTTOM", 0, -15)
  dynamicTextCodesScrollContainer.frame:SetPoint("LEFT", dynamicTextCodesFrame, "LEFT", 15, 0)
  dynamicTextCodesScrollContainer.frame:SetPoint("BOTTOMRIGHT", dynamicTextCodesFrame, "BOTTOMRIGHT", -15, 5)
  dynamicTextCodesScrollContainer:SetFullWidth(true)
  dynamicTextCodesScrollContainer:SetFullHeight(true)
  dynamicTextCodesScrollContainer:SetLayout("Fill")


  local dynamicTextCodesScrollList = AceGUI:Create("ScrollFrame")
  dynamicTextCodesScrollList:SetLayout("List")
  dynamicTextCodesScrollList:SetPoint("TOPLEFT", dynamicTextCodesScrollContainer.frame, "TOPLEFT")
  dynamicTextCodesScrollList:SetPoint("BOTTOMRIGHT", dynamicTextCodesScrollContainer.frame, "BOTTOMRIGHT")
  dynamicTextCodesScrollList.frame:SetParent(dynamicTextCodesFrame)
  dynamicTextCodesScrollList:FixScroll()
  dynamicTextCodesScrollList.scrollframe:SetScript(
    "OnScrollRangeChanged",
    function(frame)
      frame.obj:DoLayout()
    end
  )

  dynamicTextCodesScrollList.scrollframe:SetScript(
    "OnSizeChanged",
    function(frame)
      if frame.obj.scrollBarShown then
        frame.obj.content.width = frame.obj.content.original_width - 10
        frame.obj.scrollframe:SetPoint("BOTTOMRIGHT", -10, 0)
      end
    end
  )


  dynamicTextCodesFrame.scrollList = dynamicTextCodesScrollList
  dynamicTextCodesFrame.label = dynamicTextCodesLabel
  dynamicTextCodesFrame:Hide()

  function OptionsPrivate.ToggleTextReplacements(data, widget, event)
    -- If the text edit has focus when the user clicks on the button, we'll get two events:
    -- a) The OnEditFocusLost
    -- b) The ToggleButton OnClick event
    -- Since we want to hide the text replacement window in that case,
    -- ignore the ToggleButton if it is directly after the  OnEditFocusLost
    local currentTime = GetTime()
    if event == "ToggleButton"
      and dynamicTextCodesFrame.lastCaller
      and dynamicTextCodesFrame.lastCaller.event == "OnEditFocusLost"
      and currentTime - dynamicTextCodesFrame.lastCaller.time < 0.2
    then
      return
    end

    dynamicTextCodesFrame.lastCaller = {
      event = event,
      time = currentTime,
    }

    if event == "OnEnterPressed" then
      dynamicTextCodesFrame:Hide()
    elseif event == "OnEditFocusGained" or not dynamicTextCodesFrame:IsShown() then
      dynamicTextCodesFrame:Show()
      if OptionsPrivate.currentDynamicTextInput ~= widget then
        OptionsPrivate.UpdateTextReplacements(dynamicTextCodesFrame, data)
      end
      OptionsPrivate.currentDynamicTextInput = widget
    elseif not dynamicTextCodesFrame:IsMouseOver() then -- Prevents hiding when clicking inside the frame
      dynamicTextCodesFrame:Hide()
    end
  end

  frame.ClearOptions = function(self, id)
    aceOptions[id] = nil
    OptionsPrivate.commonOptionsCache:Clear()
    if type(id) == "string" then
      local data = BrAuras.GetData(id)
      if data and data.parent then
        frame:ClearOptions(data.parent)
      end
      for child in OptionsPrivate.Private.TraverseAllChildren(tempGroup) do
        if (id == child.id) then
          frame:ClearOptions(tempGroup.id)
        end
      end
    end
  end

  frame.ReloadOptions = function(self)
    if self.pickedDisplay then
      self:ClearAndUpdateOptions(self.pickedDisplay, true)
      self:FillOptions()
    end
  end

  frame.ClearAndUpdateOptions = function(self, id, clearChildren)
    frame:ClearOptions(id)

    if clearChildren then
      local data
      if type(id) == "string" then
        data = BrAuras.GetData(id)
      elseif self.pickedDisplay then
        data = tempGroup
      end

      for child in OptionsPrivate.Private.TraverseAllChildren(data) do
        frame:ClearOptions(child.id)
      end
    end
    if (type(self.pickedDisplay) == "string" and self.pickedDisplay == id)
       or (type(self.pickedDisplay) == "table" and id == tempGroup.id)
    then
      frame:UpdateOptions()
    end
  end

  frame.UpdateOptions = function(self)
    if not self.pickedDisplay then
      return
    end
    OptionsPrivate.commonOptionsCache:Clear()
    self.selectedTab = self.selectedTab or "region"
    local data
    if type(self.pickedDisplay) == "string" then
      data = BrAuras.GetData(frame.pickedDisplay)
    elseif self.pickedDisplay then
      data = tempGroup
    end

    if not data.controlledChildren or data == tempGroup then
      if self.selectedTab == "group" then
        self.selectedTab = "region"
      end
    end

    local optionTable = self:EnsureOptions(data, self.selectedTab)
    if optionTable then
      AceConfigRegistry:RegisterOptionsTable("BrAuras", optionTable, true)
    end
  end

  frame.EnsureOptions = function(self, data, tab)
    local id = data.id
    aceOptions[id] = aceOptions[id] or {}
    if not aceOptions[id][tab] then
      local optionsGenerator =
      {
        group = OptionsPrivate.GetGroupOptions,
        region =  OptionsPrivate.GetDisplayOptions,
        trigger = OptionsPrivate.GetTriggerOptions,
        conditions = OptionsPrivate.GetConditionOptions,
        load = OptionsPrivate.GetLoadOptions,
        action = OptionsPrivate.GetActionOptions,
        animation = OptionsPrivate.GetAnimationOptions,
        authorOptions = OptionsPrivate.GetAuthorOptions,
        information = OptionsPrivate.GetInformationOptions,
      }
      if optionsGenerator[tab] then
        aceOptions[id][tab] = optionsGenerator[tab](data)
      end
    end
    return aceOptions[id][tab]
  end

  -- This function refills the options pane
  -- This is ONLY necessary if AceOptions doesn't know that it should do
  -- that automatically. That is any change that goes through the AceOptions
  -- doesn't need to call this
  -- Any changes to the options that go around that, e.g. drag/drop, group,
  -- texture pick, etc should call this
  frame.FillOptions = function(self)
    if not self.pickedDisplay then
      return
    end

    OptionsPrivate.commonOptionsCache:Clear()

    frame:UpdateOptions()

    local data
    if type(self.pickedDisplay) == "string" then
      data = BrAuras.GetData(frame.pickedDisplay)
    elseif self.pickedDisplay then
      data = tempGroup
    end

    local tabsWidget

    container.frame:SetPoint("TOPLEFT", frame, "TOPRIGHT", BRA_RIGHT_PANEL_LEFT_OFFSET, -10)
    container:ReleaseChildren()
    container:SetLayout("Fill")
    tabsWidget = AceGUI:Create("TabGroup")

    -- v2.6.2 step: hide advanced editor tabs (Trigger/Conditions/Actions/Animations/Custom Options/Information)
    -- Keep only Display + Load (+ Group when applicable).
    local tabs = {
      { value = "region", text = L["Display"]},
      { value = "load", text = L["Load"]},
    }
    -- Check if group and not the temp group
    if data.controlledChildren and type(data.id) == "string" then
      tinsert(tabs, 1, { value = "group", text = L["Group"]})
    end

    -- If the previously selected tab is now hidden, fall back to a safe default.
    if frame.selectedTab == "trigger" or frame.selectedTab == "conditions" or frame.selectedTab == "action"
      or frame.selectedTab == "animation" or frame.selectedTab == "authorOptions" or frame.selectedTab == "information" then
      if data.controlledChildren and type(data.id) == "string" then
        frame.selectedTab = "group"
      else
        frame.selectedTab = "region"
      end
    end

    tabsWidget:SetTabs(tabs)
    tabsWidget:SelectTab(self.selectedTab)
    tabsWidget:SetLayout("Fill")
    container:AddChild(tabsWidget)

    local group = AceGUI:Create("BrAurasInlineGroup")
    tabsWidget:AddChild(group)

    tabsWidget:SetCallback("OnGroupSelected", function(self, event, tab)
        frame.selectedTab = tab
        frame:FillOptions()
      end)

    AceConfigDialog:Open("BrAuras", group)
    BrA_ForceSingleColumn(group)
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function() BrA_ForceSingleColumn(group) end)
    end
    ForceSingleColumn(group)
    C_Timer.After(0, function() ForceSingleColumn(group) end)
    tabsWidget:SetTitle("")

    if data.controlledChildren and #data.controlledChildren == 0 then
      BrAurasOptions:NewAura()
    end

    if frame.dynamicTextCodesFrame then
      frame.dynamicTextCodesFrame:Hide()
    end
  end

  frame.ClearPick = function(self, id)
    local index = nil
    for i, childId in pairs(tempGroup.controlledChildren) do
      if childId == id then
        index = i
        break
      end
    end

    tremove(tempGroup.controlledChildren, index)
    displayButtons[id]:ClearPick()

    -- Clear trigger expand state
    OptionsPrivate.ClearTriggerExpandState()

    self:ClearOptions(tempGroup.id)
    self:FillOptions()
  end

  frame.OnRename = function(self, uid, oldid, newid)
    if type(frame.pickedDisplay) == "string" and frame.pickedDisplay == oldid then
      frame.pickedDisplay = newid
    else
      for i, childId in pairs(tempGroup.controlledChildren) do
        if (childId == newid) then
          tempGroup.controlledChildren[i] = newid
        end
      end
    end
  end

  frame.ClearPicks = function(self, noHide)
    local suspended = OptionsPrivate.Private.PauseAllDynamicGroups()
    for id, button in pairs(displayButtons) do
      button:ClearPick(true)
      if not noHide then
        button:PriorityHide(1)
      end
    end
    if not noHide then
      for id, button in pairs(displayButtons) do
        if button.data.controlledChildren then
          button:RecheckVisibility()
        end
      end
    end

    frame.pickedDisplay = nil
    frame.pickedOption = nil
    wipe(tempGroup.controlledChildren)
    loadedButton:ClearPick(noHide)
    unloadedButton:ClearPick(noHide)
    container:ReleaseChildren()
    self.moversizer:Hide()

    OptionsPrivate.Private.ResumeAllDynamicGroups(suspended)

    -- Clear trigger expand state
    OptionsPrivate.ClearTriggerExpandState()
  end

  frame.GetTargetAura = function(self)
    if self.pickedDisplay then
      if type(self.pickedDisplay) == "table" and tempGroup.controlledChildren and tempGroup.controlledChildren[1] then
        return tempGroup.controlledChildren[1]
      elseif type(self.pickedDisplay) == "string" then
        return self.pickedDisplay
      end
    end
    return nil
  end

  frame.NewAura = function(self)
    -- v2.6.2.x: Hide the New/Create chooser page (UI simplification)
    if container then
      container:ReleaseChildren()
      container:SetLayout("Fill")
    end
    self.pickedOption = nil
    return
  end

  local function ExpandParents(data)
    if data.parent then
      if not displayButtons[data.parent]:GetExpanded() then
        displayButtons[data.parent]:Expand()
      end
      local parentData = BrAuras.GetData(data.parent)
      ExpandParents(parentData)
    end
  end

  frame.PickDisplay = function(self, id, tab, noHide)
    local data = BrAuras.GetData(id)

    -- Always expand even if already picked
    ExpandParents(data)

    if OptionsPrivate.Private.loaded[id] ~= nil then
      -- Under loaded
      if not loadedButton:GetExpanded() then
        loadedButton:Expand()
      end
    else
      -- Under Unloaded
      if not unloadedButton:GetExpanded() then
        unloadedButton:Expand()
      end
    end

    if self.pickedDisplay == id and (self.pickedDisplay == tab or tab == nil) then
      return
    end

    local suspended = OptionsPrivate.Private.PauseAllDynamicGroups()

    self:ClearPicks(noHide)

    displayButtons[id]:Pick()
    self.pickedDisplay = id


    if tab then
      self.selectedTab = tab
    end
    self:FillOptions()
    BrAuras.SetMoverSizer(id)

    local _, _, _, _, yOffset = displayButtons[id].frame:GetPoint(1)
    if not yOffset then
      yOffset = displayButtons[id].frame.yOffset
    end
    if yOffset then
      self.buttonsScroll:SetScrollPos(yOffset, yOffset - 32)
    end

    for child in OptionsPrivate.Private.TraverseAllChildren(data) do
      displayButtons[child.id]:PriorityShow(1)
    end
    displayButtons[data.id]:RecheckParentVisibility()

    OptionsPrivate.Private.ResumeAllDynamicGroups(suspended)
  end

  frame.CenterOnPicked = function(self)
    if self.pickedDisplay then
      local centerId = type(self.pickedDisplay) == "string" and self.pickedDisplay or self.pickedDisplay.controlledChildren[1]

      if displayButtons[centerId] then
        local _, _, _, _, yOffset = displayButtons[centerId].frame:GetPoint(1)
        if not yOffset then
          yOffset = displayButtons[centerId].frame.yOffset
        end
        if yOffset then
          self.buttonsScroll:SetScrollPos(yOffset, yOffset - 32)
        end
      end
    end
  end

  frame.PickDisplayMultiple = function(self, id)
    if not self.pickedDisplay then
      self:PickDisplay(id)
    else
      local wasGroup = false
      if type(self.pickedDisplay) == "string" then
        if BrAuras.GetData(self.pickedDisplay).controlledChildren or BrAuras.GetData(id).controlledChildren then
          wasGroup = true
        elseif not OptionsPrivate.IsDisplayPicked(id) then
          tinsert(tempGroup.controlledChildren, self.pickedDisplay)
        end
      end
      if wasGroup then
        self:PickDisplay(id)
      elseif not OptionsPrivate.IsDisplayPicked(id) then
        self.pickedDisplay = tempGroup
        displayButtons[id]:Pick()
        tinsert(tempGroup.controlledChildren, id)
        OptionsPrivate.ClearOptions(tempGroup.id)
        self:FillOptions()
      end
    end
  end

  frame.PickDisplayBatch = function(self, batchSelection)
    local alreadySelected = {}
    for child in OptionsPrivate.Private.TraverseAllChildren(tempGroup) do
      alreadySelected[child.id] = true
    end

    for _, id in ipairs(batchSelection) do
      if not alreadySelected[id] then
        displayButtons[id]:Pick()
        tinsert(tempGroup.controlledChildren, id)
      end
    end
    frame:ClearOptions(tempGroup.id)
    self.pickedDisplay = tempGroup
    self:FillOptions()
  end

  frame.GetPickedDisplay = function(self)
    if type(self.pickedDisplay) == "string" then
      return BrAuras.GetData(self.pickedDisplay)
    end
    return self.pickedDisplay
  end

  frame:SetClampedToScreen(true)
  local w, h = frame:GetSize()
  local left, right, top, bottom = w/2,-w/2, 0, h-25
  frame:SetClampRectInsets(left, right, top, bottom)

  return frame
end