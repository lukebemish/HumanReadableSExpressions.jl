using HumanReadableSExpressions
import HumanReadableSExpressions: Parser.HrseSyntaxException
import StructTypes
using Test

struct Foo
    a::Int
    b::String
end

mutable struct Bar
    a::Pair{Foo, String}
    b::Vector{Foo}
    c::Float64

    Bar() = new()
end

abstract type Vehicle end

struct Car <: Vehicle
    type::String
    make::String
    model::String
    seatingCapacity::Int
    topSpeed::Float64
end

struct Truck <: Vehicle
    type::String
    make::String
    model::String
    payloadCapacity::Float64
end

StructTypes.StructType(::Type{Vehicle}) = StructTypes.AbstractType()
StructTypes.StructType(::Type{Car}) = StructTypes.Struct()
StructTypes.StructType(::Type{Truck}) = StructTypes.Struct()
StructTypes.subtypekey(::Type{Vehicle}) = :type
StructTypes.subtypes(::Type{Vehicle}) = (car=Car, truck=Truck)

StructTypes.StructType(::Type{Foo}) = StructTypes.UnorderedStruct()
StructTypes.StructType(::Type{Bar}) = StructTypes.Mutable()

hrse = """
(; this is great for testing edge cases ;;) 
   and comment formats;)
a: 1
b: 2
c:
(; should still parse ;)
    1
    2
(; ;)
    3
(; ;)
d: 4
e:
    (
    1
    2
3
    4
    5:
        6
        7
        8
)
    (
    a:
        1
        2)
    b
    c
"""

# This will hit an absurd number of edge cases all at once, it turns out...
@test readhrse(hrse) == Pair{String}["a" => 1, "b" => 2, "c" => [1, 2, 3], "d" => 4, "e" => [[1, 2, 3, 4, 5 => [6, 7, 8]], ["a" => [1, 2]], "b", "c"]]

hrse = """
a=1
b=2
c=3
(
    a=1
    (b . 2)
    c: 3
)
"""

@test readhrse(hrse) == ["a" => 1, "b" => 2, "c" => 3, ["a" => 1, "b" => 2, "c" => 3]]

car = """
(
    type: car
    make: Mercedes-Benz
    model: S500
    seatingCapacity: 5
    topSpeed: 250.1
)
"""

@test readhrse(car, type=Vehicle, options=HrseReadOptions(extensions=[HumanReadableSExpressions.DENSE])) == Car("car", "Mercedes-Benz", "S500", 5, 250.1)

@test ashrse(Truck("truck", "Ford", "F-150", 1000.0), HrsePrintOptions()) == """
type: truck
make: Ford
model: F-150
payloadCapacity: 1000.0
"""

@test ashrse(Truck("truck", "Ford", "F-150", 1000.0), HrsePrintOptions(pairmode = HumanReadableSExpressions.DOT_MODE)) == """
(type . truck)
(make . Ford)
(model . F-150)
(payloadCapacity . 1000.0)
"""

@test ashrse(Truck("truck", "Ford", "F-150", 1000.0), HrsePrintOptions(pairmode = HumanReadableSExpressions.EQUALS_MODE)) == """
type = truck
make = Ford
model = F-150
payloadCapacity = 1000.0
"""

foo = Foo(1, "foo")
bar = Bar()
bar.a = Foo(2, "bar") => "bar"
bar.b = [Foo(3, "baz"), Foo(4, "qux")]
bar.c = 3.14

@test ashrse(foo, HrsePrintOptions(extensions=[HumanReadableSExpressions.DENSE])) == """
(
  a: 1
  b: foo
)
"""

@test ashrse(bar, HrsePrintOptions(pairmode=HumanReadableSExpressions.CONDENSED_MODE)) == "(a.(((a. 2)(b.bar)).bar))(b.(((a. 3)(b.baz))((a. 4)(b.qux))))(c. 3.14)"


@test readhrse("((a.(((a. 2)(b.bar)).bar))(b.(((a. 3)(b.baz))((a. 4)(b.qux))))(c. 3.14))", type=Bar, options=HrseReadOptions(extensions=[HumanReadableSExpressions.DENSE])) !== nothing

