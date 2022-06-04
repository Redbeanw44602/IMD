--[[ ----------------------------------------

    [Deps] Universal Json.

--]] ----------------------------------------

local Log = require("logger"):new('JSON')
local ori_json = require "dkjson"
JSON = {
    encode = function (obj)
        local stat,rtn = pcall(ori_json.encode,obj)
        if stat then
            return rtn
        else
            Log:Error('生成JSON时出错！')
            Log:Error(rtn)
        end
    end,
    decode = function (text)
        local stat,rtn = pcall(ori_json.decode,text)
        if stat then
            return rtn
        else
            Log:Error('解析JSON时出错！')
            Log:Error(rtn)
        end
    end
}

return JSON