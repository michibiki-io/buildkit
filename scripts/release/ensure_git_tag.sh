#!/usr/bin/env bash
set -euo pipefail

operation=$1
tag=$2
revision=$3
ref="refs/tags/$tag"

# Read from origin, since the prepare job's result can be stale on retry.
target=$(git ls-remote --tags origin "$ref" "$ref^{}" |
  awk -v ref="$ref" '$2 == ref { direct = $1 } $2 == ref "^{}" { peeled = $1 }
  END { print (peeled != "" ? peeled : direct) }')
if [[ -n $target ]]; then
  if [[ $target != "$revision" ]]; then
    printf 'Git tag %s points to %s, expected %s.\n' "$tag" "$target" "$revision" >&2
    exit 1
  fi
  exit 0
fi

if [[ $operation == publish ]]; then
  if target=$(git rev-parse --verify --quiet "$ref^{commit}"); then
    if [[ $target != "$revision" ]]; then
      printf 'Local Git tag %s points to %s, expected %s.\n' "$tag" "$target" "$revision" >&2
      exit 1
    fi
  else
    git -c user.name='github-actions[bot]' \
      -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
      tag -a "$tag" "$revision" -m "Release $tag"
  fi
  git push origin "$ref"
fi
