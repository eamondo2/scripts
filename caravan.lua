-- Adjusts properties of caravans and provides overlay for enhanced trading
--@ module = true

local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

trader_selected_state = trader_selected_state or {}
broker_selected_state = broker_selected_state or {}
handle_ctrl_click_on_render = handle_ctrl_click_on_render or false
handle_shift_click_on_render = handle_shift_click_on_render or false

dfhack.onStateChange.caravanTradeOverlay = function(code)
    if code == SC_WORLD_UNLOADED then
        trader_selected_state = {}
        broker_selected_state = {}
        handle_ctrl_click_on_render = false
        handle_shift_click_on_render = false
    end
end

local GOODFLAG = {
    UNCONTAINED_UNSELECTED = 0,
    UNCONTAINED_SELECTED = 1,
    CONTAINED_UNSELECTED = 2,
    CONTAINED_SELECTED = 3,
    CONTAINER_COLLAPSED_UNSELECTED = 4,
    CONTAINER_COLLAPSED_SELECTED = 5,
}

function select_shift_clicked_container_items(new_state, old_state, list_index)
    -- if ctrl is also held, collapse the container too
    local also_collapse = dfhack.internal.getModifiers().ctrl
    local collapsed_item_count = 0
    for k, goodflag in ipairs(new_state) do
        if old_state[k] ~= goodflag then
            local next_item_flag = new_state[k + 1]
            local this_item_is_container = df.item_binst:is_instance(df.global.game.main_interface.trade.good[list_index][k])
            if this_item_is_container then
                local container_is_selected = goodflag == GOODFLAG.UNCONTAINED_SELECTED or goodflag == GOODFLAG.CONTAINER_COLLAPSED_SELECTED
                if container_is_selected then
                    local collapsed_this_container = false

                    if goodflag == GOODFLAG.UNCONTAINED_SELECTED and also_collapse then
                        collapsed_this_container = true
                    end

                    new_state[k] = also_collapse and GOODFLAG.CONTAINER_COLLAPSED_UNSELECTED or GOODFLAG.UNCONTAINED_UNSELECTED
                    local end_of_container_reached = false
                    local contained_item_index = k + 1

                    if contained_item_index > #new_state - 1 then
                        end_of_container_reached = true
                    end

                    while not end_of_container_reached do
                        new_state[contained_item_index] = GOODFLAG.CONTAINED_SELECTED

                        if collapsed_this_container then
                            collapsed_item_count = collapsed_item_count + 1
                        end

                        local next_item_index = contained_item_index + 1

                        if next_item_index > #new_state or new_state[next_item_index] < 2 or new_state[next_item_index] >= 4 then
                            end_of_container_reached = true
                        end
                        contained_item_index = contained_item_index + 1
                    end
                end
            end
        end
    end

    if collapsed_item_count > 0 then
        df.global.game.main_interface.trade.i_height[list_index] = df.global.game.main_interface.trade.i_height[list_index] - collapsed_item_count * 3
    end
end

function collapse_ctrl_clicked_containers(new_state, old_state, list_index)
    for k, goodflag in ipairs(new_state) do
        if old_state[k] ~= goodflag then
            local next_item_flag = new_state[k + 1]
            if next_item_flag == GOODFLAG.CONTAINED_UNSELECTED or next_item_flag == GOODFLAG.CONTAINED_SELECTED then
                local target_goodflag
                if goodflag == GOODFLAG.UNCONTAINED_SELECTED then
                    target_goodflag = GOODFLAG.CONTAINER_COLLAPSED_UNSELECTED
                elseif goodflag == GOODFLAG.UNCONTAINED_UNSELECTED then
                    target_goodflag = GOODFLAG.CONTAINER_COLLAPSED_SELECTED
                end

                if target_goodflag ~= nil then
                    new_state[k] = target_goodflag
                    -- changed a container state, items inside will be reset, return contained items to state before collapse
                    local end_of_container_reached = false
                    local contained_item_index = k + 1

                    if contained_item_index > #new_state - 1 then
                        end_of_container_reached = true
                    end

                    local num_items_collapsed = 0

                    while not end_of_container_reached do
                        num_items_collapsed = num_items_collapsed + 1
                        new_state[contained_item_index] = old_state[contained_item_index]

                        local next_item_index = contained_item_index + 1

                        if next_item_index > #new_state or new_state[next_item_index] < 2 or new_state[next_item_index] >= 4 then
                            end_of_container_reached = true
                        end
                        contained_item_index = contained_item_index + 1
                    end

                    if num_items_collapsed > 0 then
                        df.global.game.main_interface.trade.i_height[list_index] = df.global.game.main_interface.trade.i_height[list_index] - num_items_collapsed * 3
                    end
                end
            end
        end
    end
end


