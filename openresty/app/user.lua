local CT_JSON = 'application/json'

local ngx = ngx
local match = string.match
local get_headers = ngx.req.get_headers

local jwt = require 'app.jwt'
local gql = require 'app.gql'

---@return string
local function get_token()
    local token = ''
    local auth = get_headers()['Authorization']
    if not auth then
        ngx.var.xlog = 'No Authorization header!'
        ngx.exit(ngx.HTTP_UNAUTHORIZED)

    elseif type(auth) == 'table' then
    else
        token = auth
    end
    return match(token, '(%S+)', 8)
end


local QUERY_USER_FETCH = [[
    query UserFetch($publicKey: String!) {
        user(where: {public_key: {_eq: $publicKey}}) {id}}
]]
local function login()
    local user, err = jwt.verify_jwt(get_token(), true)
    if not user then
        ngx.var.xlog = err
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    local data, error = gql.query(QUERY_USER_FETCH, { publicKey = user.pk })
    if data then
        ngx.header.content_type = CT_JSON
        ngx.say(jwt.sign_jwt(data['user'][1]['id']))
        return ngx.exit(ngx.OK)

    elseif error then
        --TBD: parse Hasura errors
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end
end


local QUERY_USER_CREATE = [[
    mutation UserCreate($title: String = "", $description: String = "", $publicKey: String!) {
        insert_user_one(object: {title: $title, description: $description, public_key: $publicKey}) {id}}
]]
local function register()
    local user, err = jwt.verify_jwt(get_token(), true)
    if not user then
        ngx.var.xlog = err
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    local data, error = gql.query(QUERY_USER_CREATE, { publicKey = user.pk })
    if data then
        ngx.header.content_type = CT_JSON
        ngx.say(jwt.sign_jwt(data['insert_user_one']['id']))
        return ngx.exit(ngx.OK)

    elseif error then
        --TBD: parse Hasura errors
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end
end


return {
    _VERSION = '0.0.1',
    login = login,
    register = register,
}
