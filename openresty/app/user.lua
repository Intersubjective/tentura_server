local is_empty = require 'table.isempty'
local cjson = require 'cjson'
local jwt = require 'app.jwt'
local gql = require 'app.gql'
local ngx = ngx

local CT_JSON = 'application/json'

local QUERY_USER_FETCH = [[
query ($pk: String!) {
  user(where: {public_key: {_eq: $pk}}) {
    id
  }
}
]]

---@return nil
local function login()
    local token, err = jwt.verify_jwt(true)
    if not token then
        ngx.var.xlog = err
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    local data, errors = gql.query(
        QUERY_USER_FETCH,
        { pk = token.pk }
    )
    if data then
        if is_empty(data.user) then
            return ngx.exit(ngx.HTTP_NOT_FOUND)
        end
        ngx.header.content_type = CT_JSON
        ngx.say(jwt.sign_jwt(data.user[1].id))
        return ngx.exit(ngx.OK)
    elseif errors then
        ngx.log(ngx.INFO, cjson.encode(errors))
        return ngx.exit(ngx.HTTP_BAD_REQUEST)
    end

    return ngx.exit(ngx.HTTP_BAD_GATEWAY)
end


local QUERY_USER_CREATE = [[
mutation ($pk: String!) {
  insert_user_one(object: {public_key: $pk}) {
    id
  }
}
]]

---@return nil
local function register()
    local token, err = jwt.verify_jwt(true)
    if not token then
        ngx.var.xlog = err
        return ngx.exit(ngx.HTTP_UNAUTHORIZED)
    end

    local data, errors = gql.query(
        QUERY_USER_CREATE,
        { pk = token.pk }
    )
    if data then
        ngx.header.content_type = CT_JSON
        ngx.say(jwt.sign_jwt(data.insert_user_one.id))
        return ngx.exit(ngx.OK)
    elseif errors then
        ngx.log(ngx.INFO, cjson.encode(errors))
        return ngx.exit(ngx.HTTP_CONFLICT)
    end

    return ngx.exit(ngx.HTTP_BAD_GATEWAY)
end


return {
    _VERSION = '0.0.1',
    login = login,
    register = register,
}
