# Security Policy

This policy covers every repository in the
[odin-rdf](https://github.com/odin-rdf) organization.

## Reporting a vulnerability

Please report security issues privately, through GitHub's **private
vulnerability reporting**: open the affected repository, go to the
**Security** tab, and choose **Report a vulnerability**. That keeps the
report visible only to the maintainers until a fix exists.

Please do not open a public issue for a suspected vulnerability.

Useful things to include: the affected repository and commit, the input
that triggers the problem (an RDF document, a query, a shapes graph),
and what you observed — a crash, an out-of-bounds read, a hang, or
incorrect output where correctness carries a security consequence for a
consumer.

## What is in scope

These are **libraries** that parse and evaluate untrusted input, which is
where the interesting failures live:

- Memory safety in the parsers and the storage backends: out-of-bounds
  reads or writes, use-after-free, and unbounded allocation driven by
  crafted input.
- Denial of service through pathological input — quadratic blowup,
  unbounded recursion on deeply nested documents or queries.
- Correctness failures with a security consequence for a consumer, such
  as a SHACL validation that wrongly reports conformance.

Out of scope: anything that requires the caller to violate a documented
contract. In particular, the parsers hand back **borrowed slices** whose
validity ends with the statement — using one after that is a caller bug,
not a vulnerability, and the lifetime rules are documented per package.

## Supported versions

The projects are pre-1.0 and under active development. Fixes land on
`main`; there are no maintained release branches yet.
