#!/bin/sh
# Initialize the odin-rdf checkout root: clone the four repositories as
# sibling directories of this file, skipping any already checked out.
set -e
cd "$(dirname "$0")"

for repo in odin-rdf-parser odin-rdf-record odin-rdf-shacl odin-rdf-sparql; do
  if [ -d "$repo" ]; then
    echo "=== $repo === already exists, skipping"
  else
    echo "=== $repo ==="
    git clone "git@github.com:odin-rdf/$repo.git"
  fi
done
