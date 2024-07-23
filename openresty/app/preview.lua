local ngx = ngx
local cjson = require 'cjson'
local gql = require 'app.gql'
local template = require 'resty.template'

local CT_HTML = 'text/html; charset=utf-8'

local HEADER = [[
<!doctype html>
<html lang="en" dir="ltr">
  <head>
    <title>Tentura</title>
    <link rel="stylesheet" href="/static/css/preview.css"/>
    <link rel="shortcut icon" href="/static/logo/web_24dp.png" sizes="24x24">
    <link rel="shortcut icon" href="/static/logo/web_32dp.png" sizes="32x32">
    <link rel="shortcut icon" href="/static/logo/web_36dp.png" sizes="36x36">
    <link rel="shortcut icon" href="/static/logo/web_48dp.png" sizes="48x48">
    <link rel="shortcut icon" href="/static/logo/web_64dp.png" sizes="64x64">
    <link rel="shortcut icon" href="/static/logo/web_96dp.png" sizes="96x96">
    <link rel="shortcut icon" href="/static/logo/web_512dp.png" sizes="512x512">
    <meta name="viewport" content="width=device-width, initial-scale=1,minimum-scale=1,maximum-scale=1 user-scalable=no">
    <meta name="referrer" content="origin-when-cross-origin">
    <meta name="robots" content="noindex">
    <meta property="og:type" content="website"/>
    <meta property="og:site_name" content="Tentura"/>
    <meta property="og:title" content="{{title}}"/>
    <meta property="og:description" content="{{description}}"/>
    <meta property="og:url" content="https://{{server_name}}/{*content_uri*}"/>
    <meta property="og:image" content="https://{{server_name}}/{*image_path*}.jpg"/>
  </head>
  <body>
]]

local PROFILE = [[
    <div class="profile-card">
      <div class="profile-image">
        <img src="{*image_path*}.jpg" alt="Profile Image">
      </div>
      <div class="profile-info">
        <div class="profile-name">{{title}}</div>
        <div class="profile-description">{{description}}</div>
      </div>
    </div>
  </body>
</html>
]]

local BEACON = [[
    <div class="post-card">
      <div class="header">
          <img src="https://i.imgur.com/utMtNp7.png" alt="Author Avatar" class="avatar">
          <div class="header-info">
              <div>Josh Sunderland</div>
              <div class="date">15 Jan</div>
          </div>
      </div>
      <div class="post-image">
          <img src="https://i.imgur.com/XS7HiEi.png" alt="Starry Sky">
      </div>
      <div class="post-content">
          <h1>Staying Ahead of the Curve</h1>
          <p>As technology continues to advance at an unprecedented pace, it's becoming increasingly important for individuals and businesses to stay up-to-date with the latest trends and developments in the industry.</p>
      </div>
      <div class="footer">
          <div>Copenhagen, Denmark</div>
          <div>👍 10</div>
      </div>

      <!-- Comment Section -->
      <div class="comment-card">
          <div class="comment-header">
              <img src="https://i.imgur.com/4LC76FR.png" alt="Commenter Avatar" class="avatar">
              <div class="header-info">
                  <div>Alyssa Stewart</div>
                  <div class="time">7m</div>
              </div>
          </div>
          <div class="comment-content">
              <p>One of the best ways to stay up-to-date with the latest trends and developments in the tech industry is to join online forums and communities.</p>
          </div>
          <div class="comment-footer">
              <div>👍 10</div>
          </div>
      </div>
    </div>
  </body>
</html>
]]

local PROFILE_VIEW = HEADER..PROFILE
local BEACON_VIEW = HEADER..BEACON

local QUERY_PROFILE_FETCH = [[
query ($id: String!) {
  user_by_pk(id: $id) {
    title
    description
    has_picture
  }
}
]]


---@return nil
local function profile_view()
  local id = ngx.req.get_uri_args().id
  local data, errors = gql.query(
    QUERY_PROFILE_FETCH,
    { id = id }
  )
  if errors or data == nil then
    local err = cjson.encode(errors or 'Unknown error')
    ngx.var.xlog = err
    ngx.log(ngx.INFO, err)
    return ngx.exit(ngx.HTTP_BAD_REQUEST)
  end

  local user = data.user_by_pk
  local server_name = ngx.var.server_name
  ngx.header.content_type = CT_HTML
  ngx.say(template.process_string(
    PROFILE_VIEW,
    {
      title = user.title,
      description = user.description,
      server_name = server_name == '_'
        and 'localhost'
        or server_name,
      image_path = user.has_picture
        and '/images/'..id
        or '/static/img/avatar-placeholder',
      content_uri = 'beacon/view?id='..id,
    }
  ))
  return ngx.exit(ngx.OK)
end


return {
  _VERSION = '0.0.1',
  profile_view = profile_view,
}