function collapseTypes(types_list, list_index)
    local type_on_count = 0

    for k, type_open in ipairs(types_list) do
        local type_on = df.global.game.main_interface.trade.current_type_a_on[list_index][k]
        if type_on then
            type_on_count = type_on_count + 1
        end
        types_list[k] = false
    end

    df.global.game.main_interface.trade.i_height[list_index] = type_on_count * 3
end

function collapseAllTypes()
   collapseTypes(df.global.game.main_interface.trade.current_type_a_expanded[0], 0)
   collapseTypes(df.global.game.main_interface.trade.current_type_a_expanded[1], 1)
   -- reset scroll to top when collapsing types
   df.global.game.main_interface.trade.scroll_position_item[0] = 0
   df.global.game.main_interface.trade.scroll_position_item[1] = 0
end

function collapseContainers(item_list, list_index)
    local num_items_collapsed = 0
    for k, goodflag in ipairs(item_list) do
        if goodflag ~= GOODFLAG.CONTAINED_UNSELECTED and goodflag ~= GOODFLAG.CONTAINED_SELECTED then
            local next_item_index = k + 1
            if next_item_index > #item_list - 1 then
                goto skip
            end

            local next_item = item_list[next_item_index]
            local this_item_is_container = df.item_binst:is_instance(df.global.game.main_interface.trade.good[list_index][k])
            local collapsed_this_container = false
            if this_item_is_container then
                if goodflag == GOODFLAG.UNCONTAINED_SELECTED then
                    item_list[k] = GOODFLAG.CONTAINER_COLLAPSED_SELECTED
                    collapsed_this_container = true
                elseif goodflag == GOODFLAG.UNCONTAINED_UNSELECTED then
                    item_list[k] = GOODFLAG.CONTAINER_COLLAPSED_UNSELECTED
                    collapsed_this_container = true
                end

                if collapsed_this_container then
                    num_items_collapsed = num_items_collapsed + #dfhack.items.getContainedItems(df.global.game.main_interface.trade.good[list_index][k])
                end
            end

            ::skip::
        end
    end

    if num_items_collapsed > 0 then
        df.global.game.main_interface.trade.i_height[list_index] = df.global.game.main_interface.trade.i_height[list_index] - num_items_collapsed * 3
    end
end

function collapseAllContainers()
    collapseContainers(df.global.game.main_interface.trade.goodflag[0], 0)
    collapseContainers(df.global.game.main_interface.trade.goodflag[1], 1)
end

function collapseEverything()
    collapseAllContainers()
    collapseAllTypes()
end

function copyGoodflagState()
    trader_selected_state = copyall(df.global.game.main_interface.trade.goodflag[0])
    broker_selected_state = copyall(df.global.game.main_interface.trade.goodflag[1])
end

CaravanTradeOverlay = defclass(CaravanTradeOverlay, overlay.OverlayWidget)
CaravanTradeOverlay.ATTRS{
    default_pos={x=-3,y=-12},
    default_enabled=true,
    viewscreens='dwarfmode/Trade',
    frame={w=27, h=13},
    frame_style=gui.MEDIUM_FRAME,
    frame_background=gui.CLEAR_PEN,
}

function CaravanTradeOverlay:init()
    self:addviews{
        widgets.Label{
            frame={t=0, l=0},
            text={
                {text='Shift+Click checkbox:', pen=COLOR_LIGHTGREEN},
                NEWLINE,
                {text='select items inside bin', pen=COLOR_WHITE},
            },
            text_pen=COLOR_LIGHTGREEN,
        },
        widgets.Label{
            frame={t=3, l=0},
            text={
                {text='Ctrl+Click checkbox:', pen=COLOR_LIGHTGREEN},
                NEWLINE,
                {text='collapse single bin', pen=COLOR_WHITE},
            },
            text_pen=COLOR_LIGHTGREEN,
        },
        widgets.HotkeyLabel{
            frame={t=6, l=0},
            label='collapse bins',
            key='CUSTOM_CTRL_C',
            on_activate=collapseAllContainers,
        },
        widgets.HotkeyLabel{
            frame={t=7, l=0},
            label='collapse all',
            key='CUSTOM_CTRL_X',
            on_activate=collapseEverything,
        },
        widgets.Label{
            frame={t=9, l=0},
            text = 'Shift+Scroll:',
            text_pen=COLOR_LIGHTGREEN,
        },
        widgets.Label{
            frame={t=9, l=14},
            text = 'fast scroll',
        },
    }
end

function CaravanTradeOverlay:render(dc)
    CaravanTradeOverlay.super.render(self, dc)
    if handle_shift_click_on_render then
        handle_shift_click_on_render = false
        select_shift_clicked_container_items(df.global.game.main_interface.trade.goodflag[0], trader_selected_state, 0)
        select_shift_clicked_container_items(df.global.game.main_interface.trade.goodflag[1], broker_selected_state, 1)
    elseif handle_ctrl_click_on_render then
        handle_ctrl_click_on_render = false
        collapse_ctrl_clicked_containers(df.global.game.main_interface.trade.goodflag[0], trader_selected_state, 0)
        collapse_ctrl_clicked_containers(df.global.game.main_interface.trade.goodflag[1], broker_selected_state, 1)
    end
