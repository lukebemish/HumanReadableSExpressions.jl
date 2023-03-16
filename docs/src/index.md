# HumanReadableSExpressions.jl Documentation

```@contents
Depth = 4
```

## Getting Started

HumanReadableSExpressions.jl is a Julia package for reading and writing files written in [HRSE](https://lukebemish.dev/hrse),
or Human Readable S-Expressions, which are a human-readable format for representing data and configuration files that is
equivalent and and interchangeable with s-expressions.

HumanReadableSExpressions.jl provides two main functions, `readhrse` and `writehrse`, which read and write HRSE files,
respectively. Both functions support custom serialization and deserialization of types using StructTypes.jl.

## API

```@docs
readhrse
HrseReadOptions
writehrse
ashrse
HrsePrintOptions
HumanReadableSExpressions.CommentedElement
HumanReadableSExpressions.Extension
HumanReadableSExpressions.DENSE
HumanReadableSExpressions.PairMode
HumanReadableSExpressions.CONDENSED_MODE
HumanReadableSExpressions.DOT_MODE
HumanReadableSExpressions.EQUALS_MODE
HumanReadableSExpressions.COLON_MODE
```
