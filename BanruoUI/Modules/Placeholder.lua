-- Modules/Placeholder.lua
-- 占位模块：故事集/点歌机（v1.5：元素开关已独立为可用模块）

local B = BanruoUI
if not B then return end

local function CreatePlaceholder(parent, titleKey)
  local page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints(parent)

  local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  h:SetPoint("TOPLEFT", 16, -18)
  h:SetText((titleKey and B and B.Loc) and B:Loc(titleKey) or "")

  local t = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  t:SetPoint("TOPLEFT", 16, -60)
  t:SetPoint("TOPRIGHT", -16, -60)
  t:SetJustifyH("LEFT")
  t:SetJustifyV("TOP")
  t:SetText((B and B.Loc) and B:Loc("TEXT_PLACEHOLDER_UNAVAILABLE") or "不可用/敬请期待")

  return page
end

local function register(id, titleKey, order)
  B:RegisterModule(id, {
    titleKey = titleKey,
    order = order,
    Create = function(self, parent) return CreatePlaceholder(parent, titleKey) end,
  })
end

register("story_collection", 'MODULE_STORY_COLLECTION', 20)
register("jukebox", 'MODULE_JUKEBOX', 30)