hrse = """
(; Yeah, let's just test every type imaginable... ;)
1
999999999999999999999999
1e1
1e+1
1e-1
.1e1
1.
1.e1
1.1
1.1e1
1_.1
1._1
1_000
#t
#f
#inf
-#inf
+#inf
#nan
"test"
test
"""

@test all((parsed = readhrse(hrse)) .== [1, big"999999999999999999999999", 10.0, 10.0, 0.1, 1.0, 1.0, 10.0, 1.1, 11.0, 1.1, 1.1, 1000, true, false, Inf, -Inf, Inf, NaN, "test", "test"] .|| (parsed .=== NaN))

@test ashrse([1,1.0,1e20,Inf,-Inf,NaN,"test"," test",true,false], HrsePrintOptions()) == """
1
1.0
1.0e20
#inf
-#inf
#nan
test
" test"
#t
#f
"""

# Other int encodings

hrse = """
0xAbC10
0b11010
-10
-0x10
+20
"""

@test readhrse(hrse) == [282574486936592, 26, -10, -16, 20]

# Encoding

dict = Dict([
    :a => 1,
    :b => 2,
    :c => [:a=>2,:b=>2]])

@test ashrse(dict, HrsePrintOptions(pairmode=HumanReadableSExpressions.DOT_MODE)) == """
(a . 1)
(b . 2)
(c . (
  (a . 2)
  (b . 2)
))
"""

@test ashrse(dict, HrsePrintOptions(pairmode=HumanReadableSExpressions.EQUALS_MODE)) == """
a = 1
b = 2
c = (
  a = 2
  b = 2
)
"""

@test ashrse(dict, HrsePrintOptions(pairmode=HumanReadableSExpressions.CONDENSED_MODE)) == "(a. 1)(b. 2)(c.((a. 2)(b. 2)))"

@test ashrse(dict, HrsePrintOptions(pairmode=HumanReadableSExpressions.COLON_MODE)) == """
a: 1
b: 2
c:\40
  a: 2
  b: 2
"""

@test ashrse(dict, HrsePrintOptions(trailingnewline=false)) == """
a: 1
b: 2
c:\40
  a: 2
  b: 2"""

@test ashrse(dict, HrsePrintOptions(indent="    ")) == """
a: 1
b: 2
c:\40
    a: 2
    b: 2
"""

@test ashrse(dict, HrsePrintOptions(indent="\t")) == """
a: 1
b: 2
c:\40
\ta: 2
\tb: 2
"""

@test ashrse(dict, HrsePrintOptions(extensions=[HumanReadableSExpressions.DENSE])) == """
(
  a: 1
  b: 2
  c:\40
    a: 2
    b: 2
)
"""

longlist = [:a => repeat([1], 20)]
shortlist = [:a => repeat([1], 5)]

@test ashrse(longlist, HrsePrintOptions()) == """
a:\40
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
  1
"""

@test ashrse(shortlist, HrsePrintOptions()) == """
a: (1 1 1 1 1)
"""

@test ashrse(shortlist, HrsePrintOptions(inlineprimitives=3)) == """
a:\40
  1
  1
  1
  1
  1
"""

@test ashrse(longlist, HrsePrintOptions(inlineprimitives=40)) == """
a: (1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1)
"""

@test readhrse("""
a: \"\"\"
abc
\"\"\"
""") == ["a" => "abc\n"]

@test readhrse("""
  a: \"\"\"
  abc\"\"\"
""") == ["a" => "abc"]

@test readhrse("""
  a: \"\"\"  abc
  def\"\"\"
""") == ["a" => "  abc\n  def"]

@test readhrse("""
a: \"\"\"
""-\"\"\"""") == ["a" => "\"\"-"]

# Test string literals
@test readhrse("a-b") == ["a-b"]

@test_throws HrseSyntaxException readhrse("-ax")
@test_throws HrseSyntaxException readhrse(".a")
@test_throws HrseSyntaxException readhrse("0stuff")
@test readhrse("_1 not-a-number") == [["_1", "not-a-number"]]
@test_throws HrseSyntaxException readhrse("#invalid-literal")

@test_throws HrseSyntaxException readhrse("\"\a\"")
@test_throws HrseSyntaxException readhrse("a\u00AD")
@test_throws HrseSyntaxException readhrse("a\U2019")
@test readhrse("a^") == ["a^"]
@test readhrse("a1") == ["a1"]