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
            Foo(_, _) where (foo(1) && foo(2)) => 15
            Foo(_, _) where foo(7) =>
                begin
                    if foo(9)
                        @match_return 16
                    end
                    17
                end
            Foo(_, _) where (foo(1) && foo(3)) => 18
            _ => 43
        end
    end
end

@testset "@match_fail and @match_return are lifted correctly into guard" begin
    @test begin
        2 == @match Foo(1,2) begin
            Foo(x, y) => @match_fail
            Foo(x, y) => @match_return 2
        end
    end
end

@testset "@match_fail is lifted correctly into guard" begin
    @test begin
        2 == @match Foo(1,2) begin
            Foo(x, y) => @match_fail
            Foo(x, y) => @match_return 2
        end
    end
end

#===
@testset "match_fail huge" begin

    foo(x) = x == 9

    input_val = Appl(RelVar(:x), [Constant(1, Annos()), Constant(2, Annos())], Annos())

    @test begin

    43 == @match input_val begin

        Appl(e, args, _) where (
            foo(1) &&
            foo(2)
        ) => begin
            foo(3) && &match_fail
            1
        end

        Appl(left, args, annos) where foo(1) =>
            begin
                2
            end

        Appl(base, xs, as) where Base.any(x -> x isa UnderscoreVararg, xs) =>
            begin
                3
            end

        Appl(e, [], annos) => 4

        Appl(Appl(x, xs, _), ys, annos) => 5

        Appl(CoreAppl(x, xs, _), ys, annos) => 6

        Appl(c::Constant, [e, args...], annos) where (!foo(1)) =>
            begin
                if foo(1)
                    @match_return 7
                end
                8
            end

        Appl(v::ScalarVar, [e, args...], annos) where (!foo(3)) =>
            begin
                if foo(2)
                    @match_return 9
                end
                10
            end

        Appl(RelVar(x), [op, args...], as) where foo(4) =>
            11

        Appl(e, args, annos) where foo(2) =>
            12

        Appl(CoreUnion([], _), _, _) => 13

        Appl(SuchThat(xs, e, f, as1), es, as2) => 14

        Appl(RelVar(x), args, annos) where (
            !foo(1) &&
            !foo(2) &&
            !foo(3) &&
            foo(4)
        ) => 15

        Appl(RelVar(x::RelLiteral), args, as) where (
            !isempty(x.data) &&
            let i = findfirst(arg -> arg isa Constant, args),
                j = findfirst(arg -> !(arg isa Constant), args)
                !isnothing(i) && !isnothing(j) && i < j
            end
        ) =>
            begin
                if baz()
                    @match_return 16
                end
                17
            end

        Appl(x, args, _) where (
            foo(1) &&
            foo(2)
        ) =>
            begin
                18
            end

        Appl(RelVar(x), args, _) where (
            foo(1) &&
            foo(2) &&
            !foo(3) &&
            foo(4)
        ) =>
            begin
                19
            end

        Appl(RelVar(x::Union{NativeId,AnonymousRel}), args, _) where (
            !foo(1) &&
            !foo(2) &&
            foo(3)
        ) =>
            begin
                20
            end

        Appl(RelVar(x::SourceId), args, annos) where (
            !foo(3)
        ) =>
            begin
                if foo(1)
                    foo(4) && @match_fail
                    @match_return 21
                end
                foo(2) || @match_fail
                22
            end

        Appl(e, args, annos) where (
            let nargs = foo(1) ? 1 : missing
                !ismissing(nargs) && nargs < length(args)
            end
        ) =>
            begin
                23
            end

        Appl(RelVar(x::NativeId), args, _) && e where (
            foo(2)
        ) =>
            begin
                24
            end


        Appl(e1::Constant, [e2::Constant], annos) =>
            begin
                25
            end


        Appl(e::RelAbstract, args, annos) where (
            !foo(3)
        ) =>
            begin
                26
            end

        Appl(e && CoreUnion(ambs, as), args, annos) where (
            foo(4)
        ) =>
            begin
                27
            end

        Appl(e && CoreUnion(ambs, _), args, annos) =>
            begin
                28
            end

        Appl(RelAbstract(CoreBindings([x::RelVarDecl, xs...]), f, as1), [e1, es...], as2) where (
            !foo(2) && !foo(1)
        ) =>
            29

        Appl(RelAbstract(CoreBindings([x::ScalarVarDecl, xs...]), f, as1), [e1, es...], as2) where (
            !foo(2) && foo(1)
        ) =>
            30

        Appl(RelAbstract(CoreBindings([x::ScalarVarDecl, xs...]), f, as1), [e1, es...], as2) where (
            !foo(2) && foo(3)
        ) =>
            31

        Appl(RelAbstract(CoreBindings([x::CoreVarDecl, xs...]), f, as1), [e1, es...], as2) where (
            !foo(2) && foo(1)
        ) =>
            32

        Appl(RelAbstract(CoreBindings([x::CoreVarDecl, xs...]), f, as1), [e1, es...], as2) where (
            !foo(1) && foo(3)
        ) =>
            33

        Appl(RelAbstract(CoreBindings([x::ScalarVarDecl, xs...]), _, _) && ra, [e1, es...], as) where (
            !foo(1) && !foo(2)
        ) =>
            begin
                foo(3) && @match_return 34
                foo(4) || @match_fail
                35
            end

        Appl(RelAbstract(CoreBindings([x::CoreVarDecl, xs...]), _, _) && ra, [e1, es...], as) where (
            !foo(1) && !foo(2)
        ) =>
            begin
                foo(3) && @match_return 36
                foo(4) || @match_fail
                37
            end

        Appl(CoreRelAbstract([x::CoreVarDecl, xs...], f, as1), [e1, es...], as2) where (
            !foo(1) && foo(3)
        ) =>
            38

        Appl(CoreRelAbstract([x::CoreVarDecl, xs...], f, as1), [e1, es...], as2) where (
            !foo(1) && foo(3)
        ) =>
            39

        Appl(CoreRelAbstract([x::CoreVarDecl, xs...], _, _) && ra, [e1, es...], as) where (
            !foo(2) && !foo(3)
        ) =>
            begin
                foo(4) && @match_return 40
                foo(1) || @match_fail
                41
            end

        Appl(RelVar(x::NativeId), args, annos) where foo(x) =>
            42

        _ => 43
    end
    end
end

==#


end
