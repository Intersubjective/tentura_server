local METHOD = 'POST'
local HASURA_URL = 'http://hasura:8080/v1/graphql'
local QUERY_HEADERS = {
    ['Content-Type'] = 'application/json',
}
local ngx = ngx
local cjson = require 'cjson'
local http = require 'resty.http'


---@param gql string
---@param vars table
---@return table?
---@return table?
local function query(gql, vars)
    local httpc = http.new()
    if not httpc then
        ngx.log(ngx.ERR, 'Could not create http client')
        return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
    end
    local res, err = httpc:request_uri(HASURA_URL, {
        method = METHOD,
        headers = QUERY_HEADERS,
        body = cjson.encode { query = gql, variables = vars },
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
        local json = cjson.decode(res.body)
        if json.errors then
            ngx.log(ngx.INFO, cjson.encode(json.errors))
        end
        return json.data, json.errors
    end
end


---@param hasura_url string
---@param hasura_admin_secret string
local function init(hasura_url, hasura_admin_secret)
    if type(hasura_url) == 'string' and hasura_url ~= '' then
        HASURA_URL = hasura_url
    end
    QUERY_HEADERS['X-Hasura-Admin-Secret'] = hasura_admin_secret
end


return {
    _VERSION = '0.0.1',
    init = init,
    query = query,
}
