# odin-rdf

An RDF toolchain for the [Odin](https://odin-lang.org) programming language,
written from scratch in Odin, **with no external dependencies at all**.

Four independent libraries — a strict stack from the parser up to the query
and validation engines. Each depends only downward, and each is usable on its
own.

```
odin-rdf-parser   formats, data model, and parser
      |
      +-- odin-rdf-record   tamper-evident system of record: the log,
                |           the resident projection, epoch-pinned snapshots
                |
                +-- odin-rdf-sparql   query engine
                |
                +-- odin-rdf-shacl    shape validation
```

| Project | What it does | Status |
| --- | --- | --- |
| **[odin-rdf-parser](https://github.com/odin-rdf/odin-rdf-parser)** | Streaming parsers and emitters for N-Triples, N-Quads, Turtle, and TriG, plus the shared term/triple/quad model | All 1045 W3C conformance tests pass, RDF 1.2 / RDF-star included |
| **[odin-rdf-record](https://github.com/odin-rdf/odin-rdf-record)** | The family's store. An append-only, hash-chained, segmented log is the only durable form, replayed on every start into a memory-resident projection serving epoch-pinned snapshots — third-party verifiable from the format specification alone | `v0.10.0`. Log, resident store and write path complete (format v2); cross-checked verdict for verdict against an independent Python verifier on every test run |
| **[odin-rdf-sparql](https://github.com/odin-rdf/odin-rdf-sparql)** | SPARQL 1.1 Query with the 1.2 surface: text → algebra → solutions over the record's read API, plus SPARQL results JSON and XML writers | `v0.3.0`. 352 syntax tests and 546 of the corpus's 556 evaluable entries across 39 directories |
| **[odin-rdf-shacl](https://github.com/odin-rdf/odin-rdf-shacl)** | SHACL Core validation of data graphs against shapes graphs | `v0.3.0`. All 98 entries of the W3C `core/` suite pass, with no skip list — SHACL-SPARQL is a later phase |
| **[odin-rdf-store](https://github.com/odin-rdf/odin-rdf-store)** | *Retired.* The LMDB-backed quad store both engines were originally written against, and the `match()` interface they queried through | **Retired 2026-09-07**, final tag `v0.7.0`, no consumers since both engines moved to odin-rdf-record. Read-only, kept for its ADRs |

## What these are

Libraries, not applications. Each layer supplies primitives and leaves policy to
its consumers — there are no servers or protocol layers anywhere in the stack,
by design.

Correctness is defined by executable suites: the official W3C test suites,
vendored into each repository so runs are hermetic and reproducible offline —
and in odin-rdf-record, where the format is its own rather than a W3C one, an
independent verifier written from the format specification alone that must
agree with the Odin implementation on every test run. Everything is
idiomatic Odin: explicit memory management, allocator awareness, streaming over
materialization, and zero-copy parsing that leaves the document in a
caller-owned buffer.

Start with [odin-rdf-parser](https://github.com/odin-rdf/odin-rdf-parser) — it
carries the quick-start examples and the data model the rest of the family
speaks.
