module Parser

import ..Hrse
import ..Literals

import Base: eof

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

tokentext(t::SimpleToken) = t.type
tokentext(t::StringToken) = t.value
tokentext(t::NumberToken) = t.value
tokentext(t::CommentToken) = t.comment

tokenline(t::SimpleToken) = t.line
tokenline(t::StringToken) = t.line
tokenline(t::NumberToken) = t.line
tokenline(t::CommentToken) = t.line

tokenpos(t::SimpleToken) = t.pos
tokenpos(t::StringToken) = t.pos
tokenpos(t::NumberToken) = t.pos
tokenpos(t::CommentToken) = t.pos

const STRING = :STRING
const NUMBER = :NUMBER
const COMMENT = :COMMENT

tokentype(t::SimpleToken) = t.type
tokentype(::StringToken) = STRING
tokentype(::NumberToken) = NUMBER
tokentype(::CommentToken) = COMMENT

const LPAREN = :LPAREN
const RPAREN = :RPAREN
const EQUALS = :EQUALS
const DOT = :DOT
const COLON = :COLON

const INDENT = :INDENT
const DEINDENT = :DEINDENT
const EOL = :EOL
const EOF = :EOF
const BOL = :BOL

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
    indents
    modes
    options::Hrse.ParseOptions
end

function addline(line::TokenizerContext)::TokenizerContext
    return TokenizerContext(line.line+1, line.linetext*'\n'*readline(line.io), line.io, line.posoffset, line.indents, line.modes, line.options)
end

function eof(line::TokenizerContext)
    return eof(line.io)
end

function tokenize(io::IO, options::Hrse.ParseOptions)
    tokens = Token[SimpleToken(BOL, 0, 0)]
    indents = [[]]
    modes = [I_MODE]
    linenumber = 0
    while !eof(io)
        posoffset = 0
        indent = indents[end]
        line = readline(io)
        linenumber += 1
        if all(isspace(i) for i in line)
            continue # ignore whitespace
        end
        if modes[end] == I_MODE
            # handle indents
            pos = 1
            count = 0
            for i in indent
                if pos+length(i)-1 > length(line)
                    break
                elseif line[pos:pos+length(i)-1] == i
                    pos += length(i)
                    count += 1
                else
                    break
                end
            end
            if count < length(indent)
                if isspace(line[pos])
                    throw(HrseSyntaxException("Unexpected indentation character", linenumber, pos))
                end
                for _ in 1:length(indent)-count
                    push!(tokens, SimpleToken(DEINDENT, linenumber, 0))
                end
                indent = indent[1:count-1]
            end
            line = line[pos:end]
            posoffset = pos-1
            if isspace(line[1])
                spaces = 1
                while isspace(line[spaces+1])
                    spaces += 1
                end
                push!(tokens, SimpleToken(INDENT, linenumber, 0))
                push!(tokens, SimpleToken(BOL, linenumber, 0))
                push!(indent, line[1:spaces])
                line = line[spaces+1:end]
                posoffset += spaces
            end
        end
        indents[end] = indent

        tokenizeline(tokens, TokenizerContext(linenumber, line, io, posoffset, indents, modes, options))
    end
    push!(tokens, SimpleToken(EOF, linenumber+1, 0))
    return tokens
end

function tokenizeline(tokens, ctx::TokenizerContext)
    pos = 1
    newtokens = Token[SimpleToken(BOL, 0, 0)]
    while pos <= length(ctx.linetext)
        pos, ctx = consumetoken(ctx.linetext, newtokens, pos, ctx)
    end
    push!(tokens, newtokens...)
    if tokentype(newtokens[end]) == COLON
        push!(tokens, SimpleToken(EOL, ctx.line, length(ctx.line)+ctx.posoffset))
        if ctx.modes[end] == S_MODE
            idxs = findfirst(r"^\s+", line)
            if idxs === nothing
                push!(ctx.indents, [])
            else
                push!(ctx.indents, [line[idxs]])
            end
            return push!(ctx.modes, I_MODE)
        end
    end
end

