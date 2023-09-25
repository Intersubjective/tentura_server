local ngx = ngx
local mkdir = require'lfs_ffi'.mkdir
local post = require'resty.post'
local cjson = require 'cjson'
local jwt = require 'app.jwt'

local IMAGES_BASE_PATH = '/srv/images/'

local function upload()
    local args, err = ngx.req.get_uri_args()
    if not args or not args.id then
        ngx.var.xlog = err
        return ngx.exit(ngx.HTTP_BAD_REQUEST)
    end

    local token, err = jwt.verify_jwt()
    if not token then
        ngx.var.xlog = err
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    local image_path = IMAGES_BASE_PATH .. token.sub
    local ok, err = mkdir(image_path)
    if not ok then
        ngx.log(ngx.INFO, err)
        -- return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end

    local file = post:new{
        no_tmp = true,
        path = image_path,
        name = function (name, field)
            return args.id == token.sub and 'avatar.jpg' or args.id .. '.jpg'
        end
    }
    local uploaded = file:read()
    if uploaded and uploaded.files then
        ngx.var.xlog = cjson.encode(uploaded.files)
        return ngx.exit(ngx.HTTP_CREATED)
    else
        return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    end
end


local function check_access()
    local method = ngx.req.get_method()
    if method == 'GET' then
        return ngx.exit(ngx.OK)
    elseif method == 'PUT' or method == 'DELETE' then
        local token, err = jwt.verify_jwt()
        if not token then
            ngx.var.xlog = err
            return ngx.exit(ngx.HTTP_UNAUTHORIZED)
        end
        if token.sub == ngx.var[1] then
            return ngx.exit(ngx.OK)
        end
    end
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end


---@param base_path string?
local function init(base_path)
    if base_path and base_path ~= '' then
        IMAGES_BASE_PATH = base_path
    end
end

return {
    _VERSION = '0.0.1',
    init = init,
    upload = upload,
    check_access = check_access,
}
