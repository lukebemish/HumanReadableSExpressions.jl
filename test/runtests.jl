import Hrse
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
@test Hrse.readhrse(hrse) == Pair{String}["a" => 1, "b" => 2, "c" => [1, 2, 3], "d" => 4, "e" => [[1, 2, 3, 4, 5 => [6, 7, 8]], ["a" => [1, 2]], "b", "c"]]

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

@test Hrse.readhrse(hrse) == ["a" => 1, "b" => 2, "c" => 3, ["a" => 1, "b" => 2, "c" => 3]]

car = """
(
    type: car
    make: Mercedes-Benz
    model: S500
    seatingCapacity: 5
    topSpeed: 250.1
)
"""

@test Hrse.readhrse(car, type=Vehicle, options=Hrse.ReadOptions(extensions=[Hrse.DENSE])) == Car("car", "Mercedes-Benz", "S500", 5, 250.1)

@test Hrse.ashrse(Truck("truck", "Ford", "F-150", 1000.0), Hrse.PrinterOptions()) == """
type: truck
make: Ford
model: F-150
payloadCapacity: 1000.0
"""

@test Hrse.ashrse(Truck("truck", "Ford", "F-150", 1000.0), Hrse.PrinterOptions(pairmode = Hrse.DOT_MODE)) == """
(type . truck)
(make . Ford)
(model . F-150)
(payloadCapacity . 1000.0)
"""

@test Hrse.ashrse(Truck("truck", "Ford", "F-150", 1000.0), Hrse.PrinterOptions(pairmode = Hrse.EQUALS_MODE)) == """
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

@test Hrse.ashrse(foo, Hrse.PrinterOptions(extensions=[Hrse.DENSE])) == """
(
  a: 1
  b: foo
)
"""

@test Hrse.ashrse(bar, Hrse.PrinterOptions(pairmode=Hrse.CONDENSED_MODE)) == "(a.(((a. 2)(b.bar)).bar))(b.(((a. 3)(b.baz))((a. 4)(b.qux))))(c. 3.14)"


@test Hrse.readhrse("((a.(((a. 2)(b.bar)).bar))(b.(((a. 3)(b.baz))((a. 4)(b.qux))))(c. 3.14))", type=Bar, options=Hrse.ReadOptions(extensions=[Hrse.DENSE])) !== nothing

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

@test all((parsed = Hrse.readhrse(hrse)) .== [1, big"999999999999999999999999", 10.0, 10.0, 0.1, 1.0, 1.0, 10.0, 1.1, 11.0, 1.1, 1.1, 1000, true, false, Inf, -Inf, Inf, NaN, "test", "test"] .|| (parsed .=== NaN))

@test Hrse.ashrse([1,1.0,1e20,Inf,-Inf,NaN,"test"," test",true,false], Hrse.PrinterOptions()) == """
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

# Encoding

dict = Dict([
    :a => 1,
    :b => 2,
    :c => [:a=>2,:b=>2]])

@test Hrse.ashrse(dict, Hrse.PrinterOptions(pairmode=Hrse.DOT_MODE)) == """
(a . 1)
(b . 2)
(c . (
  (a . 2)
  (b . 2)
))
"""

@test Hrse.ashrse(dict, Hrse.PrinterOptions(pairmode=Hrse.EQUALS_MODE)) == """
a = 1
b = 2
c = (
  a = 2
  b = 2
)
"""

@test Hrse.ashrse(dict, Hrse.PrinterOptions(pairmode=Hrse.CONDENSED_MODE)) == "(a. 1)(b. 2)(c.((a. 2)(b. 2)))"

@test Hrse.ashrse(dict, Hrse.PrinterOptions(pairmode=Hrse.COLON_MODE)) == """
a: 1
b: 2
c:\40
  a: 2
  b: 2
"""

@test Hrse.ashrse(dict, Hrse.PrinterOptions(trailingnewline=false)) == """
a: 1
b: 2
c:\40
  a: 2
  b: 2"""

@test Hrse.ashrse(dict, Hrse.PrinterOptions(indent="    ")) == """
a: 1
b: 2
c:\40
    a: 2
    b: 2
"""

@test Hrse.ashrse(dict, Hrse.PrinterOptions(indent="\t")) == """
a: 1
b: 2
c:\40
\ta: 2
\tb: 2
"""

@test Hrse.ashrse(dict, Hrse.PrinterOptions(extensions=[Hrse.DENSE])) == """
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

@test Hrse.ashrse(longlist, Hrse.PrinterOptions()) == """
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

@test Hrse.ashrse(shortlist, Hrse.PrinterOptions()) == """
a: (1 1 1 1 1)
"""

@test Hrse.ashrse(shortlist, Hrse.PrinterOptions(inlineprimitives=3)) == """
a:\40
  1
  1
  1
  1
  1
"""

@test Hrse.ashrse(longlist, Hrse.PrinterOptions(inlineprimitives=40)) == """
a: (1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1)
"""
