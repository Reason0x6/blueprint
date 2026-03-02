
--[[

This is an export script for Aseprite

It takes the currently selected layer and exports it into ../res/images/layername.png

Or, if it's an animation, will export all animation tags to ../res/images/spritename_tagname.png

Very helpful for quickly exporting with a keybind.

]]

local spr = app.activeSprite
if not spr then return print('No active sprite') end

-- Extract the current path and filename of the active sprite
local local_path, title, extension = spr.filename:match("^(.+[/\\])(.-)(%.[^.]*)$")

-- Construct export path by prefixing the current .aseprite file path
local export_path = local_path .. "../res/images/"
local_path = export_path

local sprite_name = app.fs.fileTitle(app.activeSprite.filename)

function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*all")
  f:close()
  return content
end

function write_file(path, content)
  local f = io.open(path, "w")
  if not f then
    print("Failed to write: " .. path)
    return false
  end
  f:write(content)
  f:close()
  return true
end

function collect_wh_from_frames_table(frames, widths, heights, width_parts, size_parts)
  local count = 0
  if type(frames) ~= "table" then
    return 0
  end
  for _, entry in ipairs(frames) do
    local fr = entry
    if type(entry) == "table" and type(entry.frame) == "table" then
      fr = entry.frame
    end
    local w = 0
    local h = 0
    if type(fr) == "table" then
      w = tonumber(fr.w) or 0
      h = tonumber(fr.h) or 0
    end
    if w > 0 and h > 0 then
      count = count + 1
      widths[#widths + 1] = w
      heights[#heights + 1] = h
      width_parts[#width_parts + 1] = tostring(w)
      size_parts[#size_parts + 1] = tostring(w) .. "x" .. tostring(h)
    end
  end
  return count
end

function collect_wh_from_json_text(json_text, widths, heights, width_parts, size_parts)
  local count = 0
  local pos = 1
  while true do
    local s, e = json_text:find('"frame"%s*:%s*%b{}', pos)
    if not s then break end
    local block = json_text:sub(s, e)
    local w = tonumber(block:match('"w"%s*:%s*(%d+)')) or 0
    local h = tonumber(block:match('"h"%s*:%s*(%d+)')) or 0
    if w > 0 and h > 0 then
      count = count + 1
      widths[#widths + 1] = w
      heights[#heights + 1] = h
      width_parts[#width_parts + 1] = tostring(w)
      size_parts[#size_parts + 1] = tostring(w) .. "x" .. tostring(h)
    end
    pos = e + 1
  end
  return count
end

function delete_file_with_retries(path)
  local attempts = 5
  for _ = 1, attempts do
    if not app.fs.isFile(path) then
      return true
    end

    pcall(function() os.remove(path) end)

    if not app.fs.isFile(path) then
      return true
    end

    if app.sleep then
      app.sleep(25)
    end
  end

  print("Failed to delete json file: " .. path)
  return false
end

function export_json_to_meta(json_path, meta_path)
  local json_text = read_file(json_path)
  if not json_text then
    print("No json found at " .. json_path)
    return
  end

  local ok, decoded = pcall(function() return json.decode(json_text) end)
  if not ok or not decoded then
    print("Failed to parse json at " .. json_path)
    return
  end

  local width_parts = {}
  local size_parts = {}
  local center_offset_parts = {}
  local widths = {}
  local heights = {}
  local count = 0

  local frames = decoded.frames or decoded
  count = collect_wh_from_frames_table(frames, widths, heights, width_parts, size_parts)

  -- Fallback parser from raw json text if decode shape is unexpected.
  if count == 0 then
    count = collect_wh_from_json_text(json_text, widths, heights, width_parts, size_parts)
  end

  if count == 0 then
    print("Unexpected json format in " .. json_path)
    return
  end

  -- Always compute centering from widths/heights only.
  local max_w = 0
  local max_h = 0
  for i = 1, #widths do
    if widths[i] > max_w then max_w = widths[i] end
    if heights[i] > max_h then max_h = heights[i] end
  end
  for i = 1, #widths do
    local w = widths[i]
    local h = heights[i]
    local off_x = 0.0
    local off_y = (max_h - h) * 0.5
    center_offset_parts[#center_offset_parts + 1] = string.format("%.3f:%.3f", off_x, off_y)
  end

  local meta = ""
  meta = meta .. "frame_count=" .. tostring(count) .. "\n"
  meta = meta .. "frame_widths=" .. table.concat(width_parts, ",") .. "\n"
  meta = meta .. "frame_sizes=" .. table.concat(size_parts, ",") .. "\n"
  meta = meta .. "frame_center_offsets=" .. table.concat(center_offset_parts, ",") .. "\n"

  write_file(meta_path, meta)
end

function layer_export()
  local fn = local_path .. "/" .. app.activeLayer.name
  local json_fn = fn .. '.json'
  app.command.ExportSpriteSheet{
      ui=false,
      type=SpriteSheetType.HORIZONTAL,
      textureFilename=fn .. '.png',
      dataFilename=json_fn,
      dataFormat=SpriteSheetDataFormat.JSON_ARRAY,
      layer=app.activeLayer.name,
      trim=true,
  }
  export_json_to_meta(json_fn, fn .. '.meta')
  delete_file_with_retries(json_fn)
end

local asset_path = local_path .. '/'

function do_animation_export()
  for i,tag in ipairs(spr.tags) do
    local fn =  asset_path .. sprite_name .. "_" .. tag.name
    local json_fn = fn .. '.json'
    app.command.ExportSpriteSheet{
      ui=false,
      type=SpriteSheetType.HORIZONTAL,
      textureFilename=fn .. '.png',
      dataFilename=json_fn,
      dataFormat=SpriteSheetDataFormat.JSON_ARRAY,
      tag=tag.name,
      listLayers=false,
      listTags=false,
      listSlices=false,
    }
    export_json_to_meta(json_fn, fn .. '.meta')
    delete_file_with_retries(json_fn)
  end
end

if #spr.tags > 0 then
  do_animation_export()
else 
  layer_export()
end
