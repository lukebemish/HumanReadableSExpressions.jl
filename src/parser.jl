module Parser

import ..Hrse
import ..Literals
import ..Literals: issymbolstartbanned, issymbolstart, issymbolbody

import Base: eof, push!

import Unicode

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
tokentype(::Nothing) = nothing

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

struct Position
    line::Integer
    pos::Integer
end

mutable struct LexerSource
    leading::Vector{Char}
    positions::Vector{Position}
    io::IO
    line::Integer
    pos::Integer
    tokens::Vector{Token}
    options::Hrse.ReadOptions
    LexerSource(io::IO, options::Hrse.ReadOptions) = new(Char[], Position[], io, 1, 0, Token[], options)
end

function emit(source::LexerSource, token::Token)
    if (tokentype(token) == INDENT || tokentype(token) == EOF) &&
        length(source.tokens) > 0 && tokentype(source.tokens[end]) == INDENT
        source.tokens[end] = token
        return source.tokens
    end
    push!(source.tokens, token)
end

function consume(source::LexerSource)
    if length(source.leading)==0 && eof(source.io)
        return nothing
    end
    if length(source.leading) == 0
        c = read(source.io, Char)
        if c == '\n'
            source.line += 1
            source.pos = 0
        else
            source.pos += 1
        end
        return c
    else
        c = popfirst!(source.leading)
        pos = popfirst!(source.positions)
        source.line = pos.line
        source.pos = pos.pos
        return c
    end
end

function peek(source::LexerSource; num=1)
    if length(source.leading) < num
        for i in 1:num
            if eof(source.io)
                return nothing
            end
            c = read(source.io, Char)
            lastpos = length(source.leading) == 0 ? Position(source.line, source.pos) : source.positions[end]
            push!(source.leading, c)
            pos = lastpos.pos
            line = lastpos.line
            if c == '\n'
                line += 1
                pos = 0
            else
                pos += 1
            end
            push!(source.positions, Position(line, pos))
        end
    end
    return source.leading[num]
end

function peekpos(source::LexerSource; num=1)
    peek(source, num=num)
    return source.positions[num]
end

function iswhitespace(char::Char)
    return char == ' ' || char == '\t'
end

function isnumericbody(char::Char)
    return isxdigit(char) || char == '_'
end

function runmachine(source::LexerSource)
    machine = source -> lexindent(source, Char[], 1, 1)
    while machine !== nothing
        machine = machine(source)
    end
end

function lex(source::LexerSource)
    char = consume(source)
    line = source.line
    pos = source.pos
    if char === nothing
        emit(source, SimpleToken(EOF, source.line, source.pos))
        return
    elseif char == '"'
        return s -> lexstring(s, Char[], line, pos)
    elseif char == '('
        return s -> lexparen(s)
    elseif char == ')'
        emit(source, SimpleToken(RPAREN, source.line, source.pos))
    elseif char == '='
        emit(source, SimpleToken(EQUALS, source.line, source.pos))
    elseif char == '.'
        return s -> lexdot(s)
    elseif char == ':'
        emit(source, SimpleToken(COLON, source.line, source.pos))
    elseif char == ';'
        return s -> lexcomment(s, Char[], line, pos)
    elseif iswhitespace(char)
        # just continue
    elseif issymbolstart(char)
        return s -> lexsymbol(s, [char])
    elseif isnumericbody(char) || char in ['.', '+', '-']
        return s -> lexnumber(s, [char], line, pos)
    elseif char == '\n'
        return s -> lexindent(s, Char[], line, pos+1)
    else
        throw(HrseSyntaxException("Unexpected character '$char'", source.line, source.pos))
    end
    return s -> lex(s)
end

function lexindent(source, chars, line, pos)
    next = peek(source)
    if next == ' ' || next == '\t'
        push!(chars, consume(source))
        return s -> lexindent(s, chars, line, pos)
    else
        emit(source, IndentToken(String(chars), line, pos))
        return s -> lex(s)
    end
end

