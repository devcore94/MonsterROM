# QPR2 sparse collection APIs for Samsung One UI 9

This ordinary Paradigm patch adds the five `compute` APIs from the local
`android17QPR2gsi` CRB project, build `CP41.260831.007.A3`:

- `SparseArray.compute(int, IntObjFunction)`
- `LongSparseArray.compute(long, LongObjFunction)`
- `SparseIntArray.compute(int, IntBinaryOperator)`
- `SparseLongArray.compute(int, LongBinaryOperator)`
- `SparseBooleanArray.compute(int, IntBinaryOperator)`

The two new `android.util.function` callback interfaces are included with their
original generic signatures and functional-interface annotations. Source DEX-041
container entries are read directly; `SOURCES.json` records the GSI JAR hash and
the exact method bodies extracted from it. Each new method is copied unchanged.

Samsung's five collection classes retain all their existing fields and methods.
The original Samsung field layouts match those used by these QPR2 methods.
The normal builder decodes and compiles the framework; this module only adds an
ordinary patch and records `ro.unica.qpr2.collections=sparse-compute` after it
succeeds. SDK 36 does not apply it. Preflight checks reject changed field layouts,
missing dependencies and existing APIs/interfaces before the patch is applied.

Object collection callbacks receive null for absent or deleted entries, and a
null result removes the entry. Primitive callbacks receive zero for an absent
value; zero and false results remain stored entries. The Boolean variant treats
every nonzero callback result as true. Callbacks must not structurally mutate
the same collection, and this API does not add thread safety or atomicity.

The retained framework plus the additions passed all five actual-DEX reference
and type-flow checks (103 resolved references) and preserved the complete
43,544-class member inventory. A deterministic TreeMap-oracle test executed
987,124 assertions on the actual framework boot classes under ARM64 ART/QEMU,
using the existing QPR2 runtime trial, retained Samsung Bionic and native
providers. Cases cover insert/update/delete, stored null, tombstone reuse,
compaction, growth, signed boundary keys, clone isolation, callback exceptions
and Boolean conversion. Compile stubs are absent from the executed probe JAR.

This provides framework compatibility for QPR2 callers. It adds no Settings
screen. The offline interpreter test does not establish phone boot, ARM32 ART,
zygote/system_server behavior or a newly generated boot-image cohort. The normal
ROM build must rebuild its own framework and boot artifacts; the isolated JAR
used for testing is not a standalone phone update.
