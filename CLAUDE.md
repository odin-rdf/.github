# odin-rdf — an RDF stack for the Odin programming language

This directory is not itself a repository. It is the shared checkout root for five
independent repositories that together form a layered RDF toolchain for Odin —
four on GitHub, plus odin-rdf-record (founded 2026-08-19; published and tagged `v0.1.0` on 2026-08-20) —
written from scratch in Odin with no external dependencies (LMDB being the single
exception — and since 2026-08-07 no longer an isolated one: it is the only storage
backend, so everything from odin-rdf-store up links it; **amended 2026-08-19**:
odin-rdf-record stands apart with no LMDB and no external dependency at all; **amended
2026-08-20, evening**: odin-rdf-shacl no longer links it either — it moved onto
odin-rdf-record, SHACL-I-0004 — so today LMDB is linked by odin-rdf-store and
odin-rdf-sparql, and after sparql's port by the store alone, which is to be retired; **amended
2026-08-25**: sparql's port is done — SPARQL-I-0003 — so **odin-rdf-store is the only
repository here that links LMDB, and it has no consumers left**. For everything anyone
builds on today, "no external dependencies" is true without qualification). Each
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
                  (Amended 2026-08-20, evening: shacl's move is done —
                  odin-rdf-shacl consumes parser + record, nothing else.
                  sparql is still on the store until its own port.)
                  (Amended 2026-08-25: **sparql's move is done too**, SPARQL-I-0003.
                  Both ports are complete and odin-rdf-store has no consumers.
                  The shape of the family is now the one below.)
```

**The family as of 2026-08-25**, the diagram above standing as the record of how it
got here:

```
odin-rdf-parser   formats + data model      ← the foundation
      ↓
odin-rdf-record   system of record — hash-chained log + memory-resident
      ↓           projection, epoch-pinned snapshots. Consumes the parser
      ↓           only. The one store, for both engines.
      ↓
odin-rdf-sparql   query engine              odin-rdf-shacl   validation engine
                                            (peer of sparql; optionally consumes it)

odin-rdf-store    RETIRABLE. No consumers since 2026-08-25. The last thing
                  holding it was odin-rdf-sparql's port; that is done. It is
                  still a working, tagged, tested LMDB store — retiring it is a
                  decision about maintenance, not a repair. See the retirement
                  handoff in odin-rdf-sparql's SPARQL-T-0039.
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

**v0.1.1 (2026-08-20)** — one scanner fix, `RDF-T-0025`: an unterminated long string
literal reported the EOF line and a negative column (the literal's own newlines had moved
the line start past the opener); it now reports the opener. Found by odin-rdf-record's
W3C sweep (RECORD-T-0017), unseeable by any vendored suite. odin-rdf-shacl pins it, and is
the only consumer with a pin to move: odin-rdf-record has no CI yet *(it does since
2026-09-01, pinning `v0.1.2`)* and builds against the
parser's `main` locally; odin-rdf-sparql is left alone by decision until it has been ported
to odin-rdf-record; odin-rdf-store is on its way out and is not touched. **odin-rdf-sparql's own query scanner has a line-for-line copy of the
defect** (`sparql/scanner.odin`, `scan_long_string`), and odin-rdf-app prints that
position; not yet filed there. *(Amended 2026-08-25: **it is filed and fixed** —
`SPARQL-T-0042`, the same change on the same branch, with a scanner test pinning the
opener's line and column across newlines. odin-rdf-app was printing `at 4:-10`; the call
site is `src/main.odin:235` and it needs no change. odin-rdf-sparql is no longer "left
alone" either — its port is done and it pins `v0.1.2`.)* *(Amended 2026-08-25, evening:
the call site is `src/main.odin:314` — odin-rdf-app was ported the same day and the file
grew above it. It still needs no change.)*

**v0.1.2 (2026-08-25)** — one resolver fix, `RDF-T-0026`, **filed by a consumer against a
headline behaviour**: `resolve()` ran *absolute* IRIs through RFC 3986 §5.2 reference
resolution and stripped their dot segments, base or no base, so
`eXAMPLE://a/./b/../b/%63/%7bfoo%7d#xyz` was parsed as `eXAMPLE://a/b/%63/%7bfoo%7d#xyz` —
a Turtle or TriG document loading an IRI it does not contain, which Turtle §6.3 does not
permit and RDF 1.1 Concepts §3.2 forbids ("further normalization MUST NOT be performed").
`resolve()` now returns a reference carrying a scheme byte for byte and never enters §5.2.
A second half came with it, not in the report: §5.2.2's `R.path == ""` branch had been
calling `remove_dot_segments` where the algorithm does not, invisible only while every
base came back normalized from `resolve()` itself — so `RDF-T-0013`'s "bases are always
dot-normalized" is now false and is amended there. Shared by `rdf/turtle` and `rdf/trig`;
`rdf/triples` and `rdf/quads` import neither. 1045/1045 unchanged — **no vendored entry
expected an absolute IRI to be normalized.**

Two consumers should care, in opposite ways. **odin-rdf-sparql filed it** — from
`SPARQL-T-0021`'s split, the DAWG entry named `normalization-02` turning out to assert
that *no* normalization happens, which is this family's policy, and to fail only because
the Turtle parser mangled the term — and pins `v0.1.2`, enabling `sparql10-i18n` at 5/5
with nothing in its own sources changing. **odin-rdf-record should care most and has not
moved**: `record/ingest` loads through this parser and the log is the durable
representation, so below `v0.1.2` a system of record can log an IRI its source document
did not contain — faithfully, tamper-evidently, and wrongly. It has no CI and builds
against the parser's `main` locally, so it has the fix and no pin to state.
*(Amended 2026-09-01: **it has moved, and it has CI.** odin-rdf-record's first
workflow pins `odin-rdf-parser@v0.1.2` for exactly the reason above — the family's
last repository to get CI, on ubuntu and macos, two runners and not three because it
is POSIX only by design. Every repository here now states a parser pin.)*
odin-rdf-shacl loads shapes through the parser too and pins `v0.1.1`; odin-rdf-store is
not touched.

### odin-rdf-store — `STORE-*` — RETIRABLE as of 2026-08-25, no consumers

