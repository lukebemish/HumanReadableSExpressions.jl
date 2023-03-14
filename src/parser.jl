module Parser

import ..Hrse
import ..Literals

import Base: eof, push!

abstract type Token end

struct SimpleToken <: Token
    type::Symbol
    line::Integer
    pos::Integer
end

struct StringToken <: Token
    value::String
    line::Integer
    pos::Integer
end

struct NumberToken <: Token
    value::Number
    line::Integer
    pos::Integer
end

struct CommentToken <: Token
    comment::String
    line::Integer
    pos::Integer
end

struct IndentToken <: Token
    indent::String
    line::Integer
    pos::Integer
end

tokentext(t::SimpleToken) = t.type
tokentext(t::StringToken) = t.value
tokentext(t::NumberToken) = t.value
tokentext(t::CommentToken) = t.comment
tokentext(t::IndentToken) = t.indent

tokenline(t::SimpleToken) = t.line
tokenline(t::StringToken) = t.line
tokenline(t::NumberToken) = t.line
tokenline(t::CommentToken) = t.line
tokenline(t::IndentToken) = t.line

tokenpos(t::SimpleToken) = t.pos
tokenpos(t::StringToken) = t.pos
tokenpos(t::NumberToken) = t.pos
tokenpos(t::CommentToken) = t.pos
tokenpos(t::IndentToken) = t.pos

const STRING = :STRING
const NUMBER = :NUMBER
const COMMENT = :COMMENT

tokentype(t::SimpleToken) = t.type
tokentype(::StringToken) = STRING
tokentype(::NumberToken) = NUMBER
tokentype(::CommentToken) = COMMENT
tokentype(::IndentToken) = INDENT

const LPAREN = :LPAREN
const RPAREN = :RPAREN
const EQUALS = :EQUALS
const DOT = :DOT
const COLON = :COLON

const INDENT = :INDENT

const EOF = :EOF

const TRUE = :TRUE
const FALSE = :FALSE

const S_MODE = :S_MODE
const I_MODE = :I_MODE

struct HrseSyntaxException <: Exception
    msg::String
    line::Integer
    pos::Integer
end

Base.showerror(io::IO, e::HrseSyntaxException) = begin
    print(io, "HrseSyntaxException: ", e.msg, " at line ", e.line, ", column ", e.pos)
end

struct TokenizerContext
    line::Integer
    linetext::String
    io::IO
    posoffset::Integer
    options::Hrse.ReadOptions
end

function addline(line::TokenizerContext)::TokenizerContext
    newline = readline(line.io)
    return TokenizerContext(line.line+1, line.linetext*'\n'*newline, line.io, line.posoffset-length(line)-1, line.options)
end

function eof(line::TokenizerContext)
    return eof(line.io)
end

function tokenize(io::IO, options::Hrse.ReadOptions)
    tokens = Token[]
    linenumber = 0
    while !eof(io)
        line = readline(io)
        linenumber += 1
        if all(isspace(i) for i in line)
            continue # ignore whitespace
        end
        indent = match(r"^\s*", line).match
        push!(tokens, IndentToken(indent, linenumber, 0))
        line = lstrip(line)
        tokenizeline(tokens, TokenizerContext(linenumber, line, io, length(indent), options))
    end
    push!(tokens, SimpleToken(EOF, linenumber+1, 0))
    return tokens
end

function tokenizeline(tokens, ctx::TokenizerContext)
    pos = 1
    newtokens = Token[]
    while pos <= length(ctx.linetext)
        pos, ctx = consumetoken(ctx.linetext, newtokens, pos, ctx)
    end
    push!(tokens, newtokens...)
end

