-- Core/Main.lua
-- v1.5.0：
-- 1) 仅管理 WA（A+B 兜底：首次导入初始化 + 已初始化隐藏式切换）
-- 2) 主题下拉：展开用于“预览选择”（临时态 pendingPreviewThemeId），收起/失焦必须回显“当前已生效主题”
-- 3) 仅点击【切换主题】且成功后才写入 BanruoUIDB.activeThemeId

local B = BanruoUI

local function norm(id) return B._normalizeId(id) end

local function ensureDB()
  BanruoUIDB = BanruoUIDB or {}
  BanruoUIDB.activeThemeId = BanruoUIDB.activeThemeId or nil
  BanruoUIDB.themeInit = BanruoUIDB.themeInit or {}
end

local function getActiveThemeId()
  ensureDB()
  return BanruoUIDB.activeThemeId
end

-- Dropdown close behavior: DropDownList1 is shared by all dropdowns
local function ensureDropdownHooks()
  if B._ddHooksInstalled then return end
  local list = _G and _G["DropDownList1"] or nil
  if not list or type(list.HookScript) ~= "function" then return end

  list:HookScript("OnShow", function()
    -- UIDROPDOWNMENU_OPEN_MENU 指向当前打开的 dropdown
    B._openDropdown = _G and _G.UIDROPDOWNMENU_OPEN_MENU or nil
  end)

  list:HookScript("OnHide", function()
    if B and B._openDropdown == B.themeDD and B.RefreshThemeDropdownCollapsed then
      B:RefreshThemeDropdownCollapsed()
    end
    B._openDropdown = nil
  end)

  B._ddHooksInstalled = true
end

