# Zig ArrayMap

ArrayMap is a data structure that maps keys to values using an array of entries, optionally kept sorted by key. The contiguous layout in memory is cache friendly and can make ArrayMap a good choice for small amounts of data or data that is already sorted, written infrequently, but read many times.

```
┌┬────────────┬┬────────────┬┬────────────┬~
││   Entry    ││   Entry    ││   Entry    │~
│├────┬┬──────┤├────┬┬──────┤├────┬┬──────┤~
││Key ││Value ││Key ││Value ││Key ││Value │~
└┴────┴┴──────┴┴────┴┴──────┴┴────┴┴──────┴~
```