end

function CaravanTradeOverlay:onInput(keys)
    if keys._MOUSE_L_DOWN then
        if dfhack.internal.getModifiers().shift then
            handle_shift_click_on_render = true
        elseif dfhack.internal.getModifiers().ctrl then
            handle_ctrl_click_on_render = true
        end

        if handle_ctrl_click_on_render or handle_shift_click_on_render then
            copyGoodflagState()
        end
    end
    CaravanTradeOverlay.super.onInput(self, keys)
    return false
end

OVERLAY_WIDGETS = {
    tradeScreenExtension=CaravanTradeOverlay,
}

INTERESTING_FLAGS = {
    casualty = 'Casualty',
    hardship = 'Encountered hardship',
    seized = 'Goods seized',
    offended = 'Offended'
}
local caravans = df.global.plotinfo.caravans

local function caravans_from_ids(ids)
    if not ids or #ids == 0 then
        return caravans
    end

    local c = {} --as:df.caravan_state[]
    for _,id in ipairs(ids) do
        local id = tonumber(id)
        if id then
            c[id] = caravans[id]
        end
    end
    return c
end

function bring_back(car)
    if car.trade_state ~= df.caravan_state.T_trade_state.AtDepot then
        car.trade_state = df.caravan_state.T_trade_state.Approaching
    end
end

local commands = {}

function commands.list()
    for id, car in pairs(caravans) do
        print(dfhack.df2console(('%d: %s caravan from %s'):format(
            id,
            df.creature_raw.find(df.historical_entity.find(car.entity).race).name[2], -- adjective
            dfhack.TranslateName(df.historical_entity.find(car.entity).name)
        )))
        print('  ' .. (df.caravan_state.T_trade_state[car.trade_state] or 'Unknown state: ' .. car.trade_state))
        print(('  %d day(s) remaining'):format(math.floor(car.time_remaining / 120)))
        for flag, msg in pairs(INTERESTING_FLAGS) do
            if car.flags[flag] then
                print('  ' .. msg)
            end
        end
    end
end

function commands.extend(days, ...)
    days = tonumber(days or 7) or qerror('invalid number of days: ' .. days) --luacheck: retype
    for id, car in pairs(caravans_from_ids{...}) do
        car.time_remaining = car.time_remaining + (days * 120)
        bring_back(car)
    end
end

function commands.happy(...)
    for id, car in pairs(caravans_from_ids{...}) do
        -- all flags default to false
        car.flags.whole = 0
        bring_back(car)
    end
end

function commands.leave(...)
    for id, car in pairs(caravans_from_ids{...}) do
        car.trade_state = df.caravan_state.T_trade_state.Leaving
    end
end

local function isDisconnectedPackAnimal(unit)
    if unit.following then
        local dragger = unit.following
        return (
            unit.relationship_ids[ df.unit_relationship_type.Dragger ] == -1 and
            dragger.relationship_ids[ df.unit_relationship_type.Draggee ] == -1
        )
    end
end

local function getPrintableUnitName(unit)
    local visible_name = dfhack.units.getVisibleName(unit)
    local profession_name = dfhack.units.getProfessionName(unit)
    if visible_name.has_name then
        return ('%s (%s)'):format(dfhack.TranslateName(visible_name), profession_name)
    end
    return profession_name  -- for unnamed animals
end

local function rejoin_pack_animals()
    print('Reconnecting disconnected pack animals...')
    local found = false
    for _, unit in pairs(df.global.world.units.active) do
        if unit.flags1.merchant and isDisconnectedPackAnimal(unit) then
            local dragger = unit.following
            print(('  %s  <->  %s'):format(
                dfhack.df2console(getPrintableUnitName(unit)),
                dfhack.df2console(getPrintableUnitName(dragger))
            ))
            unit.relationship_ids[ df.unit_relationship_type.Dragger ] = dragger.id
            dragger.relationship_ids[ df.unit_relationship_type.Draggee ] = unit.id
            found = true
        end
    end
    if (found) then
        print('All pack animals reconnected.')
    else
        print('No disconnected pack animals found.')
    end
end

function commands.unload(...)
    rejoin_pack_animals()
end

function commands.help()
    print(dfhack.script_help())
end

function main(...)
    local args = {...}
    local command = table.remove(args, 1)
    if commands[command] then
        commands[command](table.unpack(args))
    else
        commands.help()
        if command then
            qerror("No such subcommand: " .. command)
        else
            qerror("Missing subcommand")
        end
    end
end

if not dfhack_flags.module then
    main(...)
end
