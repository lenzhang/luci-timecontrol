-- LuCI Time Control Controller
-- Copyright (C) 2025 OpenWrt Community

module("luci.controller.timecontrol", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/timecontrol") then
        return
    end
    
    local page
    
    page = entry({"admin", "services", "timecontrol"}, call("main_page"), _("Time Control"), 60)
    page.dependent = true
    page.acl_depends = { "luci-app-timecontrol" }
end

function main_page()
    local http = require "luci.http"
    
    -- 处理POST请求
    if http.getenv("REQUEST_METHOD") == "POST" then
        local action = http.formvalue("action")
        
        if action == "add" then
            action_add()
            return
        elseif action == "delete" then
            action_delete()
            return
        end
    end
    
    -- 显示页面
    luci.template.render("timecontrol/main")
end

function action_add()
    local http = require "luci.http"
    local uci = require "luci.model.uci".cursor()
    
    local device = http.formvalue("device")
    local weekdays = http.formvalue("weekdays")
    local start_time = http.formvalue("start_time")
    local stop_time = http.formvalue("stop_time")
    
    if device and weekdays and start_time and stop_time then
        -- 解析设备信息
        local device_name, device_mac = device:match("^(.+)%s+%((.+)%)$")
        if device_mac then
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
                rule_type = "allow"
            })
            
            uci:commit("timecontrol")
            
            -- 重启timecontrol服务
            os.execute("/etc/init.d/timecontrol reload")
        end
    end
    
    http.prepare_content("text/plain")
    http.write("OK")
end

function action_delete()
    local http = require "luci.http"
    local uci = require "luci.model.uci".cursor()
    
    local rule_id = http.formvalue("rule_id")
    
    if rule_id then
        -- 获取设备ID
        local device_id = nil
        uci:foreach("timecontrol", "timeslot", function(s)
            if s[".name"] == rule_id then
                device_id = s.device
                return false
            end
        end)
        
        -- 删除规则
        uci:delete("timecontrol", rule_id)
        
        -- 如果设备没有其他规则则删除设备
        if device_id then
            local has_other_rules = false
            uci:foreach("timecontrol", "timeslot", function(s)
                if s.device == device_id then
                    has_other_rules = true
                    return false
                end
            end)
            
            if not has_other_rules then
                uci:delete("timecontrol", device_id)
            end
        end
        
        uci:commit("timecontrol")
        
        -- 重启服务
        os.execute("/etc/init.d/timecontrol reload")
    end
    
    http.prepare_content("text/plain")
    http.write("OK")
end