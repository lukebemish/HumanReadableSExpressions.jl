module Parser

import ..Hrse

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

struct FloatToken <: Token
    value::Float64
    line::Integer
    pos::Integer
end

struct IntegerToken <: Token
    value::Int64
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
tokentext(t::FloatToken) = t.value
tokentext(t::IntegerToken) = t.value
tokentext(t::CommentToken) = t.comment

tokenline(t::SimpleToken) = t.line
tokenline(t::StringToken) = t.line
tokenline(t::FloatToken) = t.line
tokenline(t::IntegerToken) = t.line
tokenline(t::CommentToken) = t.line

tokenpos(t::SimpleToken) = t.pos
tokenpos(t::StringToken) = t.pos
tokenpos(t::FloatToken) = t.pos
tokenpos(t::IntegerToken) = t.pos
tokenpos(t::CommentToken) = t.pos

const STRING = :STRING
const FLOAT = :FLOAT
const INTEGER = :INTEGER
const COMMENT = :COMMENT

tokentype(t::SimpleToken) = t.type
tokentype(::StringToken) = STRING
tokentype(::FloatToken) = FLOAT
tokentype(::IntegerToken) = INTEGER
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
end

function addline(line::TokenizerContext)::TokenizerContext
    return TokenizerContext(line.line+1, line.linetext*'\n'*readline(line.io), line.io, line.posoffset, line.indents, line.modes)
end

function eof(line::TokenizerContext)
    return eof(line.io)
end

function tokenize(io::IO)
    tokens = Token[]
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
                indent = indent[1:count]
            end
            line = line[pos:end]
            posoffset = pos-1
            if isspace(line[1])
                spaces = 1
                while isspace(line[spaces+1])
                    spaces += 1
                end
                push!(tokens, SimpleToken(INDENT, linenumber, 0))
                push!(indent, line[1:spaces])
                line = line[spaces+1:end]
                posoffset += spaces
            end
            push!(tokens, SimpleToken(BOL, linenumber, 0))
        end

        tokenizeline(tokens, TokenizerContext(linenumber, line, io, posoffset, indents, modes))
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
    if tokentype(newtokens[end]) == COLON
        push!(tokens, SimpleToken(EOL, ctx.line, length(line)+ctx.posoffset))
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
    if isspace(line[pos])
        return pos+1, ctx
    elseif line[pos] == '#' # comment - I'll handle capturing it later
        if length(line) > pos
            comment = lstrip(line[pos+1:end])
            if !isempty(comment)
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
    elseif line[pos] == '.'
        push!(tokens, SimpleToken(DOT, ctx.line, pos+ctx.posoffset))
        return pos+1, ctx
    elseif line[pos] == ':'
        push!(tokens, SimpleToken(COLON, ctx.line, pos+ctx.posoffset))
        return pos+1, ctx
    elseif line[pos] == '"'
        return consumestring(line, tokens, pos+1, ctx)
    elseif isletter(line[pos])
        return consumesymbol(line, tokens, pos, ctx)
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
    push!(tokens, CommentToken(strip(comment), origline, posorig+ctx.posoffset))
    return pos+found[end], TokenizerContext(ctx.line, line, ctx.io, posoffset, ctx.indents, ctx.modes)
end

