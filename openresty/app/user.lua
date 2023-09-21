local ngx = ngx
local cjson = require'cjson.safe'
local signJWT = require'app.jwt'.signJWT
local verifyJWT = require'app.jwt'.verifyJWT

local CONTENT_TYPE_KEY = 'Content-Type'
local CONTENT_TYPE_VALUE = 'application/json; charset=utf-8'


---@return table?
local function get_body()
    ngx.req.read_body()
    local bodyString = ngx.req.get_body_data() or ''
    if bodyString == '' then return ngx.exit(400) end

    local Body = cjson.decode(bodyString)
    if type(Body) ~= 'table' then return ngx.exit(400) end

    return Body
end


---@param body string
local function respond(body)
    ngx.header[CONTENT_TYPE_KEY] = CONTENT_TYPE_VALUE
    ngx.say(body)
    ngx.exit(200)
end


local function register()
    local body = get_body()
    if not body then return end

    respond(signJWT(body.sub))
end


local function login()
    local body = get_body()
    if not body then return end

    respond(signJWT(body.sub))
end


return {
    login = login,
    register = register,
}
