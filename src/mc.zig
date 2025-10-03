pub const Color = enum(u8) {
    white = 0,
    orange = 1,
    light_purple = 2,
    light_blue = 3,
    yellow = 4,
    lime = 5,
    pink = 6,
    dark_gray = 7,
    light_gray = 8,
    cyan = 9,
    purple = 10,
    blue = 11,
    brown = 12,
    green = 13,
    red = 14,
    black = 15,
};

pub const WoodType = enum(u8) {
    oak = 0,
    spruce = 1,
    birch = 2,
};

pub const GrassType = enum(u8) {
    shrub = 0,
    grass = 1,
    fern = 2,
};

pub const SlabType = enum(u8) {
    stone = 0,
    sandstone = 1,
    wood = 2,
    cobblestone = 3,
};

pub const BlockMetadata = extern union {
    /// For: Wool
    color: Color,
    /// For: Log, Leaves
    wood_type: WoodType,
    /// For: Tall grass
    grass_type: GrassType,
    /// For: Slabs
    slab_type: SlabType,

    comptime {
        if (@sizeOf(BlockMetadata) != 1) {
            @compileError("BlockMetadata must be only 1 byte");
        }
    }
};

pub const BlockId = enum(u8) {
    air = 0,
    stone = 1,
    grass = 2,
    dirt = 3,
    cobblestone = 4,
    planks = 5,
    /// Metadata: Wood type
    sapling = 6,
    bedrock = 7,
    /// Metadata: Liquid type
    water_flowing = 8,
    /// Metadata: Liquid type
    water_still = 9,
    /// Metadata: Liquid type
    lava_flowing = 10,
    /// Metadata: Liquid type
    lava_still = 11,
    sand = 12,
    gravel = 13,
    gold_ore = 14,
    iron_ore = 15,
    coal_ore = 16,
    /// Metadata: Wood type
    log = 17,
    /// Metadata: Wood type
    leaves = 18,
    sponge = 19,
    glass = 20,
    lapis_ore = 21,
    lapis_block = 22,
    dispenser = 23,
    sandstone = 24,
    noteblock = 25,
    /// Metadata: Top/Bottom and direction
    bed = 26,
    /// Metadata: Direction
    powered_rail = 27,
    /// Metadata: Direction
    detector_rail = 28,
    /// Metadata: Direction
    sticky_piston = 29,
    cobweb = 30,
    /// Metadata: Grass type
    tallgrass = 31,
    deadbush = 32,
    /// Metadata: Direction
    piston = 33,
    /// Metadata: Direction
    piston_head = 34,
    /// Metadata: Color
    wool = 35,
    dandelion = 37,
    rose = 38,
    brown_mushroom = 39,
    red_mushroom = 40,
    gold_block = 41,
    iron_block = 42,
    /// Metadata: Slab type
    double_slab = 43,
    /// Metadata: Slab type
    slab = 44,
    bricks = 45,
    tnt = 46,
    bookshelf = 47,
    mossy_cobblestone = 48,
    obsidian = 49,
    /// Metadata: Direction
    torch = 50,
    fire = 51,
    monster_spawner = 52,
    /// Metadata: Direction
    wooden_stairs = 53,
    chest = 54,
    /// Metadata: Power level
    redstone = 55,
    diamond_ore = 56,
    diamond_block = 57,
    crafting_table = 58,
    /// Metadata: Growth stage (0-7)
    wheat = 59,
    /// Metadata: Is wet
    farmland = 60,
    furnace = 61,
    furnace_lit = 62,
    /// Metadata: Direction
    sign_ground = 63,
    wood_door = 64,
    /// Metadata: Direction
    ladder = 65,
    /// Metadata: Direction
    rail = 66,
    /// Metadata: Direction
    cobblestone_stairs = 67,
    /// Metadata: Direction
    sign_wall = 68,
    /// Metadata: Direction & toggled
    lever = 69,
    /// Metadata: Toggled
    stone_pressure_plate = 70,
    iron_door = 71,
    /// Metadata: Toggled
    wooden_pressure_plate = 72,
    redstone_ore = 73,
    redstone_ore_lit = 74,
    redstone_torch = 75,
    redstone_torch_lit = 76,
    /// Metadata: Toggled
    stone_button = 77,
    snow_layer = 78,
    ice = 79,
    snow_block = 80,
    cactus = 81,
    clay = 82,
    sugarcane = 83,
    jukebox = 84,
    fence = 85,
    /// Metadata: Direction
    pumpkin = 86,
    netherrack = 87,
    soulsand = 88,
    glowstone = 89,
    nether_portal = 90,
    /// Metadata: Direction
    pumpkin_lit = 91,
    cake = 92,
    redstone_repeater = 93,
    redstone_repeater_lit = 94,
    locked_chest = 95,
    /// Metadata: Direction & toggled
    trapdoor = 96,

    pub fn fromItem(item: ItemId) ?BlockId {
        const id = @intFromEnum(item);
        if (id > 96 or id == 36) {
            return null;
        }
        return @enumFromInt(id);
    }
};

