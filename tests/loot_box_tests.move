#[test_only]
module loot_box::loot_box_tests {
    use sui::test_scenario::{Self as ts};
    use sui::coin;
    use sui::sui::SUI;
    use sui::random;
    use sui::transfer;
    use loot_box::loot_box::{Self, GameConfig, Leaderboard, LootBox, GameItem, AdminCap};

    const ADMIN: address   = @0xAD;
    const PLAYER: address  = @0xA1;
    const PLAYER2: address = @0xA2;
    const PRICE: u64 = 1_000_000_000;

    fun setup(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, ADMIN);
        loot_box::init_game_for_testing<SUI>(ts::ctx(scenario));
    }

    fun setup_random(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, @0x0);
        random::create_for_testing(ts::ctx(scenario));
        ts::next_tx(scenario, @0x0);
        let mut rand = ts::take_shared<random::Random>(scenario);
        random::update_randomness_state_for_testing(
            &mut rand, 0, x"1234567890abcdef1234567890abcdef", ts::ctx(scenario)
        );
        ts::return_shared(rand);
    }

    fun buy_and_open(scenario: &mut ts::Scenario) {
        ts::next_tx(scenario, PLAYER);
        {
            let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
            let payment = coin::mint_for_testing<SUI>(PRICE, ts::ctx(scenario));
            let lb = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(scenario));
            transfer::public_transfer(lb, PLAYER);
            ts::return_shared(config);
        };
        ts::next_tx(scenario, PLAYER);
        {
            let loot_box = ts::take_from_sender<LootBox>(scenario);
            let mut config = ts::take_shared<GameConfig<SUI>>(scenario);
            let mut leaderboard = ts::take_shared<Leaderboard>(scenario);
            let rand = ts::take_shared<random::Random>(scenario);
            loot_box::open_loot_box(&mut config, &mut leaderboard, loot_box, &rand, ts::ctx(scenario));
            ts::return_shared(config);
            ts::return_shared(leaderboard);
            ts::return_shared(rand);
        };
    }

    #[test]
    fun test_init_game() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let config = ts::take_shared<GameConfig<SUI>>(&scenario);
            assert!(loot_box::get_price(&config) == PRICE, 0);
            assert!(loot_box::get_common_weight(&config) == 60, 1);
            ts::return_shared(config);
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            ts::return_to_sender(&scenario, cap);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_purchase_loot_box() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER);
        {
            let mut config = ts::take_shared<GameConfig<SUI>>(&scenario);
            let payment = coin::mint_for_testing<SUI>(PRICE, ts::ctx(&mut scenario));
            let lb = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(&mut scenario));
            transfer::public_transfer(lb, PLAYER);
            ts::return_shared(config);
        };
        ts::next_tx(&mut scenario, PLAYER);
        {
            let lb = ts::take_from_sender<LootBox>(&scenario);
            ts::return_to_sender(&scenario, lb);
        };
        ts::end(scenario);
    }

    #[test, expected_failure(abort_code = 0)]
    fun test_purchase_insufficient_payment() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER);
        {
            let mut config = ts::take_shared<GameConfig<SUI>>(&scenario);
            let payment = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
            let lb = loot_box::purchase_loot_box(&mut config, payment, ts::ctx(&mut scenario));
            transfer::public_transfer(lb, PLAYER);
            ts::return_shared(config);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_open_loot_box() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        setup_random(&mut scenario);
        buy_and_open(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER);
        {
            let item = ts::take_from_sender<GameItem>(&scenario);
            let (_name, rarity, power, _flavor) = loot_box::get_item_stats(&item);
            assert!(rarity <= 3, 0);
            assert!(power >= 1 && power <= 50, 1);
            assert!(loot_box::get_durability(&item) == 100, 2);
            ts::return_to_sender(&scenario, item);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_transfer_item() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER);
        {
            let item = loot_box::mint_item_for_testing(b"Test Sword", 0, 5, ts::ctx(&mut scenario));
            transfer::public_transfer(item, PLAYER);
        };
        ts::next_tx(&mut scenario, PLAYER);
        {
            let item = ts::take_from_sender<GameItem>(&scenario);
            loot_box::transfer_item(item, PLAYER2);
        };
        ts::next_tx(&mut scenario, PLAYER2);
        {
            let item = ts::take_from_sender<GameItem>(&scenario);
            let (_, _, power, _) = loot_box::get_item_stats(&item);
            assert!(power == 5, 0);
            ts::return_to_sender(&scenario, item);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_burn_item() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER);
        {
            let item = loot_box::mint_item_for_testing(b"Burnable Axe", 0, 3, ts::ctx(&mut scenario));
            loot_box::burn_item(item);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_update_rarity_weights() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<GameConfig<SUI>>(&scenario);
            loot_box::update_rarity_weights(&cap, &mut config, 50, 30, 15, 5);
            assert!(loot_box::get_common_weight(&config) == 50, 0);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(config);
        };
        ts::end(scenario);
    }

    #[test, expected_failure(abort_code = 1)]
    fun test_update_weights_invalid_sum() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, ADMIN);
        {
            let cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut config = ts::take_shared<GameConfig<SUI>>(&scenario);
            loot_box::update_rarity_weights(&cap, &mut config, 50, 30, 15, 4);
            ts::return_to_sender(&scenario, cap);
            ts::return_shared(config);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_item_durability() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER);
        {
            let mut item = loot_box::mint_item_for_testing(b"War Axe", 1, 15, ts::ctx(&mut scenario));
            assert!(loot_box::get_durability(&item) == 100, 0);
            loot_box::use_item(&mut item);
            assert!(loot_box::get_durability(&item) == 90, 1);
            loot_box::repair_item(&mut item);
            assert!(loot_box::get_durability(&item) == 100, 2);
            loot_box::burn_item(item);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_item_fusion() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER);
        {
            let item1 = loot_box::mint_item_for_testing(b"Iron Dagger", 0, 8, ts::ctx(&mut scenario));
            let item2 = loot_box::mint_item_for_testing(b"Iron Dagger", 0, 6, ts::ctx(&mut scenario));
            loot_box::fuse_items(item1, item2, ts::ctx(&mut scenario));
        };
        ts::next_tx(&mut scenario, PLAYER);
        {
            let item = ts::take_from_sender<GameItem>(&scenario);
            let (_, rarity, power, _) = loot_box::get_item_stats(&item);
            assert!(rarity == 0, 0);
            assert!(power >= 7, 1);
            assert!(loot_box::is_fused(&item) == true, 2);
            ts::return_to_sender(&scenario, item);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_leaderboard() {
        let mut scenario = ts::begin(ADMIN);
        setup(&mut scenario);
        setup_random(&mut scenario);
        buy_and_open(&mut scenario);
        ts::next_tx(&mut scenario, PLAYER);
        {
            let leaderboard = ts::take_shared<Leaderboard>(&scenario);
            let (powers, _, _) = loot_box::get_leaderboard(&leaderboard);
            assert!(vector::length(&powers) == 1, 0);
            ts::return_shared(leaderboard);
        };
        ts::end(scenario);
    }
}