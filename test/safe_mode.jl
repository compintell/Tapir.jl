@testset "safety" begin

    # Forwards-pass tests.
    x = (CoDual(sin, NoTangent()), CoDual(5.0, NoFData()))
    @test_throws(ErrorException, Mooncake.SafeRRule(rrule!!)(x...))
    x = (CoDual(sin, NoFData()), CoDual(5.0, NoFData()))
    @test_throws(
        ErrorException, Mooncake.SafeRRule((x..., ) -> (CoDual(1.0, 0.0), nothing))(x...)
    )

    # Basic type checking.
    x = (CoDual(size, NoFData()), CoDual(randn(10), randn(Float16, 11)))
    @test_throws ErrorException Mooncake.SafeRRule(rrule!!)(x...)

    # Element type checking. Abstractly typed-elements prevent determining incorrectness
    # just by looking at the array.
    x = (
        CoDual(size, NoFData()),
        CoDual(Any[rand() for _ in 1:10], Any[rand(Float16) for _ in 1:10])
    )
    @test_throws ErrorException Mooncake.SafeRRule(rrule!!)(x...)

    # Test that bad rdata is caught as a pre-condition.
    y, pb!! = Mooncake.SafeRRule(rrule!!)(zero_fcodual(sin), zero_fcodual(5.0))
    @test_throws(InvalidRDataException, pb!!(5))

    # Test that bad rdata is caught as a post-condition.
    rule_with_bad_pb(x::CoDual{Float64}) = x, dy -> (5, ) # returns the wrong type
    y, pb!! = Mooncake.SafeRRule(rule_with_bad_pb)(zero_fcodual(5.0))
    @test_throws InvalidRDataException pb!!(1.0)

    # Test that bad rdata is caught as a post-condition.
    rule_with_bad_pb_length(x::CoDual{Float64}) = x, dy -> (5, 5.0) # returns the wrong type
    y, pb!! = Mooncake.SafeRRule(rule_with_bad_pb_length)(zero_fcodual(5.0))
    @test_throws ErrorException pb!!(1.0)
end
