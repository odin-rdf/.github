# odin-rdf — an RDF stack for the Odin programming language

This directory is not itself a repository. It is the shared checkout root for five
independent repositories that together form a layered RDF toolchain for Odin —
four on GitHub, plus odin-rdf-record (founded 2026-08-19), local until published —
written from scratch in Odin with no external dependencies (LMDB being the single
exception — and since 2026-08-07 no longer an isolated one: it is the only storage
backend, so everything from odin-rdf-store up links it; **amended 2026-08-19**:
odin-rdf-record stands apart with no LMDB and no external dependency at all). Each
repo is independently usable and depends only *downward*.

```
odin-rdf-parser   formats + data model      ← the foundation
      ↓
odin-rdf-store    storage + match interface
      ↓
odin-rdf-sparql   query engine              odin-rdf-shacl   validation engine
                                            (peer of sparql; optionally consumes it)

odin-rdf-record   system of record — a second store beside odin-rdf-store, not a
                  replacement: hash-chained log + memory-resident projection.
                  Consumes the parser only; sparql and shacl target it in the
                  future and the store today.
                  (Amended 2026-08-20: the family decided to move shacl, then
                  sparql, onto odin-rdf-record and retire odin-rdf-store; the
                  store's line above stands as the record.)
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
**ordered iteration (`STORE-T-0015`) and cardinality estimates (`STORE-T-0018`)** — the
planner surface, and neither has a consuming task in odin-rdf-sparql — plus `STORE-T-0053`,
a costing rather than a capability. Snapshot reads, `find_term`, `remove`, `triple_parts`,
`insert_all`, sentinel reservation, the named-graph wildcard and dataset introspection came
off that list by being built.

**The named-graph wildcard is `store.NAMED_GRAPHS`, unreleased on `main` as of 2026-08-09**
(`STORE-T-0017`): a fourth sentinel, valid in the graph position of a `Match_Pattern` and
nowhere else, meaning "every graph that has a name". It is the first sentinel added for a
*cost* rather than for an expressiveness gap — matching `WILDCARD` and dropping the
default-graph results was always correct, and always read the default graph to do it. kvstore
answers by ending the scan instead of filtering it, which the ID encoding gives for free:
`DEFAULT_GRAPH` carries the highest kind tag, so in a graph-first index the named graphs are a
prefix and the default graph is the tail. **Nothing observable changes until odin-rdf-sparql
builds the pattern** — `unify_quad` in `sparql/exec.odin` still post-filters, and the
consuming task is `SPARQL-T-0026`, blocked on the release.

**`graphs(ds)` and `nodes(ds, graph)` are unreleased on `main` too** (`STORE-T-0016`,
2026-08-09), and they widen what the match interface is *about*: every procedure before them
took a pattern and streamed quads, and these take a dataset and stream terms — the named
graphs, and the distinct subjects and objects of one graph. **A backend may not maintain
either**, which is contract rather than implementation: a stored graph list charges every
writer for a question only some readers ask, and with a time dimension it would have to be
versioned too, "the graphs as of last Tuesday" being already askable. Both walks go through
`match`, so a graph whose quads were all retracted is not a graph, and an as-of transaction
answers about the graphs of that moment with no new procedure. `nodes` is a two-way merge of
two skip-scans holding no set, since subjects ascend in gspo and objects in gosp. Consumers
again unchanged: `Plan_Graph_Scan` and `path_collect_nodes` still scan, and here there is no
task at all.

**Three unreleased capabilities on `main` and no tag** as of 2026-08-09 — the wildcard, the
two introspection procedures — with both consumers pinned to `v0.5.0`. Nothing schedules the
v0.6.0 that would let either sibling consume any of them.

### odin-rdf-record — `RECORD-*` — log, resident store and write path complete (format v1)

A tamper-evident **system of record**: an append-only, hash-chained, segmented log
is the only durable representation, replayed on every start into a memory-resident
store — pointer-free fact table, dictionary arena, six sorted `[]FactID`
permutations — serving epoch-pinned snapshots, aggregation, and per-entity history.
Independent verifiability is the value proposition: the chain is checkable by a
third party from the format specification alone. A second store *beside*
odin-rdf-store, not a replacement, a fork, or a backend of it — the two share no
durable format, no transaction model, and no ID scheme, and odin-rdf-store is
untouched. Consumes odin-rdf-parser only. Local repository, not yet published to
the GitHub organization. **Amended 2026-08-20 (RECORD-I-0003):** the sentence
stands as the founding stance; the family decided that day to move odin-rdf-shacl
and then odin-rdf-sparql off odin-rdf-store and onto this repository, the
siblings adapting to it and not the reverse, and to retire odin-rdf-store
afterwards. The two still share no format, model or ID scheme — "not a
replacement" is what no longer describes the plan.

The founding documents are `doc/design/{architecture,log,api}.md` — the
specification, implemented as written; a discovered divergence amends the document,
never quietly the code. The six phase-0 ADRs are decided: `RECORD-A-0001` froze the
inline-term encoding (u64 term IDs on disk, u32 resident with a 28-bit inline
payload) after its measurement gate ran; `A-0002` derived facts are not logged in
v1 (replay ends with a materialization pass); `A-0003` every literal lives in the
log, no blob store; `A-0004` six triple orders with `G` as residual tiebreaker, no
graph-first permutations; `A-0005` snapshots are refcounted resources
(acquire/use/release) and v1 permutation maintenance is flat copy-on-write;
`A-0006` validation is a hook wired at store construction — odin-rdf-shacl will own
the catalogue and validator, this store owns `Apply`, the overlay view, and
`Enforce`/`Record` semantics.

Status **as of 2026-08-19 (evening — the founding morning's "phase 1 in progress"
became "complete" the same day)**: `RECORD-I-0001` (the log of record: format,
write path, verification, tooling) **is complete; format version 1 holds real,
proven bytes and the frozen ADRs are no longer revisable.** All six tasks:
`T-0001` the pure encoding layer, golden vectors computed by an independent
Python script so the bytes answer to the document; `T-0002` the single-writer
append path behind the injectable `File_Ops` seam, crash-swept at every operation
cut point (no acknowledged epoch lost, nothing partial ever read as a record;
rotation happens *before* an append, never after); `T-0003` the open path —
`verify` (read-only) and `recover`, torn-tail recovery under §7.2's position
rule, with three implementation-discovered clarifications amended into `log.md`
(among them: a CRC-failed frame that provably ends before the file does halts as
corruption rather than truncating — it is evidence, not debris); `T-0004` replay
behind the `Consumer` seam the resident store will bind — one verifying reader
with delivery threaded through it, and a judged/altered split proven test by
test: a chain-perfect log that lies about what it says verifies and refuses to
replay; `T-0005` the `record` CLI (`verify`/`dump`/`head`) in `tool/`, dump being
the seam's second consumer with N-Quads from the parser repo's emitter — building
it surfaced a latent format collision (the §5.3 default-graph sentinel, ID 1,
against dictionary ids that start at 1), resolved by amendment: **the
default-graph sentinel is 0**, the same "none" actor and reason use; `T-0006` the
proof layer — an independent Python verifier written from `log.md` alone
(`tests/verify/`, ~270 lines of stdlib, every constant citing its section),
agreeing with the Odin verifier verdict for verdict, head hash and epoch
included, over a 29-case fault corpus on every `make test`, plus the ISMS-scale
measurement: **verify 105–272 ms, replay 166–342 ms** across both §9 epoch shapes
(16.9–38.4 MB logs, 4×10⁵ ops, ~10⁵ terms) — an order of magnitude inside the
vision's sub-second criterion. Writing the Python verifier surfaced no
documentation bug, which is what the amend-don't-diverge convention was for.

Next: `RECORD-I-0002` (the resident store: replay-built projection and the
snapshot read API) — fact table, dictionary arena, six permutations, refcounted
snapshots, the `api.md` §12 read API, and writer resume; `Apply` and the
validation hook stay deferred to the initiative after, where `bind.md`'s asks
land. Note for dev machines: `make test` now requires `python3` (the
cross-implementation suite); the *library* still has no external dependency
beyond the parser.

**Superseded 2026-08-20 — both done the same day.** `RECORD-I-0002` (the
resident store) completed: `store_open` boots end to end in 205–278 ms at ISMS
scale, serving the `api.md` §12 read API over refcounted snapshots. Then
`RECORD-I-0003` (the write path): **`apply(s, Changeset)` is the one entrance** —
asserts and retracts as `rdf.Quad`s with actor, reason and a `Mode`; `log.md`
§5.3's preconditions judged against head *and* the changeset's own earlier ops,
refused with a typed `Apply_Error` naming the op; resident mutation *before*
the fsync in writer-private state no published reader can observe (decision 1,
amending `log.md` §7.1 and `RECORD-A-0006`), rolled back exactly on failure;
then append, fsync, publish. **A `Validator` is wired once at `store_open`** and
receives the candidate as an ordinary `Snapshot` at the new epoch — the overlay
view is the real read API over the post-state; `Enforce` refuses before a byte
is written, `Record` commits and reports, and **the log does not record that a
judge objected** (decision 5). Around it: the term encoder and intern; the
published **term index** replacing the dictionary map (reads safe under a live
writer — acquire takes a mutex, the read path none, and the index set carries
copies of every list a reader indexes, a divergence from `api.md` §13.8 found
and closed); `snapshot_kind` and `snapshot_exists`; the **writer inside the
`Store`** (`store_open` fills `s.writer`, `store_close` releases both);
**`Mem_FS`/`mem_file_ops`**, the in-memory seam for suites and scratch;
**`record/ingest`** — `turtle`, `ntriples`, `trig`, `nquads` → `[]Op` with
`blank_prefix` scoping, a subpackage so the core still imports `rdf` alone; and
the consumer id range `CONSUMER_ID_FIRST ..= CONSUMER_ID_LAST` stated in
`api.md` §3. Measured: one commit at 4×10⁵ facts **31–35 ms** on the memory seam
(the permutation rebuild of `RECORD-A-0005`'s flat copy-on-write — its trigger
re-read, the delta structure stays deferred), bulk load of the ISMS corpus as
one epoch 222–267 ms, resident 21.2 MB. Proven by replay equivalence on both
seams, a crash sweep across `apply`, both verifiers over apply-written logs, a
reader/writer torture under the memory checker, and the W3C suites through
`ingest` by reference.

**What moves next is on the siblings' side**: the odin-rdf-shacl port
initiative (unblocked), then odin-rdf-sparql's. What they need from here —
a published repository and a tag to pin, `-collection:record=../odin-rdf-record`,
the POSIX-only note for a Windows leg (`mem_file_ops` is platform-free), and a
seven-point handoff mapping the store's read and write APIs onto theirs — is in
`RECORD-I-0003`'s Status section. Publication and tagging are the owner's.

Two deliberate departures from family conventions, both recorded in the repo:
**no `Term_ID` width matrix** — both widths are fixed by design because the inline
encoding is frozen at first write; and **POSIX only** — Linux is the production
environment, darwin is development (F_FULLFSYNC with fsync fallback), and there is
no Windows `File_Ops`; sync-primitive CI tests may be gated to Linux.

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
  (odin-rdf-record is exempt by design: its widths are fixed because the inline
  encoding is frozen at first write — see its section.)
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

odin-rdf-record (Makefile-driven; no width matrix — its widths are fixed by design;
`make test` requires python3 for the cross-implementation verifier):

```
make test    # the test suite, the fault corpus, and the scale measurement
make check   # vet every package with -vet -strict-style
make tool    # build the record CLI (verify, dump, head) into build/record
make clean   # remove build/
```
