local PRV = 'MC4CAQAwBQYDK2VwBCIEIKGa+faaHLZoQxDycBQ6SJWpxIB7s44FvpvCSN1lK6Z4'
local PUB = 'MCowBQYDK2VwAyEAU2q1YNCwpkvyUWucu64JdVMUGAwODc9vfBLCtlvNzec='
local sign_message = require 'luasodium'.crypto_sign_detached
local to_base64url = require 'ngx.base64'.encode_base64url
local to_json = require 'cjson'.encode

local PK = string.sub(ngx.decode_base64(PUB), -32)
local SK = string.sub(ngx.decode_base64(PRV), -32) .. PK

local now = ngx.time()
local jwt_body = to_base64url(to_json {
    pk = to_base64url(PK),
    iat = now,
    exp = now + 3600
})
local message = 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.' .. jwt_body
ngx.say(message .. '.' .. to_base64url(sign_message(message, SK)))
