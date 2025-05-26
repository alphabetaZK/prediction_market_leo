// Test file for prediction market program

import alpha_beta_zk.aleo;

program alpha_beta_zk_test.aleo {
    // Test market creation
    transition test_create_market() -> bool {
        let result: bool = alpha_beta_zk.aleo/create_market(1u32, 1u32);
        return result;
    }

    // Test placing a bet
    transition test_place_bet(
        market_id: u32,
        choice: u8,
        amount: u64,
        bet_record: alpha_beta_zk.aleo/Bet
    ) -> bool {
        let result: bool = alpha_beta_zk.aleo/place_bet(market_id, choice, amount, bet_record);
        return result;
    }

    // Test closing a market
    transition test_close_market(market_id: u32) -> bool {
        let result: bool = alpha_beta_zk.aleo/close_market(market_id);
        return result;
    }

    // Test revealing result
    transition test_reveal_result(market_id: u32, correct_outcome: u8) -> bool {
        let result: bool = alpha_beta_zk.aleo/reveal_result(market_id, correct_outcome);
        return result;
    }

    // Test claiming reward
    transition test_claim_reward(
        market_id: u32,
        bet_record: alpha_beta_zk.aleo/Bet
    ) -> bool {
        let result: bool = alpha_beta_zk.aleo/claim_reward(market_id, bet_record);
        return result;
    }
} 