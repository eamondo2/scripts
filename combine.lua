-- Combines food and plant items across stockpiles.
local argparse = require('argparse')
local utils = require('utils')

local opts, args = {
    help = false,
    all = nil,
    here = nil,
    dry_run = false,
    types = nil,
    verbose = false
  }, {...}

  -- default max stack size of 30
local DEF_MAX=30

-- list of valid item types for merging
local valid_types_map = {
    ['all'] = { },
    ['drink'] = {[df.item_type.DRINK]={type_id=df.item_type.DRINK, type_name='DRINK',type_caste=false,max_stack_size=DEF_MAX}},
    ['fat'] =   {[df.item_type.GLOB]={type_id=df.item_type.GLOB, type_name='GLOB',type_caste=false,max_stack_size=DEF_MAX},
                [df.item_type.CHEESE]={type_id=df.item_type.CHEESE, type_name='CHEESE',type_caste=false,max_stack_size=DEF_MAX}},
    ['fish'] = {[df.item_type.FISH]={type_id=df.item_type.FISH, type_name='FISH',type_caste=true,max_stack_size=DEF_MAX},
                [df.item_type.FISH_RAW]={type_id=df.item_type.FISH_RAW, type_name='FISH_RAW',type_caste=true,max_stack_size=DEF_MAX},
                [df.item_type.EGG]={type_id=df.item_type.EGG, type_name='EGG',type_caste=true,max_stack_size=DEF_MAX}},
    ['food'] = {[df.item_type.FOOD]={type_id=df.item_type.FOOD, type_name='FOOD',type_caste=false,max_stack_size=DEF_MAX}},
    ['meat'] = {[df.item_type.MEAT]={type_id=df.item_type.MEAT, type_name='MEAT',type_caste=false,max_stack_size=DEF_MAX}},
    ['plant'] = {[df.item_type.PLANT]={type_id=df.item_type.PLANT, type_name='PLANT',type_caste=false,max_stack_size=DEF_MAX},
                [df.item_type.PLANT_GROWTH]={type_id=df.item_type.PLANT_GROWTH, type_name='PLANT_GROWTH',type_caste=false,max_stack_size=DEF_MAX}}
}

-- populate all types entry
for k1,v1 in pairs(valid_types_map) do
    if k1 ~= 'all' then
        for k2,v2 in pairs(v1) do
            valid_types_map['all'][k2]={}
            for k3,v3 in pairs (v2) do
                valid_types_map['all'][k2][k3]=v3
            end
        end
    end
end

function log(...)
    -- if verbose is specified, then print the arguments, or don't.
    if opts.verbose then dfhack.print(string.format(...)) end
end

-- CList class
-- generic list class used for key value pairs.
local CList = { }

function CList:new(o)
    -- key, value pair table structure. __len allows # to be used for table count.
    o = o or { }
    setmetatable(o, self)
    self.__index = self
    self.__len = function (t) local n = 0 for _, __ in pairs(t) do n = n + 1 end return n end
    return o
end

local function comp_item_new(comp_key, max_stack_size)
    -- create a new comp_item entry to be added to a comp_items table.
    local comp_item = {}
    if not comp_key then qerror('new_comp_item: comp_key is nil') end
    comp_item.comp_key = comp_key
    comp_item.item_qty = 0
    comp_item.max_stack_size = max_stack_size or 0
    comp_item.before_stacks = 0
    comp_item.after_stacks = 0
    comp_item.before_stack_size = CList:new(nil)    -- key:item.id, val:item.stack_size
    comp_item.after_stack_size = CList:new(nil)     -- key:item.id, val:item.stack_size
    comp_item.items = CList:new(nil)                -- key:item.id, val:item
    comp_item.sorted_items = CList:new(nil)         -- key:-1*item.id | item.id, val:item_id
    return comp_item
end

