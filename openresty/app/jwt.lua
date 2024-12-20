local JWT_HEADER = 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.'
local JWT_BODY_START_AT = #JWT_HEADER + 1
local JWT_SIGNATURE_LENGTH = 86
local JWT_MIN_LENGTH = JWT_BODY_START_AT + JWT_SIGNATURE_LENGTH
local JWT_EXPIRES_IN = 3600
local PK, SK

local ngx = ngx
local time = ngx.time
local sub = string.sub
local tostring = tostring
local match = string.match
local from_b64 = ngx.decode_base64
local get_headers = ngx.req.get_headers

local to_json = require 'cjson.safe'.encode
local from_json = require 'cjson.safe'.decode
local to_b64url = require 'ngx.base64'.encode_base64url
local from_b64url = require 'ngx.base64'.decode_base64url
local verify = require 'luasodium'.crypto_sign_verify_detached
local sign = require 'luasodium'.crypto_sign_detached


---@param token string?
---@return table?
---@return string?
local function parse_jwt(token)
    if not token or #token < JWT_MIN_LENGTH then
        return nil, 'No JWT!'
    end

    local message = sub(token, 1, #token - JWT_SIGNATURE_LENGTH - 1)
    local jwt, err = from_json(from_b64url(sub(message, JWT_BODY_START_AT)) or '')
    if err then
        return nil, err
    elseif type(jwt) ~= 'table' then
        return nil, 'Wrong JWT!'
    elseif (jwt.exp or 0) < time() then
        return nil, 'JWT expired'
    else
        jwt.message = message
    end

    jwt.signature, err = from_b64url(sub(token, -JWT_SIGNATURE_LENGTH))
    if err then
        return nil, err
    end

    return jwt
end


---@param extract_pk boolean?
---@param token string?
---@return table?
---@return string?
local function verify_jwt(extract_pk, token)
    local jwt, err = parse_jwt(token or match(tostring(get_headers()['Authorization'] or ''), '(%S+)', 8))
    if not jwt then
        return nil, err
    end
    if verify(jwt.signature, jwt.message, extract_pk and from_b64url(jwt.pk) or PK) then
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
    local jwt_body = to_b64url(to_json {
        sub = subject,
        iat = now,
        exp = now + JWT_EXPIRES_IN
    } or '')
    local message = JWT_HEADER .. jwt_body
    return to_json {
        subject = subject,
        token_type = 'bearer',
        access_token = message .. '.' .. to_b64url(sign(message, SK)),
        expires_in = JWT_EXPIRES_IN,
    }
end


---@param pk string
---@param sk string
---@param exp string
---@return nil
local function init(pk, sk, exp)
    local expire = tonumber(exp)
    if expire then
        JWT_EXPIRES_IN = math.floor(expire)
    end
    local re = '\n(.+)\n'
    PK = sub(from_b64(pk:match(re)), -32)
    SK = sub(from_b64(sk:match(re)), -32) .. PK
    print(
        'jwt keys inited: ',
        verify_jwt(false, from_json(sign_jwt('test') or '{}').access_token) ~= nil)
end


return {
    _VERSION = '0.0.1',
    init = init,
    sign_jwt = sign_jwt,
    verify_jwt = verify_jwt,
}
