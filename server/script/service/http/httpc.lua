local net = require "service.net"
local internal = require "service.http.internal"

local httpc = {}

local function check_protocol(host)
    local protocol = host:match("^%a+://")
    if protocol then
        protocol = string.lower(protocol)
        if protocol == "http://" then
            return string.gsub(host, "^"..protocol, "")
        else
            error(string.format("Invalid protocol: %s", protocol))
        end
    else
        return host
    end
end

local function gen_interface(fd)
    local rbuf = ""
    function fd:on_data(data)
        rbuf = rbuf .. data
    end
    local function read(sz)
        if sz == nil then
            fd:update()
            local r = rbuf
            rbuf = ""
            return r
        else
            while not fd:is_closed() do
                fd:update()
                if #rbuf >= sz then
                    local r = rbuf:sub(1, sz)
                    rbuf = rbuf:sub(sz + 1)
                    return r
                end
            end
            return ""
        end
    end
    local function write(data)
        fd:write(data)
    end
    local function readall()
        while not fd:is_closed() do
            net.update()
        end
        local r = rbuf
        rbuf = ""
        return r
    end
    return {
        read = read,
        write = write,
        readall = readall,
    }
end

function httpc.request(method, host, url, recvheader, header, content)
    host = check_protocol(host)
    local hostname, port = host:match"([^:]+):?(%d*)$"
    port = port == "" and 80 or tonumber(port)
    local fd = net.connect("tcp", hostname, port)
    if not fd then
        error(string.format("http connect error host:%s, port:%s, timeout:%s", hostname, port))
        return
    end
	local interface = gen_interface(fd)
    local ok , statuscode, body = pcall(internal.request, interface, method, host, url, recvheader, header, content)
    fd:close()
    if ok then
        return statuscode, body
    else
        error(statuscode)
    end
end

function httpc.get(...)
    return httpc.request("GET", ...)
end

local function escape(s)
    return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

function httpc.post(host, url, form, recvheader)
    local header = {
        ["content-type"] = "application/x-www-form-urlencoded"
    }
    local body = {}
    for k,v in pairs(form) do
        table.insert(body, string.format("%s=%s",escape(k),escape(v)))
    end
    return httpc.request("POST", host, url, recvheader, header, table.concat(body , "&"))
end

return httpc
