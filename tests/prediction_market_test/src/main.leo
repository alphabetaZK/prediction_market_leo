// The 'prediction_market_test' program.
program prediction_market_test.aleo {
    transition main(public a: u32, b: u32) -> u32 {
        let c: u32 = a + b;
        return c;
    }
}
