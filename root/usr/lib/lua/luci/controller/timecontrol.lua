-- LuCI Time Control Controller
-- Copyright (C) 2025 OpenWrt Community

module("luci.controller.timecontrol", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/timecontrol") then
        return
    end
    
    local page
    
    page = entry({"admin", "network", "timecontrol"}, template("timecontrol/main"), _("Time Control"), 60)
    page.dependent = true
    page.acl_depends = { "luci-app-timecontrol" }
    
    page = entry({"admin", "network", "timecontrol", "add"}, call("action_add"), nil)
    page.leaf = true
    
    page = entry({"admin", "network", "timecontrol", "delete"}, call("action_delete"), nil)
    page.leaf = true
end

function action_add()
    local http = require "luci.http"
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    
    local device_name = http.formvalue("device_name")
    local device_mac = http.formvalue("device_mac")
    local rule_type = http.formvalue("rule_type")
    local weekdays = http.formvalue("weekdays")
    local start_time = http.formvalue("start_time")
    local stop_time = http.formvalue("stop_time")
    
    if not device_name or not device_mac or not weekdays or not start_time or not stop_time then
        http.status(400, "Bad Request")
        http.write("Missing required parameters")
        return
    end
    
    -- 生成设备ID
    local device_id = "device_" .. string.gsub(string.lower(device_mac), ":", "")
    
    -- 检查设备是否已存在
    local device_exists = false
    uci:foreach("timecontrol", "device", function(section)
        if section[".name"] == device_id then
            device_exists = true
            return false
        end
    end)
    
    -- 如果设备不存在则创建
    if not device_exists then
        uci:section("timecontrol", "device", device_id, {
            name = device_name,
            mac = device_mac,
            enable = "1"
        })
    end
    
    -- 创建时间规则
    local rule_id = "rule_" .. device_id .. "_" .. os.time()
    uci:section("timecontrol", "timeslot", rule_id, {
        device = device_id,
        weekdays = weekdays,
        start_time = start_time,
        stop_time = stop_time,
        rule_type = rule_type
    })
    
    uci:commit("timecontrol")
    
    -- 重启timecontrol服务
    sys.call("/etc/init.d/timecontrol reload")
    
    http.status(200, "OK")
    http.write("Success")
end

function action_delete()
    local http = require "luci.http"
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    
    local rule_id = http.formvalue("rule_id")
    
    if not rule_id then
        http.status(400, "Bad Request")
        http.write("Missing rule_id parameter")
        return
    end
    
    -- 删除规则
    uci:delete("timecontrol", rule_id)
    uci:commit("timecontrol")
    
    -- 重启timecontrol服务
    sys.call("/etc/init.d/timecontrol reload")
    
    http.status(200, "OK")
    http.write("Success")
end