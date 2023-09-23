local JWT_HEADER = 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.'
local JWT_BODY_START_AT = #JWT_HEADER + 1
local JWT_EXPIRES_IN = 3600
local PK, SK

local ngx = ngx
local time = ngx.time
local sub = string.sub
local find = string.find
local from_base64 = ngx.decode_base64
local to_json = require 'cjson'.encode
local from_json = require 'cjson.safe'.decode
local to_base64url = require 'ngx.base64'.encode_base64url
local from_base64url = require 'ngx.base64'.decode_base64url
local sign = require 'luasodium'.crypto_sign_detached
local verify = require 'luasodium'.crypto_sign_verify_detached


---@param token string?
---@return table?
---@return string?
local function parse_jwt(token)
    if not token or #token < JWT_BODY_START_AT then
        return nil, 'Wrong JWT!'
    end

    local dotPosition = find(token, '.', JWT_BODY_START_AT, true) or 0
    local message = sub(token, 1, dotPosition - 1)

    local jwt, err = from_json(from_base64url(sub(message, JWT_BODY_START_AT)) or 'not json')
    if err then
        return nil, err

    elseif type(jwt) ~= 'table' then
        return nil, 'Wrong JWT!'

    elseif (jwt.exp or 0) < time() then
        return nil, 'JWT expired'
    else
        jwt.message = message
    end

    jwt.signature, err = from_base64url(sub(token, dotPosition + 1))
    if err then
        return nil, err
    end

    return jwt
end


---@param token string
---@param extract_pk boolean?
---@return table?
---@return string?
local function verify_jwt(token, extract_pk)
    local jwt, err = parse_jwt(token)
    if not jwt then
        return nil, err
    end
    local pk = extract_pk and from_base64url(jwt.pk) or PK
    if verify(jwt.signature, jwt.message, pk) then
        return jwt
    else
        return nil, 'Wrong signature!'
    end
end


---@param subject string?
---@return string?
local function sign_jwt(subject)
    if not subject or subject == '' then
        return
    end
    local now = time()
    local jwt_body = to_base64url(to_json {
        sub = subject,
        iat = now,
        exp = now + JWT_EXPIRES_IN
    })
    local message = JWT_HEADER .. jwt_body
    return to_json{
        subject = subject,
        token_type = 'bearer',
        access_token = message .. '.' .. to_base64url(sign(message, SK)),
        expires_in = JWT_EXPIRES_IN,
    }
end


---@param pk string
---@param sk string
---@param exp string
local function init(pk, sk, exp)
    local expire = tonumber(exp)
    if expire then
        JWT_EXPIRES_IN = math.floor(expire)
    end
    local re = '\n(.+)\n'
    PK = sub(from_base64(pk:match(re)), -32)
    SK = sub(from_base64(sk:match(re)), -32) .. PK
    print(
        'jwt keys inited: ',
        verify_jwt(from_json(sign_jwt('test') or '{}').access_token) ~= nil)
end


return {
    _VERSION = '0.0.1',
    init = init,
    sign_jwt = sign_jwt,
    verify_jwt = verify_jwt,
}
