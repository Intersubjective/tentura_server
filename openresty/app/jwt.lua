local sodium = require'luasodium'
-- local base64 = ngx.base64

local _seed, _pk, _sk

local Header = {
    typ = 'JWT',
    kty = 'OKP',
    kid = '',
    alg = 'EdDSA',
    crv = 'Ed25519',
    x = '[publicKey]',
}

local Message = {
    jti = "22916f3c-9093-4813-8397-f10e6b704b68",
    delegationId = "b4ae47a7-625a-4630-9727-45764a712cce",
    exp = 1655279109,
    nbf = 1655278809,
    scope = "read openid",
    iss = "https://idsvr.example.com",
    sub = "username",
    aud = "api.example.com",
    iat = 1655278809,
    purpose = "access_token",
}

local _M = {
    _VERSION = '0.0.1',
}

--- seed is a base64 encoded token 32 bytes length
---@param seed string?
---@return table
function _M.init(seed)
    _seed = seed and ngx.decode_base64(seed) or sodium.randombytes_buf(32)
    _pk, _sk = sodium.crypto_sign_seed_keypair(_seed)
    print'jwt keys inited'
    return _M
end

function _M.printSeed()
    print(_seed)
end

function _M.printPublic()
    local sk = sodium.crypto_sign_ed25519_sk_to_pk(_seed)
    print(ngx.encode_base64(sk))
end

return _M
