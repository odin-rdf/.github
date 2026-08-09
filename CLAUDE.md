# odin-rdf — an RDF stack for the Odin programming language

This directory is not itself a repository. It is the shared checkout root for four
independent GitHub repositories that together form a layered RDF toolchain for Odin,
written from scratch in Odin with no external dependencies (LMDB being the single
exception — and since 2026-08-07 no longer an isolated one: it is the only storage
backend, so everything from odin-rdf-store up links it). Each repo is independently
usable and depends only *downward*.

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

### odin-rdf-store — `STORE-*` — one backend, over LMDB

The queryable storage layer and, more importantly, the **match interface** that every
downstream engine programs against: `match(subject, predicate, object, graph)` with
per-position wildcards, returning streaming iterators. Packages: `store` (the vocabulary
and the interface contract) and `store/kvstore` (the backend: term dictionary, three
permutation indexes, LMDB-backed). The conformance suite (`conformance/`) is the
executable form of the contract and runs against kvstore at both `Term_ID` widths.

**`store/memstore` — the in-memory reference backend — was retired on 2026-08-07**
(`STORE-A-0006`, STORE-I-0003), together with `sparql/memstore` and `shacl/memstore`.
No consumer outside the test suites had ever asked for one, and the transaction model
the layers above need came out dominated by accommodating a backend with no versioning.
Two consequences run family-wide: **every consumer links LMDB**, and **every dataset is
a filesystem path** — LMDB has no anonymous or in-memory mode. The second is softened but
not repealed by `open_ephemeral` (v0.3.0): a scratch dataset is still a file, but no
caller has to name it, make it unique, or clean it up, and it dies with the process. The
suites in every repo use it; it is not for data anyone keeps. The core/instantiation split
in every repo survives, and the `conformance.Backend` adapter is retained, so a second
backend is an addition rather than an excavation.

Key ADRs: `STORE-A-0001` (kind-tagged dense `Term_ID`s with build-time width — quads are
`[4]Term_ID`, so joins and dedup are integer comparisons and a term's kind is readable
without a dictionary lookup), `STORE-A-0002` (match interface as a procedure-set convention —
compile-time backend binding, no dynamic dispatch on the hot path), `STORE-A-0003`
(LMDB persistent format), `STORE-A-0006` (the single-backend stance, and what it retracts
from the vision), `STORE-A-0007` (transactions and snapshots: one `Txn` handle, two modes,
and **a read transaction *is* the snapshot** — no separate snapshot type anywhere),
`STORE-A-0008` (transaction time: format v2, the negated epoch suffix, and as-of on the
transaction).

**Transactions were the v0.3.0 release line** and both siblings adopted them: shacl
validates through a caller's write transaction (validate-before-commit), sparql holds a read
transaction for a `Query`'s lifetime (one query, one dataset). Every operation has a `_txn`
form; the bare procedures are unchanged and *defined* as autocommit. v0.4.0 followed from a
Windows failure `open_ephemeral` surfaced downstream (`STORE-T-0042`).

**Transaction time is the current release line, and it is unreleased on `main` as of
2026-08-08** (`STORE-I-0005`, `STORE-A-0008`). It is the largest change since the LMDB
backend itself and it changes what the store *is*:

- **A quad has a lifetime.** Every index key carries the epoch of the transaction that wrote
  it, **bitwise-complemented so a quad's versions sort newest-first**, and every entry
  carries an assert/retract flag. A current-state read finds the live version in one seek
  whatever the edit depth — that negation is the whole design, and without it the store
  would get slower the longer it ran.
- **`remove` exists, and it retracts rather than erases.** `remove(ds, pattern)` takes a
  `Match_Pattern`, not a quad, and appends a retraction. `STORE-A-0002` point 5 specified it
  as *logical visibility* four ADRs before anything implemented it, and it is satisfied **as
  written rather than revised**. Nothing is ever physically deleted; the dictionary never
  reclaims a `Term_ID`.
