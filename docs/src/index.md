# Hrse.jl Documentation

```@contents
Depth = 4
```

## Getting Started

Hrse.jl is a Julia package for reading and writing file written in [HRSE](https://lukebemish.dev/hrse), or Human Readable
S-Expressions, which are a human-readable format for representing data and configuration files that is equivalent and
and interchangeable with s-expressions.

Hrse.jl provides two main functions, `readhrse` and `writehrse`, which read and write HRSE files, respectively.

## API

```@docs
Hrse.readhrse
Hrse.ReadOptions
Hrse.writehrse
Hrse.ashrse
Hrse.PrinterOptions
Hrse.CommentedElement
Hrse.Extension
Hrse.DENSE
Hrse.PairMode
Hrse.CONDENSED_MODE
Hrse.DOT_MODE
Hrse.EQUALS_MODE
Hrse.COLON_MODE
```