function consumetoken(line, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    remainder = line[pos:end]
    if isspace(line[pos])
        return pos+1, ctx
    elseif line[pos] == ';'
        if length(line) > pos
            comment = lstrip(line[pos+1:end])
            if !isempty(comment) && ctx.options.readcomments
                push!(tokens, CommentToken(comment, ctx.line, pos+ctx.posoffset))
            end 
        end
        return length(line)+1, ctx
    elseif line[pos] == '('
        if length(line) > pos && line[pos+1] == ';'
            return consumecomment(line, tokens, pos+1, ctx)
        end
        push!(tokens, SimpleToken(LPAREN, ctx.line, pos+ctx.posoffset))
        return pos+1, ctx
    elseif line[pos] == ')'
        push!(tokens, SimpleToken(RPAREN, ctx.line, pos+ctx.posoffset))
        return pos+1, ctx
    elseif line[pos] == '='
        push!(tokens, SimpleToken(EQUALS, ctx.line, pos+ctx.posoffset))
        return pos+1, ctx
    elseif (matched = match(Literals.FLOAT_REGEX, remainder)) !== nothing
        text = string(matched.match)
        push!(tokens, NumberToken(Literals.parsefloat(text; type=ctx.options.floattype), ctx.line, pos+ctx.posoffset))
        return pos+length(text), ctx
    elseif (matched = match(Literals.INT_REGEX, remainder)) !== nothing
        text = string(matched.match)
        parsed = Literals.parseint(text; types=ctx.options.integertypes)
        if parsed === nothing
            throw(HrseSyntaxException("Invalid integer literal '$(matched.match)'; may be out of bounds", ctx.line, pos+ctx.posoffset))
        end
        push!(tokens, NumberToken(parsed, ctx.line, pos+ctx.posoffset))
        return pos+length(text), ctx
    elseif line[pos] == '.'
        push!(tokens, SimpleToken(DOT, ctx.line, pos+ctx.posoffset))
        return pos+1, ctx
    elseif line[pos] == ':'
        push!(tokens, SimpleToken(COLON, ctx.line, pos+ctx.posoffset))
        return pos+1, ctx
    elseif line[pos] == '"'
        return consumestring(line, tokens, pos+1, ctx)
    elseif (matched = match(Literals.SYMBOL_REGEX, remainder)) !== nothing
        return consumesymbol(matched, tokens, pos, ctx)
    elseif line[pos] == '#' && (matched = match(Literals.SYMBOL_REGEX, remainder[2:end])) !== nothing
        return consumeliteral(matched, tokens, pos+1, ctx)
    elseif startswith(remainder, "+#inf")
        push!(tokens, NumberToken(ctx.options.floattype(Inf), ctx.line, pos+ctx.posoffset))
        return pos+4, ctx
    elseif startswith(remainder, "-#inf")
        push!(tokens, NumberToken(ctx.options.floattype(-Inf), ctx.line, pos+ctx.posoffset))
        return pos+4, ctx
    else
        throw(HrseSyntaxException("Unexpected character '$(line[1])'", ctx.line, pos+ctx.posoffset))
    end
end

function consumecomment(line, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    pos += 1
    count = 1
    while pos <= length(line) && line[pos] == ';'
        pos += 1
        count += 1
    end
    posorig = pos
    search = Regex("[^;]"*';'^count*"\\)")
    found = findfirst(search, line[pos:end])
    posoffset = ctx.posoffset
    origline = ctx.line
    while isnothing(found) && !eof(ctx)
        pos = length(line)
        ctx = addline(ctx)
        line = ctx.linetext
        found = findfirst(search, line[pos:end])
    end
    if isnothing(found)
        throw(HrseSyntaxException("Unterminated comment", origline, posorig+posoffset))
    end
    comment = line[posorig:pos+found[1]-1]
    push!(tokens, CommentToken(strip(comment), origline, posorig+posoffset))
    return pos+found[end], ctx
end

function consumestring(line, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    posorig = pos
    builder = Char[]
    while pos <= length(line) && line[pos] != '"'
        if line[pos] == '\\'
            pos += 1
            if pos > length(line)
                throw(HrseSyntaxException("Unterminated string", ctx.line, posorig+ctx.posoffset))
            end
            char = line[pos]
            if char == 'n'
                push!(builder, '\n')
                pos += 1
            elseif char == 't'
                push!(builder, '\t')
                pos += 1
            elseif char == 'r'
                push!(builder, '\r')
                pos += 1
            elseif char == 'b'
                push!(builder, '\b')
                pos += 1
            elseif char == 'f'
                push!(builder, '\f')
                pos += 1
            elseif char == 'v'
                push!(builder, '\v')
                pos += 1
            elseif char == 'a'
                push!(builder, '\a')
                pos += 1
            elseif char == 'e'
                push!(builder, '\e')
                pos += 1
            elseif char == '\\'
                push!(builder, '\\')
                pos += 1
            elseif char == '"'
                push!(builder, '"')
                pos += 1
            elseif char == 'u'
                matched = match(r"^[0-9a-fA-F]{1,4}", line[pos+1:end])
                if isnothing(matched)
                    throw(HrseSyntaxException("Invalid escape sequence '\\$(char)'", ctx.line, pos+ctx.posoffset))
                end
                push!(builder, Char(parse(UInt32, matched.match; base=16)))
                pos += length(matched.match)
            elseif char == 'U'
                matched = match(r"^[0-9a-fA-F]{1,8}", line[pos+1:end])
                if isnothing(matched)
                    throw(HrseSyntaxException("Invalid escape sequence '\\$(char)'", ctx.line, pos+ctx.posoffset))
                end
                push!(builder, Char(parse(UInt32, matched.match; base=16)))
                pos += length(matched.match)
            elseif char == 'x'
                matched = match(r"^[0-9a-fA-F]{1,2}", line[pos+1:end])
                if isnothing(matched)
                    throw(HrseSyntaxException("Invalid escape sequence '\\$(char)'", ctx.line, pos+ctx.posoffset))
                end
                push!(builder, Char(parse(UInt8, matched.match; base=16)))
                pos += length(matched.match)
            elseif '0' <= char < '8'
                matched = match(r"^[0-7]{1,3}", line[pos:end])
                push!(builder, Char(parse(UInt8, matched.match; base=8)))
                pos += length(matched.match)-1
            else
                throw(HrseSyntaxException("Invalid escape sequence '\\$(char)'", ctx.line, pos+ctx.posoffset))
            end
        else
            push!(builder, line[pos])
            pos += 1
        end
    end
    if pos > length(line)
        throw(HrseSyntaxException("Unterminated string", ctx.line, posorig+ctx.posoffset))
    end
    push!(tokens, StringToken(String(builder), ctx.line, posorig+ctx.posoffset))
    return pos+1, ctx
end

function consumesymbol(matched, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    text = matched.match
    posorig = pos
    pos = pos+length(text)
    push!(tokens, StringToken(text, ctx.line, posorig+ctx.posoffset))
    return pos, ctx
end

function consumeliteral(matched, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    text = matched.match
    posorig = pos
    pos = pos+length(text)
    if text == "t"
        push!(tokens, SimpleToken(TRUE, ctx.line, posorig+ctx.posoffset))
    elseif text == "f"
        push!(tokens, SimpleToken(FALSE, ctx.line, posorig+ctx.posoffset))
    elseif text == "inf"
        push!(tokens, NumberToken(ctx.options.floattype(Inf), ctx.line, pos+ctx.posoffset))
    elseif text == "nan"
        push!(tokens, NumberToken(ctx.options.floattype(NaN), ctx.line, pos+ctx.posoffset))
    else
        throw(HrseSyntaxException("Invalid hash literal '$(text)'", ctx.line, posorig+ctx.posoffset))
    end
    return pos, ctx
end

mutable struct Tokens
    tokens
    indentlevel
    rootlevel
end

peek(tokens::Tokens) = tokens.tokens[1]
push!(tokens::Tokens, token::Token) = pushfirst!(tokens.tokens, token)
function consume(tokens::Tokens)
    token = popfirst!(tokens.tokens)
    if tokentype(token) == INDENT
        tokens.indentlevel = token
    end
    return token
end

abstract type Expression end

struct DotExpression <: Expression
    left::Expression
    right::Expression
end

struct ListExpression <: Expression
    expressions::Vector{Expression}
end

struct StringExpression <: Expression
    string::String
end

struct BoolExpression <: Expression
    value::Bool
end

struct NumberExpression <: Expression
    value::Number
end

struct CommentExpression <: Expression
    comments::Vector{String}
    expression::Expression
end

function parsefile(tokens, options::Hrse.ReadOptions)
    inner = Expression[]
    baseindent = peek(tokens)
    comments = []
    if tokentype(baseindent) == INDENT
        if isempty(tokens.rootlevel) || startswith(baseindent.indent, tokens.rootlevel[end].indent)
            while tokentype(peek(tokens)) != EOF
                comments = parsecomments(tokens, options)
                peeked = peek(tokens)
                if tokentype(peeked) == INDENT
                    if peeked.indent == baseindent.indent
                    elseif peeked.indent != tokens.rootlevel[end].indent
                        throw(HrseSyntaxException("Unexpected indent level", peek.line, peek.pos))
                    else
                        break
                    end
                end
                expression = parseexpression(tokens, options)
                if !isempty(comments)
                    expression = CommentExpression([i.comment for i in comments], expression)
                    comments = []
                end
                push!(inner, expression)
            end
            if !isempty(comments)
                for comment in reverse(comments)
                    push!(tokens, comment)
                end
            end
            if !isempty(tokens.rootlevel) pop!(tokens.rootlevel) end
            return ListExpression(inner)
        end
    end
    throw(HrseSyntaxException("Expected indent", peek(tokens).line, peek(tokens).pos))
end

function stripindent(tokens)
    indent = peek(tokens)
    if tokentype(indent) == INDENT
        return consume(tokens)
    end
end

function parsecomments(tokens, options::Hrse.ReadOptions)
    comments = []
    indent = stripindent(tokens)
    while tokentype(peek(tokens)) == COMMENT
        push!(comments, consume(tokens))
        newindent = stripindent(tokens)
        if isnothing(newindent)
            indent = newindent
        end
    end
    if !isnothing(indent)
        push!(tokens, indent)
    end
    return options.readcomments ? comments : []
end

function parseexpression(tokens, options::Hrse.ReadOptions)
    comments = parsecomments(tokens, options)
    if !isempty(comments)
        return CommentExpression([i.comment for i in comments], parseexpression(tokens, options))
    end
    expression = parsecompleteexpression(tokens, options)
    if tokentype(peek(tokens)) == COLON
        consume(tokens)
        if tokentype(peek(tokens)) == INDENT
            push!(tokens.rootlevel, tokens.indentlevel)
            indent = peek(tokens)
            if startswith(tokens.rootlevel[end].indent, indent.indent)
                pop!(tokens.rootlevel)
                return DotExpression(expression, ListExpression([]))
            elseif startswith(indent.indent, tokens.indentlevel.indent)
                return DotExpression(expression, parsefile(tokens, options))
            else
                throw(HrseSyntaxException("Unexpected indent level", indent.line, indent.pos))
            end
        else
            return DotExpression(expression, parseexpression(tokens, options)) 
        end
    elseif tokentype(peek(tokens)) == EQUALS
        consume(tokens)
        return DotExpression(expression, parseexpression(tokens, options))
    else
        return expression
    end
end

function parsecompleteexpression(tokens, options::Hrse.ReadOptions)
    if tokentype(peek(tokens)) == LPAREN
        return parselistexpression(tokens, options)
    elseif tokentype(peek(tokens)) == STRING
        return parsestringexpression(tokens, options)
    elseif tokentype(peek(tokens)) == TRUE || tokentype(peek(tokens)) == FALSE
        return parseboolexpression(tokens, options)
    elseif tokentype(peek(tokens)) == NUMBER
        token = consume(tokens)
        return NumberExpression(token.value)
    elseif tokentype(peek(tokens)) == INDENT
        return parseimodelineexpression(tokens, options)
    else
        throw(HrseSyntaxException("Unexpected token '$(tokentext(peek(tokens)))'", tokenline(peek(tokens)), tokenpos(peek(tokens))))
    end
end

function parselistexpression(tokens, options::Hrse.ReadOptions)
    consume(tokens)
    expressions = Expression[]
    dotexpr = false
    dotpos = 0
    dotline = 0
    while tokentype(peek(tokens)) != RPAREN
        if !isnothing(stripindent(tokens))
            continue
        end
        if tokentype(peek(tokens)) == EOF
            throw(HrseSyntaxException("Unexpected end of file", tokenline(peek(tokens)), tokenpos(peek(tokens))))
        end
        if tokentype(peek(tokens)) == DOT
            dotexpr = true
            dotpos = tokenpos(peek(tokens))
            dotline = tokenline(peek(tokens))
            consume(tokens)
            continue
        end
        push!(expressions, parseexpression(tokens, options))
    end
    consume(tokens)
    if dotexpr
        if length(expressions) != 2
            throw(HrseSyntaxException("Expected exactly two expressions surrounding dot in list", dotline, dotpos))
        end
        return DotExpression(expressions[1], expressions[2])
    end
    return ListExpression(expressions)
end

function parsestringexpression(tokens, options::Hrse.ReadOptions)
    token = consume(tokens)
    return StringExpression(token.value)
end

function parseboolexpression(tokens, options::Hrse.ReadOptions)
    token = consume(tokens)
    return BoolExpression(tokentype(token) == TRUE)
end

function parseimodelineexpression(tokens, options::Hrse.ReadOptions)
    expressions = Expression[]
    while tokentype(peek(tokens)) == INDENT
        consume(tokens)
    end
    dotexpr = false
    dotpos = 0
    dotline = 0
    while tokentype(peek(tokens)) != INDENT && tokentype(peek(tokens)) != EOF
        if tokentype(peek(tokens)) == DOT
            dotexpr = true
            dotpos = tokenpos(peek(tokens))
            dotline = tokenline(peek(tokens))
            consume(tokens)
            continue
        end
        push!(expressions, parseexpression(tokens, options))
    end
    if dotexpr
        if length(expressions) != 2
            throw(HrseSyntaxException("Expected exactly two expressions surrounding dot in list", dotline, dotpos))
        end
        return DotExpression(expressions[1], expressions[2])
    end
    if length(expressions) == 1
        return expressions[1]
    end
    return ListExpression(expressions)
end

function translate(expression::ListExpression, options::Hrse.ReadOptions)
    [translate(e, options) for e in expression.expressions]
end

function translate(expression::DotExpression, options::Hrse.ReadOptions)
    translate(expression.left, options) => translate(expression.right, options)
end

function translate(expression::StringExpression, ::Hrse.ReadOptions)
    expression.string
end

function translate(expression::BoolExpression, ::Hrse.ReadOptions)
    expression.value
end

function translate(expression::CommentExpression, options::Hrse.ReadOptions)
    return Hrse.CommentedElement(translate(expression.expression, options),expression.comments)
end

function translate(expression::NumberExpression, ::Hrse.ReadOptions)
    expression.value
end

end