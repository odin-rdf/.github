#!/bin/sh
# Pull the four odin-rdf repositories checked out beside this file.
cd "$(dirname "$0")"

for repo in odin-rdf-parser odin-rdf-record odin-rdf-shacl odin-rdf-sparql; do
  echo "=== $repo ==="
  git -C "$repo" pull
done