function lexparen(source::LexerSource)
    next = peek(source)
    line = source.line
    pos = source.pos
    if next == ';'
        return s -> lexlistcommentopen(s, 0, line, pos)
    end
    emit(source, SimpleToken(LPAREN, source.line, source.pos))
    return s -> lex(s)
end

function lexcomment(source::LexerSource, chars, line, pos)
    char = peek(source)
    if char === nothing || char == '\n'
        comment = strip(String(chars))
        emit(source, CommentToken(comment, line, pos))
        return s -> lex(s)
    else
        push!(chars, consume(source))
        return s -> lexcomment(s, chars, line, pos)
    end
end

function lexlistcommentopen(source::LexerSource, count, line, pos)
    char = peek(source)
    if char === nothing
        throw(HrseSyntaxException("Unterminated multiline comment", line, pos))
    elseif char == ';'
        consume(source)
        return s -> lexlistcommentopen(s, count+1, line, pos)
    else
        return s -> lexlistcommentbody(s, Char[], count, 0, line, pos)
    end
end

function lexlistcommentbody(source::LexerSource, chars, count, counting, line, pos)
    char = consume(source)
    if char === nothing
        throw(HrseSyntaxException("Unterminated multiline comment", line, pos))
    elseif char == ')'
        if counting == count
            comment = strip(String(chars))
            emit(source, CommentToken(comment, line, pos))
            return s -> lex(s)
        else
            if counting != 0
                for _ in 1:counting
                    push!(chars, ';')
                end
            end
            push!(chars, char)
            return s -> lexlistcommentbody(s, chars, count, 0, line, pos)
        end
    elseif char == ';'
        return s -> lexlistcommentbody(s, chars, count, counting+1, line, pos)
    else
        if counting != 0
            for _ in 1:counting
                push!(chars, ';')
            end
        end
        push!(chars, char)
        return s -> lexlistcommentbody(s, chars, count, 0, line, pos)
    end
end

function lexnumber(source::LexerSource, chars, line::Integer, pos::Integer)
    char = peek(source)
    if isnumericbody(char) || char in ['.', 'e', 'E', '+', '-', 'x', 'X', 'b', 'B']
        push!(chars, consume(source))
        return s -> lexnumber(s, chars, line, pos)
    else
        text = String(chars)
        if !isnothing(match(Literals.FLOAT_REGEX, text))
            emit(source, NumberToken(Literals.parsefloat(text; type=source.options.floattype), line, pos))
        elseif !isnothing(match(Literals.INT_REGEX, text))
            parsed = Literals.parseint(text; types=source.options.integertypes)
            if parsed === nothing
                throw(HrseSyntaxException("Invalid number '$text'", line, pos))
            end
            emit(source, NumberToken(parsed, line, pos))
        else
            throw(HrseSyntaxException("Invalid number '$text'", line, pos))
        end
        return s -> lex(s)
    end
end

function lexdot(source::LexerSource)
    i = 1
    digits = false
    while (char = peek(source, num=i)) !== nothing && isdigit(char) && isnumericbody(char)
        i += 1
        if isdigit(char)
            digits = true
        end
    end
    if digits
        line = source.line
        pos = source.pos
        return s -> lexnumber(s, Char['.'], line, pos)
    else
        emit(source, SimpleToken(DOT, source.line, source.pos))
    end
    return s -> lex(s)
end

function lexsymbol(source::LexerSource, chars)
    char = peek(source)
    if char === nothing || !issymbolbody(char)
        emit(source, StringToken(String(chars), source.line, source.pos))
        return s -> lex(s)
    else
        push!(chars, consume(source))
        return s -> lexsymbol(s, chars)
    end
end

function lexstring(source::LexerSource, chars, startline::Integer, startpos::Integer)
    char = consume(source)
    if char === nothing
        throw(HrseSyntaxException("Unterminated string", startline, startpos))
    elseif char == '\\'
        return s -> lexescape(s, chars, startline, startpos)
    elseif char == '"'
        next = peek(source)
        if issymbolbody(next)
            pos = peekpos(source)
            throw(HrseSyntaxException("Unexpected symbol character directly after string", pos.line, pos.pos))
        end
        emit(source, StringToken(String(chars), startline, startpos))
        return s -> lex(s)
    else
        push!(chars, char)
        return s -> lexstring(s, chars, startline, startpos)
    end
