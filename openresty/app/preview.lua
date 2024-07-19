local template = require 'resty.template.safe'
local cjson = require 'cjson'
local gql = require 'app.gql'
local ngx = ngx

local CT_JSON = 'application/json'

local HEADER_VIEW = template.new[[
<head>
  <title>Tentura</title>
  <base href="https://{{server_name}}/">
  <link rel="canonical" href="https://{{server_name}}/">
  <link rel="shortcut icon" href="//{{server_name}}/static/logo/web_24dp.png" sizes="24x24">
  <link rel="shortcut icon" href="//{{server_name}}/static/logo/web_32dp.png" sizes="32x32">
  <link rel="shortcut icon" href="//{{server_name}}/static/logo/web_36dp.png" sizes="36x36">
  <link rel="shortcut icon" href="//{{server_name}}/static/logo/web_48dp.png" sizes="48x48">
  <link rel="shortcut icon" href="//{{server_name}}/static/logo/web_64dp.png" sizes="64x64">
  <link rel="shortcut icon" href="//{{server_name}}/static/logo/web_96dp.png" sizes="96x96">
  <link rel="shortcut icon" href="//{{server_name}}/static/logo/web_512dp.png" sizes="512x512">
  <meta name="robots" content="noindex">
  <meta name="referrer" content="origin-when-cross-origin">
  <meta name="description" content="Social network for communities.">
  <meta name="viewport" content="width=device-width, initial-scale=1,minimum-scale=1,maximum-scale=1 user-scalable=no">
  <meta property="og:url" content="https://{{server_name}}"/>
  <meta property="og:type" content="website"/>
  <meta property="og:title" content="Tentura"/>
  <meta property="og:description" content="Social network for communities."/>
  <meta property="og:image" content="https://{{server_name}}/static/logo/web_96dp.png"/>
</head>
]]

local PROFILE_VIEW = template.new[[
<!doctype html>
<html lang="en" dir="ltr">
  {*header*}
	<body style="height:100%;overflow:hidden;-webkit-font-smoothing:antialiased;color:rgba(0,0,0,0.87);font-family:Roboto,RobotoDraft,Helvetica,Arial,sans-serif;font-weight:400;margin:0;-webkit-text-size-adjust:100%;-webkit-text-size-adjust:100%;text-size-adjust:100%;-webkit-user-select:none">
		<div class="root">
			<div style="padding:32px 64px">
				<img src="https://{{server_name}}/static/logo/web_96dp.png" alt="Tentura" style="border:none">
			</div>
			<div style="color:#5f6368;font-size:20px;font-weight:500;padding-left:16px">
				Social network for communities.
			</div>
		</div>
	</body>
</html>
]]

local QUERY_PROFILE_FETCH = [[
query ($id: String!) {
  user(where: {id: {_eq: $id}}) {
    id
    title
    description
    has_picture
  }
}
]]

---@return nil
local function profile_view()
  local data, errors = gql.query(
    QUERY_PROFILE_FETCH,
    { id = ngx.req.get_uri_args().id })
  if errors then
    ngx.log(ngx.INFO, cjson.encode(errors))
    return ngx.exit(ngx.HTTP_BAD_REQUEST)
  end

  ngx.header.content_type = CT_JSON
  ngx.say(data)
  return ngx.exit(ngx.OK)
end


---@param server_name string
---@return nil
local function init(server_name)
  HEADER_VIEW.server_name = server_name
  PROFILE_VIEW.server_name = server_name
  PROFILE_VIEW.header = HEADER_VIEW:render()
end


return {
  _VERSION = '0.0.1',
  init = init,
  profile_view = profile_view,
}
