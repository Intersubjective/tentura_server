local ngx = ngx
local cjson = require'cjson.safe'

local hasuraUrl = '/v1/graphql'

---@return boolean
local function _checkSignature()
    return true
end

---@return table?
local function _getBody()
    local bodyString = ngx.req.get_body_data() or ''
    if bodyString == '' then return ngx.exit(400) end

    local Body = cjson.decode(bodyString)
    if type(Body) ~= 'table' then return ngx.exit(400) end

    return Body
end

local _M = {}

function _M.register()
    local Body = _getBody()
    if not Body then return end
end

function _M.login()
end

return _M