local function comp_item_add_item(comp_item, item)
    -- add an item into the comp_items table, setting the comp_item attributes.
    if not comp_item.items[item.id] then

        comp_item.items[item.id] = item
        comp_item.item_qty = comp_item.item_qty + item.stack_size
        if item.stack_size > comp_item.max_stack_size then
            comp_item.max_stack_size = item.stack_size
        end
        comp_item.before_stack_size[item.id] = item.stack_size
        comp_item.after_stack_size[item.id] = item.stack_size
        comp_item.before_stacks = comp_item.before_stacks + 1
        comp_item.after_stacks = comp_item.after_stacks + 1

        local contained_item = dfhack.items.getGeneralRef(item, df.general_ref_type.CONTAINED_IN_ITEM)

        -- used to merge contained items before loose items
        if contained_item then
            table.insert(comp_item.sorted_items, -1*item.id)
        else
            table.insert(comp_item.sorted_items, item.id)
        end
        return comp_item.items[item.id]
    else
        -- this case should not happen, unless an item is contained by more than one container.
        -- in which case, only allow one instance for the merge.
        return nil
    end
end

local function stack_type_new(type_vals)
    -- create a new stack type entry to be added to the stacks table.
    local stack_type = {}
    for k,v in pairs(type_vals) do
        stack_type[k] = v
    end
    stack_type.item_qty = 0
    stack_type.before_stacks = 0
    stack_type.after_stacks = 0
    stack_type.comp_items = CList:new(nil)          -- key:comp_key, val=comp_item
    return stack_type
end

local function stacks_type_add_item(stacks_type, item)
    -- add an item to the matching comp_items table; based on comp_key.
    local comp_key = ''

    if stacks_type.type_caste then
        comp_key = tostring(stacks_type.type_id) .. tostring(item.race) .. tostring(item.caste)
    else
        comp_key = tostring(stacks_type.type_id) .. tostring(item.mat_type) .. tostring(item.mat_index)
    end

    if not stacks_type.comp_items[comp_key] then
        stacks_type.comp_items[comp_key] = comp_item_new(comp_key, stacks_type.max_stack_size)
    end

    if comp_item_add_item(stacks_type.comp_items[comp_key], item) then
        stacks_type.before_stacks = stacks_type.before_stacks + 1
        stacks_type.after_stacks = stacks_type.after_stacks + 1
        stacks_type.item_qty = stacks_type.item_qty + item.stack_size
        if item.stack_size > stacks_type.max_stack_size then
            stacks_type.max_stack_size = item.stack_size
        end
    end
end

