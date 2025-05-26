// Aleo Anonymous Prediction Market Platform
// Team: Ramzy, Salim, Mathieu, Lina, Abdellahi

program prediction_market.aleo {
    // Constants
    const CREATION_FEE: u64 = 3000000u64;
    const MIN_BET: u64 = 3000000u64;
    const MAX_OPTIONS: u8 = 5u8;
    const SECONDS_PER_DAY: u32 = 86400u32;
    const MAX_OPEN_MARKETS: u8 = 100u8;

    const STATUS_OPEN: u8 = 0u8;
    const STATUS_CLOSED: u8 = 1u8;
    const STATUS_CANCELED: u8 = 2u8;
    const STATUS_INVALID: u8 = 3u8;

    const ADMIN: address = aleo12l0r3y89h30ts35d68mzf0ak35zepxw58gns2t4607a8a3jy65qs9gxuuj;

    struct Market {
        id: field,
        creator: address,
        question: field,
        options: [field; 5],
        num_options: u8,
        closing_block: u32,
        status: u8,
        winning_option: u8,
        total_pool: u64,
        option_pools: [u64; 5],
    }

    record BetRecord {
        owner: address,
        market_id: field,
        chosen_option: u8,
        amount: u64,
        nonce: field,
    }

    record MarketReceipt {
        owner: address,
        market_id: field,
        creation_fee_paid: u64,
    }

    record RewardReceipt {
        owner: address,
        market_id: field,
        bet_nonce: field,
        reward_amount: u64,
    }

    mapping markets: field => Market;
    mapping admin_fees: address => u64;
    mapping claimed_bets: field => bool;
    mapping open_markets: u8 => field;
    mapping market_count: bool => u8;

    async transition create_market(
        market_id: field, 
        question_hash: field, 
        option_hashes: [field; 5], 
        num_options: u8, 
        duration_days: u32, 
        public fee_payment: u64
    ) -> (MarketReceipt, Future) {
        assert(fee_payment >= CREATION_FEE);
        assert(num_options >= 2u8);
        assert(num_options <= MAX_OPTIONS);
        assert(duration_days > 0u32);
        assert(duration_days <= 365u32);

        let duration_secs: u32 = duration_days * SECONDS_PER_DAY;
    
        let market_receipt: MarketReceipt = MarketReceipt {
            owner: self.caller,
            market_id: market_id,
            creation_fee_paid: CREATION_FEE,
        };

        let future: Future = create_market_finalize(
            market_id, 
            question_hash, 
            option_hashes, 
            num_options, 
            duration_secs, 
            self.caller
        );
        
        return (market_receipt, future);
    }

    async function create_market_finalize(market_id: field, question_hash: field, option_hashes: [field; 5], num_options: u8, duration_secs: u32, caller: address) {
        let closing_block: u32 = block.height + duration_secs; 
        
        let new_market: Market = Market {
            id: market_id,
            creator: caller,
            question: question_hash,
            options: option_hashes,
            num_options: num_options,
            closing_block: closing_block,
            status: STATUS_OPEN,
            winning_option: 0u8,
            total_pool: 0u64,
            option_pools: [0u64, 0u64, 0u64, 0u64, 0u64],
        };

        Mapping::set(markets, market_id, new_market);

        let current_fees: u64 = Mapping::get_or_use(admin_fees, ADMIN, 0u64);
        let updated_fees: u64 = current_fees + CREATION_FEE;
        Mapping::set(admin_fees, ADMIN, updated_fees);

        let current_count: u8 = Mapping::get_or_use(market_count, true, 0u8);
        let is_room: bool = current_count < MAX_OPEN_MARKETS;
        if is_room {
            Mapping::set(open_markets, current_count, market_id);
            let new_count: u8 = current_count + 1u8;
            Mapping::set(market_count, true, new_count);
        }
    }

    async transition place_bet(market_id: field, chosen_option: u8, bet_amount: u64, nonce: field) -> (BetRecord, Future) {
        assert(bet_amount >= MIN_BET);
        assert(chosen_option >= 1u8);
        assert(chosen_option <= MAX_OPTIONS);

        let bet_record: BetRecord = BetRecord {
            owner: self.caller,
            market_id: market_id,
            chosen_option: chosen_option,
            amount: bet_amount,
            nonce: nonce,
        };

        let future: Future = place_bet_finalize(market_id, chosen_option, bet_amount);
        return (bet_record, future);
    }

    async function place_bet_finalize(market_id: field, chosen_option: u8, bet_amount: u64) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);
        assert(block.height < market.closing_block);
        assert(chosen_option <= market.num_options);

        let is_1: bool = chosen_option == 1u8;
        let is_2: bool = chosen_option == 2u8;
        let is_3: bool = chosen_option == 3u8;
        let is_4: bool = chosen_option == 4u8;
        let is_5: bool = chosen_option == 5u8;

        // Utilisation d'expressions ternaires avec accès explicite aux indices
        let pool_0: u64 = is_1 ? market.option_pools[0u8] + bet_amount : market.option_pools[0u8];
        let pool_1: u64 = is_2 ? market.option_pools[1u8] + bet_amount : market.option_pools[1u8];
        let pool_2: u64 = is_3 ? market.option_pools[2u8] + bet_amount : market.option_pools[2u8];
        let pool_3: u64 = is_4 ? market.option_pools[3u8] + bet_amount : market.option_pools[3u8];
        let pool_4: u64 = is_5 ? market.option_pools[4u8] + bet_amount : market.option_pools[4u8];

        let new_total_pool: u64 = market.total_pool + bet_amount;

        let new_market: Market = Market {
            id: market.id,
            creator: market.creator,
            question: market.question,
            options: market.options,
            num_options: market.num_options,
            closing_block: market.closing_block,
            status: market.status,
            winning_option: market.winning_option,
            total_pool: new_total_pool,
            option_pools: [pool_0, pool_1, pool_2, pool_3, pool_4],
        };

        Mapping::set(markets, market_id, new_market);
    }
    async transition close_market_with_winner(market_id: field, winning_option: u8) -> Future {
        assert(self.caller == ADMIN);
        let future: Future = close_market_winner(market_id, winning_option);
        return future;
    }

    async function close_market_winner(market_id: field, winning_option: u8) {

        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);
        assert(block.height >= market.closing_block);
        assert(winning_option >= 1u8 && winning_option <= market.num_options);

        let closed_market: Market = Market {
            id: market.id,
            creator: market.creator,
            question: market.question,
            options: market.options,
            num_options: market.num_options,
            closing_block: market.closing_block,
            status: STATUS_CLOSED,
            winning_option: winning_option,
            total_pool: market.total_pool,
            option_pools: market.option_pools,
        };

        Mapping::set(markets, market_id, closed_market);
    }

    async transition cancel_market(market_id: field) -> Future {
        assert(self.caller == ADMIN);
        let future: Future = cancel_market_finalize(market_id);
        return future;
    }

    async function cancel_market_finalize(market_id: field) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);

        let canceled_market: Market = Market {
            id: market.id,
            creator: market.creator,
            question: market.question,
            options: market.options,
            num_options: market.num_options,
            closing_block: market.closing_block,
            status: STATUS_CANCELED,
            winning_option: market.winning_option,
            total_pool: market.total_pool,
            option_pools: market.option_pools,
        };

        Mapping::set(markets, market_id, canceled_market);
    }

    async transition mark_market_invalid(market_id: field) -> Future {
        assert(self.caller == ADMIN);
        let future: Future = mark_market_invalid_finalize(market_id);
        return future;
    }

    async function mark_market_invalid_finalize(market_id: field) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);

        let invalid_market: Market = Market {
            id: market.id,
            creator: market.creator,
            question: market.question,
            options: market.options,
            num_options: market.num_options,
            closing_block: market.closing_block,
            status: STATUS_INVALID,
            winning_option: market.winning_option,
            total_pool: market.total_pool,
            option_pools: market.option_pools,
        };

        Mapping::set(markets, market_id, invalid_market);
    }

    async transition claim_winnings(bet_record: BetRecord) -> (RewardReceipt, Future) {
        let reward_receipt: RewardReceipt = RewardReceipt {
            owner: bet_record.owner,
            market_id: bet_record.market_id,
            bet_nonce: bet_record.nonce,
            reward_amount: 0u64, // Sera calculé dans finalize
        };

        let future: Future = claim_winnings_finalize(
            bet_record.market_id,
            bet_record.chosen_option,
            bet_record.amount,
            bet_record.nonce,
            bet_record.owner
        );

        return (reward_receipt, future);
    }

    async function claim_winnings_finalize(market_id: field, chosen_option: u8, bet_amount: u64, bet_nonce: field, bettor: address) {
        let market: Market = Mapping::get(markets, market_id);
        
        // Vérifier que le marché est dans un état final
        assert(market.status == STATUS_CLOSED || market.status == STATUS_CANCELED || market.status == STATUS_INVALID);
        
        // Vérifier que le pari n'a pas déjà été réclamé
        let is_claimed: bool = Mapping::get_or_use(claimed_bets, bet_nonce, false);
        assert(!is_claimed);

        // Marquer le pari comme réclamé
        Mapping::set(claimed_bets, bet_nonce, true);

        // Si le marché est fermé avec un gagnant, vérifier si c'est la bonne option
        if market.status == STATUS_CLOSED {
            assert(chosen_option == market.winning_option);
            // Le calcul des récompenses proportionnelles sera fait côté client
            // car Leo a des limitations pour les divisions complexes
        }
        
        // Si le marché est annulé, le parieur récupère sa mise
        // Si le marché est invalide, aucune récompense n'est distribuée
    }

    async transition claim_refund(bet_record: BetRecord) -> (RewardReceipt, Future) {
        let refund_receipt: RewardReceipt = RewardReceipt {
            owner: bet_record.owner,
            market_id: bet_record.market_id,
            bet_nonce: bet_record.nonce,
            reward_amount: bet_record.amount, // Remboursement complet
        };

        let future: Future = claim_refund_finalize(
            bet_record.market_id,
            bet_record.amount,
            bet_record.nonce
        );

        return (refund_receipt, future);
    }

    async function claim_refund_finalize(market_id: field, bet_amount: u64, bet_nonce: field) {
        let market: Market = Mapping::get(markets, market_id);
        
        // Seuls les marchés annulés permettent les remboursements
        assert(market.status == STATUS_CANCELED);
        
        // Vérifier que le pari n'a pas déjà été réclamé
        let is_claimed: bool = Mapping::get_or_use(claimed_bets, bet_nonce, false);
        assert(!is_claimed);

        // Marquer le pari comme réclamé
        Mapping::set(claimed_bets, bet_nonce, true);
    }
    
    // Fonction pour révéler les résultats d'un marché (transparence)
    async transition reveal_market_results(market_id: field) -> Future {
        let future: Future = reveal_market_results_finalize(market_id);
        return future;
    }

    async function reveal_market_results_finalize(market_id: field) {
        let market: Market = Mapping::get(markets, market_id);
        // Cette fonction permet de rendre publiques les informations du marché
        // Les pools et résultats sont déjà stockés dans le mapping public
    }
    
    // Fonction pour que l'admin puisse retirer ses frais (optionnelle)
    async transition withdraw_admin_fees(amount: u64) -> Future {
        assert(self.caller == ADMIN);
        let future: Future = withdraw_admin_fees_finalize(amount);
        return future;
    }

    async function withdraw_admin_fees_finalize(amount: u64) {
        let current_fees: u64 = Mapping::get(admin_fees, ADMIN);
        assert(current_fees >= amount);
        
        let remaining_fees: u64 = current_fees - amount;
        Mapping::set(admin_fees, ADMIN, remaining_fees);
    }
    
    // Fonction pour lister les marchés ouverts (aide à la découverte)
    async transition list_open_markets() -> Future {
        let future: Future = list_open_markets_finalize();
        return future;
    }

    async function list_open_markets_finalize() {
        // Cette fonction permet d'accéder au mapping open_markets
        // pour lister les marchés disponibles (limité à 100)
        let market_count_value: u8 = Mapping::get_or_use(market_count, true, 0u8);
        // Les IDs des marchés ouverts sont stockés dans open_markets[0] à open_markets[market_count_value-1]
    }
    
}