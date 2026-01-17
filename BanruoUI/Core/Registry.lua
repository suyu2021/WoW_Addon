-- Core/Registry.lua
-- 只负责：WA / ElvUI 字符串“仓库”与注册接口
-- 不负责：主题注册（主题注册在 Core/Bootstrap.lua 里）

local B = BanruoUI
if not B then return end

B._waPool  = B._waPool  or {}  -- id -> {id,name,data}
B._elvPool = B._elvPool or {}  -- id -> {id,name,data}

function B:RegisterWA(def)
  if type(def) ~= "table" then return false end
  if not def.id or not def.data then return false end
  self._waPool[tostring(def.id)] = def
  return true
end

function B:RegisterElvUIProfile(def)
  if type(def) ~= "table" then return false end
  if not def.id or not def.data then return false end
  self._elvPool[tostring(def.id)] = def
  return true
end

function B:GetWA(id)
  if not id then return nil end
  return self._waPool[tostring(id)]
end

function B:GetElvUIProfile(id)
  if not id then return nil end
  return self._elvPool[tostring(id)]
end
