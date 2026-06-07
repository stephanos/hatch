#[test]
fn cli_snapshots() {
    trycmd::TestCases::new().case("tests/cmd/*.trycmd");
}
