-- Hexuma rewritten engine entry point. Game logic lives in Lua.
local assets = require("assets")
local dialogue = require("dialogue")
local verbs = require("verbs")
local game = require("game")
local texts = require("texts")
local locale = require("locale")

local M = {}

function M.main()
  hexuma.log("hexuma-zig Lua runtime ready")
  local count = 0
  for _ in pairs(assets.images) do count = count + 1 end
  local verb_count = 0
  for _ in pairs(game.verbs) do verb_count = verb_count + 1 end
  local noun_count = 0
  for _ in pairs(game.vocabulary) do noun_count = noun_count + 1 end
  hexuma.log("decoded images: " .. count)
  hexuma.log("dialogue strings: " .. #dialogue)
  local text_count = 0
  for _ in pairs(texts) do text_count = text_count + 1 end
  hexuma.log("TEXT records: " .. text_count)
  hexuma.log("verbs: " .. verb_count .. " / vocabulary: " .. noun_count)
  hexuma.log("locale labels: " .. #locale.verbs .. " verbs")
  return count, #dialogue, verb_count
end

M.main()
return M
