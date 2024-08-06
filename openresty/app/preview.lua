local ngx = ngx
local sub = string.sub
local fmt = string.format
local gql = require 'app.gql'
local template = require 'resty.template.safe'

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
    <meta property="og:url" content="https://{{server_name}}/shared/view?id={{id}}"/>
    <meta property="og:image" content="https://{{server_name}}/{*image_path*}.jpg"/>
  </head>
  <body>
]]

local PROFILE_VIEW = HEADER .. [[
    <div class="profile-card">
      <div class="profile-image">
        <img src="/{*image_path*}.jpg" alt="Profile Image">
      </div>
      <div class="profile-info">
        <div class="profile-name">{{title}}</div>
        <div class="profile-description">{{description}}</div>
      </div>
    </div>
  </body>
</html>
]]

local BEACON_VIEW = HEADER .. [[
    <div class="post-card">
      <div class="header">
        <img src="/{*author_image*}.jpg" alt="Author Avatar" class="avatar">
        <div class="header-info">{{author_name}}</div>
      </div>
      <div class="post-image">
        <img src="/{*image_path*}.jpg" alt="Beacon Image">
      </div>
      <div class="post-content">
        <h1>{{title}}</h1>
        <p>{{description}}</p>
      </div>
      {% if place then %}
        <div class="footer">{*place*}</div>
      {% end %}
      {% if time then %}
        <div class="footer">{*time*}</div>
      {% end %}

      {% if comment then %}
      <div class="comment-card">
        <div class="comment-header">
          <img src="/{*commenter_avatar*}.jpg" alt="Commenter Avatar" class="avatar">
          <div>{{commenter_name}}</div>
        </div>
        <div class="comment-content">
          <p>{{comment}}</p>
        </div>
      </div>
      {% end %}
    </div>
  </body>
</html>
]]

local QUERY_PROFILE_FETCH = [[
query ($id: String!) {
  user_by_pk(id: $id) {
    id
    title
    description
    has_picture
  }
}
]]

local QUERY_BEACON_FETCH = [[
query ($id: String!) {
  beacon_by_pk(id: $id) {
    id
    title
    description
    has_picture
    timerange
    user_id
    context
    long
    lat
    author {
      id
      title
      has_picture
    }
  }
}
]]

local QUERY_COMMENT_FETCH = [[
query ($id: String!) {
  comment_by_pk(id: $id) {
    content
    author {
      id
      title
      has_picture
    }
    beacon {
      id
      title
      description
      has_picture
      timerange
      context
      long
      lat
      author {
        id
        title
        has_picture
      }
    }
  }
}
]]


---@return table
local function new_context()
  return {
    title = nil,
    description = nil,
    image_path = nil,
    id = ngx.req.get_uri_args().id,
    server_name = ngx.var.server_name,
}
end


---@param id string
---@param has_picture boolean
---@return string
local function get_user_image(id, has_picture)
  return has_picture
    and fmt('images/%s/avatar', id)
    or 'static/img/avatar-placeholder'
end


---@param user_id string
---@param beacon_id string
---@param has_picture boolean
---@return string
local function get_beacon_image(user_id, beacon_id, has_picture)
  return has_picture
    and fmt('images/%s/%s', user_id, beacon_id)
    or 'static/img/image-placeholder'
end


---@param lat string?
---@param long string?
---@return string?
local function get_place(lat, long)
  if lat and long then
    if lat == ngx.null or long == ngx.null then
      return
    end
    return fmt('lat: %s, long: %s', lat, long)
  end
end


---@param timerange string?
---@return string?
local function get_timerange(timerange)
  if timerange and timerange ~= ngx.null then
    return timerange
  end
end


---@return nil
local function shared_view()
  local response
  local context = new_context()
  local prefix = sub(context.id, 1, 1)

  -- User
  if prefix == 'U' then
    local data = gql.query(
      QUERY_PROFILE_FETCH,
      { id = context.id }
    ).user_by_pk

    context.title = data.title
    context.description = data.description
    context.image_path = get_user_image(
      data.id,
      data.has_picture
    )
    -- print(require 'cjson.safe'.encode(context))
    response = template.process_string(PROFILE_VIEW, context)

  -- Beacon
  elseif prefix == 'B' then
    local data = gql.query(
      QUERY_BEACON_FETCH,
      { id = context.id }
    ).beacon_by_pk

    context.title = data.title
    context.description = data.description
    context.image_path = get_beacon_image(
      data.author.id,
      data.id,
      data.has_picture
    )
    context.author_name = data.author.title
    context.author_image = get_user_image(
      data.author.id,
      data.author.has_picture
    )
    context.time = get_timerange(data.timerange)
    context.place = get_place(data.lat, data.long)
    response = template.process_string(BEACON_VIEW, context)

  -- Comment
  elseif prefix == 'C' then
    local data = gql.query(
      QUERY_COMMENT_FETCH,
      { id = context.id }
    ).comment_by_pk

    context.title = data.beacon.title
    context.description = data.beacon.description
    context.image_path = get_beacon_image(
      data.author.id,
      data.beacon.id,
      data.beacon.has_picture
    )
    context.author_name = data.author.title
    context.author_image = get_user_image(
      data.author.id,
      data.author.has_picture
    )
    context.time = get_timerange(data.beacon.timerange)
    context.place = get_place(data.beacon.lat, data.beacon.long)
    context.comment = data.content
    context.commenter_name = data.author.title
    context.commenter_avatar = get_user_image(
      data.author.id,
      data.author.has_picture
    )
    response = template.process_string(BEACON_VIEW, context)

  -- Wrong
  else
    response = 'Wrong id'
    ngx.var.xlog = response
    ngx.status = ngx.HTTP_BAD_REQUEST
  end

  ngx.header.content_type = CT_HTML
  ngx.say(response)
  return ngx.exit(ngx.OK)
end


return {
  _VERSION = '0.0.1',
  shared_view = shared_view,
}
