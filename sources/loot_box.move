/// Loot Box System with On-Chain Randomness
/// Sui Move Hackathon Submission
module loot_box::loot_box {
    use sui::random::{Self, Random};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::dynamic_field;
    use std::string::{Self, String};

    const EInsufficientPayment: u64 = 0;
    const EInvalidWeights: u64     = 1;
    const EItemBroken: u64         = 2;
    const ESameRarityRequired: u64 = 3;

    const RARITY_COMMON: u8    = 0;
    const RARITY_RARE: u8      = 1;
    const RARITY_EPIC: u8      = 2;
    const RARITY_LEGENDARY: u8 = 3;

    const PITY_THRESHOLD: u64  = 30;
    const STREAK_THRESHOLD: u64 = 5;
    const MAX_DURABILITY: u8   = 100;
    const LEADERBOARD_SIZE: u64 = 5;

    public struct GameConfig<phantom T> has key {
        id: UID,
        loot_box_price: u64,
        treasury: Coin<T>,
        common_weight: u8,
        rare_weight: u8,
        epic_weight: u8,
        legendary_weight: u8,
    }

    public struct Leaderboard has key {
        id: UID,
        top_power: vector<u8>,
        top_owners: vector<address>,
        top_names: vector<String>,
    }

    public struct AdminCap has key, store { id: UID }

    public struct LootBox has key, store { id: UID }

    public struct GameItem has key, store {
        id: UID,
        name: String,
        rarity: u8,
        power: u8,
        durability: u8,
        flavor: String,
        is_fused: bool,
    }

    public struct LootBoxOpened has copy, drop {
        item_id: ID,
        rarity: u8,
        power: u8,
        owner: address,
        pity_triggered: bool,
        streak_active: bool,
    }

    public struct ItemsFused has copy, drop {
        new_item_id: ID,
        new_power: u8,
        owner: address,
    }

    public struct LeaderboardUpdated has copy, drop {
        owner: address,
        power: u8,
        rank: u64,
    }

    // 1. init_game
    public fun init_game<T>(ctx: &mut TxContext) {
        let config = GameConfig<T> {
            id: object::new(ctx),
            loot_box_price: 1_000_000_000,
            treasury: coin::zero<T>(ctx),
            common_weight: 60,
            rare_weight: 25,
            epic_weight: 12,
            legendary_weight: 3,
        };
        transfer::share_object(config);
        let leaderboard = Leaderboard {
            id: object::new(ctx),
            top_power: vector[],
            top_owners: vector[],
            top_names: vector[],
        };
        transfer::share_object(leaderboard);
        transfer::transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
    }

    // 2. purchase_loot_box
    public fun purchase_loot_box<T>(
        config: &mut GameConfig<T>,
        payment: Coin<T>,
        ctx: &mut TxContext
    ): LootBox {
        assert!(coin::value(&payment) >= config.loot_box_price, EInsufficientPayment);
        coin::join(&mut config.treasury, payment);
        LootBox { id: object::new(ctx) }
    }

    // 3. open_loot_box — entry NOT public (prevents frontrunning)
    entry fun open_loot_box<T>(
        config: &mut GameConfig<T>,
        leaderboard: &mut Leaderboard,
        loot_box: LootBox,
        r: &Random,
        ctx: &mut TxContext
    ) {
        let sender = ctx.sender();

        let pity_count = if (dynamic_field::exists_(&config.id, sender)) {
            *dynamic_field::borrow<address, u64>(&config.id, sender)
        } else { 0u64 };

        let streak_count = if (dynamic_field::exists_(&leaderboard.id, sender)) {
            *dynamic_field::borrow<address, u64>(&leaderboard.id, sender)
        } else { 0u64 };

        let streak_active = streak_count >= STREAK_THRESHOLD;

        // Create generator INSIDE function — never pass as argument
        let mut gen = random::new_generator(r, ctx);

        let pity_triggered = pity_count >= PITY_THRESHOLD;
        let rarity = if (pity_triggered) {
            RARITY_LEGENDARY
        } else {
            let roll = random::generate_u8_in_range(&mut gen, 0, 99);
            if (streak_active) { determine_rarity_boosted(roll) }
            else { determine_rarity(roll) }
        };

        let (min_power, max_power) = get_power_range(rarity);
        let power = random::generate_u8_in_range(&mut gen, min_power, max_power);

        // Update pity counter
        if (dynamic_field::exists_(&config.id, sender)) {
            dynamic_field::remove<address, u64>(&mut config.id, sender);
        };
        dynamic_field::add(&mut config.id, sender,
            if (rarity == RARITY_LEGENDARY) { 0u64 } else { pity_count + 1 }
        );

        // Update streak counter
        if (dynamic_field::exists_(&leaderboard.id, sender)) {
            dynamic_field::remove<address, u64>(&mut leaderboard.id, sender);
        };
        dynamic_field::add(&mut leaderboard.id, sender, streak_count + 1);

        // Burn loot box
        let LootBox { id } = loot_box;
        object::delete(id);

        let item_name = generate_item_name(rarity);

        // Update leaderboard
        try_update_leaderboard(leaderboard, power, sender, item_name);

        let item = GameItem {
            id: object::new(ctx),
            name: item_name,
            rarity,
            power,
            durability: MAX_DURABILITY,
            flavor: generate_flavor(rarity),
            is_fused: false,
        };

        event::emit(LootBoxOpened {
            item_id: object::id(&item),
            rarity, power, owner: sender,
            pity_triggered, streak_active,
        });

        transfer::transfer(item, sender);
    }

