-- config ui for confirm

confirm = require 'plugins.confirm'
gui = require 'gui'
widgets = require 'gui.widgets'

Opts = defclass(Opts, widgets.Window)
Opts.ATTRS = {
    frame_title = 'Confirmation dialogs',
    frame={w=36, h=17},
}

function Opts:init()
    self:addviews{
        widgets.List{
            view_id = 'list',
            frame = {t = 0, l = 0},
            text_pen = COLOR_GREY,
            cursor_pen = COLOR_WHITE,
            choices = {},
            on_submit = function(idx) self:toggle(idx) self:refresh() end,
        },
        widgets.HotkeyLabel{
            frame = {b=2, l=0},
            label='Toggle all',
            key='CUSTOM_ALT_E',
            on_activate=function() self:toggle_all(self.subviews.list:getSelected()) self:refresh() end,
        },
        widgets.HotkeyLabel{
            frame = {b=1, l=0},
            label='Resume paused confirmations',
            key='CUSTOM_P',
            on_activate=function() self:unpause_all() self:refresh() end,
            enabled=function() return self.any_paused end
        },
        widgets.HotkeyLabel{
            frame = {b=0, l=0},
            label='Toggle',
            key='SELECT',
            on_activate=function() self:toggle(self.subviews.list:getSelected()) self:refresh() end,
        },
    }
    self:refresh()

    local active_id = confirm.get_active_id()
    for i, choice in ipairs(self.subviews.list:getChoices()) do
        if choice.id == active_id then
            self.subviews.list:setSelected(i)
            break
        end
    end
end

function Opts:refresh()
    self.data = confirm.get_conf_data()
    self.any_paused = false
    local choices = {}
    for i, c in ipairs(self.data) do
        if c.paused then
            self.any_paused = true
        end

        local text = (c.enabled and 'Enabled' or 'Disabled')
        if c.paused then
            text = '[' .. text .. ']'
        end

        table.insert(choices, {
            id = c.id,
            enabled = c.enabled,
            paused = c.paused,
            text = {
                c.id .. ': ',
                {
                    text = text,
                    pen = self:callback('choice_pen', i, c.enabled)
                }
            }
        })
    end
    self.subviews.list:setChoices(choices)
end

function Opts:choice_pen(index, enabled)
    return (enabled and COLOR_GREEN or COLOR_RED) + (index == self.subviews.list:getSelected() and 8 or 0)
end

function Opts:toggle(idx)
    local choice = self.data[idx]
    confirm.set_conf_state(choice.id, not choice.enabled)
    self:refresh()
end

function Opts:toggle_all(choice)
    for _, c in pairs(self.data) do
        confirm.set_conf_state(c.id, not self.data[choice].enabled)
    end
    self:refresh()
end

function Opts:unpause_all()
    for _, c in pairs(self.data) do
         confirm.set_conf_paused(c.id, false)
    end
    self:refresh()
end

OptsScreen = defclass(OptsScreen, gui.ZScreen)
OptsScreen.ATTRS {
    focus_path='confirm/options',
}

function OptsScreen:init()
    self:addviews{Opts{}}
end

function OptsScreen:onDismiss()
    view = nil
end

view = view and view:raise() or OptsScreen{}:show()