- **Every commit is dated and attributed.** `txn_begin` grew a defaulted annotation, so every
  existing call site in all three repos compiles unchanged. A write naming nobody is recorded
  as the reserved IRI `…/ns/store#unattributed` — an ordinary term, so "who" is total.
  Two times are stored per commit, and where a clock ran backwards **they disagree and an
  auditor can see that they disagree**.
- **The past is readable, and it costs the siblings nothing.** `txn_begin_as_of(s, epoch)`
  returns a read transaction carrying a horizon, and *every* read through it is as-of — so
  `sparql.query_init_txn` and `shacl_kvstore.session_init_txn`, both of which already take a
  `^Txn`, inherit it with no source change. Verified, not assumed. `epoch_at` turns a
  wall-clock time into a horizon; `match_history` + `epoch_info` answer "who changed X",
  which is deliberately **not** a SPARQL question, since `match` hides version boundaries.

**Format version 2 does not read version 1 and there is no migration** — an unknown format
aborts the open, the rule the format already had. Two costs, measured: a single autocommit
`insert` of a new quad is **−28%** (set membership is a seek where a failing `NOOVERWRITE`
put used to do it; on the bulk-load path it is −4 to −9%), and the database is **+15%** on
disk. ~~**v0.4.0 remains the pin in both consumers** until v0.5.0 is tagged, which is held
until `STORE-T-0052` lands as-of tests in both siblings.~~ **Superseded 2026-08-09: v0.5.0 is
tagged and is the pin in both consumers**, and in odin-rdf-shacl a documented floor
(`SHACL-T-0030`) rather than a pin.

The interface is deliberately minimal and grows only on downstream evidence. The backlog
(`.metis/backlog/features/`) holds what is left of the anticipated planner-support surface:
**ordered iteration (`STORE-T-0015`), cardinality estimates (`STORE-T-0018`), and
named-graph introspection (`STORE-T-0016`)** — plus `STORE-T-0053`, a costing rather than a
capability. Snapshot reads, `find_term`, `remove`, `triple_parts`, `insert_all`, sentinel
reservation and the named-graph wildcard came off that list by being built.

**The named-graph wildcard is `store.NAMED_GRAPHS`, unreleased on `main` as of 2026-08-09**
(`STORE-T-0017`): a fourth sentinel, valid in the graph position of a `Match_Pattern` and
nowhere else, meaning "every graph that has a name". It is the first sentinel added for a
*cost* rather than for an expressiveness gap — matching `WILDCARD` and dropping the
default-graph results was always correct, and always read the default graph to do it. kvstore
answers by ending the scan instead of filtering it, which the ID encoding gives for free:
`DEFAULT_GRAPH` carries the highest kind tag, so in a graph-first index the named graphs are a
prefix and the default graph is the tail. **Nothing observable changes until odin-rdf-sparql
builds the pattern** — `unify_quad` in `sparql/exec.odin` still post-filters, and no task
there consumes this yet.

### odin-rdf-sparql — `SPARQL-*` — parser and evaluation engine complete

SPARQL 1.1 Query with the SPARQL 1.2 surface (triple terms, reified triples, annotations,
VERSION): hand-written recursive-descent parser → AST → W3C algebra (§18.2/§18.4), plus an
evaluation engine that runs the algebra against any store backend *through the match
interface alone*. Packages: `sparql` (tokenizer, parser, translation, SSE algebra printer,
backend-independent evaluation), `sparql/srj` and `sparql/srx` (SPARQL results JSON and
XML writers), `sparql/kvstore` — the engine instantiated against the backend. `sparql`
names no backend and imports none; since memstore's retirement that split is the seam a
future backend binds to rather than a linkage guarantee.

Status: 352 vendored syntax tests (154 SPARQL 1.1, 198 SPARQL 1.2) and 483 evaluation tests
across 35 suite directories, each run against kvstore at **both** `Term_ID` widths. **A query
is one snapshot** since `SPARQL-T-0024`: `query_init` takes a read transaction and
`query_destroy` ends it, so evaluation answers about one dataset rather than about however
many its independent reads landed on; `query_init_txn` runs a query inside a transaction the
caller holds. Remaining backlog: GRAPH scoping for OPTIONAL/MINUS, and a family-wide
term-identity question (language-tag case, IRI normalization).

