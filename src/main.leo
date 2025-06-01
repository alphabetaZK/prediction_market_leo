// Aleo Anonymous Prediction Market Platform - Version 2 avec Création Automatique de Tokens
// Team: Ramzy, Salim, Mathieu, Lina, Abdellahi
// Système de prix dynamique inspiré de Polymarket avec intégration token_registry

import token_registry.aleo;
 
program prediction_market_paris_vp.aleo {
    // Constants
    const CREATION_FEE: u64 = 3000000u64;
    const MIN_BET: u64 = 1000000u64; // 1 Aleo minimum
    const MIN_LIQUIDITY: u64 = 1000000u64; // 1 Aleo minimum de liquidité
    const SECONDS_PER_DAY: u32 = 86400u32;
    const MAX_OPEN_MARKETS: u8 = 100u8;
    const MAX_SUPPLY: u128 = 1_000_000_000_000_000u128;
    const PRECISION: u64 = 1000000u64; // Précision pour les calculs (6 décimales)
    const AMM_FEE: u64 = 3000u64; // Frais AMM 0.3% (3000/1000000)
    const ORACLE_FEE: u64 = 1000000u64; // Frais oracle 1 Aleo
    const TOKEN_INITIAL_SUPPLY: u128 = 1000000000000u128; // 1 trillion tokens
    const TOKEN_DECIMALS: u8 = 6u8;

    const STATUS_OPEN: u8 = 0u8;
    const STATUS_CLOSED: u8 = 1u8;
    const STATUS_RESOLVED: u8 = 2u8;
    const STATUS_CANCELED: u8 = 3u8;

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

    struct MarketTokenMetadata {
        market_id: field,
        yes_token_id: field,
        no_token_id: field,
        created_at: u32,
        question_hash: field,
        question_title: field,
    }

    record BetRecord {
        owner: address,
        market_id: field,
        chosen_option: u8, // 1 = YES, 2 = NO
        amount_paid: u64,  // Montant payé en Aleo
        tokens_received: u64, // Tokens reçus
        price_paid: u64,   // Prix payé par token (en microAleo)
        token_id: field,   // ID du token reçu
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
        question_title: field,
    }

    record RewardReceipt {
        owner: address,
        market_id: field,
        bet_nonce: field,
        reward_amount: u64,
        token_id: field,
    }

    record TokenMintReceipt {
        owner: address,
        market_id: field,
        yes_tokens_minted: u128,
        no_tokens_minted: u128,
        yes_token_id: field,
        no_token_id: field,
    }

    mapping markets: field => Market;
    mapping admin_fees: address => u64;
    mapping claimed_bets: field => bool;
    mapping open_markets: u8 => field;
    mapping market_count: bool => u8;
    mapping trade_volume: field => u64; // Volume de trading par marché
    mapping market_tokens: field => MarketTokenMetadata; // Métadonnées des tokens par marché
    mapping token_holders: field => u128; // Balance des tokens par utilisateur

    // Créer un marché avec tokens automatiques et liquidité initiale
    async transition create_market_with_auto_tokens(
        market_id: field,
        question_hash: field,
        question_title: field, // Titre pour nommer les tokens
        initial_yes_price: u64, // Prix initial en microAleo
        initial_liquidity: u64, // Liquidité initiale en Aleo
        duration_days: u32,
        public fee_payment: u64
    ) -> (MarketReceipt, Future) {
        assert(fee_payment >= CREATION_FEE);
        assert(duration_days > 0u32);
        assert(duration_days <= 365u32);
        assert(initial_yes_price > 0u64 && initial_yes_price < PRECISION);
        assert(initial_liquidity >= 10000000u64); // Minimum 10 Aleo de liquidité

        // Générer des IDs uniques pour les tokens basés sur market_id
        let yes_token_id: field = BHP256::hash_to_field(market_id + 1000field);
        let no_token_id: field = BHP256::hash_to_field(market_id + 2000field);
        
        let initial_no_price: u64 = PRECISION - initial_yes_price;
        let duration_secs: u32 = duration_days * SECONDS_PER_DAY;

        let market_receipt: MarketReceipt = MarketReceipt {
            owner: self.signer,
            market_id: market_id,
            yes_token_id: yes_token_id,
            no_token_id: no_token_id,
            initial_yes_price: initial_yes_price,
            initial_no_price: initial_no_price,
            creation_fee_paid: CREATION_FEE,
            question_title: question_title,
        };

        let future: Future = create_market_tokens_finalize(
            market_id,
            question_hash,
            question_title,
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

    async function create_market_tokens_finalize(
        market_id: field,
        question_hash: field,
        question_title: field,
        yes_token_id: field,
        no_token_id: field,
        initial_yes_price: u64,
        initial_no_price: u64,
        initial_liquidity: u64,
        duration_secs: u32,
        caller: address
    ) {
        let closing_block: u32 = block.height + duration_secs;

        // Créer les noms et symboles des tokens
        let yes_symbol: field = BHP256::hash_to_field(question_title + 100field);
        let yes_name: field = BHP256::hash_to_field(question_title + 200field);
        let no_symbol: field = BHP256::hash_to_field(question_title + 300field);  
        let no_name: field = BHP256::hash_to_field(question_title + 400field);

        // Calculer les réserves initiales pour l'AMM
        let yes_reserve: u64 = (initial_liquidity * PRECISION) / initial_yes_price;
        let no_reserve: u64 = (initial_liquidity * PRECISION) / initial_no_price;

        // Créer le marché
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

        // Stocker les métadonnées des tokens
        let token_metadata: MarketTokenMetadata = MarketTokenMetadata {
            market_id: market_id,
            yes_token_id: yes_token_id,
            no_token_id: no_token_id,
            created_at: block.height,
            question_hash: question_hash,
            question_title: question_title,
        };

        // Sauvegarder dans les mappings
        Mapping::set(markets, market_id, new_market);
        Mapping::set(market_tokens, market_id, token_metadata);
        Mapping::set(trade_volume, market_id, 0u64);

        // Mint automatique pour le créateur du marché
        let mint_amount: u128 = 100000u128; // Tu peux changer la quantité ici
        let yes_key: field = BHP256::hash_to_field(caller as field + yes_token_id);
        let no_key: field = BHP256::hash_to_field(caller as field + no_token_id);

        let current_yes_balance: u128 = Mapping::get_or_use(token_holders, yes_key, 0u128);
        let current_no_balance: u128 = Mapping::get_or_use(token_holders, no_key, 0u128);

        Mapping::set(token_holders, yes_key, current_yes_balance + mint_amount);
        Mapping::set(token_holders, no_key, current_no_balance + mint_amount);

        //  Frais d'administration
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
    // Acheter des tokens avec prix dynamique (intégrant les tokens automatiques)
    async transition buy_prediction_tokens(
        market_id: field,
        chosen_option: u8, // 1 = YES, 2 = NO
        aleo_amount: u64,  // Montant en Aleo à dépenser
        min_tokens_expected: u64, // Protection contre slippage
        nonce: field
    ) -> (BetRecord, Future) {
        // Vérifications de base
        assert(aleo_amount >= MIN_BET);
        assert(chosen_option == 1u8 || chosen_option == 2u8);

        let bet_record: BetRecord = BetRecord {
            owner: self.signer,
            market_id: market_id,
            chosen_option: chosen_option,
            amount_paid: aleo_amount,
            tokens_received: 0u64, // Sera calculé dans finalize
            price_paid: 0u64,      // Sera calculé dans finalize
            token_id: 0field,      // Sera rempli dans finalize
            nonce: nonce,
        };

        let future: Future = buy_prediction_tokens_finalize(
            market_id,
            chosen_option,
            aleo_amount,
            min_tokens_expected,
            self.signer
        );

        return (bet_record, future);
    }

    async function buy_prediction_tokens_finalize(
        market_id: field,
        chosen_option: u8,
        aleo_amount: u64,
        min_tokens_expected: u64,
        buyer: address
    ) {
        // Vérifications de base
        let market: Market = Mapping::get(markets, market_id);
        let token_metadata: MarketTokenMetadata = Mapping::get(market_tokens, market_id);
        
        assert(market.status == STATUS_OPEN);
        assert(block.height < market.closing_block);
        assert(market.yes_reserve > MIN_LIQUIDITY);
        assert(market.no_reserve > MIN_LIQUIDITY);
        assert(aleo_amount >= MIN_BET);

        // Calcul des frais
        let fee_amount: u64 = (aleo_amount * AMM_FEE) / PRECISION;
        let net_amount: u64 = aleo_amount - fee_amount;
        assert(net_amount > 0u64);
        assert(net_amount >= MIN_BET / 2u64);

        // Calcul de k
        let k: u64 = market.yes_reserve * market.no_reserve;
        assert(k > 0u64);

        // Vérification des dénominateurs pour éviter division par zéro
        let denominator_yes: u64 = market.no_reserve + net_amount;
        let denominator_no: u64 = market.yes_reserve + net_amount;
        assert(denominator_yes > 0u64);
        assert(denominator_no > 0u64);

        // Calcul des nouvelles réserves avec vérifications
        let new_yes_reserve: u64 = chosen_option == 1u8 ? 
            market.yes_reserve + net_amount : 
            k / denominator_yes;
        let new_no_reserve: u64 = chosen_option == 1u8 ? 
            k / new_yes_reserve : 
            market.no_reserve + net_amount;

        // Vérifications strictes des nouvelles réserves
        assert(new_yes_reserve > MIN_LIQUIDITY);
        assert(new_no_reserve > MIN_LIQUIDITY);
        assert(new_yes_reserve > market.yes_reserve || new_no_reserve > market.no_reserve);

        // Vérification que k reste constant
        let k_after_trade: u64 = new_yes_reserve * new_no_reserve;
        assert(k_after_trade >= k - PRECISION);
        assert(k_after_trade <= k + PRECISION);

        // Calcul des tokens à recevoir avec vérification
        let tokens_to_buy: u64 = chosen_option == 1u8 ? 
            market.no_reserve - new_no_reserve :
            market.yes_reserve - new_yes_reserve;

        // Vérifications strictes du montant de tokens
        assert(tokens_to_buy > 0u64);
        assert(tokens_to_buy >= min_tokens_expected);
        assert(tokens_to_buy >= MIN_BET / 2u64); // Minimum de tokens à recevoir

        // Vérification de k avec marge de sécurité
        let new_k: u64 = new_yes_reserve * new_no_reserve;
        assert(new_k >= k - PRECISION);
        assert(new_k <= k + PRECISION);

        // Vérification du prix effectif
        let effective_price: u64 = (net_amount * PRECISION) / tokens_to_buy;
        assert(effective_price > 0u64);
        assert(effective_price <= PRECISION);

        // Mise à jour des balances et du marché
        let purchased_token_id: field = chosen_option == 1u8 ? 
            token_metadata.yes_token_id : 
            token_metadata.no_token_id;

        let balance_key: field = BHP256::hash_to_field(buyer as field + purchased_token_id);
        let current_balance: u128 = Mapping::get_or_use(token_holders, balance_key, 0u128);
        let new_balance: u128 = current_balance + (tokens_to_buy as u128);
        assert(new_balance > current_balance);
        Mapping::set(token_holders, balance_key, new_balance);

        // Mise à jour du marché
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
            last_yes_price: chosen_option == 1u8 ? 
                (new_yes_reserve * PRECISION) / (new_yes_reserve + new_no_reserve) : 
                market.last_yes_price,
            last_no_price: chosen_option == 2u8 ? 
                (new_no_reserve * PRECISION) / (new_yes_reserve + new_no_reserve) : 
                market.last_no_price,
            trade_count: market.trade_count + 1u32,
        };

        Mapping::set(markets, market_id, updated_market);

        // Mise à jour du volume
        let current_volume: u64 = Mapping::get_or_use(trade_volume, market_id, 0u64);
        let new_volume: u64 = current_volume + aleo_amount;
        assert(new_volume > current_volume);
        Mapping::set(trade_volume, market_id, new_volume);

        // Mise à jour des frais admin
        let current_admin_fees: u64 = Mapping::get_or_use(admin_fees, ADMIN, 0u64);
        let new_admin_fees: u64 = current_admin_fees + fee_amount;
        assert(new_admin_fees > current_admin_fees);
        Mapping::set(admin_fees, ADMIN, new_admin_fees);
    }

   
    // Vendre des tokens prediction
    async transition sell_prediction_tokens(
        market_id: field,
        chosen_option: u8,
        tokens_to_sell: u64,
        min_aleo_expected: u64,
        nonce: field
    ) -> (BetRecord, Future) {
        // Vérifications de base
        assert(tokens_to_sell > 0u64);
        assert(chosen_option == 1u8 || chosen_option == 2u8);

        let sell_record: BetRecord = BetRecord {
            owner: self.signer,
            market_id: market_id,
            chosen_option: chosen_option,
            amount_paid: 0u64, // Vente
            tokens_received: tokens_to_sell,
            price_paid: 0u64, // Prix de vente
            token_id: 0field, // Sera rempli
            nonce: nonce,
        };

        let future: Future = sell_prediction_tokens_finalize(
            market_id,
            chosen_option,
            tokens_to_sell,
            min_aleo_expected,
            self.signer
        );

        return (sell_record, future);
    }

    async function sell_prediction_tokens_finalize(
        market_id: field,
        chosen_option: u8,
        tokens_to_sell: u64,
        min_aleo_expected: u64,
        seller: address
    ) {
        // Vérifications de base
        let market: Market = Mapping::get(markets, market_id);
        let token_metadata: MarketTokenMetadata = Mapping::get(market_tokens, market_id);
        
        assert(market.status == STATUS_OPEN);
        assert(block.height < market.closing_block);
        assert(market.yes_reserve > MIN_LIQUIDITY);
        assert(market.no_reserve > MIN_LIQUIDITY);
        assert(tokens_to_sell >= MIN_BET / 2u64);

        // Vérification que les tokens à vendre ne dépassent pas les réserves
        assert(tokens_to_sell < market.yes_reserve);
        assert(tokens_to_sell < market.no_reserve);

        // Vérification du solde
        let sold_token_id: field = chosen_option == 1u8 ? 
            token_metadata.yes_token_id : 
            token_metadata.no_token_id;
        let balance_key: field = BHP256::hash_to_field(seller as field + sold_token_id);
        let current_balance: u128 = Mapping::get(token_holders, balance_key);
        assert(current_balance >= tokens_to_sell as u128);
        assert(current_balance > 0u128);

        // Calcul de k
        let k: u64 = market.yes_reserve * market.no_reserve;
        assert(k > 0u64);

        // Vérification des dénominateurs pour éviter division par zéro
        let denominator_yes: u64 = market.yes_reserve - tokens_to_sell;
        let denominator_no: u64 = market.no_reserve - tokens_to_sell;
        assert(denominator_yes > MIN_LIQUIDITY);
        assert(denominator_no > MIN_LIQUIDITY);

        // Calcul des nouvelles réserves avec vérifications
        let new_yes_reserve: u64 = chosen_option == 1u8 ? 
            denominator_yes : 
            k / denominator_no;
        let new_no_reserve: u64 = chosen_option == 1u8 ? 
            k / new_yes_reserve : 
            denominator_no;

        // Vérifications strictes des nouvelles réserves
        assert(new_yes_reserve > MIN_LIQUIDITY);
        assert(new_no_reserve > MIN_LIQUIDITY);
        assert(new_yes_reserve < market.yes_reserve || new_no_reserve < market.no_reserve);

        // Calcul de l'Aleo reçu avec vérification
        let aleo_received: u64 = chosen_option == 1u8 ? 
            new_no_reserve - market.no_reserve :
            new_yes_reserve - market.yes_reserve;

        // Vérifications strictes de l'Aleo reçu
        assert(aleo_received > 0u64);
        assert(aleo_received >= MIN_BET / 2u64); // Minimum d'Aleo à recevoir

        // Application des frais avec vérification
        let fee_amount: u64 = (aleo_received * AMM_FEE) / PRECISION;
        let net_aleo_received: u64 = aleo_received - fee_amount;
        assert(net_aleo_received > 0u64);
        assert(net_aleo_received >= MIN_BET / 2u64); // Minimum après frais

        // Vérification du slippage
        assert(net_aleo_received >= min_aleo_expected);

        // Vérification de k avec marge de sécurité
        let new_k: u64 = new_yes_reserve * new_no_reserve;
        assert(new_k >= k - PRECISION);
        assert(new_k <= k + PRECISION);

        // Vérification du prix effectif
        let effective_price: u64 = (net_aleo_received * PRECISION) / tokens_to_sell;
        assert(effective_price > 0u64);
        assert(effective_price <= PRECISION);

        // Mise à jour des balances avec vérification
        let new_balance: u128 = current_balance - (tokens_to_sell as u128);
        assert(new_balance < current_balance);
        assert(new_balance >= 0u128);
        Mapping::set(token_holders, balance_key, new_balance);

        // Mise à jour du marché
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
            last_yes_price: chosen_option == 1u8 ? 
                (new_yes_reserve * PRECISION) / (new_yes_reserve + new_no_reserve) : 
                market.last_yes_price,
            last_no_price: chosen_option == 2u8 ? 
                (new_no_reserve * PRECISION) / (new_yes_reserve + new_no_reserve) : 
                market.last_no_price,
            trade_count: market.trade_count + 1u32,
        };

        Mapping::set(markets, market_id, updated_market);

        // Mise à jour du volume avec vérification
        let current_volume: u64 = Mapping::get_or_use(trade_volume, market_id, 0u64);
        let new_volume: u64 = current_volume + net_aleo_received;
        assert(new_volume > current_volume);
        Mapping::set(trade_volume, market_id, new_volume);

        // Mise à jour des frais admin avec vérification
        let current_admin_fees: u64 = Mapping::get_or_use(admin_fees, ADMIN, 0u64);
        let new_admin_fees: u64 = current_admin_fees + fee_amount;
        assert(new_admin_fees > current_admin_fees);
        Mapping::set(admin_fees, ADMIN, new_admin_fees);
    }

    // Résoudre le marché et gérer les tokens
    async transition resolve_market_with_tokens(
        market_id: field,
        winning_option: u8, // 1 pour YES, 2 pour NO
        public oracle_fee: u64
    ) -> Future {
        assert(self.caller == ADMIN);
        assert(oracle_fee >= ORACLE_FEE);
        assert(winning_option == 1u8 || winning_option == 2u8);
        
        let future: Future = resolve_market_tokens_finalize(
            market_id, 
            winning_option
        );
        return future;
    }

    async function resolve_market_tokens_finalize(
        market_id: field,
        winning_option: u8
    ) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);
        assert(block.height >= market.closing_block);
        
        // Résoudre le marché
        let resolved_market: Market = Market {
            id: market.id,
            creator: market.creator,
            question: market.question,
            yes_token_id: market.yes_token_id,
            no_token_id: market.no_token_id,
            closing_block: market.closing_block,
            status: STATUS_RESOLVED,
            winning_option: winning_option,
            yes_reserve: market.yes_reserve,
            no_reserve: market.no_reserve,
            total_liquidity: market.total_liquidity,
            last_yes_price: market.last_yes_price,
            last_no_price: market.last_no_price,
            trade_count: market.trade_count,
        };
        
        Mapping::set(markets, market_id, resolved_market);
    }

    // Réclamer les gains avec les tokens
    async transition claim_token_winnings(
        market_id: field,
        token_amount: u128
    ) -> (RewardReceipt, Future) {
        let reward_receipt: RewardReceipt = RewardReceipt {
            owner: self.signer,
            market_id: market_id,
            bet_nonce: 0field,
            reward_amount: 0u64, // Sera calculé
            token_id: 0field,    // Sera rempli
        };

        let future: Future = claim_token_winnings_finalize(
            market_id,
            token_amount,
            self.signer
        );

        return (reward_receipt, future);
    }

    async function claim_token_winnings_finalize(
        market_id: field,
        token_amount: u128,
        claimer: address
    ) {
        let market: Market = Mapping::get(markets, market_id);
        let token_metadata: MarketTokenMetadata = Mapping::get(market_tokens, market_id);
        
        assert(market.status == STATUS_RESOLVED);
        
        // Déterminer le token gagnant
        let winning_token_id: field = market.winning_option == 1u8 ? 
            token_metadata.yes_token_id : token_metadata.no_token_id;
            
        // Vérifier que le claimer a les tokens gagnants
        let balance_key: field = BHP256::hash_to_field(claimer as field + winning_token_id);
        let token_balance: u128 = Mapping::get(token_holders, balance_key);
        assert(token_balance >= token_amount);
        
        // Burn les tokens utilisés pour claim
        Mapping::set(token_holders, balance_key, token_balance - token_amount);
        
        // Les tokens gagnants valent 1 Aleo chacun
        // La récompense serait transférée ici
    }

    // Obtenir un devis de prix
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
    }

    // Fermer le marché (fonction legacy maintenue pour compatibilité)
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

        // Obtenir le nombre de marchés ouverts
    async transition get_open_market_count() -> Future {
        let future: Future = get_open_market_count_finalize();
        return future;
    }

    async function get_open_market_count_finalize() {
        let count: u8 = Mapping::get_or_use(market_count, true, 0u8);
    }

    // Obtenir l'ID d'un marché à un index donné
    async transition get_market_id_at_index(index: u8) -> Future {
        let future: Future = get_market_id_at_index_finalize(index);
        return future;
    }

    async function get_market_id_at_index_finalize(index: u8) {
        let market_id: field = Mapping::get(open_markets, index);
    }

    // Obtenir les détails complets d'un marché
    async transition get_market_details(market_id: field) -> Future {
        let future: Future = get_market_details_finalize(market_id);
        return future;
    }

    async function get_market_details_finalize(market_id: field) {
        let market: Market = Mapping::get(markets, market_id);
        let token_metadata: MarketTokenMetadata = Mapping::get(market_tokens, market_id);
        let volume: u64 = Mapping::get_or_use(trade_volume, market_id, 0u64);
        
        // Vérifier que le marché est ouvert et actif
        assert(market.status == STATUS_OPEN);
        assert(block.height < market.closing_block);
    }

    // Vérifier si un marché est encore actif
    async transition is_market_still_active(market_id: field) -> Future {
        let future: Future = is_market_still_active_finalize(market_id);
        return future;
    }

    async function is_market_still_active_finalize(market_id: field) {
        let market: Market = Mapping::get(markets, market_id);
        let is_active: bool = market.status == STATUS_OPEN && block.height < market.closing_block;
    }

    // Obtenir les prix actuels d'un marché
    async transition get_current_prices(market_id: field) -> Future {
        let future: Future = get_current_prices_finalize(market_id);
        return future;
    }

    async function get_current_prices_finalize(market_id: field) {
        let market: Market = Mapping::get(markets, market_id);
        assert(market.status == STATUS_OPEN);
    }
}