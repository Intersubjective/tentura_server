local config_file = io.open('/etc/nginx/nginx.conf', 'r')
if config_file then
    local config_template = config_file:read'*a'
    config_file:close()
    require 'resty.template'.render_string(config_template)
else
    return print'Cant read template'
end
