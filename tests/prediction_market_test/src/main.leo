import prediction_market.aleo;

// ERRORS:
// Error [EPAK0375054]: Conflicting data for dependency prediction_market.aleo.

// This error occurs when the same dependency is defined multiple times with different data.

program prediction_market_test.aleo {
    
    transition test_create_market() -> bool { 

        let q_hash: field = 123field;
        let opt_hashes: [field;5] = [1field, 2field, 0field, 0field, 0field];

        let (receipt, _dummy) = prediction_market.aleo/create_market
        (
            // Market ID 
            42field, q_hash, opt_hashes, 2u8, 7u32, 3000000u64

        );
        return receipt.market_id == 42field;
    }

    transition test_place_bet() -> prediction_market.aleo/BetRecord {

        let (ticket, _dummy) = prediction_market.aleo/place_bet
        (
            42field, 1u8, 5000000u64, 789field
        );
        // Place bet on option 1 with 5 Aleo tokens
        ticket               
    }

    transition test_close_market() -> bool { 

        let _dummy = prediction_market.aleo/close_market_with_winner
        (
            42field, 1u8
        );
        // close W
        return true;
    }

    transition test_claim_winnings(

        ticket: prediction_market.aleo/BetRecord) -> bool {
        let (receipt, _dummy) = prediction_market.aleo/claim_winnings(ticket);
        return receipt.bet_nonce == ticket.nonce;
    }

}