    // Fusion: combine 2 same-rarity items into 1 stronger item
    public entry fun fuse_items(
        item1: GameItem, item2: GameItem, ctx: &mut TxContext
    ) {
        assert!(item1.rarity == item2.rarity, ESameRarityRequired);
        assert!(item1.durability > 0 && item2.durability > 0, EItemBroken);
        let rarity = item1.rarity;
        let raw_power = ((item1.power as u64) + (item2.power as u64)) / 2 + 3;
        let (_, max_power) = get_power_range(rarity);
        let fused_power = if (raw_power > (max_power as u64)) { max_power } else { raw_power as u8 };
        let GameItem { id: id1, name: _, rarity: _, power: _, durability: _, flavor: _, is_fused: _ } = item1;
        let GameItem { id: id2, name: _, rarity: _, power: _, durability: _, flavor: _, is_fused: _ } = item2;
        object::delete(id1);
        object::delete(id2);
        let fused_item = GameItem {
            id: object::new(ctx),
            name: generate_fused_name(rarity),
            rarity, power: fused_power,
            durability: MAX_DURABILITY,
            flavor: string::utf8(b"Two souls merged into one unstoppable force."),
            is_fused: true,
        };
        event::emit(ItemsFused { new_item_id: object::id(&fused_item), new_power: fused_power, owner: ctx.sender() });
        transfer::transfer(fused_item, ctx.sender());
    }

    // Durability: use reduces it, repair restores it
    public entry fun use_item(item: &mut GameItem) {
        assert!(item.durability > 0, EItemBroken);
        if (item.durability >= 10) { item.durability = item.durability - 10; }
        else { item.durability = 0; }
    }

    public entry fun repair_item(item: &mut GameItem) {
        item.durability = MAX_DURABILITY;
    }

    // 4. get_item_stats
    public fun get_item_stats(item: &GameItem): (String, u8, u8, String) {
        (item.name, item.rarity, item.power, item.flavor)
    }

    public fun get_item_full_stats(item: &GameItem): (String, u8, u8, u8, bool, String) {
        (item.name, item.rarity, item.power, item.durability, item.is_fused, item.flavor)
    }

    // 5. transfer_item
    public entry fun transfer_item(item: GameItem, to: address) {
        transfer::public_transfer(item, to);
    }

    // 6. burn_item
    public entry fun burn_item(item: GameItem) {
        let GameItem { id, name: _, rarity: _, power: _, durability: _, flavor: _, is_fused: _ } = item;
        object::delete(id);
    }

    // 7. update_rarity_weights
    public entry fun update_rarity_weights<T>(
        _cap: &AdminCap, config: &mut GameConfig<T>,
        common: u8, rare: u8, epic: u8, legendary: u8
    ) {
        assert!((common as u64)+(rare as u64)+(epic as u64)+(legendary as u64)==100, EInvalidWeights);
        config.common_weight = common;
        config.rare_weight = rare;
        config.epic_weight = epic;
        config.legendary_weight = legendary;
    }

