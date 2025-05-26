program prediction_market.aleo;

record BetRecord:
    owner as address.private;
    market_id as field.private;
    chosen_option as u8.private;
    amount as u64.private;
    nonce as field.private;

record MarketReceipt:
    owner as address.private;
    market_id as field.private;
    creation_fee_paid as u64.private;

struct Market:
    id as field;
    creator as address;
    question as field;
    options as [field; 5u32];
    num_options as u8;
    closing_block as u32;
    status as u8;
    winning_option as u8;
    total_pool as u64;
    option_pools as [u64; 5u32];

mapping markets:
    key as field.public;
    value as Market.public;

mapping admin_fees:
    key as address.public;
    value as u64.public;

mapping claimed_bets:
    key as field.public;
    value as boolean.public;

mapping open_markets:
    key as u8.public;
    value as field.public;

mapping market_count:
    key as boolean.public;
    value as u8.public;

function create_market:
    input r0 as field.private;
    input r1 as field.private;
    input r2 as [field; 5u32].private;
    input r3 as u8.private;
    input r4 as u32.private;
    input r5 as u64.public;
    gte r5 3000000u64 into r6;
    assert.eq r6 true;
    gte r3 2u8 into r7;
    assert.eq r7 true;
    lte r3 5u8 into r8;
    assert.eq r8 true;
    gt r4 0u32 into r9;
    assert.eq r9 true;
    lte r4 365u32 into r10;
    assert.eq r10 true;
    mul r4 86400u32 into r11;
    cast self.caller r0 3000000u64 into r12 as MarketReceipt.record;
    async create_market r0 r1 r2 r3 r11 self.caller into r13;
    output r12 as MarketReceipt.record;
    output r13 as prediction_market.aleo/create_market.future;

finalize create_market:
    input r0 as field.public;
    input r1 as field.public;
    input r2 as [field; 5u32].public;
    input r3 as u8.public;
    input r4 as u32.public;
    input r5 as address.public;
    add block.height r4 into r6;
    cast 0u64 0u64 0u64 0u64 0u64 into r7 as [u64; 5u32];
    cast r0 r5 r1 r2 r3 r6 0u8 0u8 0u64 r7 into r8 as Market;
    set r8 into markets[r0];
    get.or_use admin_fees[aleo12l0r3y89h30ts35d68mzf0ak35zepxw58gns2t4607a8a3jy65qs9gxuuj] 0u64 into r9;
    add r9 3000000u64 into r10;
    set r10 into admin_fees[aleo12l0r3y89h30ts35d68mzf0ak35zepxw58gns2t4607a8a3jy65qs9gxuuj];
    get.or_use market_count[true] 0u8 into r11;
    lt r11 100u8 into r12;
    branch.eq r12 false to end_then_0_0;
    set r0 into open_markets[r11];
    add r11 1u8 into r13;
    set r13 into market_count[true];
    branch.eq true true to end_otherwise_0_1;
    position end_then_0_0;
    position end_otherwise_0_1;

function place_bet:
    input r0 as field.private;
    input r1 as u8.private;
    input r2 as u64.private;
    input r3 as field.private;
    gte r2 3000000u64 into r4;
    assert.eq r4 true;
    gte r1 1u8 into r5;
    assert.eq r5 true;
    lte r1 5u8 into r6;
    assert.eq r6 true;
    cast self.caller r0 r1 r2 r3 into r7 as BetRecord.record;
    async place_bet r0 r1 r2 into r8;
    output r7 as BetRecord.record;
    output r8 as prediction_market.aleo/place_bet.future;

finalize place_bet:
    input r0 as field.public;
    input r1 as u8.public;
    input r2 as u64.public;
    get markets[r0] into r3;
    is.eq r3.status 0u8 into r4;
    assert.eq r4 true;
    lt block.height r3.closing_block into r5;
    assert.eq r5 true;
    lte r1 r3.num_options into r6;
    assert.eq r6 true;
    is.eq r1 1u8 into r7;
    is.eq r1 2u8 into r8;
    is.eq r1 3u8 into r9;
    is.eq r1 4u8 into r10;
    is.eq r1 5u8 into r11;
    add r3.option_pools[0u32] r2 into r12;
    ternary r7 r12 r3.option_pools[0u32] into r13;
    add r3.option_pools[1u32] r2 into r14;
    ternary r8 r14 r3.option_pools[1u32] into r15;
    add r3.option_pools[2u32] r2 into r16;
    ternary r9 r16 r3.option_pools[2u32] into r17;
    add r3.option_pools[3u32] r2 into r18;
    ternary r10 r18 r3.option_pools[3u32] into r19;
    add r3.option_pools[4u32] r2 into r20;
    ternary r11 r20 r3.option_pools[4u32] into r21;
    add r3.total_pool r2 into r22;
    cast r13 r15 r17 r19 r21 into r23 as [u64; 5u32];
    cast r3.id r3.creator r3.question r3.options r3.num_options r3.closing_block r3.status r3.winning_option r22 r23 into r24 as Market;
    set r24 into markets[r0];