pub const ItemId = enum(u16) {
    air = 0,

    // Blocks
    stone_block = 1,
    grass_block = 2,
    dirt_block = 3,
    cobblestone_block = 4,
    planks_block = 5,
    /// Metadata: Wood type
    sapling_block = 6,
    bedrock_block = 7,
    /// Metadata: Liquid type
    water_flowing_block = 8,
    /// Metadata: Liquid type
    water_still_block = 9,
    /// Metadata: Liquid type
    lava_flowing_block = 10,
    /// Metadata: Liquid type
    lava_still_block = 11,
    sand_block = 12,
    gravel_block = 13,
    gold_ore_block = 14,
    iron_ore_block = 15,
    coal_ore_block = 16,
    /// Metadata: Wood type
    log_block = 17,
    /// Metadata: Wood type
    leaves_block = 18,
    sponge_block = 19,
    glass_block = 20,
    lapis_ore_block = 21,
    dispenser_block = 23,
    sandstone_block = 24,
    noteblock_block = 25,
    /// Metadata: Top/Bottom and direction
    bed_block = 26,
    /// Metadata: Direction
    powered_rail_block = 27,
    /// Metadata: Direction
    detector_rail_block = 28,
    /// Metadata: Direction
    sticky_piston_block = 29,
    cobweb_block = 30,
    /// Metadata: Grass type
    tallgrass_block = 31,
    deadbush_block = 32,
    /// Metadata: Direction
    piston_block = 33,
    /// Metadata: Direction
    piston_head_block = 34,
    /// Metadata: Color
    wool_block = 35,
    dandelion_block = 37,
    rose_block = 38,
    brown_mushroom_block = 39,
    red_mushroom_block = 40,
    gold_block_block = 41,
    iron_block_block = 42,
    /// Metadata: Slab type
    double_slab_block = 43,
    /// Metadata: Slab type
    slab_block = 44,
    bricks_block = 45,
    tnt_block = 46,
    bookshelf_block = 47,
    mossy_cobblestone_block = 48,
    obsidian_block = 49,
    /// Metadata: Direction
    torch_block = 50,
    fire_block = 51,
    monster_spawner_block = 52,
    /// Metadata: Direction
    wooden_stairs_block = 53,
    chest_block = 54,
    /// Metadata: Power level
    redstone_block = 55,
    diamond_ore_block = 56,
    diamond_block_block = 57,
    crafting_table_block = 58,
    /// Metadata: Growth stage (0-7)
    wheat_block = 59,
    /// Metadata: Is wet
    farmland_block = 60,
    furnace_block = 61,
    furnace_lit_block = 62,
    /// Metadata: Direction
    sign_ground_block = 63,
    wood_door_block = 64,
    /// Metadata: Direction
    ladder_block = 65,
    /// Metadata: Direction
    rail_block = 66,
    /// Metadata: Direction
    cobblestone_stairs_block = 67,
    /// Metadata: Direction
    sign_wall_block = 68,
    /// Metadata: Direction & toggled
    lever_block = 69,
    /// Metadata: Toggled
    stone_pressure_plate_block = 70,
    iron_door_block = 71,
    /// Metadata: Toggled
    wooden_pressure_plate_block = 72,
    redstone_ore_block = 73,
    redstone_ore_lit_block = 74,
    redstone_torch_block = 75,
    redstone_torch_lit_block = 76,
    /// Metadata: Toggled
    stone_button_block = 77,
    snow_layer_block = 78,
    ice_block = 79,
    snow_block_block = 80,
    cactus_block = 81,
    clay_block = 82,
    sugarcane_block = 83,
    jukebox_block = 84,
    fence_block = 85,
    /// Metadata: Direction
    pumpkin_block = 86,
    netherrack_block = 87,
    soulsand_block = 88,
    glowstone_block = 89,
    nether_portal_block = 90,
    /// Metadata: Direction
    pumpkin_lit_block = 91,
    cake_block = 92,
    redstone_repeater_block = 93,
    redstone_repeater_lit_block = 94,
    locked_chest_block = 95,
    /// Metadata: Direction & toggled
    trapdoor_block = 96,

    // Items
    iron_shovel = 256,
    iron_pickaxge = 257,
    iron_axe = 258,
    flint_and_steel = 259,
    apple = 260,
    bow = 261,
    arrow = 262,
    coal = 263,
    diamond = 264,
    iron = 265,
    gold = 266,
    iron_sword = 267,
    wooden_sword = 268,
    wooden_shovel = 269,
    wooden_pickaxe = 270,
    wooden_axe = 271,
    stone_sword = 272,
    stone_shovel = 273,
    stone_pickaxe = 274,
    stone_axe = 275,
    diamond_sword = 276,
    diamond_shovel = 277,
    diamond_pickaxe = 278,
    diamond_axe = 279,
    stick = 280,
    bowl = 281,
    mushroom_stew = 282,
    gold_sword = 283,
    gold_shovel = 284,
    gold_pickaxe = 285,
    gold_axe = 286,
    string = 287,
    feather = 288,
    gunpowder = 289,
    wooden_hoe = 290,
    stone_hoe = 291,
    iron_hoe = 292,
    diamond_hoe = 293,
    gold_hoe = 294,
    seeds = 295,
    wheat = 296,
    bread = 297,
    leather_cap = 298,
    leather_chestplate = 299,
    leather_pants = 300,
    leather_boots = 301,
    chainmail_helmet = 302,
    chainmail_chestplate = 303,
    chainmail_pants = 304,
    chainmail_boots = 305,
    iron_helmet = 306,
    iron_chestplate = 307,
    iron_pants = 308,
    iron_boots = 309,
    diamond_helmet = 310,
    diamond_chestplate = 311,
    diamond_pants = 312,
    diamond_boots = 313,
    gold_helmet = 314,
    gold_chestplate = 315,
    gold_pants = 316,
    gold_boots = 317,
    flint = 318,
    porkchop = 319,
    cooked_porkchop = 320,
    painting = 321,
    golden_apple = 322,
    sign = 323,
    wooden_door = 324,
    bucket = 325,
    water_bucket = 326,
    lava_bucket = 327,
    minecart = 328,
    saddle = 329,
    iron_door = 330,
    redstone = 331,
    snowball = 332,
    boat = 333,
    leather = 334,
    milk_bucket = 335,
    brick = 336,
    clay = 337,
    sugarcane = 338,
    paper = 339,
    book = 340,
    slime = 341,
    minecart_chest = 342,
    minecart_furance = 343,
    egg = 344,
    compass = 345,
    fishing_rod = 346,
    clock = 347,
    glowstone_dust = 348,
    fish = 349,
    cooked_fish = 350,
    dye = 351,
    bone = 352,
    sugar = 353,
    cake = 354,
    bed = 355,
    redstone_repeater = 356,
    cookie = 357,
    map = 358,
    shears = 359,

    pub fn fromBlock(block: BlockId) ItemId {
        return @bitCast(block);
    }
};

pub const GenericEntityType = enum(u8) {
    boat = 1,
    minecart = 10,
    minecart_chest = 11,
    minecart_furnace = 12,
    activated_tnt = 50,
    arrow = 60,
    thrown_snowball = 61,
    thrown_egg = 62,
    falling_sand = 70,
    falling_gravel = 71,
    fishing_float = 90,
};

pub const LivingEntityType = enum(u8) {
    creeper = 50,
    skeleton = 51,
    spider = 52,
    giant_zombie = 53,
    zombie = 54,
    slime = 55,
    ghast = 56,
    zombie_pigman = 57,
    pig = 90,
    sheep = 91,
    cow = 92,
    chicken = 93,
    squid = 94,
    wolf = 95,
};
