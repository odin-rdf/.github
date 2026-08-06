# odin-rdf — an RDF stack for the Odin programming language

This directory is not itself a repository. It is the shared checkout root for four
independent GitHub repositories that together form a layered RDF toolchain for Odin,
written from scratch in Odin with no external dependencies (LMDB being the single,
isolated exception). Each repo is independently usable and depends only *downward*.

```
odin-rdf-parser   formats + data model      ← the foundation
      ↓
odin-rdf-store    storage + match interface
      ↓
odin-rdf-sparql   query engine              odin-rdf-shacl   validation engine
                                            (peer of sparql; optionally consumes it)
```

Each repo is developed with the **Metis** tools and Metis MCP: `.metis/vision.md` is
the strategic source of truth, with initiatives, tasks, ADRs, and backlog under
`.metis/`. Read the relevant `vision.md` and ADRs before making design decisions —
they record the *why* behind the contracts described below.

## The projects

### odin-rdf-parser — `RDF-*` — complete

Streaming parsers and emitters for the four core RDF serializations plus the shared
data model. Packages: `rdf` (terms, triples, quads, equality/hashing/cloning/interning,
vocabulary constants), `rdf/triples` (N-Triples), `rdf/quads` (N-Quads), `rdf/turtle`,
`rdf/trig`. All four format packages share one API shape: `parser_init` / `parser_next` /
`parser_destroy` and `emitter_init` / `emit` / `emitter_finish` / `emitter_destroy`.

Status: core scope delivered. 100% conformance on the 10 vendored W3C suites (1045 tests),
RDF 1.2 / RDF-star included, with steady-state-zero-allocation parsing verified by benchmarks.
Key ADRs: `RDF-A-0001` (zero-copy slice-borrowing parser style, designed around LMDB's
read semantics) and `RDF-A-0002` (term representation as a tagged union with value semantics).
Input contract: whole document in a caller-owned buffer, mmap for large files; parser memory
is bounded by nesting depth and the prefix map, not document size.

Out of scope: RDF/XML, JSON-LD, N3 — and everything downstream.

### odin-rdf-store — `STORE-*` — both backends shipped

The queryable storage layer and, more importantly, the **match interface** that every
downstream engine programs against: `match(subject, predicate, object, graph)` with
per-position wildcards, returning streaming iterators. Packages: `store` (interface,
term dictionary, permutation indexes), `store/memstore` (in-memory reference backend),
`store/kvstore` (persistent, LMDB-backed). One shared conformance suite (`conformance/`)
runs verbatim against both backends at both `Term_ID` widths.

Key ADRs: `STORE-A-0001` (kind-tagged dense `Term_ID`s with build-time width — quads are
`[4]Term_ID`, so joins and dedup are integer comparisons and a term's kind is readable
without a dictionary lookup), `STORE-A-0002` (match interface as a procedure-set convention —
compile-time backend binding, no dynamic dispatch on the hot path), `STORE-A-0003`
(LMDB persistent format).

The interface is deliberately minimal and grows only on downstream evidence. The backlog
(`.metis/backlog/features/`) holds the anticipated planner-support surface: snapshot reads,
ordered iteration, cardinality estimates, `find_term`, named-graph introspection.

### odin-rdf-sparql — `SPARQL-*` — parser and evaluation engine complete

SPARQL 1.1 Query with the SPARQL 1.2 surface (triple terms, reified triples, annotations,
VERSION): hand-written recursive-descent parser → AST → W3C algebra (§18.2/§18.4), plus an
evaluation engine that runs the algebra against any store backend *through the match
interface alone*. Packages: `sparql` (tokenizer, parser, translation, SSE algebra printer,
backend-independent evaluation), `sparql/memstore`, `sparql/kvstore` — the engine
instantiated per backend, so an in-memory-only program never links LMDB.

Status: 352 vendored syntax tests (154 SPARQL 1.1, 198 SPARQL 1.2) and 483 evaluation tests
across 35 suite directories, each run against **both** backends at **both** `Term_ID` widths.
Remaining backlog: GRAPH scoping for OPTIONAL/MINUS, and a family-wide term-identity question
(language-tag case, IRI normalization).

Out of scope: result serialization (SPARQL JSON/XML writers), SPARQL Update, the HTTP and
Graph Store protocols, federation (SERVICE), full-text search.

### odin-rdf-shacl — `SHACL-*` — **not yet implemented**

Only scaffolding exists: `LICENSE`, `Makefile`, `ols.json`, and `.metis/vision.md`. No
initiatives, tasks, ADRs, or source. A peer of odin-rdf-sparql on the same foundation —
shapes graphs are ordinary RDF loaded via the parser, and validation reads the data graph
through the store's match interface.

Planned: shapes-graph loading and compilation into a shapes model, SHACL Core (target
resolution, the full Core constraint catalogue, property paths, logical combinators,
shape-based constraints), `sh:ValidationReport` result graphs plus a programmatic result
API, and the official W3C SHACL suite run hermetically. **SHACL Core must have zero
dependency on odin-rdf-sparql**; SHACL-SPARQL (`sh:sparql` constraints and SPARQL-based
constraint components) is a strictly optional later phase — the Makefile notes exactly
where the `sparql:` collection gets added when that phase starts.

Out of scope: SHACL Advanced Features (rules, functions), inference/entailment, servers.

## Family-wide conventions

- **Libraries, not applications.** Primitives over frameworks: each layer supplies building
  blocks and leaves policy to consumers. No servers, no protocol layers, anywhere.
- **Suite-driven correctness.** The official W3C test suites define "done" and are vendored
  for offline, hermetic, reproducible runs. Not example programs.
- **Consume the interface, don't bypass it.** Downstream projects touch storage only through
  the store's published match contract. Capability gaps become evidence-backed upstream
  proposals, never backend-specific workarounds.
- **Idiomatic Odin.** Explicit memory management, allocator awareness, straightforward
  procedural APIs, streaming over materialization.
- **Zero-copy discipline.** Honor the borrowing/lifetime model of `RDF-A-0001`; interned
  terms and mapped pages over defensive copies.
- **Contract-level doc comments** on every public API — the standard set by odin-rdf-parser.
- **Sibling checkouts, reached via collections** — never vendored copies:
  `-collection:rdf=../odin-rdf-parser`, `-collection:store=../odin-rdf-store`. Declared in
  each `Makefile` and mirrored in `ols.json`. Note that a collection resolves in the
  *importing* compilation: a project using the store must also declare `rdf:`, because the
  store's own sources import it.
- **Dual-width testing.** `Term_ID` width is a build-time choice (`-define:RDF_STORE_TERM_ID_BITS`,
  64-bit default, 32-bit opt-in). Anything width-sensitive is tested at both.
- **Deployment shape** driving the design: ~200 processes per physical machine, each embedding
  a store. CPU frugality is a first-order requirement.

## Commands

odin-rdf-parser (no Makefile — invoke `odin` directly from the repo root):

```
odin test rdf -all-packages   # unit tests for the model and all four formats
odin test tests/w3c/harness   # the 10 vendored W3C suites (1045 tests)
odin test tests/guards        # allocation guards for the zero-copy paths
odin test tests/readme        # the README's compile-verified examples
odin run bench -o:speed       # throughput benchmarks
```

odin-rdf-store, odin-rdf-sparql, odin-rdf-shacl (Makefile-driven; `make help` lists targets):

```
make test    # full suite at both Term_ID widths
make check   # vet every package at the default width
make bench   # build and run benchmarks with release flags
make clean   # remove build/
```
