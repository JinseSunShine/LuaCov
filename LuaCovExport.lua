--[[
    导出 Scripts 目录下所有脚本的函数名称
    格式：Export
    {
        [file_path:文件路径] = { 
            [line:行号] = func_name:函数名
        }
    }

]]


-------------------------------------------
-------- 测试导出所有函数名 -----------------

local LuaCovExport = {}

local szSwordGameDir = os.getenv("SWORDGAME_HOME")
local szSourceDir = szSwordGameDir..'\\Source'
local szSelfDir = szSourceDir..'\\CMakeModules\\bin\\LuaTools\\bin\\CheckDataTableReferenced\\' 
local szLogPath = szSelfDir..'CheckDataTableReferencedLog.txt'
local szScriptsDir = szSwordGameDir.."\\Scripts"
local szExportPath = szScriptsDir.."\\Common\\Profiler\\luacov"

local CommonFunctions = require "CommonFunctions"
local lexer = require('pl.lexer') 
local utils = require("pl.utils")

-- 遍历收集所有的lua文件，返回路径数组
local function CollectScripts(szRootDir)
    local ScriptPaths = {}
    CommonFunctions:GatherDir(szRootDir, ScriptPaths, '.lua') -- szScriptsDir

    return ScriptPaths
end

local function retrieval(file_path, out_functions)
    
    local src = utils.readfile(file_path)
    if not src then
        return
    end

    local IdentCache = {}
    local function pushIdentString(szIdent)
        table.insert(IdentCache, szIdent)
        -- 只用缓存四个即可
        if #IdentCache > 5 then
            table.remove( IdentCache, 1 )
        end
    end

    local function clearIdentString()
        IdentCache = {}
    end

    local function getItem(nPos)
        if nPos >= 0 then
            return IdentCache[nPos]
        else
            -- -1 最后一个
            nPos = #IdentCache + nPos + 1
            return IdentCache[nPos]
        end
    end

    
    local szFuncName, line
    local bFuncFlag = false
    local INVALID = -1
    local nDecrease = INVALID

    local function cleanflag()
        nDecrease = INVALID
        bFuncFlag = false
    end

    local function record(szFuncName, line)
        out_functions[line] = szFuncName
    end

    local filter = {space=true,comments=true}
    local options = {number=true,string=true}

    local tok = lexer.lua(src,filter, options)
    for t,v in (tok) do
        pushIdentString(v)

        if t == 'keyword' and v == 'function' then
            bFuncFlag = true
            nDecrease = 3
        end

        if bFuncFlag then 
            if t == '(' and nDecrease == 2 then
                if getItem(-3) == 'return' then
                    szFuncName = 'unname' -- 匿名函数
                else
                    szFuncName = getItem(-4)
                    if szFuncName == ']' then
                        szFuncName = getItem(-5)
                    end
                end
                
                line = lexer.lineno(tok)
                
                record(szFuncName, line)
                cleanflag()
            end

            if t == '(' and nDecrease == 1 then
                szFuncName = getItem(-2)
                line = lexer.lineno(tok)

                record(szFuncName, line)
                cleanflag()
            end
            
            if nDecrease == 0 then
                szFuncName = v
                line = lexer.lineno(tok)

                record(szFuncName, line)
                cleanflag()
            end

            nDecrease = nDecrease - 1
            if nDecrease < 0 then
                cleanflag()
            end
        end
    end
end

local function format_path(path_file)

    local index = string.find( path_file,'Scripts' )
    if index then
        local new_path = string.sub( path_file, index+7, -1 )
        return new_path
    else
        return path_file
    end
end

function table2string(t, name, indent)
    local cart     -- a container
    local autoref  -- for self references

    -- (RiciLake) returns true if the table is empty
    local function isemptytable(t) return next(t) == nil end

    local function basicSerialize (o)
        local so = tostring(o)
        if type(o) == "function" then
            local info = debug.getinfo(o, "S")
            -- info.name is nil because o is not a calling level
            if info.what == "C" then
                return string.format("%q", so .. ", C function")
            else
                -- the information is defined through lines
                return string.format("%q", so .. ", defined in (" ..
                info.linedefined .. "-" .. info.lastlinedefined ..
                ")" .. info.source)
            end
        elseif type(o) == "number" or type(o) == "boolean" then
            return so
        else
            return string.format("%q", so)
        end
    end

    local function addtocart (value, name, indent, saved, field)
        indent = indent or ""
        saved = saved or {}
        field = field or name

        cart = cart .. indent .. field

        if type(value) ~= "table" and type(value) ~= "userdata" then
            cart = cart .. " = " .. basicSerialize(value) .. ";\n"
        else
            if saved[value] then
                cart = cart .. " = {}; -- " .. saved[value]
                        .. " (self reference)\n"
                autoref = autoref ..  name .. " = " .. saved[value] .. ";\n"
            else
                saved[value] = name
                --if tablecount(value) == 0 then
                if isemptytable(value) then
                    cart = cart .. " = {};\n"
                else
                    cart = cart .. " = {\n"
                    for k, v in pairs(value) do
                        k = basicSerialize(k)
                        local fname = string.format("%s[%s]", name, k)
                        field = string.format("[%s]", k)
                        -- three spaces between levels
                        addtocart(v, fname, indent .. "   ", saved, field)
                    end
                    cart = cart .. indent .. "};\n"
                end
            end
        end
    end

    name = name or ""
    if type(t) ~= "table" then
        return name .. " = " .. basicSerialize(t)
    end
    cart, autoref = "", ""
    
    local prefix = 'local '..name
    addtocart(t, prefix, indent)
    
    return cart .. autoref .. '\n return ' .. name
end

local function run()
    local ScriptPaths = CollectScripts(szScriptsDir)
    if #ScriptPaths <= 0 then
        return
    end

    local tbReport = {}

    local file_num = #ScriptPaths
    print('-------- Lua Cov Retrival ----------')
    for i, file in pairs(ScriptPaths) do
        local tbfunctions = {}
        retrieval(file, tbfunctions)

        local file_path = format_path(file)

        tbReport[file_path] = tbfunctions
    end
    print('-------- Lua Cov Export ----------')
    local szExportString = table2string(tbReport, 'LuaCovExport')

    local szExportPath = szExportPath..'\\LuaCovRecordFunc.lua'

    utils.writefile(szExportPath ,szExportString)
end

function LuaCovExport.Export()
    return run()
end

return LuaCovExport