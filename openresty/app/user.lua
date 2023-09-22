local ngx = ngx
local http = require'resty.http'
local to_json = require 'cjson'.encode
local from_json = require 'cjson.safe'.decode
local verifyJWT = require 'app.jwt'.verifyJWT
local signJWT = require 'app.jwt'.signJWT

local CT_JSON = 'application/json'
local HASURA_URL = 'http://hasura:8080/v1/graphql'
local QUERY_HEADERS = {['Content-Type'] = CT_JSON}
local QUERY_USER_FETCH = [[
    query UserFetch($publicKey: String!) {
        user(where: {public_key: {_eq: $publicKey}}) {id}}
]]
local QUERY_USER_CREATE = [[
    mutation UserCreate($title: String = "", $description: String = "", $publicKey: String!) {
        insert_user_one(object: {title: $title, description: $description, public_key: $publicKey}) {id}}
]]


---@return table?
local function get_auth_token()
    return verifyJWT(string.match(ngx.var.http_authorization or '', 'Bearer[%s+](%S+)'))
        or ngx.exit(ngx.HTTP_UNAUTHORIZED)
end


---@param gql string
---@param vars table
---@return table?
local function query(gql, vars)
    local httpc = http.new()
    local res, err = httpc:request_uri(HASURA_URL, {
        method = 'POST',
        headers = QUERY_HEADERS,
        body = to_json { query = gql, variables = vars },
    })
    if not res then
        ngx.status = ngx.HTTP_BAD_GATEWAY
        ngx.say(err)
        return ngx.exit(ngx.OK)
    elseif res.status ~= 200 then
        ngx.status = res.status or ngx.HTTP_BAD_GATEWAY
        ngx.say(res.body)
        return ngx.exit(ngx.OK)
    else
        return from_json(res.body)
    end
end


local function respond(body)
    if body == nil then
        return ngx.exit(ngx.HTTP_BAD_REQUEST)
    end
    if type(body) == 'table' then
        ngx.header.content_type = CT_JSON
        ngx.say(to_json(body))
    else
        ngx.say(tostring(body))
    end
    return ngx.exit(ngx.OK)
end


--=== Public methods ===--


---@param hasura_admin_secret string
local function init(hasura_admin_secret)
    QUERY_HEADERS['X-Hasura-Admin-Secret'] = hasura_admin_secret
end


---@param method string
local function serve(method)
    local jwt = get_auth_token()
    if not jwt then
        return print'Wrong token!'
    end

    if method == 'register' then
        local resp = query(QUERY_USER_CREATE, {publicKey = jwt.sub})
        if resp then
            respond(resp)
            -- respond(signJWT(jwt.sub))
        end
    elseif method == 'login' then
        local resp = query(QUERY_USER_FETCH, {publicKey = jwt.sub})
        if resp then
            respond(resp)
            -- respond(signJWT(jwt.sub))
        end
    end
    return respond()
end


local function test()
    respond(signJWT'test')
end

return {
    _VERSION = '0.0.1',
    init = init,
    serve = serve,
    test = test,
}
