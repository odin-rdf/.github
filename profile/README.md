# odin-rdf

An RDF toolchain for the [Odin](https://odin-lang.org) programming language,
with no external dependencies.

Four independent libraries in a strict stack — each layer depends only on the
ones below it, and each is usable on its own.

```
odin-rdf-parser   formats, data model, and parser
      |
odin-rdf-store    storage and the match interface
      |
      +-- odin-rdf-sparql   query engine
      +-- odin-rdf-shacl    shape validation
```

| Project | What it does | Status |
| --- | --- | --- |
| **[odin-rdf-parser](https://github.com/odin-rdf/odin-rdf-parser)** | Streaming parsers and emitters for N-Triples, N-Quads, Turtle, and TriG, plus the shared term/triple/quad model | All 1045 W3C conformance tests pass, RDF 1.2 / RDF-star included |
| **[odin-rdf-store](https://github.com/odin-rdf/odin-rdf-store)** | Quad store and the `match()` interface engines query through — in-memory and LMDB-backed backends | Both backends pass one shared conformance suite |
| **[odin-rdf-sparql](https://github.com/odin-rdf/odin-rdf-sparql)** | SPARQL 1.1 Query with the 1.2 surface: text → algebra → solutions, over any store backend | 352 syntax and 483 evaluation tests, run against both backends |
| **[odin-rdf-shacl](https://github.com/odin-rdf/odin-rdf-shacl)** | SHACL Core validation of data graphs against shapes graphs | Not yet implemented |

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
