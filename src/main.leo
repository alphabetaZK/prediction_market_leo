// Aleo Anonymous Prediction Market Platform - Version 1 avec AMM Dynamique
// Team: Ramzy, Salim, Mathieu, Lina, Abdellahi
// Système de prix dynamique inspiré de Polymarket

import token_registry.aleo;

program prediction_market_paris_v1.aleo {
    // Constants
    const CREATION_FEE: u64 = 3000000u64;
    const MIN_BET: u64 = 1000000u64; // 1 Aleo minimum
    const SECONDS_PER_DAY: u32 = 86400u32;
    const MAX_OPEN_MARKETS: u8 = 100u8;
    const MAX_SUPPLY: u128 = 1_000_000_000_000_000u128;
    const PRECISION: u64 = 1000000u64; // Précision pour les calculs (6 décimales)
    const AMM_FEE: u64 = 3000u64; // Frais AMM 0.3% (3000/1000000)

    const STATUS_OPEN: u8 = 0u8;
    const STATUS_CLOSED: u8 = 1u8;
    const STATUS_CANCELED: u8 = 2u8;
    const STATUS_INVALID: u8 = 3u8;

    const ADMIN: address = aleo12l0r3y89h30ts35d68mzf0ak35zepxw58gns2t4607a8a3jy65qs9gxuuj;

    struct Market {
        id: field,
        creator: address,
        question: field,
        yes_token_id: field,
        no_token_id: field,
        closing_block: u32,
        status: u8,
        winning_option: u8, // 1 = YES, 2 = NO
        // Réserves pour l'AMM (Automated Market Maker)
        yes_reserve: u64,    // Réserve de tokens YES
        no_reserve: u64,     // Réserve de tokens NO
        total_liquidity: u64, // Liquidité totale dans le pool
        // Données de prix
        last_yes_price: u64, // Dernier prix YES (en microAleo, 1 Aleo = 1000000)
        last_no_price: u64,  // Dernier prix NO
        trade_count: u32,    // Nombre de trades pour statistiques
    }

    record BetRecord {
        owner: address,
        market_id: field,
        chosen_option: u8, // 1 = YES, 2 = NO
        amount_paid: u64,  // Montant payé en Aleo
        tokens_received: u64, // Tokens reçus
        price_paid: u64,   // Prix payé par token (en microAleo)
        nonce: field,
    }

    record MarketReceipt {
        owner: address,
        market_id: field,
        yes_token_id: field,
        no_token_id: field,
        initial_yes_price: u64,
        initial_no_price: u64,
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
    mapping trade_volume: field => u64; // Volume de trading par marché

    // Créer un marché avec liquidité initiale et prix de départ
    async transition create_amm_market(
        market_id: field,
        question_hash: field,
        yes_token_id: field,
        no_token_id: field,
        initial_yes_price: u64, // Prix initial en microAleo (ex: 200000 = 0.2 Aleo = 20¢)
        initial_liquidity: u64, // Liquidité initiale en Aleo
        duration_days: u32,
        public fee_payment: u64
    ) -> (MarketReceipt, Future) {
        assert(fee_payment >= CREATION_FEE);
        assert(duration_days > 0u32);
        assert(duration_days <= 365u32);
        assert(initial_yes_price > 0u64 && initial_yes_price < PRECISION); // Prix entre 0 et 1 Aleo
        assert(initial_liquidity >= 10000000u64); // Minimum 10 Aleo de liquidité

        let initial_no_price: u64 = PRECISION - initial_yes_price; // NO = 1 - YES
        let duration_secs: u32 = duration_days * SECONDS_PER_DAY;

        let market_receipt: MarketReceipt = MarketReceipt {
            owner: self.signer,
            market_id: market_id,
            yes_token_id: yes_token_id,
            no_token_id: no_token_id,
            initial_yes_price: initial_yes_price,
            initial_no_price: initial_no_price,
            creation_fee_paid: CREATION_FEE,
        };

        let future: Future = create_amm_finalize(
            market_id,
            question_hash,
            yes_token_id,
            no_token_id,
            initial_yes_price,
            initial_no_price,
            initial_liquidity,
            duration_secs,
            self.signer
        );

        return (market_receipt, future);
    }

    async function create_amm_finalize(
        market_id: field,
        question_hash: field,
        yes_token_id: field,
        no_token_id: field,
        initial_yes_price: u64,
        initial_no_price: u64,
        initial_liquidity: u64,
        duration_secs: u32,
        caller: address
    ) {
        let closing_block: u32 = block.height + duration_secs;

        // Calculer les réserves initiales basées sur la formule x*y=k
        // yes_reserve * no_reserve = constant
        let yes_reserve: u64 = (initial_liquidity * PRECISION) / initial_yes_price;
        let no_reserve: u64 = (initial_liquidity * PRECISION) / initial_no_price;

        let new_market: Market = Market {
            id: market_id,
            creator: caller,
            question: question_hash,
            yes_token_id: yes_token_id,
            no_token_id: no_token_id,
            closing_block: closing_block,
            status: STATUS_OPEN,
            winning_option: 0u8,
            yes_reserve: yes_reserve,
            no_reserve: no_reserve,
            total_liquidity: initial_liquidity,
            last_yes_price: initial_yes_price,
            last_no_price: initial_no_price,
            trade_count: 0u32,
        };

        Mapping::set(markets, market_id, new_market);
        Mapping::set(trade_volume, market_id, 0u64);

        // Gestion des frais d'administration
        let current_fees: u64 = Mapping::get_or_use(admin_fees, ADMIN, 0u64);
        let updated_fees: u64 = current_fees + CREATION_FEE;
        Mapping::set(admin_fees, ADMIN, updated_fees);

        // Mise à jour du compteur de marchés ouverts
        let current_count: u8 = Mapping::get_or_use(market_count, true, 0u8);
        let is_room: bool = current_count < MAX_OPEN_MARKETS;
        if is_room {
            Mapping::set(open_markets, current_count, market_id);
            let new_count: u8 = current_count + 1u8;
            Mapping::set(market_count, true, new_count);
        }
    }

    // Acheter des tokens avec prix dynamique (comme Polymarket)
    async transition buy_dynamic_tokens(
        market_id: field,
        chosen_option: u8, // 1 = YES, 2 = NO
        aleo_amount: u64,  // Montant en Aleo à dépenser
        min_tokens_expected: u64, // Protection contre slippage
        nonce: field
    ) -> (BetRecord, Future) {
        assert(aleo_amount >= MIN_BET);
        assert(chosen_option == 1u8 || chosen_option == 2u8);

        let bet_record: BetRecord = BetRecord {
            owner: self.signer,
            market_id: market_id,
            chosen_option: chosen_option,
            amount_paid: aleo_amount,
            tokens_received: 0u64, // Sera calculé dans finalize
            price_paid: 0u64,      // Sera calculé dans finalize
            nonce: nonce,
        };

        let future: Future = buy_dynamic_finalize(
            market_id,
            chosen_option,
            aleo_amount,
            min_tokens_expected
        );

        return (bet_record, future);
    }

    async function buy_dynamic_finalize(
        market_id: field,
        chosen_option: u8,
        aleo_amount: u64,
        min_tokens_expected: u64
    ) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);
        assert(block.height < market.closing_block);

        // Calculer les frais AMM
        let fee_amount: u64 = (aleo_amount * AMM_FEE) / PRECISION;
        let net_amount: u64 = aleo_amount - fee_amount;

        // Calculer selon la formule AMM x*y=k en utilisant l'opérateur ternaire
        let k: u64 = market.yes_reserve * market.no_reserve;
        
        // Utiliser l'opérateur ternaire pour éviter les réassignations conditionnelles
        let new_yes_reserve: u64 = chosen_option == 1u8 ? 
            market.yes_reserve + net_amount : 
            k / (market.no_reserve + net_amount);
            
        let new_no_reserve: u64 = chosen_option == 1u8 ? 
            k / new_yes_reserve : 
            market.no_reserve + net_amount;
            
        let tokens_to_buy: u64 = chosen_option == 1u8 ? 
            market.no_reserve - new_no_reserve : 
            market.yes_reserve - new_yes_reserve;
            
        let current_price: u64 = net_amount * PRECISION / tokens_to_buy;

        // Protection contre slippage
        assert(tokens_to_buy >= min_tokens_expected);

        // Mettre à jour le marché avec les nouvelles réserves
        let updated_market: Market = Market {
            id: market.id,
            creator: market.creator,
            question: market.question,
            yes_token_id: market.yes_token_id,
            no_token_id: market.no_token_id,
            closing_block: market.closing_block,
            status: market.status,
            winning_option: market.winning_option,
            yes_reserve: new_yes_reserve,
            no_reserve: new_no_reserve,
            total_liquidity: market.total_liquidity + net_amount,
            last_yes_price: chosen_option == 1u8 ? current_price : market.last_yes_price,
            last_no_price: chosen_option == 2u8 ? current_price : market.last_no_price,
            trade_count: market.trade_count + 1u32,
        };

        Mapping::set(markets, market_id, updated_market);

        // Mettre à jour le volume de trading
        let current_volume: u64 = Mapping::get_or_use(trade_volume, market_id, 0u64);
        Mapping::set(trade_volume, market_id, current_volume + aleo_amount);

        // Ajouter les frais aux frais d'administration
        let current_admin_fees: u64 = Mapping::get_or_use(admin_fees, ADMIN, 0u64);
        Mapping::set(admin_fees, ADMIN, current_admin_fees + fee_amount);
    }

    // Obtenir le prix actuel pour une option (simulation)
    async transition get_price_quote(
        market_id: field,
        chosen_option: u8,
        aleo_amount: u64
    ) -> Future {
        let future: Future = get_price_quote_finalize(market_id, chosen_option, aleo_amount);
        return future;
    }

    async function get_price_quote_finalize(
        market_id: field,
        chosen_option: u8,
        aleo_amount: u64
    ) {
        let market: Market = Mapping::get(markets, market_id);
        
        // Simuler l'achat pour obtenir le prix actuel
        let fee_amount: u64 = (aleo_amount * AMM_FEE) / PRECISION;
        let net_amount: u64 = aleo_amount - fee_amount;
        let k: u64 = market.yes_reserve * market.no_reserve;
        
        let estimated_tokens: u64 = chosen_option == 1u8 ? 
            market.no_reserve - (k / (market.yes_reserve + net_amount)) :
            market.yes_reserve - (k / (market.no_reserve + net_amount));
        
        // Le prix par token = net_amount / estimated_tokens
        // Cette information sera disponible via les mappings publics
    }

    // Vendre des tokens (pour ceux qui veulent sortir avant la fin)
    async transition sell_tokens(
        market_id: field,
        chosen_option: u8,
        tokens_to_sell: u64,
        min_aleo_expected: u64,
        nonce: field
    ) -> (BetRecord, Future) {
        assert(tokens_to_sell > 0u64);
        assert(chosen_option == 1u8 || chosen_option == 2u8);

        let sell_record: BetRecord = BetRecord {
            owner: self.signer,
            market_id: market_id,
            chosen_option: chosen_option,
            amount_paid: 0u64, // Vente = montant négatif conceptuellement
            tokens_received: tokens_to_sell,
            price_paid: 0u64, // Sera calculé comme prix de vente
            nonce: nonce,
        };

        let future: Future = sell_tokens_finalize(
            market_id,
            chosen_option,
            tokens_to_sell,
            min_aleo_expected
        );

        return (sell_record, future);
    }

    async function sell_tokens_finalize(
        market_id: field,
        chosen_option: u8,
        tokens_to_sell: u64,
        min_aleo_expected: u64
    ) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);
        assert(block.height < market.closing_block);

        // Calculer combien d'Aleo on récupère en vendant les tokens
        let k: u64 = market.yes_reserve * market.no_reserve;
        
        // Utiliser l'opérateur ternaire pour éviter les réassignations conditionnelles
        let new_yes_reserve: u64 = chosen_option == 1u8 ? 
            k / (market.no_reserve + tokens_to_sell) :
            market.yes_reserve + tokens_to_sell;
            
        let new_no_reserve: u64 = chosen_option == 1u8 ? 
            market.no_reserve + tokens_to_sell :
            k / new_yes_reserve;
            
        let aleo_received: u64 = chosen_option == 1u8 ? 
            market.yes_reserve - new_yes_reserve :
            market.no_reserve - new_no_reserve;

        // Appliquer les frais AMM
        let fee_amount: u64 = (aleo_received * AMM_FEE) / PRECISION;
        let net_aleo_received: u64 = aleo_received - fee_amount;

        // Protection contre slippage
        assert(net_aleo_received >= min_aleo_expected);

        // Mettre à jour le marché
        let updated_market: Market = Market {
            id: market.id,
            creator: market.creator,
            question: market.question,
            yes_token_id: market.yes_token_id,
            no_token_id: market.no_token_id,
            closing_block: market.closing_block,
            status: market.status,
            winning_option: market.winning_option,
            yes_reserve: new_yes_reserve,
            no_reserve: new_no_reserve,
            total_liquidity: market.total_liquidity,
            last_yes_price: market.last_yes_price,
            last_no_price: market.last_no_price,
            trade_count: market.trade_count + 1u32,
        };

        Mapping::set(markets, market_id, updated_market);

        // Ajouter les frais aux frais d'administration
        let current_admin_fees: u64 = Mapping::get_or_use(admin_fees, ADMIN, 0u64);
        Mapping::set(admin_fees, ADMIN, current_admin_fees + fee_amount);
    }

    // Fermer le marché avec le résultat
    async transition close_market_with_winner(market_id: field, winning_option: u8) -> Future {
        assert(self.caller == ADMIN);
        assert(winning_option == 1u8 || winning_option == 2u8);
        let future: Future = close_market_winner(market_id, winning_option);
        return future;
    }

    async function close_market_winner(market_id: field, winning_option: u8) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);
        assert(block.height >= market.closing_block);

        let closed_market: Market = Market {
            id: market.id,
            creator: market.creator,
            question: market.question,
            yes_token_id: market.yes_token_id,
            no_token_id: market.no_token_id,
            closing_block: market.closing_block,
            status: STATUS_CLOSED,
            winning_option: winning_option,
            yes_reserve: market.yes_reserve,
            no_reserve: market.no_reserve,
            total_liquidity: market.total_liquidity,
            last_yes_price: market.last_yes_price,
            last_no_price: market.last_no_price,
            trade_count: market.trade_count,
        };

        Mapping::set(markets, market_id, closed_market);
    }

    // Réclamer les gains
    async transition claim_winnings(bet_record: BetRecord) -> (RewardReceipt, Future) {
        let reward_receipt: RewardReceipt = RewardReceipt {
            owner: bet_record.owner,
            market_id: bet_record.market_id,
            bet_nonce: bet_record.nonce,
            reward_amount: 0u64,
        };

        let future: Future = claim_winnings_finalize(
            bet_record.market_id,
            bet_record.chosen_option,
            bet_record.tokens_received,
            bet_record.nonce,
            bet_record.owner
        );

        return (reward_receipt, future);
    }

    async function claim_winnings_finalize(
        market_id: field,
        chosen_option: u8,
        tokens_owned: u64,
        bet_nonce: field,
        bettor: address
    ) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_CLOSED);
        assert(chosen_option == market.winning_option);

        let is_claimed: bool = Mapping::get_or_use(claimed_bets, bet_nonce, false);
        assert(!is_claimed);

        Mapping::set(claimed_bets, bet_nonce, true);
        
        // Les tokens gagnants valent 1 Aleo chacun
        // Récompense = tokens_owned * 1 Aleo
    }

    // Annuler un marché
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
            yes_token_id: market.yes_token_id,
            no_token_id: market.no_token_id,
            closing_block: market.closing_block,
            status: STATUS_CANCELED,
            winning_option: market.winning_option,
            yes_reserve: market.yes_reserve,
            no_reserve: market.no_reserve,
            total_liquidity: market.total_liquidity,
            last_yes_price: market.last_yes_price,
            last_no_price: market.last_no_price,
            trade_count: market.trade_count,
        };

        Mapping::set(markets, market_id, canceled_market);
    }

    // Retirer les frais d'administration
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

    // Lister les marchés ouverts
    async transition list_open_markets() -> Future {
        let future: Future = list_open_markets_finalize();
        return future;
    }

    async function list_open_markets_finalize() {
        let market_count_value: u8 = Mapping::get_or_use(market_count, true, 0u8);
    }
}