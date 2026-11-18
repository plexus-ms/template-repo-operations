#!/bin/sh
# A newborn operations repo passes its own check: the template is rendered as copier would render
# it for a new repo, birth tasks included, and the generated repo's own `mise run check` is run in
# it: lint, then each playbook's syntax against the collections its requirements.yml pins. Nothing
# here resolves a secret or reaches a host. The working tree is what is rendered, uncommitted
# changes included.
#
# Each shape of the template that changes what is generated is rendered: the defaults (the forge's
# runners, no infrastructure layer); infrastructure with the hybrid strategy (infrastructure.yml,
# ci.yml, the daily sweep, an own registry, review requests); on-prem over the overlay (ci.yml, an
# own registry, deploys over netbird); and the forge's runners with an own registry (the monthly
# rotation without ci.yml). The collections are installed once, into the scratch directory, not
# into ~/.ansible.
#
#   tests/newborn.sh           # render every shape and check it
#   KEEP=1 tests/newborn.sh    # leave the rendered repos in place and say where
set -eu

# git runs a hook with GIT_DIR (and GIT_WORK_TREE) pointing at the pushing repository. Left set,
# the newborn's `git init` and copier's clones act on that repository instead of the scratch
# directory: from a linked worktree `git init` marks the shared repository bare.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/newborn.XXXXXX")
if [ -n "${KEEP:-}" ]; then trap 'echo "kept: $tmp"' EXIT; else trap 'rm -rf "$tmp"' EXIT; fi
export ANSIBLE_COLLECTIONS_PATH="$tmp/collections"

newborn() {
  name=$1
  shift
  echo "→ $name: render"
  copier copy --quiet --defaults --trust --vcs-ref HEAD -d tenant=acme "$@" "$here" "$tmp/$name"
  echo "→ $name: check"
  (cd "$tmp/$name" && mise run check)
  # plx doctor: the newborn's `plx doctor` goes here, once the released plx has the new doctor.
  echo "✓ $name"
}

newborn github
newborn hybrid -d infrastructure=true -d ci_strategy=hybrid -d renovate_reviewers=reviewer-a,reviewer-b
newborn on-prem -d ci_strategy=on-prem -d ci_overlay=netbird
newborn own-registry -d ci_registry=own
