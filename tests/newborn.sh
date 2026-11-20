#!/bin/sh
# A newborn operations repo passes its own check, lint, `plx doctor` and the playbooks' syntax: the
# working tree, uncommitted changes included, is rendered with its birth tasks in each shape that
# changes what is generated, and the collections go into the scratch directory, not ~/.ansible.
#
#   tests/newborn.sh           # render every shape and check it
#   KEEP=1 tests/newborn.sh    # leave the rendered repos in place and say where
set -eu

# Left set by a hook, GIT_DIR and GIT_WORK_TREE would point the newborn's `git init` and copier's
# clones at the pushing repository: from a linked worktree, `git init` marks it bare.
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
  # A tool mise builds through uv (uv, and a `pipx:`/`pypi:` key or `uvx = true`) needs python
  # pinned: mise's Python keeps the uv tools' environments inside the cached data directory.
  python3 - "$tmp/$name/mise.toml" "$name" <<'EOF'
import sys, tomllib
tools = tomllib.load(open(sys.argv[1], "rb")).get("tools", {})
built = [k for k, v in tools.items() if k.startswith(("pipx:", "pypi:")) or (isinstance(v, dict) and str(v.get("uvx")).lower() == "true")]
if "uv" in tools and built and "python" not in tools:
    sys.exit(f"✗ {sys.argv[2]}: mise.toml builds {', '.join(built)} through uv but pins no python")
EOF
  echo "→ $name: check"
  (cd "$tmp/$name" && mise run check)
  echo "✓ $name"
}

newborn github
newborn hybrid -d infrastructure=true -d ci_strategy=hybrid -d pr_reviewers=reviewer-a,reviewer-b
newborn on-prem -d ci_strategy=on-prem -d ci_overlay=netbird
newborn own-registry -d ci_registry=own