    // Leaderboard
    fun try_update_leaderboard(lb: &mut Leaderboard, power: u8, owner: address, name: String) {
        let len = vector::length(&lb.top_power);
        let mut min_power = 255u8;
        let mut min_idx = 0u64;
        let mut i = 0u64;
        while (i < len) {
            let p = *vector::borrow(&lb.top_power, i);
            if (p < min_power) { min_power = p; min_idx = i; };
            i = i + 1;
        };
        if (len < LEADERBOARD_SIZE) {
            vector::push_back(&mut lb.top_power, power);
            vector::push_back(&mut lb.top_owners, owner);
            vector::push_back(&mut lb.top_names, name);
            event::emit(LeaderboardUpdated { owner, power, rank: len + 1 });
        } else if (power > min_power) {
            *vector::borrow_mut(&mut lb.top_power, min_idx) = power;
            *vector::borrow_mut(&mut lb.top_owners, min_idx) = owner;
            *vector::borrow_mut(&mut lb.top_names, min_idx) = name;
            event::emit(LeaderboardUpdated { owner, power, rank: min_idx + 1 });
        }
    }

    public fun get_leaderboard(lb: &Leaderboard): (vector<u8>, vector<address>, vector<String>) {
        (lb.top_power, lb.top_owners, lb.top_names)
    }

    // Helpers
    fun determine_rarity(roll: u8): u8 {
        if (roll < 60) { RARITY_COMMON }
        else if (roll < 85) { RARITY_RARE }
        else if (roll < 97) { RARITY_EPIC }
        else { RARITY_LEGENDARY }
    }

    fun determine_rarity_boosted(roll: u8): u8 {
        if (roll < 55) { RARITY_COMMON }
        else if (roll < 82) { RARITY_RARE }
        else if (roll < 95) { RARITY_EPIC }
        else { RARITY_LEGENDARY }
    }

    fun get_power_range(rarity: u8): (u8, u8) {
        if (rarity == RARITY_COMMON) { (1, 10) }
        else if (rarity == RARITY_RARE) { (11, 25) }
        else if (rarity == RARITY_EPIC) { (26, 40) }
        else { (41, 50) }
    }

    fun generate_item_name(rarity: u8): String {
        if (rarity == RARITY_COMMON) { string::utf8(b"Iron Dagger") }
        else if (rarity == RARITY_RARE) { string::utf8(b"Silver Bow") }
        else if (rarity == RARITY_EPIC) { string::utf8(b"Void Staff") }
        else { string::utf8(b"Sunfire Blade") }
    }

    fun generate_fused_name(rarity: u8): String {
        if (rarity == RARITY_COMMON) { string::utf8(b"Twin Iron Daggers [Fused]") }
        else if (rarity == RARITY_RARE) { string::utf8(b"Dual Silver Bow [Fused]") }
        else if (rarity == RARITY_EPIC) { string::utf8(b"Twin Void Staves [Fused]") }
        else { string::utf8(b"Eternal Sunfire Blade [Fused]") }
    }

    fun generate_flavor(rarity: u8): String {
        if (rarity == RARITY_COMMON) { string::utf8(b"A sturdy blade, well-worn but reliable.") }
        else if (rarity == RARITY_RARE) { string::utf8(b"Moonlight gleams along its polished curve.") }
        else if (rarity == RARITY_EPIC) { string::utf8(b"Whispers of the abyss echo within.") }
        else { string::utf8(b"Forged at the heart of a dying star.") }
    }

    #[test_only]
    public fun init_game_for_testing<T>(ctx: &mut TxContext) { init_game<T>(ctx); }
    #[test_only]
    public fun get_price<T>(config: &GameConfig<T>): u64 { config.loot_box_price }
    #[test_only]
    public fun get_common_weight<T>(config: &GameConfig<T>): u8 { config.common_weight }
    #[test_only]
    public fun get_durability(item: &GameItem): u8 { item.durability }
    #[test_only]
    public fun is_fused(item: &GameItem): bool { item.is_fused }
    #[test_only]
    public fun mint_item_for_testing(name: vector<u8>, rarity: u8, power: u8, ctx: &mut TxContext): GameItem {
        GameItem {
            id: object::new(ctx),
            name: string::utf8(name), rarity, power,
            durability: MAX_DURABILITY,
            flavor: string::utf8(b"Test item"),
            is_fused: false,
        }
    }
}