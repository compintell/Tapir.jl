@testset "diff_tests" begin
    @testset "$f, $(_typeof(x))" for (n, (interface_only, f, x...)) in enumerate(vcat(
        TestResources.DIFFTESTS_FUNCTIONS[1:31], # SKIPPING SPARSE_LDIV mat2num_4 and softmax due to `_apply_iterate` handling
        TestResources.DIFFTESTS_FUNCTIONS[34:66], # SKIPPING SPARSE_LDIV
        TestResources.DIFFTESTS_FUNCTIONS[68:89], # SKIPPING SPARSE_LDIV
        TestResources.DIFFTESTS_FUNCTIONS[91:end], # SKIPPING SPARSE_LDIV
    ))
        @info "$n: $(_typeof((f, x...)))"
        test_rule(sr(123456), f, x...; interface_only=false, is_primitive=false)
    end
end