end

function lexescape(source::LexerSource, chars, startline::Integer, startpos::Integer)
    char = consume(source)
    callback = (s, c) -> lexstring(s, push!(chars, c), startline, startpos)
    if char === nothing
        throw(HrseSyntaxException("Unterminated string", startline, startpos))
    elseif char == 'n'
        push!(chars, '\n')
    elseif char == 't'
        push!(chars, '\t')
    elseif char == 'r'
        push!(chars, '\r')
    elseif char == 'b'
        push!(chars, '\b')
    elseif char == 'f'
        push!(chars, '\f')
    elseif char == 'v'
        push!(chars, '\v')
    elseif char == 'a'
        push!(chars, '\a')
    elseif char == 'e'
        push!(chars, '\e')
    elseif char == '\\'
        push!(chars, '\\')
    elseif char == '"'
        push!(chars, '"')
    elseif char == 'u'
        return s -> lexunicode(s, callback)
    elseif '0' <= char < '8'
        return s -> lexoctal(s, callback, [char])
    else
        throw(HrseSyntaxException("Invalid escape sequence '\\$(char)'", source.line, source.pos))
    end
    return s -> lexstring(s, chars, startline, startpos)
end

function lexunicode(source::LexerSource, callback)
    char = consume(source)
    if char == '{'
        return s -> lexunicodepoint(s, Char[], callback)
    else
        throw(HrseSyntaxException("Invalid unicode character escape \"\\u$char\"", source.line, source.pos))
    end
end

function lexoctal(source::LexerSource, callback, chars)
    next = peek(source)
    if length(chars) < 3 && '0' <= next < '8'
        char = consume(source)
        push!(chars, char)
        return s -> lexoctal(s, callback, chars)
    else
        i = tryparse(UInt8, String(chars); base=8)
        if i === nothing
            throw(HrseSyntaxException("Invalid octal character \"\\$(String(chars))\"", source.line, source.pos))
        end
        return s -> callback(s, i)
    end
end

function lexunicodepoint(source::LexerSource, chars, callback)
    char = consume(source)
    if char == '}'
        i = tryparse(UInt32, String(chars); base=16)
        if i === nothing || !Unicode.isassigned(i)
            throw(HrseSyntaxException("Invalid unicode character \"\\u{$(String(chars))}\"", source.line, source.pos))
        end
        u = Char(i)
        return s -> callback(s, i)
    elseif isxdigit(char)
        push!(chars, char)
        return s -> lexunicodepoint(s, chars, callback)
    else
        throw(HrseSyntaxException("Invalid unicode character escape \"\\u{$(String(chars))}$char\"", source.line, source.pos))
    end
end

mutable struct Tokens
    tokens
    indentlevel
    rootlevel
end

peek(tokens::Tokens) = tokens.tokens[1]
peek(tokens::Tokens, i::Integer) = length(tokens.tokens) >= i ? tokens.tokens[i] : nothing
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
            while tokentype(peek(tokens)) != EOF && tokentype(peek(tokens)) != RPAREN
                comments = parsecomments(tokens, options)
                peeked = peek(tokens)
                if tokentype(peeked) == INDENT
                    if peeked.indent == baseindent.indent
                    elseif peeked.indent != tokens.rootlevel[end].indent
                        following = tokentype(peek(tokens, 2))
                        if following == EOF || following == RPAREN
                            consume(tokens)
                            break
                        end
                        throw(HrseSyntaxException("Unexpected indent level", peeked.line, peeked.pos))
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
        if !isnothing(newindent)
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
            comments = parsecomments(tokens, options)
            indent = peek(tokens)
            for comment in reverse(comments)
                push!(tokens, comment)
            end
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
    while tokentype(peek(tokens)) != INDENT && tokentype(peek(tokens)) != EOF && tokentype(peek(tokens)) != RPAREN
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