-- -------------------------
-- Theme dropdown
-- -------------------------
function B:RefreshThemeDropdown()
  local dd = self.themeDD
  if not dd then return end

  local themes = self:GetThemes()

  ensureDropdownHooks()

  UIDropDownMenu_Initialize(dd, function(_, level)
    local info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true

    if #themes == 0 then
      info.text = B:Loc("DD_NO_THEME_PACK")
      info.disabled = true
      UIDropDownMenu_AddButton(info, level)
      return
    end

    for _, t in ipairs(themes) do
      local id = t.themeId or t.id
      info.text = t.title or id or "Theme"
      info.func = function()
        self:SetPendingPreviewTheme(id)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  -- pending preview default
  self.state = self.state or {}
  local pending = self.state.pendingPreviewThemeId
  local active = getActiveThemeId()
  if not pending then
    pending = active
    if not pending and #themes > 0 then
      pending = themes[1].themeId or themes[1].id
    end
    self.state.pendingPreviewThemeId = pending
  end

  -- 收起状态：必须回显“当前已生效主题”
  self:RefreshThemeDropdownCollapsed()

  -- 预览区使用 pending（不代表已切换）
  self:UpdatePreviewPanel()
  if self.UpdateSwitchButtonState then self:UpdateSwitchButtonState() end
  if self.UpdateThemePackLabel then self:UpdateThemePackLabel() end
end

function B:RefreshThemeDropdownCollapsed()
  local dd = self.themeDD
  if not dd then return end

  local themes = self:GetThemes()
  if #themes == 0 then
    UIDropDownMenu_SetText(dd, B:Loc("DD_NO_THEME_PACK"))
    return
  end

  local active = getActiveThemeId()
  local t = active and self:GetTheme(active) or nil
  if t then
    UIDropDownMenu_SetText(dd, t.title)
  else
    UIDropDownMenu_SetText(dd, B:Loc("DD_UNKNOWN"))
  end
end

-- 下拉展开时选择主题：仅用于预览（临时态），不写入 DB
function B:SetPendingPreviewTheme(themeId)
  themeId = norm(themeId)
  local theme = themeId and self:GetTheme(themeId) or nil
  if not theme then return end

  self.state = self.state or {}
  self.state.pendingPreviewThemeId = themeId

  -- 展开状态允许回显预览选择（收起/失焦会被 hook 回滚到 active）
  if self.themeDD then
    UIDropDownMenu_SetText(self.themeDD, theme.title)
  end

  self:UpdatePreviewPanel()
  if self.UpdateSwitchButtonState then self:UpdateSwitchButtonState() end
end

-- -------------------------
-- Preview (ThemePreview module reads B.previewText/B.previewTex)
-- -------------------------
function B:UpdatePreviewPanel()
  local id = self.state and self.state.pendingPreviewThemeId or nil
  local theme = id and self:GetTheme(id) or nil

  if not theme then
    if self.previewText then
      self.previewText:SetText(B:Loc("PREVIEW_NO_THEME_PACK"))
    end
    if self.previewTex then
      self.previewTex:SetTexture(nil)
      self.previewTex:SetColorTexture(0,0,0,0.25)
    end
    return
  end

  local lines = {}

  -- Theme packs may optionally provide bilingual fields (e.g., title_en / author_en)
  local loc = self.__activeLocale
  local title = theme.title
  local author = theme.author
  if loc == "enUS" then
    if theme.title_en and theme.title_en ~= "" then title = theme.title_en end
    if theme.author_en and theme.author_en ~= "" then author = theme.author_en end
  end

  table.insert(lines, title or "")
  if author and author ~= "" then table.insert(lines, B:Loc("PREVIEW_AUTHOR_LINE", author)) end
  if theme.version and theme.version ~= "" then table.insert(lines, B:Loc("PREVIEW_VERSION_LINE", theme.version)) end

  local hasWA = (theme.wa and theme.wa.main and theme.wa.main ~= "") and true or false

  table.insert(lines, "")
  table.insert(lines, B:Loc("PREVIEW_INCLUDES_LINE", hasWA and B:Loc("PREVIEW_INCLUDES_WA") or B:Loc("PREVIEW_INCLUDES_NONE")))

  table.insert(lines, "")
  table.insert(lines, B:Loc("PREVIEW_TIP_APPLY_REQUIRED"))
  table.insert(lines, B:Loc("PREVIEW_TIP_SWITCH_NO_OVERRIDE"))
  table.insert(lines, B:Loc("PREVIEW_TIP_ELVUI_MANUAL"))

  if self.previewText then
    self.previewText:SetText(table.concat(lines, "\n"))
  end

  if self.previewTex then
    if theme.preview and theme.preview ~= "" then
      self.previewTex:SetTexture(theme.preview)
    else
      self.previewTex:SetTexture(nil)
      self.previewTex:SetColorTexture(0,0,0,0.25)
    end
  end
end

-- -------------------------
-- Switch / Force Restore
-- -------------------------
local function getThemeById(id)
  id = norm(id)
  return id and B:GetTheme(id) or nil
end

local function getWAString(theme)
  local waId = theme and theme.wa and theme.wa.main or nil
  if not waId or waId == "" then return nil end
  local def = B.GetWA and B:GetWA(waId) or nil
  if not def or type(def.data) ~= "string" then return nil end
  return def.data
end

local function waNeedInit(themeId, theme)
  ensureDB()
  if not theme or not theme.wa or not theme.wa.main or theme.wa.main == "" then return false end

  local init = (BanruoUIDB.themeInit and BanruoUIDB.themeInit[themeId] == true) and true or false
  if not init then return true end

  local gn = theme.wa.groupName
  if type(gn) == "string" and gn ~= "" then
    if B.WA_RootExists and not B:WA_RootExists(gn) then
      return true -- B 兜底：DB 说已初始化，但 WA 根组不存在
    end
  end

  return false
end

local function setRootNever(gn, never)
  -- v2.1：切换主题只管 Root（不递归、不关子树），避免误伤其它主题。
  if not (B.WA_SetRootNever and B.WA_RefreshLoads) then
    return true, B:Loc("ERR_WA_ADAPTER_NOT_READY")
  end
  if type(gn) ~= "string" or gn == "" then
    return true, B:Loc("ERR_WA_NO_GROUPNAME")
  end

  local okRoot, msgRoot, rootId = B:WA_SetRootNever(gn, never)

  if B.WA_RebuildDisplays and rootId then
    B:WA_RebuildDisplays({[rootId] = true})
  elseif B.WA_RefreshLoads then
    B:WA_RefreshLoads()
  end

  return okRoot, msgRoot
end

local function doWASwitch(oldTheme, newTheme, newThemeId, mode)
  if not newTheme or not newTheme.wa or not newTheme.wa.main or newTheme.wa.main == "" then
    return true, B:Loc("ERR_THEME_NO_WA_REF")
  end

  local newGN = newTheme.wa.groupName
  local oldGN = oldTheme and oldTheme.wa and oldTheme.wa.groupName or nil

  if mode == "force" then
    -- 强制还原默认：删除式清理 + 重新导入
    if type(newGN) == "string" and newGN ~= "" and B.WA_DeleteByKeyword then
      local okDel, msgDel = B:WA_DeleteByKeyword(newGN)
      if not okDel then return false, msgDel end
    end

    local waStr = getWAString(newTheme)
    if not waStr then return false, B:Loc("ERR_WA_REG_MISSING") end
    local okImp, msgImp = B:WA_Import(waStr)
    if not okImp then return false, msgImp end

    ensureDB()
    BanruoUIDB.themeInit[newThemeId] = true

    -- 切到新主题（隐藏旧/显示新）
    if type(oldGN) == "string" and oldGN ~= "" and oldGN ~= newGN then
      setRootNever(oldGN, true)
    end
    if type(newGN) == "string" and newGN ~= "" then
      setRootNever(newGN, false)
    end

    return true, B:Loc("WA_FORCE_RESTORE_OK")
  end

  -- 普通切换：A+B 判定，必要时首次导入；然后做隐藏式切换（root-only + parent 残留兜底）
  local needInit = waNeedInit(newThemeId, newTheme)
  if needInit then
    local waStr = getWAString(newTheme)
    if not waStr then return false, B:Loc("ERR_WA_REG_MISSING") end
    local okImp, msgImp = B:WA_Import(waStr)
    if not okImp then return false, msgImp end

    ensureDB()
    BanruoUIDB.themeInit[newThemeId] = true
  end

  if type(oldGN) == "string" and oldGN ~= "" and oldGN ~= newGN then
    setRootNever(oldGN, true)
  end
  if type(newGN) == "string" and newGN ~= "" then
    setRootNever(newGN, false)
  end

  if needInit then
    return true, B:Loc("WA_FIRST_IMPORT_OK")
  end
  return true, B:Loc("WA_HIDDEN_SWITCH_OK")
end

local function finalizeSuccess(themeId, theme)
  ensureDB()
  BanruoUIDB.activeThemeId = themeId
  if theme and theme.wa and theme.wa.groupName then
    BanruoUIDB.activeWAGroupName = theme.wa.groupName
  end
end

local function runApply(mode)
  ensureDB()

  local themeId = B.state and B.state.pendingPreviewThemeId or nil
  themeId = norm(themeId)
  local theme = getThemeById(themeId)
  if not theme then
    B:Print(B:Loc("PRINT_NO_THEME_PACK"))
    return
  end

  -- 口径：pending == active 时不允许切换
  if mode == "switch" and themeId == BanruoUIDB.activeThemeId then
    B:Print(B:Loc("PRINT_ALREADY_ACTIVE"))
    return
  end

  local oldId = BanruoUIDB.activeThemeId
  local oldTheme = oldId and getThemeById(oldId) or nil

  local okWA, msgWA = doWASwitch(oldTheme, theme, themeId, mode)
  if not okWA then
    B:Print(B:Loc("PRINT_WA_FAIL", tostring(msgWA)))
    return
  end

  finalizeSuccess(themeId, theme)

  -- UI 刷新：activeThemeId 发生变化
  if B.OnActiveThemeChanged then
    pcall(B.OnActiveThemeChanged, B)
  else
    -- 兜底：至少把下拉收起回显与按钮状态刷新
    if B.RefreshThemeDropdownCollapsed then B:RefreshThemeDropdownCollapsed() end
    if B.UpdateSwitchButtonState then B:UpdateSwitchButtonState() end
    if B.UpdateThemePackLabel then B:UpdateThemePackLabel() end
  end

  B:Print(B:Loc("PRINT_SWITCH_OK", tostring(theme.title or themeId)))
  B:Print(B:Loc("PRINT_WA_RESULT", tostring(msgWA)))
  B:Print(B:Loc("PRINT_RELOAD_SUGGEST"))
end

function B:SwitchSelectedTheme()
  runApply("switch")
end

function B:ForceRestoreSelectedTheme()
  runApply("force")
end

-- -------------------------
-- Events
-- -------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, _, name)
  if name ~= B.addonName then return end

  B:CreateMainFrame()
  B:RefreshThemeDropdown()

  if B.frame then
    B.frame:Hide()
  end

  B:Print(B:Loc("PRINT_LOADED_HINT"))
end)
