-- thx uwukson

local clases = {}
function class(name)
    return function(tab)
        if not tab then
            return clases[name]
        end
        tab.__index, tab.__classname = tab, name
        if tab.call then
            tab.__call = tab.call
        end
        setmetatable(tab, tab)
        clases[name], _G[name] = tab, tab
        return tab
    end
end
local g_ctx = {
    local_player = nil,
    weapon = nil,
    aimbot = ui.reference("RAGE", "Aimbot", "Enabled"),
    doubletap = {ui.reference("RAGE", "Aimbot", "Double tap")},
    hideshots = {ui.reference("AA", "Other", "On shot anti-aim")},
    fakeduck = ui.reference("RAGE", "Other", "Duck peek assist")
}
local clamp = function(value, min, max)
    return math.min(math.max(value, min), max)
end
class "exploits" {
    max_process_ticks = math.abs(client.get_cvar("sv_maxusrcmdprocessticks")) - 1, -- we lost 1 tick due to createmove processing
    tickbase_difference = 0,
    ticks_processed = 0,
    command_number = 0,
    choked_commands = 0,
    need_force_defensive = false,
    current_shift_amount = 0,
    reset_vars = function(self)
        self.ticks_processed = 0
        self.tickbase_difference = 0
        self.choked_commands = 0
        self.command_number = 0
    end,
    store_vars = function(self, ctx)
        self.command_number = ctx.command_number
        self.choked_commands = ctx.chokedcommands
    end,
    store_tickbase_difference = function(self, ctx)
        if ctx.command_number == self.command_number then
            self.ticks_processed =
                clamp(
                math.abs(entity.get_prop(g_ctx.local_player, "m_nTickBase") - self.tickbase_difference),
                0,
                self.max_process_ticks - self.choked_commands
            )
            self.tickbase_difference =
                math.max(entity.get_prop(g_ctx.local_player, "m_nTickBase"), self.tickbase_difference or 0)
            self.command_number = 0
        end
    end,
    is_doubletap = function(self)
        return ui.get(g_ctx.doubletap[2])
    end,
    is_hideshots = function(self)
        return ui.get(g_ctx.hideshots[2])
    end,
    is_active = function(self)
        return self:is_doubletap() or self:is_hideshots()
    end,
    in_defensive = function(self)
        return self:is_active() and (self.ticks_processed > 1 and self.ticks_processed < self.max_process_ticks)
    end,
    is_defensive_ended = function(self)
        return not self:in_defensive() or
            (self.ticks_processed >= 0 and self.ticks_processed <= 5) and self.tickbase_difference > 0
    end,
    is_lagcomp_broken = function(self)
        return not self:is_defensive_ended() or
            self.tickbase_difference < entity.get_prop(g_ctx.local_player, "m_nTickBase")
    end,
    can_recharge = function(self)
        if not self:is_active() then
            return false
        end
        local curtime = globals.tickinterval() * (entity.get_prop(g_ctx.local_player, "m_nTickBase") - 16)
        if curtime < entity.get_prop(g_ctx.local_player, "m_flNextAttack") then
            return false
        end
        if curtime < entity.get_prop(g_ctx.weapon, "m_flNextPrimaryAttack") then
            return false
        end
        return true
    end,
    in_recharge = function(self)
        if not (self:is_active() and self:can_recharge()) or self:in_defensive() then
            return false
        end
        local latency_shift = math.ceil(toticks(client.latency()) * 1.25)
        local current_shift_amount = ((self.tickbase_difference - globals.tickcount()) * -1) + latency_shift
        local max_shift_amount, min_shift_amount =
            (self.max_process_ticks - 1) - latency_shift,
            -(self.max_process_ticks - 1) + latency_shift
        if latency_shift ~= 0 then
            return current_shift_amount > min_shift_amount and current_shift_amount < max_shift_amount
        else
            return current_shift_amount > (min_shift_amount / 2) and current_shift_amount < (max_shift_amount / 2)
        end
    end,
    should_force_defensive = function(self, state)
        if not self:is_active() then
            return false
        end
        self.need_force_defensive = state and self:is_defensive_ended()
    end,
    allow_unsafe_charge = function(self, state)
        if not (self:is_active() and self:can_recharge()) then
            ui.set(g_ctx.aimbot, true)
            return
        end
        if not state then
            ui.set(g_ctx.aimbot, true)
            return
        end
        if ui.get(g_ctx.fakeduck) then
            ui.set(g_ctx.aimbot, true)
            return
        end
        ui.set(g_ctx.aimbot, not self:in_recharge())
    end,
    force_reload_exploits = function(self, state)
        if not state then
            ui.set(g_ctx.doubletap[1], true)
            ui.set(g_ctx.hideshots[1], true)
            return
        end
        if self:is_doubletap() and not self:in_recharge() then
            ui.set(g_ctx.doubletap[1], false)
        else
            ui.set(g_ctx.doubletap[1], true)
        end
        if self:is_hideshots() and not self:in_recharge() then
            ui.set(g_ctx.hideshots[1], false)
        else
            ui.set(g_ctx.hideshots[1], true)
        end
    end
}
local event_list = {
    on_setup_command = function(ctx)
        if
            not (entity.get_local_player() and entity.is_alive(entity.get_local_player()) and
                entity.get_player_weapon(entity.get_local_player()))
         then
            return
        end
        g_ctx.local_player = entity.get_local_player()
        g_ctx.weapon = entity.get_player_weapon(g_ctx.local_player)
        if exploits.need_force_defensive then
            ctx.force_defensive = true
        end
    end,
    on_run_command = function(ctx)
        exploits:store_vars(ctx)
    end,
    on_predict_command = function(ctx)
        exploits:store_tickbase_difference(ctx)
    end,
    on_player_death = function(ctx)
        if not (ctx.userid and ctx.attacker) then
            return
        end
        if g_ctx.local_player ~= client.userid_to_entindex(ctx.userid) then
            return
        end
        exploits:reset_vars()
    end,
    on_level_init = function()
        exploits:reset_vars()
    end,
    on_round_start = function()
        exploits:reset_vars()
    end,
    on_round_end = function()
        exploits:reset_vars()
    end,
    on_shutdown = function()
        collectgarbage("collect")
    end
}
for k, v in next, event_list do
    client.set_event_callback(
        k:sub(4),
        function(ctx)
            v(ctx)
        end
    )
end
return exploits
