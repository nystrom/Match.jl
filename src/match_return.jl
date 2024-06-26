"""
    @match_fail

This statement permits early-exit from the value of a @match case.
The programmer may write the value as a `begin ... end` and then,
within the value, the programmer may write

    @match_fail

to cause the case to terminate as if its pattern had failed.
This permits cases to perform some computation before deciding if the
rule "*really*" matched.
"""
macro match_fail()
    # These are rewritten during expansion of the `@match` macro,
    # so the actual macro should not be used directly.
    error("$(__source__.file):$(__source__.line): @match_fail may only be used within the value of a @match case.")
end

"""
    @match_return value

This statement permits early-exit from the value of a @match case.
The programmer may write the value as a `begin ... end` and then,
within the value, the programmer may write

    @match_return value

to terminate the value expression **early** with success, with the
given value.
"""
macro match_return(x)
    # These are rewritten during expansion of the `@match` macro,
    # so the actual macro should not be used.
    error("$(__source__.file):$(__source__.line): @match_return may only be used within the value of a @match case.")
end

function is_match_return(p::Base.Expr)
    is_expr(p, :macrocall) || return false
    return p.args[1] == :var"@match_return" || p.args[1] == Expr(:., Symbol(string(@__MODULE__)), QuoteNode(:var"@match_return"))
end
is_match_return(p) = false
function is_match_fail(p::Base.Expr)
    is_expr(p, :macrocall) || return false
    return p.args[1] == :var"@match_fail" || p.args[1] == Expr(:., Symbol(string(@__MODULE__)), QuoteNode(:var"@match_fail"))
end
is_match_fail(p) = false
function is_match(p::Base.Expr)
    is_expr(p, :macrocall) || return false
    return p.args[1] == :var"@match" || p.args[1] == Expr(:., Symbol(string(@__MODULE__)), QuoteNode(:var"@match"))
end
is_match(p) = false

#
# We implement @match_fail and @match_return as follows:
#
# Given a case (part of a @match)
#
#    pattern => value
#
# in which the value part contains a use of one of these macros, we create
# two synthetic names: one for a `label`, and one for an intermediate `temp`.
# Then we rewrite `value` into `new_value` by replacing every occurrence of
#
#    @match_return value
#
# with
#
#    begin
#        $temp = $value
#        @goto $label
#    end
#
# and every occurrence of
#
#    @match_fail
#
# With
#
#    @match_return $MatchFailure
#
# And then we replace the whole `pattern => value` with
#
#    pattern where begin
#        $temp = $value'
#        @label $label
#        $tmp !== $MatchFailure
#        end => $temp
#
# Note that we are using the type `MatchFailure` as a sentinel value to indicate that the
# match failed.  Therefore, don't use the @match_fail and @match_return macros for cases
# in which `MatchFailure` is a possible result.
#
function adjust_case_for_return_macro(__module__, location, pattern, result, predeclared_temps)

    # Lift up useless @match_return.
    if is_match_return(result)
        return adjust_case_for_return_macro(
            __module__,
            location,
            pattern,
            Expr(:block, result.args[2:end]...),
            predeclared_temps)
    end

    # Lift up useless @match_fail.
    if is_match_fail(result)
        return adjust_case_for_return_macro(
            __module__,
            location,
            Expr(:where, pattern, false),
            nothing,
            predeclared_temps)
    end

    # Lift @match_fail from the beginning of the body into the guard
    # so we can analyze the guard.
    #
    # p => begin
    #     foo() || @match_fail
    #     e
    # end
    # -->
    # p where foo() => e
    #
    # p => begin
    #     foo() && @match_fail
    #     e
    # end
    # -->
    # p where !foo() => e
    #
    # p => begin
    #     @match_fail
    #     e
    # end
    # -->
    # p where false => e

    if result isa Expr && result.head == :block
        for i in eachindex(result.args)
            arg = result.args[i]
            arg isa LineNumberNode && continue
            arg isa Expr || break

            # Rewrite `if foo; bar end` to `foo && bar`
            if arg.head == :if && length(arg.args) == 2
                arg = Expr(:(&&), arg.args...)
            end

            # Rewrite `@match_fail` to `true && @match_fail`.
            if is_match_fail(arg)
                arg = Expr(:(||), false, arg)
            end

            if arg.head == :(||) || arg.head == :(&&)
                arg.args[end] isa Expr || break
                p = arg.args[end]
                is_match_fail(p) || break

                guards = result.args[1:i-1]
                if length(arg.args) == 2
                    push!(guards, arg.args[1])
                else
                    push!(guards, Expr(arg.head, arg.args[1:end-1]...))
                end

                guard = Expr(:block, guards...)
                if arg.head == :(&&)
                    guard = Expr(:call, :!, guard)
                end

                # Pull the guard up into a `where` clause and try again.
                return adjust_case_for_return_macro(
                    __module__,
                    location,
                    Expr(:where, pattern, guard),
                    Expr(:block, result.args[i+1:end]...),
                    predeclared_temps)
            else
                break
            end
        end
    end

    value = gensym("value")
    found_early_exit::Bool = false
    function adjust_top(p)
        is_expr(p, :macrocall) || return p
        if length(p.args) == 3 && is_match_return(p)
            # :(@match_return e) -> :($value = $e; @break)
            found_early_exit = true
            return Expr(:block, p.args[2], :($value = $(p.args[3])), :(@break))
        elseif length(p.args) == 2 && is_match_fail(p)
            # :(@match_fail) -> :($value = $MatchFaulure; @break)
            found_early_exit = true
            return Expr(:block, p.args[2], :($value = $MatchFailure), :(@break))
        elseif length(p.args) == 4 && is_match(p)
            # Nested uses of @match should be treated as independent
            return macroexpand(__module__, p)
        elseif p.args[1] == Symbol("@break")
            return p
        else
            # It is possible for a macro to expand into @match_fail, so only expand one step.
            return adjust_top(macroexpand(__module__, p; recursive = false))
        end
    end

    rewritten_result = MacroTools.prewalk(adjust_top, result)
    if found_early_exit
        # Since we found an early exit, we need to predeclare the temp to ensure
        # it is in scope both for where it is written and in the constructed where clause.
        push!(predeclared_temps, value)
        where_expr = Expr(:block, location,
            :(Match.@__breakable__ begin $value = $rewritten_result; end),
            :($value !== $MatchFailure))
        new_pattern = :($pattern where $where_expr)
        new_result = value
        (new_pattern, new_result)
    else
        (pattern, rewritten_result)
    end
end
