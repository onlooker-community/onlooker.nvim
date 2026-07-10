local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local onlooker = require("onlooker")

local setup_set = MiniTest.new_set({
    hooks = {
        pre_case = function()
            onlooker.setup()
        end,
    },
})

setup_set["setup() uses default config"] = function()
    MiniTest.expect.equality(onlooker.config.claude_bin, "claude")
end

setup_set["setup() merges user options"] = function()
    onlooker.setup({ claude_bin = "~/Code/claude-cli/bin/claude" })
    MiniTest.expect.equality(onlooker.config.claude_bin, "~/Code/claude-cli/bin/claude")
end

T["setup"] = setup_set

return T