**Amended 2026-08-25.** Both engines have been ported off this store —
odin-rdf-shacl on 2026-08-20 (`SHACL-I-0004`), odin-rdf-sparql on
2026-08-25 (`SPARQL-I-0003`) — so **nothing in the family depends on it**, and
it is the only repository here that still links LMDB. It is not broken: it is a
working, tagged, tested store with three unreleased capabilities on `main`
(the `NAMED_GRAPHS` wildcard, `graphs`, `nodes`) that no consumer will ever
ask for. **Retiring it is a decision about maintenance, not a repair**; the
concrete handoff — what "retire" should mean, and what still points here — is
in odin-rdf-sparql's `SPARQL-T-0039`. The section below is left as written.

### odin-rdf-store — `STORE-*` — one backend, over LMDB (superseded 2026-08-25)

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

### odin-rdf-record — `RECORD-*` — log, resident store and write path complete (format v2)

A tamper-evident **system of record**: an append-only, hash-chained, segmented log
is the only durable representation, replayed on every start into a memory-resident
store — pointer-free fact table, dictionary arena, six sorted `[]FactID`
permutations — serving epoch-pinned snapshots, aggregation, and per-entity history.
Independent verifiability is the value proposition: the chain is checkable by a
third party from the format specification alone. A second store *beside*
odin-rdf-store, not a replacement, a fork, or a backend of it — the two share no
durable format, no transaction model, and no ID scheme, and odin-rdf-store is
untouched. Consumes odin-rdf-parser only. Local repository, not yet published to
the GitHub organization *(published to `odin-rdf/odin-rdf-record` and tagged
`v0.1.0` on 2026-08-20 — the pin the sibling ports use; **the repository was
private at first and the first consumer CI run failed on that — it is public
now**. Two more tags the same day, both cut from findings of the shacl port:
`v0.2.0` (RECORD-T-0019, `ingest` emits a document's *set* of statements — a
legal Turtle document that states a triple twice loads, where before `apply`
refused the second assert; one W3C SHACL entry cannot load below it) and
`v0.3.0` (RECORD-T-0020, distinct `Term_ID`/`Fact_ID`/`Epoch` types across the
public API — an engine holding `u32` ids does not compile against it; holding
`record.Term_ID` natively is the adaptation). **`v0.3.0` is the pin, and a floor,
in odin-rdf-shacl.**)*. **Amended 2026-08-20
(RECORD-I-0003):** the sentence
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

**Amended 2026-08-25 — `RECORD-I-0004`, RDF 1.2's two term kinds, and the first
time this format has moved.** `v0.4.0` is tagged. The reservation
`architecture.md` §11.3 made — tag `0x07`, "the only decision needed today is
whether to reserve the tag byte" — was spent: **triple terms** encode as
`0x07 | sID | pID | oID`, permitted in every position, with the intern and the
decoder recursing and §5.2's ordering rule now transitive and enforced on both
the write and the replay path (`Load_Error.Term_Order`). **Base-direction
literals** got tag `0x08`, which had no reservation ([[RECORD-A-0007]]), and an
empty language with a direction is still not a term. **Format version 2 does not
read version 1 and there is no migration** — the format's standing rule, and
there are no deployments. Two ADRs carry the design: `RECORD-A-0007` (the version
bump) and `RECORD-A-0008` (how a recursive term is decoded, and who owns it).

The initiative was filed *by* a consumer: odin-rdf-sparql's port
(`SPARQL-I-0003`) was gated on it rather than allowed to narrow a headline
capability of that engine — 38 evaluated W3C entries in
`sparql12-eval-triple-terms` would have gone dark. This is not the family stance
weakening. It is the other thing the stance allowed for: a capability this
store's own architecture named, costed and left unbuilt until a consumer needed
it, and the encoding built is the one specified before sparql asked. What a
consumer sees: `Term_Kind` gains **`.Triple`** (an exhaustive `switch` on it is a
compile error until it is handled — which is how odin-rdf-shacl found out);
**`snapshot_triple_parts`** reads a triple term's three component ids with no
allocation, no decode and no recursion, so taking one apart is *cheaper* here
than in odin-rdf-store, where it cost two round trips (`SPARQL-T-0019`); and
**`snapshot_term` can return a term it owns** — a triple term wholly, a split IRI
its joined string — paired with the new **`snapshot_term_destroy`**, which is a
no-op for the borrowing kinds. Proven against the W3C rdf12 eval suites end to
end (29 turtle, 25 trig documents, every one carrying a triple term), with both
verifiers still agreeing over the fault corpus — the Python one needed one
constant changed, for the header's sake and not the encoding's.

