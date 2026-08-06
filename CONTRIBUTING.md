# Contributing to the Odin RDF family

This file applies to every repository in the [odin-rdf](https://github.com/odin-rdf)
organization: [odin-rdf-parser](https://github.com/odin-rdf/odin-rdf-parser),
[odin-rdf-store](https://github.com/odin-rdf/odin-rdf-store),
[odin-rdf-sparql](https://github.com/odin-rdf/odin-rdf-sparql), and
[odin-rdf-shacl](https://github.com/odin-rdf/odin-rdf-shacl).

## Getting set up

The projects reach each other through **relative Odin collections**, not
vendored copies or submodules — `-collection:rdf=../odin-rdf-parser`,
`-collection:store=../odin-rdf-store`. They must therefore sit side by side
in one directory:

```
odin-rdf/
├── odin-rdf-parser/
├── odin-rdf-store/
├── odin-rdf-sparql/
└── odin-rdf-shacl/
```

Clone the ones you need into that layout. A collection resolves in the
*importing* compilation, not the imported checkout, so a project that uses
the store also needs the parser present — the store's own sources import
`rdf:`.

## Building and testing

Every repository except the parser is `make`-driven:

```sh
make test    # the full suite; where Term_ID width applies, both widths
make check   # vet every package with -vet -strict-style
make bench   # benchmarks with release flags
make help    # list targets
```

The parser has no Makefile; its README lists the `odin test` invocations.

**A change is not done until `make test` and `make check` are both green.**
CI runs exactly these, so there are no surprises waiting in the pull request.

## What correctness means here

- **The W3C test suites define "done."** Each project vendors the official
  suites for its layer and runs them hermetically, offline. A feature that
  the relevant suite does not cover still needs a test; a feature the suite
  *does* cover is measured by the suite.
- **Both `Term_ID` widths stay green.** Width is a build-time choice
  (64-bit default, 32-bit opt-in). Anything width-sensitive is tested at
  both, which `make test` does for you.
- **Memory is checked, not assumed.** Suites run with
  `ODIN_TEST_FAIL_ON_BAD_MEMORY=true`, promoting leaks and bad frees from
  warnings a passing build hides into failures.
- **README examples are compiled.** Each repository holds its README's code
  in `tests/readme` so documentation cannot drift from the API. If you
  change an example, change it in both places.

## Design conventions

- **Primitives over frameworks.** Each layer supplies building blocks and
  leaves policy to its consumers. Servers, protocol layers, and pipelines
  are out of scope everywhere in the family.
- **Consume the interface, don't bypass it.** Downstream projects reach
  storage only through odin-rdf-store's published match contract. If
  something is missing, propose it upstream with the evidence that
  motivated it rather than working around it locally.
- **Idiomatic Odin.** Explicit memory management, allocator awareness,
  streaming over materialization, straightforward procedural APIs.
- **Public APIs carry contract documentation** — lifetimes, ownership, and
  what a caller may rely on, not a restatement of the signature.

## Architecture decisions

Non-obvious decisions are recorded as ADRs in each repository's `.metis/adrs/`
and referenced from the code they govern (`STORE-A-0001`, `RDF-A-0001`, and
so on). If you are about to contradict one, that is worth discussing in an
issue first — and if the ADR is simply wrong, saying so is a welcome
contribution.

## Pull requests

Small and focused beats large and comprehensive. Explain *why* in the
commit message; the diff already shows *what*. If a change is a trade-off,
say what you traded and what you considered.

Bug reports are most useful with the input that triggers them — an RDF
document, a query, a shapes graph — reduced as far as you can get it.
