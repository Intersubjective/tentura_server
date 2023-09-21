local formats = {"png", "webp", "jpg", "jpeg"}

local inlist = function(list, item)
    for k, v in pairs(list) do
        if v == item then  return true  end
    end

    return false
end

rawset(_G, 'lfs', false) --to fix global 'lfs' variable using
local mkdir = require'lfs_ffi'.mkdir
local token = require("random").token
local root = ngx.var.document_root.."/i/"
local rtoken = token(32)
local image_path = root..rtoken
local ok, err = mkdir(image_path)

if not ok then
    ngx.log(ngx.WARN, "Image. Cannot create dir: ", image_path, "Error: ", err)
    rtoken = token(33)
    image_path = root..rtoken
    assert(mkdir(image_path), "Can not create a directory!")
end

local post = require("post")
local post = post:new{path = image_path.."/", no_tmp = true}
local uploaded = post:read()
local image_filename

if uploaded and uploaded.files and uploaded.files.data
        and uploaded.files.data.tmp_name
        and inlist(formats, uploaded.files.data.tmp_name:match(".+%.(.+)")) then

    local cjson = require("cjson")
    ngx.log(ngx.DEBUG, cjson.encode(uploaded.files.data))
    image_filename = image_path.."/"..uploaded.files.data.tmp_name
    ngx.log(ngx.DEBUG, image_filename)
else
    os.remove(image_path)
    ngx.log(ngx.WARN, "Not a file!")
    ngx.status = ngx.HTTP_NOT_ACCEPTABLE

    return ngx.exit(ngx.OK)
end

if not uploaded.files.data.type or uploaded.files.data.type:sub(1,5) ~= "image" then
    os.remove(image_filename)
    os.remove(image_path)
    ngx.log(ngx.WARN, "Not an image!")
    ngx.status = ngx.HTTP_NOT_ACCEPTABLE

    return ngx.exit(ngx.OK)
end

ngx.header.content_type = "application/json; charset=utf-8"
ngx.status = ngx.HTTP_CREATED
ngx.say('{"id": "'..rtoken..'"}')
collectgarbage()

return ngx.exit(ngx.OK)