function consumetoken(line, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    remainder = line[pos:end]
    if isspace(line[pos])
        return pos+1, ctx
    elseif line[pos] == '#' # comment - I'll handle capturing it later
        if length(line) > pos
            comment = lstrip(line[pos+1:end])
            if !isempty(comment) && ctx.options.readcomments
                push!(tokens, CommentToken(comment, ctx.line, pos+ctx.posoffset))
            end 
        end
        return length(line)+1, ctx
    elseif line[pos] == '('
        if length(line) > pos && line[pos+1] == '#'
            return consumecomment(line, tokens, pos+1, ctx)
        end
        push!(tokens, SimpleToken(LPAREN, ctx.line, pos+ctx.posoffset))
        push!(ctx.modes, S_MODE)
        return pos+1, ctx
    elseif line[pos] == ')'
        while length(ctx.modes) != 0 && ctx.modes[end] == I_MODE
            pop!(ctx.modes)
            pop!(ctx.indents)
        end
        if length(ctx.modes) == 0
            throw(HrseSyntaxException("Unexpected closing parenthesis", ctx.line, pos+ctx.posoffset))
        end
        pop!(ctx.modes)
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
    else
        throw(HrseSyntaxException("Unexpected character '$(line[1])'", ctx.line, pos+ctx.posoffset))
    end
    # I'll do numbers later
end

function consumecomment(line, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    pos += 1
    count = 1
    while pos <= length(line) && line[pos] == '#'
        pos += 1
        count += 1
    end
    posorig = pos
    search = Regex("[^#]"*'#'^count*"\\)")
    found = findfirst(search, line[pos:end])
    posoffset = ctx.posoffset
    origline = ctx.line
    while isnothing(found) && !eof(ctx)
        pos = length(line)
        ctx = addline(ctx)
        posoffset = -length(line)
        line = ctx.linetext
        found = findfirst(search, line[pos:end])
    end
    if isnothing(found)
        throw(HrseSyntaxException("Unterminated comment", origline, posorig+ctx.posoffset))
    end
    comment = line[posorig:pos+found[1]-1]
    if ctx.options.readcomments
        push!(tokens, CommentToken(strip(comment), origline, posorig+ctx.posoffset))
    end
    return pos+found[end], TokenizerContext(ctx.line, line, ctx.io, posoffset, ctx.indents, ctx.modes, ctx.options)
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
    if text == "true"
        push!(tokens, SimpleToken(TRUE, ctx.line, posorig+ctx.posoffset))
    elseif text == "false"
        push!(tokens, SimpleToken(FALSE, ctx.line, posorig+ctx.posoffset))
    else
        push!(tokens, StringToken(text, ctx.line, posorig+ctx.posoffset))
    end
    return pos, ctx
end

peek(tokens) = tokens[1]

consume(tokens) = popfirst!(tokens)

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

function parsefile(tokens, options::Hrse.ParseOptions)
    consume(tokens)
    inner = Expression[]
    while !(tokentype(peek(tokens)) in [DEINDENT, EOF, RPAREN])
        push!(inner, parseexpression(tokens, options))
    end
    if tokentype(peek(tokens)) == DEINDENT
        consume(tokens)
    end
    return ListExpression(inner)
end

function parseexpression(tokens, options::Hrse.ParseOptions)
    if options.readcomments
        comments = []
        while tokentype(peek(tokens)) == COMMENT
            push!(comments, consume(tokens).comment)
        end
        if length(comments) > 0
            return CommentExpression(comments, parseexpression(tokens, options))
        end
    end
    expression = parsecompleteexpression(tokens, options)
    if tokentype(peek(tokens)) == COLON
        consume(tokens)
        if tokentype(peek(tokens)) == EOL
            consume(tokens)
            if tokentype(peek(tokens)) == INDENT
                consume(tokens)
                return DotExpression(expression, parsefile(tokens, options))
            else
                return DotExpression(expression, ListExpression([]))
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

function parsecompleteexpression(tokens, options::Hrse.ParseOptions)
    if tokentype(peek(tokens)) == LPAREN
        return parselistexpression(tokens, options)
    elseif tokentype(peek(tokens)) == STRING
        return parsestringexpression(tokens, options)
    # TODO: numbers
    elseif tokentype(peek(tokens)) == TRUE || tokentype(peek(tokens)) == FALSE
        return parseboolexpression(tokens, options)
    elseif tokentype(peek(tokens)) == NUMBER
        token = consume(tokens)
        return NumberExpression(token.value)
    elseif tokentype(peek(tokens)) == BOL
        return parseimodelineexpression(tokens, options)
    else
        throw(HrseSyntaxException("Unexpected token '$(tokentext(peek(tokens)))'", tokenline(peek(tokens)), tokenpos(peek(tokens))))
    end
end

function parselistexpression(tokens, options::Hrse.ParseOptions)
    consume(tokens)
    expressions = Expression[]
    dotexpr = false
    dotpos = 0
    dotline = 0
    while tokentype(peek(tokens)) != RPAREN
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

function parsestringexpression(tokens, options::Hrse.ParseOptions)
    token = consume(tokens)
    return StringExpression(token.value)
end

function parseboolexpression(tokens, options::Hrse.ParseOptions)
    token = consume(tokens)
    return BoolExpression(tokentype(token) == TRUE)
end

function parseimodelineexpression(tokens, options::Hrse.ParseOptions)
    expressions = Expression[]
    while tokentype(peek(tokens)) == BOL
        consume(tokens)
    end
    dotexpr = false
    dotpos = 0
    dotline = 0
    while !(tokentype(peek(tokens)) in [EOL, BOL, RPAREN, EOF, DEINDENT])
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

function translate(expression::ListExpression, options::Hrse.ParseOptions)
    [translate(e, options) for e in expression.expressions]
end

function translate(expression::DotExpression, options::Hrse.ParseOptions)
    translate(expression.left, options) => translate(expression.right, options)
end

function translate(expression::StringExpression, ::Hrse.ParseOptions)
    expression.string
end

function translate(expression::BoolExpression, ::Hrse.ParseOptions)
    expression.value
end

function translate(expression::CommentExpression, options::Hrse.ParseOptions)
    return Hrse.CommentedElement(translate(expression.expression, options),expression.comments)
end

function translate(expression::NumberExpression, ::Hrse.ParseOptions)
    expression.value
end

end