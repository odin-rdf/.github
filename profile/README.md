# odin-rdf

An RDF toolchain for the [Odin](https://odin-lang.org) programming language,
written from scratch in Odin. LMDB — the storage engine under the store — is
the single external dependency.

Four independent libraries in a strict stack — each layer depends only on the
ones below it, and each is usable on its own.

```
odin-rdf-parser   formats, data model, and parser
      |
odin-rdf-store    storage and the match interface
      |
      +-- odin-rdf-sparql   query engine
      |
      +-- odin-rdf-shacl    shape validation
```

| Project | What it does | Status |
| --- | --- | --- |
| **[odin-rdf-parser](https://github.com/odin-rdf/odin-rdf-parser)** | Streaming parsers and emitters for N-Triples, N-Quads, Turtle, and TriG, plus the shared term/triple/quad model | All 1045 W3C conformance tests pass, RDF 1.2 / RDF-star included |
| **[odin-rdf-store](https://github.com/odin-rdf/odin-rdf-store)** | LMDB-backed quad store and the `match()` interface engines query through — transactional, with transaction time: every commit is dated and attributed, and the past is readable as-of | One shared conformance suite, run at both `Term_ID` widths |
| **[odin-rdf-sparql](https://github.com/odin-rdf/odin-rdf-sparql)** | SPARQL 1.1 Query with the 1.2 surface: text → algebra → solutions over the store's match interface, plus SPARQL results JSON and XML writers | 352 syntax and 483 evaluation tests, run at both `Term_ID` widths |
| **[odin-rdf-shacl](https://github.com/odin-rdf/odin-rdf-shacl)** | SHACL Core validation of data graphs against shapes graphs | All 98 entries of the W3C `core/` suite pass, run at both `Term_ID` widths — SHACL-SPARQL is a later phase |

## What these are

Libraries, not applications. Each layer supplies primitives and leaves policy to
its consumers — there are no servers or protocol layers anywhere in the stack,
by design.

Correctness is defined by the official W3C test suites, vendored into each
repository so runs are hermetic and reproducible offline. Everything is
idiomatic Odin: explicit memory management, allocator awareness, streaming over
materialization, and zero-copy parsing that leaves the document in a
caller-owned buffer.

Start with [odin-rdf-parser](https://github.com/odin-rdf/odin-rdf-parser) — it
carries the quick-start examples and the data model the rest of the family
speaks.