local function print_stacks_details(stacks)
    -- print stacks details
    log(('Details #types:%5d\n'):format(#stacks))
    for _, stacks_type in pairs(stacks) do
        log(('   type: <%12s> <%d>  comp item types#:%5d  #item_qty:%5d  stack sizes: max: %5d before:%5d after:%5d\n'):format(stacks_type.type_name, stacks_type.type_id,  stacks_type.item_qty, #stacks_type.comp_items, stacks_type.max_stack_size, stacks_type.before_stacks, stacks_type.after_stacks))
        for _, comp_item in pairs(stacks_type.comp_items) do
            log(('      compare key:%12s  #item qty:%5d  #comp item stacks:%5d  stack sizes: max: %5d before:%5d after:%5d\n'):format(comp_item.comp_key, comp_item.item_qty, #comp_item.items, comp_item.max_stack_size, comp_item.before_stacks, comp_item.after_stacks))
            for _, item in pairs(comp_item.items) do
                log(('         item:%40s <%6d> before:%5d after:%5d\n'):format(utils.getItemDescription(item), item.id, comp_item.before_stack_size[item.id], comp_item.after_stack_size[item.id]))
            end
        end
    end
end

local function print_stacks_summary(stacks)
    -- print stacks summary to the console
    dfhack.print('Summary:\n')
    for _, stacks_type in pairs(stacks) do
        dfhack.print(('   type: <%12s> <%d>   #item_qty:%5d  stack sizes:  max: %5d  before:%5d  after:%5d\n'):format(stacks_type.type_name, stacks_type.type_id,  stacks_type.item_qty, stacks_type.max_stack_size, stacks_type.before_stacks, stacks_type.after_stacks))
    end
end

local function isRestrictedItem(item)
    -- is the item restricted from merging?
    local flags = item.flags
    return flags.rotten or flags.trader or flags.hostile or flags.forbid
        or flags.dump or flags.on_fire or flags.garbage_collect or flags.owned
        or flags.removed or flags.encased or flags.spider_web or #item.specific_refs > 0
end


function stacks_add_items(stacks, items, ind)
-- loop through each item and add it to the matching stack[type_id].comp_items table
-- recursively calls itself to add contained items
    if not ind then ind = '' end

    for _, item in pairs(items) do
        local type_id = item:getType()
        local stacks_type = stacks[type_id]

        -- item type in list of included types?
        if stacks_type then
            if not isRestrictedItem(item) then

                stacks_type_add_item(stacks_type, item)

                log(('      %sitem:%40s <%6d> is incl, type %d\n'):format(ind, utils.getItemDescription(item), item.id, type_id))
            else
                -- restricted; such as marked for action or dump.
                log(('      %sitem:%40s <%6d> is restricted\n'):format(ind, utils.getItemDescription(item), item.id))
            end

        -- add contained items
        elseif dfhack.items.getGeneralRef(item, df.general_ref_type.CONTAINS_ITEM) then
            local contained_items = dfhack.items.getContainedItems(item)
            log(('      %sContainer:%s <%6d> #items:%5d\n'):format(ind, utils.getItemDescription(item), item.id, #contained_items))
            stacks_add_items(stacks, contained_items, ind .. '   ')

        -- excluded item types
        else
            log(('      %sitem:%40s <%6d> is excl, type %d\n'):format(ind, utils.getItemDescription(item), item.id, type_id))
        end
    end
end

local function populate_stacks(stacks, stockpiles, types)
    -- 1. loop through the specified types and add them to the stacks table. stacks[type_id]
    -- 2. loop through the table of stockpiles, get each item in the stockpile, then add them to stacks if the type_id matches
    -- an item is stored at the bottom of the structure: stacks[type_id].comp_items[comp_key].item
    -- comp_key is a compound key comprised of type_id+race+caste or type_id+mat_type+mat_index
    log('Populating phase\n')

    -- iterate across the types
    log('stack types\n')
    for type_id, type_vals in pairs(types) do
        if not stacks[type_id] then
            stacks[type_id] = stack_type_new(type_vals)
            local stacks_type = stacks[type_id]
            log(('   type: <%12s> <%d>   #item_qty:%5d  stack sizes:  max: %5d  before:%5d  after:%5d\n'):format(stacks_type.type_name, stacks_type.type_id,  stacks_type.item_qty, stacks_type.max_stack_size, stacks_type.before_stacks, stacks_type.after_stacks))
        end
    end

    -- iterate across the stockpiles, get the list of items and call the add function to check/add as needed
    log(('stockpiles\n'))
    for _, stockpile in pairs(stockpiles) do

        local items = dfhack.buildings.getStockpileContents(stockpile)
        log(('   stockpile:%30s <%6d> pos:(%3d,%3d,%3d) #items:%5d\n'):format(stockpile.name, stockpile.id, stockpile.centerx, stockpile.centery, stockpile.z,  #items))

        if #items > 0 then
            stacks_add_items(stacks, items)
        else
            log('      skipping stockpile: no items\n')
        end
    end
end

local function preview_stacks(stacks)
    -- calculate the stacks sizes and store in after_stack_size
    -- the max stack size for each comp item is determined as the maximum stack size for it's type
    log('\nPreview phase\n')
    for _, stacks_type in pairs(stacks) do
        for comp_key, comp_item in pairs(stacks_type.comp_items) do
            -- sort the items.
            table.sort(comp_item.sorted_items)

            if stacks_type.max_stack_size > comp_item.max_stack_size then
                comp_item.max_stack_size = stacks_type.max_stack_size
            end

            -- how many stacks are needed ?
            local max_stacks_needed = math.floor(comp_item.item_qty / comp_item.max_stack_size)

            -- how many items are left over after the max stacks are allocated?
            local stack_remainder = comp_item.item_qty - max_stacks_needed * comp_item.max_stack_size

            -- update the after stack sizes. use the sorted items list to get the items.
            for _, s_item in ipairs(comp_item.sorted_items) do
                local item_id = s_item
                if s_item < 0 then item_id = s_item * -1 end
                local item = comp_item.items[item_id]
                if max_stacks_needed > 0 then
                    max_stacks_needed = max_stacks_needed - 1
                    comp_item.after_stack_size[item.id] = comp_item.max_stack_size
                elseif stack_remainder > 0 then
                    comp_item.after_stack_size[item.id] = stack_remainder
                    stack_remainder = 0
                elseif stack_remainder == 0 then
                    comp_item.after_stack_size[item.id] = stack_remainder
                    comp_item.after_stacks = comp_item.after_stacks - 1
                    stacks_type.after_stacks = stacks_type.after_stacks - 1
                end
            end
        end
    end
end

local function merge_stacks(stacks)
    -- apply the stack size changes in the after_stack_size
    -- if the after_stack_size is zero, then remove the item
    log('Merge phase\n')
    for _, stacks_type in pairs(stacks) do
        for comp_key, comp_item in pairs(stacks_type.comp_items) do
            for _, item in pairs(comp_item.items) do
                if comp_item.after_stack_size[item.id] == 0 then
                    local remove_item = df.item.find(item.id)
                    dfhack.items.remove(remove_item)
                elseif item.stack_size ~= comp_item.after_stack_size[item.id] then
                    item.stack_size = comp_item.after_stack_size[item.id]
                end
            end
        end
    end
end

local function get_stockpile_all()
    -- attempt to get all the stockpiles for the fort, or exit with error
    -- return the stockpiles as a table
    local stockpiles = {}
    for _, building in pairs(df.global.world.buildings.all) do
        if building:getType() == df.building_type.Stockpile then
            table.insert(stockpiles, building)
        end
    end
    dfhack.print(('Stockpile(all): %d found\n'):format(#stockpiles))
    return stockpiles
end

local function get_stockpile_here()
    -- attempt to get the stockpile located at the game cursor, or exit with error
    -- return the stockpile as a table
    local stockpiles = {}
    local pos = argparse.coords('here', 'here')
    local building = dfhack.buildings.findAtTile(pos)
    if not building or building:getType() ~= df.building_type.Stockpile then qerror('Stockpile not found at game cursor position.') end
    table.insert(stockpiles, building)
    local items = dfhack.buildings.getStockpileContents(building)
    dfhack.print(('Stockpile(here): %s <%d> #items:%d\n'):format(building.name, building.id, #items))
    return stockpiles
end

local function parse_types_opts(arg)
    -- check the types specified on the command line, or exit with error
    -- return the selected types as a table
    local types = {}
    local div = ''
    local types_output = ''

    if not arg then
        qerror('Expected: comma separated list of types')
    end

    types_output='Types: '

    for _, t in pairs(argparse.stringList(arg)) do
        if not valid_types_map[t] then
            qerror(('Unknown type: %s'):format(t))
        end

        for k2, v2 in pairs(valid_types_map[t]) do
            if not types[k2] then
                types[k2]={}
                for k3, v3 in pairs(v2) do
                    types[k2][k3]=v3
                end
                types_output = types_output .. div .. types[k2].type_name
                div=', '
            else
                qerror(('Expected: only one value for %s'):format(t))
            end
        end
    end
    dfhack.print(types_output .. '\n')
    return types
end

local function parse_commandline(opts, args)
    -- check the command line/exit on error, and set the defaults
    local positionals = argparse.processArgsGetopt(args, {
            {'h', 'help', handler=function() opts.help = true end},
            {'t', 'types', hasArg=true, handler=function(optarg) opts.types=parse_types_opts(optarg) end},
            {'d', 'dry-run', handler=function(optarg) opts.dry_run = true end},
            {'v', 'verbose', handler=function(optarg) opts.verbose = true end},
    })

    -- if stockpile option is not specificed, then default to all
    if args[1] == 'all' then
        opts.all=get_stockpile_all()
    elseif args[1] == 'here' then
        opts.here=get_stockpile_here()
    else
        opts.help = true
    end

    -- if types option is not specified, then default to all
    if not opts.types then
        opts.types = valid_types_map['all']
    end

end


-- main program starts here
local function main()

    if df.global.gamemode ~= df.game_mode.DWARF or not dfhack.isMapLoaded() then
        qerror('combine needs a loaded fortress map to work\n')
    end

    parse_commandline(opts, args)

    if opts.help then
        print(dfhack.script_help())
        return
    end

    local stacks = CList:new()

    populate_stacks(stacks,  opts.all or opts.here, opts.types)

    preview_stacks(stacks)

    if not opts.dry_run then
        merge_stacks(stacks)
    end

    print_stacks_details(stacks)
    print_stacks_summary(stacks)

end

if not dfhack_flags.module then
    main()
end