**Amended 2026-08-27 — `v0.5.0`, `RECORD-T-0029`: graph scope is stated.** The
first release cut for the *application* rather than an engine. Its workspace
design (2026-08-26; a named graph per workspace, `W` and `W/private` as
audiences, a read scope computed per request as a graph set that is an
authorization ceiling) was the first consumer to design a *computed*
`Filter.graphs` — and `Filter.graphs` decided scoped-versus-unscoped by whether
the slice was nil, which Odin makes a fact about allocation history: a
zero-value dynamic array's slice is nil, one made with a capacity hint is not,
so the same empty set read the whole store or nothing. `Filter` now carries
`scope: Graph_Scope { All, Set }` beside `origin`, under `origin`'s rule — no
valid zero, refused by `range_iter` at the first read; under `.Set` the length
alone decides. An API change, not a format change; both engines walked the same
day (`SPARQL-T-0045`, `SHACL-T-0040`: ten sites state `.All`, nothing else
moves). Filed beside it from the same design: `RECORD-T-0028` (a seventh order,
`GPOS`, so "which Risks are in this workspace" is a prefix), `SPARQL-T-0044`
(the graph set on `query_init`) and `SHACL-T-0039` (validating a set's union).
*(`RECORD-T-0028` is **built** as of 2026-08-27, on `main` and unreleased:
`Order.GPOS`, chosen when G is bound, S is not, and O is not bound without P;
`RECORD-A-0004` amended on its own review trigger; +1.6 MB at 4×10⁵ facts,
+12 ms on the sort, +5 ms mean per commit. Both engines call `snapshot_match`,
so at whatever pin includes it their graph-bound patterns become prefix reads
with no source change — sparql's `GRAPH <g>` case, `RECORD-T-0026`'s 169,055
candidates for 4,122 answers, becomes 4,122 for 4,122. No tag yet.)* *(**Tagged
`v0.6.0` the same day and walked** — `SPARQL-T-0046`, `SHACL-T-0041`: no source change
in either engine; sparql's bench re-pinned, the `graph` case at 4,122 candidates for
4,122 answers at both sizes and three other cases each narrower by exactly the named
graph's 500 facts, every solution count identical.)* *(`SPARQL-T-0044` and `SHACL-T-0039` are both **built** the same day — see the engines' sections. All four of the design's filings are built; two are released.)*
One thing to know before adopting: an unstated `Filter` reached from a spawned
thread hangs a test runner rather than failing it — grep `origin = .` without
`scope` first.

**Amended 2026-09-01 — `v0.7.0`, `RECORD-I-0005` and `RECORD-I-0007`: the
exported surface is a decision, and it is 73 names where it was 195.** Odin
exports every top-level declaration not marked `@(private)`, so what this
package offered was a residue of what its own code needed to share with `tool/`,
with the `tests/*` suites, and with itself — 65 of the 195 were the API, and
typing `record.` listed all 195. **`doc/api-surface.txt` now states the surface
normatively and `make api` holds it**, running inside `make check` on every
runner: a name that quietly stops being `@(private)` fails the build.

The set was computed rather than grepped, and in both directions: 18 names are
reached only by inference and appear in no consumer's source (a consumer writes
`r := snapshot_match(...)` and never names `Range`), while three documented read
verbs — `snapshot_bytes`, `snapshot_visible`, `snapshot_derived` — had to be
**promoted back** after being marked private for want of a caller. Under-
exporting is as wrong as over-exporting.

Two structural changes came with it, because `@(private)` is package-scoped.
**The proof, scale and tool suites moved into the package** as
`record/*_test.odin` — a suite outside it had been holding 43 names public — and
the scale measurement keeps its optimized run behind
`when #config(RECORD_SCALE, false)` plus a second `make test` pass.
**`log_read` is new and public**: the decoded counterpart to `replay`, owning
the dictionary and the term resolution and handing a consumer `rdf.Quad`s valid
for the callback's duration. It exists because `tool/` had been reassembling the
format by hand, which is what kept 13 format internals exported; `replay` and
`Consumer` are private with them. Writing that loop once surfaced two defects,
both now pinned: a commit record carries its term definitions *after* the header
naming the attribution (so resolving there reads an id the dictionary does not
yet hold), and the CLI passed no `resolve_term` to `term_decode`, so **`record
dump` could not read a triple term** — any log written since `v0.4.0`.

**Not a format change**: the log, the encoding and both verifiers are untouched,
and a `v0.6.0` store reads and writes identically. Both engines compile with no
source change and were walked the same day (`SHACL-T-0042`, `SPARQL-T-0047`) —
122 names stopped being exported and neither engine named one of them, which is
the strongest test the "consume the interface, don't bypass it" convention has
had. Two near-misses worth knowing: `DEFAULT_GRAPH` (the log's sentinel) is
private now while `MATCH_DEFAULT_GRAPH` (a `Pattern`'s G binding) is API; and
`dict_bytes`/`store_fact` are gone in favour of `snapshot_bytes`/`snapshot_fact`,
which the record's own out-of-package suite had been bypassing until this work.
`RECORD-A-0009` decided to move the format layer into a `record/log` subpackage
and `RECORD-A-0010` superseded it the same day — the split would have forced 38
private symbols public and taken the total exported from 121 to 161.

**What moves next is on the siblings' side**: the odin-rdf-shacl port
initiative (unblocked), then odin-rdf-sparql's. *(Both done as of
2026-08-25 — shacl 2026-08-20, sparql `SPARQL-I-0003`. odin-rdf-record's
consumers are now both engines, and it is the family's only store.)* *(Superseded 2026-08-20, evening:
shacl's port is done — see below.)* What they need from here —
a published repository and a tag to pin, `-collection:record=../odin-rdf-record`,
the POSIX-only note for a Windows leg (`mem_file_ops` is platform-free), and a
seven-point handoff mapping the store's read and write APIs onto theirs — is in
`RECORD-I-0003`'s Status section. Publication and tagging are the owner's
*(done 2026-08-20: `odin-rdf/odin-rdf-record`, tag `v0.1.0` at `e29764e`)*.

**Handoff for the sibling ports — what a session working on odin-rdf-shacl or
odin-rdf-sparql needs to know (2026-08-20, evening).** Neither port initiative
exists yet; they are created on the siblings' side, shacl first, sparql second.
*(Superseded the same evening: **shacl's port is done** — `SHACL-I-0004`, seven
tasks, one day, all 98 W3C entries green on the record, `make test` with parser
and record as the only dependencies. **sparql's is next**, and its initiative
does not exist yet. *(Superseded 2026-08-25: **sparql's port is done** —
`SPARQL-I-0003`, ten tasks. Both engines are on the record and
odin-rdf-store has no consumers. The handoff below served its purpose and
stands as the record of what it asked for.)* The handoff for it is `SHACL-T-0037`'s Status
(`odin-rdf-shacl/.metis/initiatives/SHACL-I-0004/tasks/SHACL-T-0037.md`): what
the port cost, the call-site patterns that worked, the record facts an engine
must know (a candidate is the delta; `.Record` commits a violation; terms are not
epoch-scoped; language tags fold on intern; non-canonical numerics are distinct
terms; inlineable literals always resolve; triple terms are refused — *amended
2026-08-25: they are stored, `RECORD-I-0004`*), and the
note that shacl's no-dual-backend and one-and-only-store decisions were made
for shacl — sparql asks the owner, not assumes. The bullets below stand as the
record and are still accurate, with one correction: pin `v0.3.0` or later, not
`v0.1.0`. **Amended 2026-08-25: `v0.4.0` or later** — a sparql port needs triple
terms, and a shacl-shaped engine needs the two API changes that came with
them.)*
The seven-point API mapping and the CI list are in `RECORD-I-0003`'s Status
(`odin-rdf-record/.metis/initiatives/RECORD-I-0003/initiative.md`); what is *not*
there:

- **The pin mechanism is the existing one.** Both siblings' `ci.yml` check out
  the parser and the store as sibling directories at released tags
  (`odin-rdf-parser@v0.1.0`, `odin-rdf-store@v0.6.0`, `actions/checkout@v5` with
  `repository:`/`ref:`/`path:`), and reach them through `COLL :=
  -collection:rdf=../odin-rdf-parser -collection:store=../odin-rdf-store` in the
  Makefile, mirrored in `ols.json`. The port adds `odin-rdf-record@v0.1.0` the
  same way as `-collection:record=../odin-rdf-record`; `rdf:` stays because the
  record's sources import it. shacl's CI comment explains its store *floor*
  history (`SHACL-T-0020`, `-T-0028`, `-T-0030`) — the record pin wants the same
  kind of comment. Windows legs: `record` has no Windows `File_Ops`; suites use
  `mem_file_ops` (platform-free, `Mem_FS`), and the posix file is
  `#+build linux, darwin`, so `record` compiles on Windows without it.
- **What a harness call site becomes.** `open_ephemeral` → `Mem_FS` +
  `store_open(&s, "x", mem_file_ops(&fs))` … `store_close(&s)` (every snapshot
  released first — `store_destroy` asserts it); `load_turtle(ds, src, graph)` →
  `ingest.turtle(src, graph, allocator, blank_prefix = <test name>, base = …)`
  + `apply(&s, {ops = ops})` + `ingest.ops_destroy(ops, allocator)`;
  `blank_prefix` is the `Load_Scope`, and **must be label characters** (`t1_`,
  not `t1/`) if anything is ever dumped and re-ingested. The ops own their terms;
  `base` is needed for documents with relative IRIs (the W3C eval inputs resolve
  against `https://w3c.github.io/rdf-tests/rdf/rdf11/rdf-turtle/`). Triple terms
  (20 of sparql's vendored data files) are refused by `apply` with
  `.Unsupported_Term` at the op — a recorded backend limit on sparql's side.
  *(Amended 2026-08-25: not any more. `RECORD-I-0004` built them and `v0.4.0` was
  cut for that port; those 20 files load. The limit that remains is the empty
  one: a base direction with no language, which is not an RDF 1.2 term either.)*
- **Term identity differs from odin-rdf-store in two places that affect SPARQL
  value semantics:** language tags are lowercased on intern (`"x"@EN` and
  `"x"@en` are one term — the canonical encoding's rule), and a non-canonical
  numeric lexical form (`"01"^^xsd:integer`) is a *different term* from the
  inlined canonical one (`"1"`) — term identity is RDF's; value equality is the
  engine's job.
- **The read side in one breath.** Ids are `u32`; `0` is unbound in a `Pattern`,
  `MATCH_DEFAULT_GRAPH` binds the default graph in G; `Filter{origin = .Any}` —
  origin must be stated *(and `scope = .All` since `v0.5.0`, `RECORD-T-0029`: an
  unstated scope is refused at the first read, and an empty `.Set` admits nothing)*; `range_iter`/`scan_next` stream fact ids, `snapshot_fact`
  reads one; `snapshot_kind` replaces `id_kind`; `snapshot_epoch_meta` carries
  actor/reason/wall; a `Snapshot` is acquire/use/release and a `Validator`'s
  candidate snapshot must not be retained. *(Amended 2026-08-25, `v0.4.0`:
  `snapshot_kind` has a fourth answer, `.Triple`, and panics on a tag it does not
  define rather than guessing `.Literal`; `snapshot_triple_parts` takes a triple
  term apart into three ids without decoding it; and `snapshot_term` is no longer
  always-borrowing — pair every decode with `snapshot_term_destroy`.)* The consumer id range for the
  engines' own values is `CONSUMER_ID_FIRST ..= CONSUMER_ID_LAST`.
- **Process.** The Metis MCP reports "no active workspace" when the session's
  working directory is this family root; work on a repo from inside it (or edit
  `.metis/*.md` directly, keeping the frontmatter's closing `---`). This file
  lives in the `odin-rdf/.github` repository (the family root is a git repo of
  its own), so family-level amendments are committed and pushed there. Tags are
  annotated, `Release vX: title` with a bulleted body. One observation owed to
  odin-rdf-parser: on an unterminated long string the scanner error's `column`
  comes out negative while `offset` and `line` are right (RECORD-T-0017).

**Amended 2026-09-04 — `v0.8.0`, `RECORD-I-0009` and `RECORD-A-0012`: the
permutations are copy-on-write B+trees of fact ids, and a commit costs 0.24 ms
where it cost 37.** Every `apply` had been running the boot path's seven-order
radix re-sort — 37.1 ms of a 37.5 ms commit at 4×10⁵ facts, 20 MB transient —
which `RECORD-A-0005` part 3 had priced as "allocator traffic" and the
application's interactive commit rate made visible. The investigation
(`record/btree_bench_test.odin`, behind `RECORD_XBENCH`) measured three shapes
over one fact table: the re-sort, a flat array merged in place (440 µs, the
recorded fallback), and the tree (9–11 µs for one assert across all seven
orders). Leaves hold fact ids only, so resident bytes are 11.1 MB packed
against 10.7 flat, drifting toward ~15.5 MB at steady-state fill between wakes;
inner nodes hold each child's minimum key and count, so `range_len` is still
exact and matches are 10–30% *faster*. Scans are 2.5 ns per candidate on both.
**Boot is unchanged in shape**: `log.md` §8's sort-once argument was re-asked
for the tree and holds by 13× (streaming inserts 568 ms against sort-and-pack
44 ms), so every wake sorts and packs full — the pack is 1.1 ms. A set that
dies on a reader's thread retires its roots for the writer to drain, so the
node arena is mutated on one thread only; `apply` inserts below 8,192 asserts
and sort-and-packs above. **Not a format change.** Both engines compile and
pass with no source change and every read pin holds — shacl's 7503, sparql's
sixteen. For a session landing here: `Range` is two ranks and `Scan` a cursor
now, `prefix_bound` is gone, and the six suites that once read `s.ord[o]` as a
slice go through `perm_collect`.

**Amended 2026-09-04, later — `RECORD-T-0044`, unreleased on `main`:
`snapshot_history(snap, p) -> Range`.** The first capability gap filed against
this store by odin-rdf-app, on adopting `v0.8.0`: one call site on a miss path
had been reading `Range.main` to tell "never asserted" from "asserted and
since retracted", and `v0.8.0` made `Range` opaque in fact. `api.md` §12.6 had
already decided the shape — history is its own entry point, not a flag on
`Filter`, so that no filter combination makes `snapshot_match` return a
retracted generation — and it is built as written: the same window, the same
`range_iter`/`scan_next`, the interval test omitted and nothing else; each id
carries its interval through `snapshot_fact` and its origin through
`snapshot_derived`. Neither engine needs it. ~~**The consumer needs a tag to pin
it** — nothing on `main` is pinnable — and cutting `v0.9.0` is the owner's call.~~
**Tagged `v0.9.0` the same evening** (`eb270c1`, GitHub release with notes) and
both engines walked — `SHACL-T-0044`, `SPARQL-T-0049`: pins bumped, no source
change, 7503 as pinned and every sparql bench count unmoved. odin-rdf-app pins
`v0.9.0` for `snapshot_history`; the consumer handoff is at the end of
`RECORD-T-0044`. One finding, about CI rather than code: the record's optimized
scale pass measures a one-second boot budget with two test threads on a shared
runner and came in at 1007 ms against 941 the run before — a rerun passed.
`RECORD-T-0045` made every clock in that pass a warning rather than a gate the
same evening: the sub-second criterion is about production hardware, a release
is measured there, and CI logs the figure without failing on it.

**Amended 2026-09-05 — `v0.9.1`, `RECORD-T-0047`: a test-only release, and
the first defect this repository's *tests* have shipped to a consumer.**
Three of them located what they needed relative to the process's working
directory rather than to their own source file: the two proof tests ran
`tests/verify/rdflog_verify.py` through `python3`, and `test_tool` ran
`build/record`. That is invisible here, where `make test` runs from the
repository root — and fatal for **odin-rdf-app**, whose suite is one binary
(`odin test <main> -all-packages`, which compiles this package's tests into
it and runs them from the application's directory): python found no script,
its stdout was empty, and every corpus case failed as "implementations
disagree" against an empty verdict, while the CLI test asserted exit codes
against a binary that was never there. `PY` and `BIN` are
`#directory + "..."` now — the form the three sibling repositories' W3C
harnesses have used all along, and the record's task cites all three as
precedent — and `test_tool` returns early with a `log.warn` when the CLI is
simply not built, a missing build reading as a missing build. The scratch
directories stay relative deliberately: they are the runner's litter, and
anchoring them would have the package write into its own checkout from a
consumer's build. **No source, format or API change**; a `v0.9.0` store
reads and writes identically. Both engines walked the same day
(`SHACL-T-0045`, `SPARQL-T-0051`): pins bumped, no source change, 7503 as
pinned and every sparql bench count unmoved — and neither ever had the
defect, their harnesses being the precedent. The rule worth carrying:
**a test locates its fixtures by `#directory`, not by the cwd**, because a
library's tests are compiled and run by its consumers.

**Where a test goes (2026-09-01, `RECORD-T-0034`).** Most of this repository's
tests are **in-package**, `record/*_test.odin`, and that is the default for
anything new. The reason is not taste: `@(private)` in Odin is *package*-scoped,
so a suite in its own package can only reach exported names, and four of them
were holding 43 internal names public — which is what `RECORD-I-0007` was
closing. `record/*_test.odin` keeps full access to everything private.

Two suites stay outside, under `tests/`, and both for the same hard reason:
`tests/ingest` and `tests/readme` import `record/ingest`, which imports
`record`, so in-package they would be an import cycle. Neither holds an internal
name — `tests/ingest` was ported onto `snapshot_fact`, `snapshot_bytes` and
`snapshot_terms` to get there, which is what a suite outside the package should
be asking anyway. `tests/verify/` is not an Odin package at all; it is the
independent Python verifier. `tests/api/api_surface.py` is the surface tool
`make api` runs.

Three things to know before adding one:

- **`_test.odin` is a naming convention in Odin, not a build tag.** Those files
  are part of package `record` for every consumer that compiles it. An
  in-package test that touches `posix_file_ops` therefore makes the *package*
  POSIX-only, which is how `RECORD-A-0011` came about — `record/proof_test.odin`,
  `scale_test.odin` and `tool_test.odin` do exactly that, deliberately and
  untagged, and Windows was dropped rather than tagged around.
- **The scale measurement is guarded**, `when #config(RECORD_SCALE, false)`, so
  the ordinary run does not execute a wall-clock budget in a debug build.
  `make test` runs a second, optimized pass for it. Only the `@(test)`
  procedures are guarded and not the helpers: an `import` is a syntax error
  inside a `when` block and an unused import is a compile error, while an unused
  procedure is neither.
- **Helpers are `@(private = "file")`**, the house convention, which is also
  what lets `WALL`, `append_framed`, `splitmix` and `BIN` exist in several test
  files at once.

Two deliberate departures from family conventions, both recorded in the repo:
**no `Term_ID` width matrix** — both widths are fixed by design because the inline
encoding is frozen at first write; and **POSIX only** — Linux is the production
environment, darwin is development (F_FULLFSYNC with fsync fallback), and there is
no Windows `File_Ops`; sync-primitive CI tests may be gated to Linux.

*(Amended 2026-09-01, `RECORD-A-0011`: **the second departure is now the family's
position, not this repository's alone. Windows is not supported from
odin-rdf-record upward.** odin-rdf-shacl and odin-rdf-sparql have dropped their
`windows-latest` legs; both run ubuntu and macos. The legs had been green, because
their suites open every store over the platform-free memory seam and never touch a
real directory — so the family was claiming that a Windows build compiles and
passes while the store beneath it cannot keep a byte there. `v0.7.0` made that
concrete: `RECORD-T-0034` moved three POSIX-using suites into package `record`, and
**Odin's `_test.odin` is a naming convention rather than a build tag**, so those
files are part of the package every consumer compiles and both engines went red.
The files stay untagged deliberately — the package genuinely does not compile on
Windows now, an honest failure rather than a half-built one. **odin-rdf-parser
keeps Windows**: platform support belongs to the layer that touches the platform,
and the parser touches none. A consumer wanting durable storage on Windows is the
review trigger; `File_Ops` is already the seam.)*

### odin-rdf-sparql — `SPARQL-*` — complete, on odin-rdf-record (v0.6.0)

**Amended 2026-08-25 (`SPARQL-I-0003`): this engine was ported off odin-rdf-store onto
odin-rdf-record, the second and last of the family's two ports.** The old section stands
below as the record of the store era. What is true now:

**One package**, `sparql`, importing `rdf` and `record` only, plus `sparql/srj` and
`sparql/srx` for the two results serializations. **`sparql/kvstore` is deleted**, not
re-pointed — and with it the parapoly `$MATCH`/`$NEXT`/`$DESTROY` binding, six
backend-spanning procedure types, the harness `Backend` enum, the `store:` collection, and
nine test files that existed only because there was an instantiation to test. **No
`Term_ID` width matrix**: record's widths are fixed by design, so `make test` runs once,
and all three CI runners run it, the suites opening every store over record's
platform-free memory seam (`Mem_FS` + `mem_file_ops`). Pins: odin-rdf-parser `v0.1.2`
*(`v0.1.0` until later the same day, when `RDF-T-0026` landed — the first parser bump this
engine has ever needed, and it filed the bug)*, odin-rdf-record `v0.4.0` *(→ `v0.5.0` on 2026-08-27, `SPARQL-T-0045`; → `v0.6.0` the same day, `SPARQL-T-0046`)* — `v0.4.0` was cut *for this port*, `RECORD-I-0004` building
triple terms because the owner declined to let the port narrow a headline capability.

**537 of 537 evaluated W3C entries across 38 enabled directories**, up from 512/37; 286
tests in `make test`. The gain is triple-term evaluation restored, plus
`sparql10-expr-builtin` enabled — which record's language-tag fold on intern made green
without a line changing here.

*(Amended 2026-08-25, later the same day: **542 across 39 directories, and 288 tests.**
`sparql10-i18n` was enabled by odin-rdf-parser's `RDF-T-0026`, not by anything here — the
same shape as the row above it, a directory going green because a layer below stopped
being wrong. **`sparql11-subquery` is now the only vendored directory left dark**, and its
ten RDF/XML data documents are a permanent ceiling rather than a task, so of the corpus's
556 evaluable entries **546 pass**. The extra two tests are `SPARQL-T-0042`'s scanner
position — this repository's own copy of `RDF-T-0025`, filed and fixed the same day — and
the i18n suite.)*

**The port moved cost, not behaviour, and it is measured** (`SPARQL-T-0036`). `bench/` was
built *before* the port precisely so this could be checked (`SPARQL-T-0040`): **fourteen of
its sixteen read-count pins reproduce against record to the integer**, along with all
sixteen solution counts. The two that moved are both `GROUP BY`'s `load`, by the number of
groups, because record *inlines* a small canonical integer that odin-rdf-store never
interned — a term-identity difference behaving correctly. This is the second independent
instance of a port's read counts surviving; odin-rdf-shacl's did too.

**Four things a session working here should know:**

- **`join_order` is no longer the identity permutation** (`SPARQL-T-0037`). `range_len`
  is an exact O(1) candidate count, so a BGP is ordered **connected-first, then
  cheapest, then as written**. Connectivity is not optional: this executor is a nested
  loop, and a pattern sharing no variable with what is bound re-scans instead of probing,
  so cost-only ordering makes plans arbitrarily *worse*. 12x fewer scans and 9.9x faster
  on a badly-ordered three-pattern join; nothing else in the benchmark moved, every other
  query having already been written in the order a planner would choose.
- **The ordered read cannot answer `ORDER BY`, and that is settled** (`SPARQL-T-0038`,
  closed as evidence). record's ids are ordered but not in SPARQL's order — every
  dictionary id sorts before every inlined one, and an integer past 2^27, any decimal, and
  any non-canonical lexical form are each dictionary terms. No plan can establish when the
  two orders agree, because SPARQL has no static types. `MIN`/`MAX` inherit it. Guarded by
  `sparql/order_id_gap_test.odin`; **do not "optimize" `Plan_Order` on the grounds that
  record's ids are ordered.** *(Scoped 2026-08-25: this read "the ordered read is
  unusable", which was too broad and got `SPARQL-T-0029` wrongly closed. **Only the uses
  that need the ids to mean something are dead.** `snapshot_match_as` is fine for anything
  needing a consistent total order — a merge join, clustering for `DISTINCT`/`GROUP BY` —
  and `SPARQL-T-0029` is reopened for exactly that. Keep the two apart: "ordered" and
  "ordered the way SPARQL sorts" are different claims. **Built the same evening:
  `SPARQL-T-0029` shipped the merge join on `snapshot_match_as`, needing nothing new
  from record — `bgp2` opens 2 scans where it opened 20,001 and runs 6.2x faster,
  546/546 unchanged. Both halves of this bullet are now measured.)*
- **A BGP's first join may be a merge, and the planner prices it** (`SPARQL-T-0029`).
  Two cursors advanced in step over two named permutations replace one index probe per
  row, but only where `MERGE_SCAN_PRICE` says the right side's window is worth reading
  whole — a selective left side still probes, and `bench/`'s `bgp2-narrow-left` is the
  case that pins the refusal. Two things not to re-derive: the merge is **only** at
  depth 1, because a monotone right cursor requires a left side that never restarts;
  and the price constant is **measured**, ~134 ns a scan open against ~6.7 ns a
  candidate visit, where counting instructions suggests single digits and is wrong by
  3x — a probe's binary searches are random access, a merge's walk is sequential.
- **`GRAPH <g> { … }` is a scan here** (`RECORD-A-0004`: G is never a prefix), where
  odin-rdf-store answered from a prefix range. 169,055 candidates to return 4,122 — the
  whole store. Correctness is unaffected and it is the only benchmark case that got
  slower. *(Amended 2026-08-27: answered on record's `main` by `RECORD-T-0028`'s
  `GPOS` order — a prefix at whatever pin includes it, with no change here.)* *(Pinned
  the same day, `v0.6.0`, `SPARQL-T-0046`: 4,122 candidates for 4,122 answers at both
  sizes, measured by `make bench` and re-pinned.)*
- **`query_init` takes the application's graph set** (`SPARQL-T-0044`, 2026-08-27):
  `scope := record.Graph_Scope.All` and `graphs: []record.Term_ID = nil`, resident ids
  resolved against the same snapshot with misses dropped, copied into the query. Every
  read carries them as `Exec.filter` — record's `Filter`, applied per fact inside
  `scan_next`, below every operator — so the set is an authorization ceiling the query
  text cannot widen: `GRAPH <x>` outside it yields nothing, `GRAPH ?g` ranges over the
  set's named graphs, an empty `.Set` yields no solutions, `.All` is unchanged
  behaviour. Dataset clauses are still `SPARQL-T-0043`'s and will intersect it. Note for
  callers: `query_init`'s trailing parameters are positional — name `allocator`.

The ordered-read and `GRAPH` findings are filed on record's backlog as evidence —
`RECORD-T-0027` and `RECORD-T-0026` — under the family's "capability gaps become
evidence, not workarounds" convention. Neither is a request.

**As-of costs this engine nothing, still**: `record.store_at(&db, epoch)` where the present
uses `store_latest`, and no line of non-test source allows it — the same result the store
era got (`SPARQL-T-0034`, `-T-0025`). **Triple terms are *cheaper* than they were**:
`snapshot_triple_parts` reads a stored triple term's three component ids with no
allocation, no decode and no recursion, against odin-rdf-store's two round trips.

~~**Unreleased.** `v0.1.0` is the store-era engine and is still the only tag; whether the
port warrants one is the owner's call.~~ **Released as `v0.2.0` on 2026-08-25** (annotated
tag at `b1f1667`, GitHub release with notes) — the record-era engine's first tag, cut the
same evening the merge join landed and on a commit CI had just proved green on all three
runners. `v0.1.0` remains the store-era engine, the same split odin-rdf-shacl's two tags
carry and for the same reason. **No consumer pins it** — odin-rdf-app reaches this
repository by path and is still store-era, which is a fact about that application and not
a constraint on this one; the tag exists so that odin-rdf-shacl's SHACL-SPARQL phase, or
anything later, pins a fixed point instead of tracking `main`.

*(Amended 2026-08-25, evening: **odin-rdf-app is not store-era any more.** It was ported
the same day this tag was cut — `store:` dropped, `sparql/kvstore` gone with it, one
`record.store_latest` snapshot where a read transaction used to be, and no `Term_ID` width
to pick — and it reaches both repositories by path, so it still pins nothing. The sentence
above stands as the record; what it said about tags is unchanged, and **`v0.2.0` still has
no pinning consumer.** Worth knowing about that application if a session lands in it: it
is a demonstration in the checkout root, not one of the five repositories and not tracked
by any of them, its `rdf/` tree and Makefile are a copy of `odin-vsuite`'s, and since the
port it seeds its own record store with its own `src/rdfseed` — `make seed && make run` —
where before it read an LMDB database no checkout could reproduce.)*

---

*The section below is the store era, left standing as the record:*

### odin-rdf-sparql — `SPARQL-*` — parser and evaluation engine complete (store era, superseded 2026-08-25)

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

### odin-rdf-shacl — `SHACL-*` — SHACL Core complete, on odin-rdf-record (v0.2.0)

Shape-based validation, a peer of odin-rdf-sparql: shapes graphs are ordinary RDF loaded
via the parser, and the data graph is an epoch-pinned **snapshot of odin-rdf-record**, read
through one file of session verbs (`shacl/session.odin`) and nothing else. **One package,
`shacl`**, importing `rdf` and `record` only — compilation, target resolution, property
paths, the constraint catalogue, `sh:ValidationReport` building, and the `Validator`
binding. Dependencies: odin-rdf-parser `v0.1.1`, odin-rdf-record `v0.3.0` as a floor. No
LMDB, no native code, no width matrix; the suites open every store over the record's
platform-free memory seam, so all three CI runners run the same `make test`.
*(Amended 2026-08-27, `SHACL-T-0040`: **`v0.5.0`** — `Filter.scope`, seven sites state `.All`, nothing else moves.)* *(And **`v0.6.0`** the same day, `SHACL-T-0041`: record's `GPOS` order — every graph-bound session read is a prefix, no source change.)* *(Amended 2026-08-25, `SHACL-T-0038`: the record floor is **`v0.4.0`**. This
engine needs neither of RDF 1.2's term kinds and adopted the release for the two
things their arrival changed — `record.Term_Kind` gained `.Triple`, which
`node_kind_of` switches on exhaustively (the port's one compile error, and the
right one), and `snapshot_term` can now return a term it owns, so
`session_term_destroy` is paired with every decode. That pairing also closed the
split-IRI leak `session_term`'s contract had admitted since the port and had no
verb to fix. **A triple term is an ordinary value node here**: counted, reported,
rendered into `sh:value` — and it satisfies no `sh:nodeKind`, since SHACL 1.0's
six kinds do not name a fourth. `shacl/rdf12_term_test.odin` is where that lives,
because the vendored corpus has none and never will. 98/98 unchanged, every read
pin unmoved (7503 on the reference configuration), which is what a pin bump for a
*type* rather than a capability should look like. No new shacl tag: `v0.2.0` is
still the release, and whether this warrants one is the owner's call.)*

**It was ported on 2026-08-20 (`SHACL-I-0004`, seven tasks, one day)** from odin-rdf-store,
against which it was written backend-independent with a `shacl/kvstore` instantiation, a
`purity` target grepping a binary for `mdb_` symbols, and a `Term_ID` width matrix — all
deleted, not retained. Two owner decisions govern it and are recorded in the repo's vision
Current State: **no dual-backend goal at any point**, and **odin-rdf-record is the one and
only store, forever** — where targeting it directly made code simpler, faster or smaller,
that path was taken. Those decisions were made for shacl; the sparql port asks rather than
inherits. The old sections of this file and the repo's documents stand under dated notes.

Status: all twenty-nine non-SPARQL constraint components of §4, and all 98 entries of the
W3C SHACL 1.0 `core/` tree green against the record — no skip list, no expected-failure
file. **The read counts survived the port to the integer** (7503 on the reference
configuration, and every other pin): the engine asks the record exactly the questions it
asked LMDB, and only the cost moved — `validate` 4.69 → 1.17 ms, `compile` 146 → 35 µs,
peak memory the old 32-bit figure (20868 B). `make bench` is two builds, because read
counting is a build-time switch in the engine (`SHACL_COUNT_READS`) rather than a seam.
Key ADRs: `SHACL-A-0001` (the shapes model owns every term it holds — on the record a
stronger necessity than the one it was decided on, since `session_term` borrows the
dictionary arena that closing the store frees) and `SHACL-A-0002` (suppressed validation),
both amended 2026-08-20.

**Validate-before-commit is the record's `Validator` hook** (`shacl/validator.odin`,
replacing `session_init_txn`): a compiled model wired in at `record.store_open`, handed
*the dataset the write would produce* — head plus changeset, as an ordinary snapshot at
the new epoch — before a byte is written. `.Enforce` refuses (`apply` returns `.Rejected`,
nothing written); `.Record` commits and reports; the log does not record that a validator
objected (RECORD-A-0006 decision 5); a `Failure` is a refusal. The argument is unchanged:
validating an isolated candidate is wrong rather than slow — every constraint that must
consult existing data reads an empty world and passes vacuously. **As-of validation is
`record.store_at(&db, epoch)`** where the present uses `store_latest`, nothing below the
session changing; the coordinate is the epoch, and terms are not epoch-scoped (facts are),
so one compiled model binds at any epoch.

Two term-identity shifts came with the store and moved no verdict: language tags fold to
lowercase on intern (so the `sh:hasValue`/`sh:in` exposure `docs/language-tag-status.md`
tracked is closed there, and the latent one is report rendering — the family's parser-side
fold decision is flagged for discussion, not rescinded), and inlineable literals are always
resolvable (a small canonical integer named by `sh:targetNode` is bound even when absent
from the data).

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
  silently under-reports, and `sh:targetClass` walks the same closure. *(Amended 2026-08-27, `SHACL-T-0039`: **a session may now read the
  union of a set of graphs** — `session_init_union`, `validator_init_union` —
  `SHACL-A-0001` decision 5 generalised on its own review trigger for the workspace
  design; the single graph is the one-element case, every read pin holds (7503), and
  the answer to this bullet is to put the ontology's graph in the set. Found on the
  way: the compiler's `reader_match` in `shacl/query.odin` had been writing its own
  pattern and filter since the port; it reads through the session's filter now.)*

Remaining: SHACL-SPARQL (`sh:sparql` and SPARQL-based constraint components), the only thing
that would add odin-rdf-sparql as a dependency — the Makefile notes where the `sparql:`
collection gets added, and `docs/handover-sparql.md` carries the phase's starting point with
a post-port translation note. **SHACL Core does not depend on it and will not.** **Released
as `v0.2.0` on 2026-08-20** (tag at `b3ca168`, GitHub release with notes) — the record
engine's first tag; `v0.1.0` is the store-era engine. The owner's reading: complete, and
the version to use for the foreseeable future unless a consumer or the record's API moving
for the sparql port says otherwise. No shacl consumer pins a tag today.

Out of scope: SHACL Advanced Features (rules, functions), inference/entailment, servers.

## Family-wide conventions

- **Libraries, not applications.** Primitives over frameworks: each layer supplies building
  blocks and leaves policy to consumers. No servers, no protocol layers, anywhere.
- **Suite-driven correctness.** The official W3C test suites define "done" and are vendored
  for offline, hermetic, reproducible runs. Not example programs.
- **Consume the interface, don't bypass it.** Downstream projects touch storage only through
  the store's published match contract. Capability gaps become evidence-backed upstream
  proposals, never backend-specific workarounds. *(Amended 2026-08-25: read
  "odin-rdf-record's published read API". The **portability** half is gone — one store,
  no goal of a second, both engines naming it directly — and the second sentence is what
  actually does the work. The two ports tested it in both directions and it held: triple
  terms were **asked for and built** (`RECORD-I-0004`, `v0.4.0` cut for a consumer),
  record's untyped ids were **fixed** at shacl's asking (`v0.3.0`), and the two costs
  sparql found and could not fix were **measured and filed** as `RECORD-T-0026` and
  `RECORD-T-0027` rather than worked around. No special case was built in either
  engine.)*
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
  `-collection:rdf=../odin-rdf-parser`, `-collection:store=../odin-rdf-store`,
  `-collection:record=../odin-rdf-record` (shacl since 2026-08-20, in place of `store:`).
  Declared in each `Makefile` and mirrored in `ols.json`. Note that a collection resolves in
  the *importing* compilation: a project using the store or the record must also declare
  `rdf:`, because their own sources import it. *(Amended 2026-08-25: **`store:` is
  declared by nothing** — sparql dropped it with `SPARQL-I-0003`, as shacl had. The two
  collections anyone needs are `rdf:` and `record:`, and the resolves-in-the-importing-
  compilation rule is why `rdf:` is still required alongside `record:`.)*
- ~~**Dual-width testing.**~~ `Term_ID` width is a build-time choice (`-define:RDF_STORE_TERM_ID_BITS`,
  64-bit default, 32-bit opt-in). Anything width-sensitive is tested at both.
  (odin-rdf-record is exempt by design: its widths are fixed because the inline
  encoding is frozen at first write — see its section. odin-rdf-shacl is exempt since
  2026-08-20 for the same reason, being on the record; the convention now binds
  odin-rdf-store and odin-rdf-sparql.) *(**Retired 2026-08-25**: odin-rdf-sparql became
  exempt for the same reason at `SPARQL-T-0031`, so **this convention now binds only
  odin-rdf-store, which has no consumers**. It was a real discipline for a year and it
  is worth keeping the reason: the width was the store's build-time choice and its
  consumers compiled the store's sources into their own binaries, so a width-sensitive
  bug was a *consumer's* bug to find. Nothing compiles a store's sources any more.)*
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

odin-rdf-store, odin-rdf-sparql, odin-rdf-shacl (Makefile-driven; `make help` lists targets;
**odin-rdf-shacl since 2026-08-20**: `make test` is one run with no width matrix, `make check`
ends with an import-alias grep, and `make bench` is two builds — timing, then instrumented;
**odin-rdf-sparql since 2026-08-25**: all three of those, for the same reasons — so the
width-matrix comment below is true of odin-rdf-store alone):

```
make test    # full suite at both Term_ID widths
make check   # vet every package at the default width
make bench   # build and run benchmarks with release flags
make clean   # remove build/
```

*(Amended 2026-08-25: **odin-rdf-sparql joined shacl's shape** at `SPARQL-I-0003` — one
`make test` run with no width matrix, `make check` ending with the same import-alias grep,
and `make bench` two builds for the same reason, a read counter inside the timed binary
being an instrument measuring itself. So the block above describes **odin-rdf-store
alone**, which has no consumers. sparql also has `make build-bench`, which builds both
benchmark binaries without running them.)*

odin-rdf-record (Makefile-driven; no width matrix — its widths are fixed by design;
`make test` requires python3 for the cross-implementation verifier, and since
2026-09-01 `make check` needs it too — the surface check is Python):

```
make test    # the suite, the fault corpus, then the scale measurement optimized
make check   # vet every package with -vet -strict-style, then `make api`
make api     # diff the exported surface against doc/api-surface.txt
make tool    # build the record CLI (verify, dump, head) into build/record
make clean   # remove build/
```

*(Amended 2026-09-01, `RECORD-I-0005`/`-I-0007`, tag `v0.7.0`: `make check` ends in
`make api`, and `make test` is two passes — the ordinary one, then the scale
measurement again with `-define:RECORD_SCALE=true -o:speed`. The proof, scale and tool
suites are `record/*_test.odin` now rather than packages under `tests/`; see **Where a
test goes** in this repository's section above for the layout and the three rules that
come with it.)*
