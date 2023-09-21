local ngx = ngx
local time = ngx.time
local sub = string.sub
local find = string.find
local match = string.match
local from_base64 = ngx.decode_base64
local to_json = require 'cjson'.encode
local from_json = require 'cjson'.decode
local to_base64url = require 'ngx.base64'.encode_base64url
local from_base64url = require 'ngx.base64'.decode_base64url
local sign = require 'luasodium'.crypto_sign_detached
local verify = require 'luasodium'.crypto_sign_verify_detached

local JWT_HEADER = 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.'
local JWT_BODY_START_AT = #JWT_HEADER + 1
local PK, SK

--=== Public methods ===--


---@param subject string?
---@return string?
local function signJWT(subject)
    if not subject or subject == '' then
        return
    end
    local now = time()
    local jwt_body = to_base64url(to_json {
        sub = subject,
        iat = now,
        exp = now + 3600
    })
    local message = JWT_HEADER .. jwt_body
    return message .. '.' .. to_base64url(sign(message, SK))
end


---@param jwt string?
---@return table?
local function verifyJWT(jwt)
    if not jwt or #jwt < JWT_BODY_START_AT then
        return
    end
    local dotPosition = find(jwt, '.', JWT_BODY_START_AT, true)
    local message = sub(jwt, 1, dotPosition - 1)
    local signature = from_base64url(sub(jwt, dotPosition + 1))
    if verify(signature, message, PK) then
        local body = from_base64url(sub(message, JWT_BODY_START_AT))
        --TBD: verify iat, exp and etc
        if body then
            return from_json(body)
        end
    end
end


---@param pk string
---@param sk string
local function init(pk, sk)
    PK = sub(from_base64(match(pk, '\n(.+)\n')), -32)
    SK = sub(from_base64(match(sk, '\n(.+)\n')), -32) .. PK
    print('jwt keys inited: ', verifyJWT(signJWT 'test') ~= nil)
end


return {
    _VERSION = '0.0.1',
    init = init,
    signJWT = signJWT,
    verifyJWT = verifyJWT,
}