Out of scope: SPARQL Update, the HTTP and Graph Store protocols, federation (SERVICE),
full-text search. (Result serialization *was* out of scope and no longer is — `sparql/srj`
and `sparql/srx` ship the JSON and XML results formats.)

### odin-rdf-shacl — `SHACL-*` — SHACL Core complete (v0.1.0)

Shape-based validation, a peer of odin-rdf-sparql on the same foundation: shapes graphs are
ordinary RDF loaded via the parser, and the data graph is read through the store's match
interface alone, so the shapes model binds to any backend the store offers. Packages:
`shacl` (backend-independent core — compilation, target resolution, property paths, the
constraint catalogue, `sh:ValidationReport` building) and `shacl/kvstore` (the validator
instantiated against the backend, a peer rather than a layer).

Status: all twenty-nine non-SPARQL constraint components of §4 implemented, and all 98
entries of the W3C SHACL 1.0 suite's `core/` tree passing against kvstore at both
`Term_ID` widths — no skip list, no expected-failure file. Key ADRs: `SHACL-A-0001` (the
shapes model — it owns every term it holds, so it outlives the store it compiled from and
binds to any other) and `SHACL-A-0002` (suppressed validation: conformance without results).
`make check` still runs a `purity` target that greps a built binary for `mdb_` symbols. It
used to protect a consumer that wanted no LMDB in its link; with memstore gone there is no
such consumer, so it now catches a stray `store:store/kvstore` import in the core — internal
hygiene guarding the seam a future backend would use.

**Validate-before-commit is reachable** since `SHACL-T-0029`: `session_init_txn` binds a
`Session` to a caller's `^kvstore.Txn`, so a candidate built inside a write transaction is
validated against *the dataset that write would produce*. The alternative an isolated
store steers you toward is wrong rather than slow — every constraint that must consult
existing data reads an empty world and passes vacuously. `session_init` still means
autocommit and is still the default.

Four contracts to know before extending it:

- **An unimplemented constraint is ignored, not an error** — erroring would reject the
  spec's own non-validating annotations and every vendor extension. `shapes_ignored` returns
  what the compile skipped, and must be checked before trusting `sh:conforms true`.
- **`sh:datatype` checks the lexical form only for the datatypes it models** (xsd:string,
  boolean, the integer tower, decimal/float/double, dateTime, date, rdf:langString). Others
  skip the lexical check rather than fail it — an engine may call a lexical form invalid
  only when it knows the space.
- **`sh:pattern` is Odin's `core:text/regex`, not XPath's dialect.** Flags `i m x` carry
  over; `s` and `q` are compile-time errors rather than silent downgrades.
- **`sh:class` needs the class hierarchy in the *data* graph**, not the shapes graph.
  Validation reads one caller-named graph and cannot express a union, so a shape saying
  `sh:class ex:Asset` will not see that `ex:ResourceAsset rdfs:subClassOf ex:Asset` unless
  that triple is in the graph being validated. It is the most common way a shapes graph
  silently under-reports, and `sh:targetClass` walks the same closure.

Remaining: SHACL-SPARQL (`sh:sparql` and SPARQL-based constraint components), the only thing
that would add odin-rdf-sparql as a dependency — the Makefile notes where the `sparql:`
collection gets added. **SHACL Core does not depend on it and will not.**

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
- **A release is not done until its consumers' Current State is re-read.** Version numbers
  and "remaining backlog" lists go stale silently, in `.metis/vision.md` and in this file,
  and they are what the next session trusts. When a repo here tags a release, walk the
  consumers: bump the CI pin, and re-read their vision's Current State for claims the
  release just falsified. Amend rather than rewrite — the convention everywhere here is
  that the old paragraph stands as the record of what was true, with a dated note saying
  what moved.
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
