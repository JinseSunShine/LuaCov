------------------------
-- Hook module, creates debug hook used by LuaCov.
-- @class module
-- @name luacov.hook
local hook = {}

local debug_getinfo = debug.getinfo
----------------------------------------------------------------
--- Creates a new debug hook.
-- @param runner runner module.
-- @return debug hook function that uses runner fields and functions
-- and sets `runner.data`.
function hook.new(runner)
   -- 忽略文件列表
   local ignored_files = {}
   -- hook执行的次数count
   local steps_after_save = 0

   return function(_)
      -- Do not use string metamethods within the debug hook:
      -- they may be absent if it's called from a sandboxed environment
      -- or because of carelessly implemented monkey-patching.
      local level = 2   -- 栈层次1 luacov, 2测试的文件

      if not runner.initialized then
         return
      end

      -- 这部分是hook核心，调用原生getinfo性能较差，这里是性能消耗较大的部分
      -- Get name of processed file.
      local info = debug_getinfo( level,"S" )
      if info.linedefined <= 0 then
         return
      end
      
      local source = info.source
      -- local name = info.name
      local line = info.linedefined

      if source == "=[C]" or line <= 0 then
         return
      end

      runner.call_hookIN(source, line)



      --[[
      local name = debug.getinfo(level, "S").source
      local prefixed_name = string.match(name, "^@(.*)")
      if prefixed_name then
         name = prefixed_name
      elseif not runner.configuration.codefromstrings then
         -- Ignore Lua code loaded from raw strings by default.
         return
      end

      local data = runner.data
      local file = data[name]

      if not file then
         -- New or ignored file.
         if ignored_files[name] then
            return
         elseif runner.file_included(name) then
            file = {max = 0, max_hits = 0}
            data[name] = file
         else
            ignored_files[name] = true
            return
         end
      end

      if line_nr > file.max then
         file.max = line_nr
      end

      local hits = (file[line_nr] or 0) + 1
      file[line_nr] = hits

      if hits > file.max_hits then
         file.max_hits = hits
      end

      if runner.tick then
         steps_after_save = steps_after_save + 1

         if steps_after_save == runner.configuration.savestepsize then
            steps_after_save = 0

            if not runner.paused then
               runner.save_stats()
            end
         end
      end
      
      ]]

   end
end

return hook
