# Macro used in test below
macro user_match_fail()
    quote
        @match_fail
    end
end

# Macro used in test below
macro user_match_return(e)
    esc(quote
        @match_return($e)
    end)
end

@testset "@match_return tests" begin

@testset "simple uses work correctly" begin
    @test (@match Foo(1, 2) begin
        Foo(x, 2) => begin
            x
            @match_fail
        end
        Foo(1, x) => begin
            @match_return x
            12
        end
    end) == 2
end

file = Symbol(@__FILE__)

@testset "uses of early-exit macros outside @match produce errors 1" begin
    let line = 0
        try
            line = (@__LINE__) + 1
            @eval @match_return 2
            @test false
        catch ex
            @test ex isa LoadError
            e = ex.error
            @test e isa ErrorException
            @test e.msg == "$file:$line: @match_return may only be used within the value of a @match case."
        end
    end
end

@testset "uses of early-exit macros outside @match produce errors 2" begin
    let line = 0
        try
            line = (@__LINE__) + 1
            @eval @match_fail
            @test false
        catch ex
            @test ex isa LoadError
            e = ex.error
            @test e isa ErrorException
            @test e.msg == "$file:$line: @match_fail may only be used within the value of a @match case."
        end
    end
end

@testset "uses of early-exit macros outside @match produce errors 3" begin
    try
        @eval @match_fail nothing
        @test false
    catch ex
        @test ex isa LoadError
        e = ex.error
        @test e isa MethodError # wrong number of arguments to @match_fail
    end
end

@testset "nested uses do not interfere with each other" begin
    @test (@match 1 begin
        1 => begin
            t = @match 1 begin
                1 => begin
                    # yield from inner only
                    @match_return 1
                    error()
                end
            end
            # yield from outer only
            @match_return t + 1
            error()
        end
    end) == 2
end

@testset "a macro may expand to @match_return or @match_fail" begin
    @test (@match Foo(1, 2) begin
        Foo(x, 2) => begin
            x
            @user_match_fail
        end
        Foo(1, x) => begin
            @user_match_return x
            12
        end
    end) == 2
end

@testset "a macro may use the long form 1" begin
    @test (@match Foo(1, 2) begin
        Foo(x, 2) => begin
            x
            Match.@match_fail
        end
        Foo(1, x) => begin
            Match.@match_return x
            12
        end
    end) == 2
end

@testset "a macro may use the long form 2" begin
    @test (@match Foo(1, 2) begin
        Foo(x, 2) => begin
            x
            Match.@match_fail
        end
        Foo(1, x) => begin
            Match.@match_return x
            12
        end
    end) == 2
end

@testset "lift || expressions into guard" begin
    @test (@match Foo(1, 2) begin
        Foo(x, 2) => begin
            x == 1 || @match_fail
            2
        end
        # TODO this should be recognized as a duplicate.
        Foo(x, 2) where (x == 1) => 3
        _ => 4
    end) == 2
end

@testset "lift && expressions into guard" begin
    @test (@match Foo(1, 2) begin
        Foo(x, 2) => begin
            x == 1 && @match_fail
            2
        end
        # TODO this should be recognized as a duplicate.
        Foo(x, 2) where (x == 1) => 3
        _ => 4
    end) == 3
end

@testset "lift if expressions into guard" begin
    @test (@match Foo(1, 2) begin
        Foo(x, 2) => begin
            if x == 1
                @match_fail
            end
            2
        end
        # TODO this should be recognized as a duplicate.
        Foo(x, 2) where (x == 1) => 3
        _ => 4
    end) == 3
end

# This was generating duplicate goto labels.
@testset "do not generate duplicate labels" begin

    foo(x) = x == 9

    @test begin

        43 == @match Foo(1,2) begin

            # Changing this to a simpler condition passes
            Foo(_, _) where (foo(1) && foo(2)) => 15

            Foo(_, _) where foo(7) =>
                begin
                    if foo(9)
                        @match_return 16
                    end
                    17
                end

            # foo(1) fails, foo(2) passes
            # moving this up, passes
            Foo(_, _) where (foo(1) && foo(3)) => 18

            _ => 43
        end
    end
end


end
