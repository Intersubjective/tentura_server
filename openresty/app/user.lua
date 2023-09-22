local ngx = ngx
local to_json = require 'cjson'.encode
local get_auth = require 'app.jwt'.get_auth
local signJWT = require 'app.jwt'.sign_jwt
local query = require 'app.gql'.query

local QUERY_USER_FETCH = [[
    query UserFetch($publicKey: String!) {
        user(where: {public_key: {_eq: $publicKey}}) {id}}
]]
local QUERY_USER_CREATE = [[
    mutation UserCreate($title: String = "", $description: String = "", $publicKey: String!) {
        insert_user_one(object: {title: $title, description: $description, public_key: $publicKey}) {id}}
]]


---@param method string
local function serve(method)
    local jwt = get_auth()
    local respond

    if method == 'register' then
        local resp, err = query(QUERY_USER_CREATE, { publicKey = jwt.sub })
        if resp then
            respond(resp)
            -- respond(signJWT(jwt.sub))
        end
    elseif method == 'login' then
        local resp = query(QUERY_USER_FETCH, { publicKey = jwt.sub })
        if resp then
            respond(resp)
            -- respond(signJWT(jwt.sub))
        end
    end

    if respond then
        ngx.header.content_type = 'application/json'
        ngx.say(to_json(respond))
        return ngx.exit(ngx.OK)
    end

    return ngx.exit(ngx.HTTP_NOT_FOUND)
end


local function test()
    ngx.say(to_json(signJWT 'test'))
end

return {
    _VERSION = '0.0.1',
    serve = serve,
    test = test,
}