function consumestring(line, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    posorig = pos
    while pos <= length(line) && line[pos] != '"'
        # I'll do escapes later
        #if line[pos] == '\\'
        #    pos += 1
        #end
        pos += 1
    end
    if pos > length(line)
        throw(HrseSyntaxException("Unterminated string", ctx.line, posorig+ctx.posoffset))
    end
    push!(tokens, StringToken(line[posorig:pos-1], ctx.line, posorig+ctx.posoffset))
    return pos+1, ctx
end

function consumesymbol(line, tokens, pos, ctx::TokenizerContext)::Tuple{Integer,TokenizerContext}
    posorig = pos
    while pos <= length(line) && isletter(line[pos])
        pos += 1
    end
    if line[posorig:pos-1] == "true"
        push!(tokens, SimpleToken(TRUE, ctx.line, posorig+ctx.posoffset))
    elseif line[posorig:pos-1] == "false"
        push!(tokens, SimpleToken(FALSE, ctx.line, posorig+ctx.posoffset))
    else
        push!(tokens, StringToken(line[posorig:pos-1], ctx.line, posorig+ctx.posoffset))
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

struct CommentExpression <: Expression
    comments::Vector{String}
    expression::Expression
end

function parsefile(tokens)
    consume(tokens)
    inner = Expression[]
    while !(tokentype(peek(tokens)) in [DEINDENT, EOF, RPAREN])
        push!(inner, parseexpression(tokens))
    end
    if tokentype(peek(tokens)) == DEINDENT
        consume(tokens)
    end
    return ListExpression(inner)
end

function parseexpression(tokens)
    comments = []
    while tokentype(peek(tokens)) == COMMENT
        push!(comments, consume(tokens).comment)
    end
    if length(comments) > 0
        return CommentExpression(comments, parseexpression(tokens))
    end
    expression = parsecompleteexpression(tokens)
    if tokentype(peek(tokens)) == COLON
        consume(tokens)
        if tokentype(peek(tokens)) == EOL
            consume(tokens)
            if tokentype(peek(tokens)) == INDENT
                consume(tokens)
                return DotExpression(expression, parsefile(tokens))
            else
                throw(HrseSyntaxException("Expected indent", tokenline(peek(tokens)), tokenpos(peek(tokens))))
            end
        else
            return DotExpression(expression, parseexpression(tokens))
        end
    elseif tokentype(peek(tokens)) == EQUALS
        consume(tokens)
        return DotExpression(expression, parseexpression(tokens))
    else
        return expression
    end
end

function parsecompleteexpression(tokens)
    if tokentype(peek(tokens)) == LPAREN
        return parselistexpression(tokens)
    elseif tokentype(peek(tokens)) == STRING
        return parsestringexpression(tokens)
    # TODO: numbers
    elseif tokentype(peek(tokens)) == TRUE || tokentype(peek(tokens)) == FALSE
        return parseboolexpression(tokens)
    elseif tokentype(peek(tokens)) == BOL
        return parseimodelineexpression(tokens)
    else
        throw(HrseSyntaxException("Unexpected token '$(tokentext(peek(tokens)))'", tokenline(peek(tokens)), tokenpos(peek(tokens))))
    end
end

function parselistexpression(tokens)
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
        push!(expressions, parseexpression(tokens))
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

function parsestringexpression(tokens)
    token = consume(tokens)
    return StringExpression(token.value)
end

function parseboolexpression(tokens)
    token = consume(tokens)
    return BoolExpression(tokentype(token) == TRUE)
end

function parseimodelineexpression(tokens)
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
        push!(expressions, parseexpression(tokens))
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

struct TranslationOptions
    comment::Bool
end

function translate(expression::ListExpression, options::TranslationOptions)
    [translate(e, options) for e in expression.expressions]
end

function translate(expression::DotExpression, options::TranslationOptions)
    translate(expression.left, options) => translate(expression.right, options)
end

function translate(expression::StringExpression, options::TranslationOptions)
    expression.string
end

function translate(expression::BoolExpression, options::TranslationOptions)
    expression.value
end

function translate(expression::CommentExpression, options::TranslationOptions)
    if !options.comment
        return translate(expression.expression, options)
    end
    return Hrse.CommentedElement(translate(expression.expression, options),expression.comments)
end

function read(io::IO; comment::Bool=false)
    tokens = tokenize(io)
    parsetree = parsefile(tokens)
    if tokentype(peek(tokens)) != EOF
        throw(HrseSyntaxException("Unexpected token '$(tokentext(peek(tokens)))'", tokenline(peek(tokens)), tokenpos(peek(tokens))))
    end
    return translate(parsetree, TranslationOptions(comment))
end

end