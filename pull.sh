for d in odin-rdf-*/; do
  echo "=== $d ==="
  git -C "$d" pull
done
