local files   = require 'files'
local define  = require 'proto.define'
local log     = require 'log'
local lspconfig = require 'config'
local luacheck = require "luacheck.check"
local lcformat = require "luacheck.format"
local lcfilter = require "luacheck.filter"
local lcconfig = require "luacheck.config"
local workspace = require "workspace"
local util     = require 'utility'
local fs       = require "luacheck.fs"
local inspect    = require 'inspect'


local config_stack = nil

-- a bit hacky but this will monkey patch the isLua function so that
-- we can know when the .luacheckrc file has been changed
-- a call to isLua is done in workspace.lua fw.event() on change
-- we could also add .luacheck as a recognised file association using
-- a config file (see config.template and the files.associations value)
-- but this works equally well for our purposes
local isLua = files.isLua
files.isLua = function(uri)
    if util.stringEndWith(uri:lower(), '.luacheckrc') then
        config_stack = nil
        return false
    end
    return isLua(uri)
end

local defold_config = {
    options = {
        stds = {},
        files = {},
        globals = {
            -- defold
            "buffer",
            "collectionproxy",
            "collectionfactory",
            "crash",
            "factory",
            "go",
            "gui",
            "html5",
            "http",
            "image",
            "json",
            "label",
            "model",
            "msg",
            "particlefx",
            "physics",
            "profiler",
            "render",
            "resource",
            "socket",
            "sprite",
            "sound",
            "sys",
            "timer",
            "tilemap",
            "url",
            "vmath",
            "window",
            "zlib",

            -- defold builtin functions
            "pprint",
            "hash",
            "hash_to_hex",

            -- script lifecycle functions
            "init",
            "final",
            "update",
            "fixed_update",
            "on_input",
            "on_message",
            "on_reload",
        }
    }
}

return function (uri, callback)

    if not config_stack then
        log.info("loading .luacheckrc")
        local rootUri = (workspace.rootUri or ""):gsub("file://", "")
        local path = fs.join(rootUri, ".luacheckrc")
        local global_path = nil
        local config = lcconfig.load_config(path, global_path)

        -- get editor provided globals
        local editor_config = {
            options = {
                stds = {},
                files = {},
                globals = lspconfig.get(workspace.rootUri, 'Lua.diagnostics.globals') or {},
            }
        }

        -- create final config stack combining LuaCheck config, Defold globals and editor globals
        config_stack = lcconfig.stack_configs({ config, defold_config, editor_config })
    end

    local text = files.getText(uri)
    local report = luacheck(text)
    local reports = { report }
    local opts = { config_stack:get_options(uri) }
    local stds = config_stack:get_stds()
    lcfilter.filter(reports, opts, stds)

    for i,warning in ipairs(report.filtered_warnings) do
        local message = lcformat.get_message(warning)
        local start = ((warning.line - 1) * 10000) + warning.column - 1
        local finish = ((warning.line - 1) * 10000) + warning.end_column
        callback({
            start   = start,
            finish  = finish,
            tags    = { define.DiagnosticTag.Unnecessary },
            message = message,
        })
    end
end
