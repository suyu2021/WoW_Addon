---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local L = BrAuras.L

local optionsVersion = "5.20.7"
--[==[@debug@
optionsVersion = "Dev"
--@end-debug@]==]

if optionsVersion ~= BrAuras.versionString then
  local message = string.format(L["The BrAuras Options Addon version %s doesn't match the BrAuras version %s. If you updated the addon while the game was running, try restarting World of Warcraft. Otherwise try reinstalling BrAuras"],
                    optionsVersion, BrAuras.versionString)
  ---@diagnostic disable-next-line: duplicate-set-field
  BrAuras.IsLibsOk = function() return false end
  ---@diagnostic disable-next-line: duplicate-set-field
  BrAuras.ToggleOptions = function()
       BrAuras.prettyPrint(message)
  end

end
