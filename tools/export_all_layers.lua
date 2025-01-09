local spr = app.activeSprite
if not spr then return print('No active sprite') end

-- Extract the current path and filename of the active sprite
local local_path, title, extension = spr.filename:match("^(.+[/\\])(.-)(%.[^.]*)$")

-- Construct export path by prefixing the current .aseprite file path
local export_path = local_path .. "images/"
local_path = export_path

local sprite_name = app.fs.fileTitle(app.activeSprite.filename)

function layer_export(layer)
  local fn = local_path .. "/" .. layer.name
  app.command.ExportSpriteSheet{
      ui=false,
      type=SpriteSheetType.HORIZONTAL,
      textureFilename=fn .. '.png',
      dataFormat=nil,
      layer=layer.name,
      trim=true,
  }
end

local asset_path = local_path .. '/' ---.. sprite_name .. '/'

-- Export all visible layers instead of just the active layer
for i, layer in ipairs(spr.layers) do
  if layer.isVisible then
    layer_export(layer)
  end
end
