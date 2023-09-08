local ngx = ngx
local cjson = require'cjson.safe'
local sodium = require'luasodium'

local hasuraUrl = '/v1/graphql'
local tokenRegExp = '[B|b]earer[%s|=]+(%S+)'
local anonymousRoleBody = '{"X-Hasura-Role": "anonymous"}'

local _M = {}

---@param allowAnonymous boolean
function _M.getAuth(allowAnonymous)
  local token = string.match(
    ngx.var.http_authorization or ngx.var.http_cookie or '',
    tokenRegExp
    )
  if not token then
    if allowAnonymous then
      ngx.say(anonymousRoleBody)
      return ngx.exit(200)
    else
      return ngx.exit(401)
    end
  end

  local res = ngx.location.capture(hasuraUrl)
  if not res or res.truncated or res.status ~= 200 then
    return ngx.exit(allowAnonymous and 500 or 0)
  else
    ngx.req.read_body()
  end

  local Body = cjson.decode(res.body)
  if Body then
    ngx.log(ngx.DEBUG, 'user_id: ', Body.sub)
  else
    return ngx.exit(401)
  end
end

return _M
