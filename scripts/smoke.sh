#!/usr/bin/env sh
# Smoke test for install.sh: asserts the four properties the README promises.
# Runs entirely inside a temp dir; never touches a real ~/.claude or ~/.codex.
# Usage: ./scripts/smoke.sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
installer="$repo_root/scripts/install.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fails=0
ok()   { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

fresh() {
    rm -rf "$work/home"
    mkdir -p "$work/home/.codex/skills"
    CLAUDE_HOME="$work/home/.claude"
    CODEX_HOME="$work/home/.codex"
    export CLAUDE_HOME CODEX_HOME
}
run() { sh "$installer" "$@" 2>&1; }

echo '1. --check writes nothing'
fresh
run --check --codex >/dev/null
count=$(find "$work/home" -type f | wc -l)
[ "$count" -eq 0 ] && ok "no files created (found $count)" || fail "--check created $count file(s)"

echo '2. fresh install adds every file'
fresh
run --codex >/dev/null
count=$(find "$work/home/.claude" -type f | wc -l)
[ "$count" -eq 13 ] && ok "13 files installed" || fail "expected 13 files, got $count"

echo '3. re-running is idempotent'
before=$(find "$work/home/.claude" -type f -exec cksum {} + | sort)
out=$(run --codex)
after=$(find "$work/home/.claude" -type f -exec cksum {} + | sort)
[ "$before" = "$after" ] && ok "no file changed on re-run" || fail "re-run modified files"
echo "$out" | grep -q 'current' && ok "reports 'current'" || fail "no 'current' in re-run output"

echo '4. a user file at the destination is never destroyed'
fresh
printf 'USER FILE\n' > "$CODEX_HOME/skills/vmodel-test"
out=$(run --codex)
if [ -f "$CODEX_HOME/skills/vmodel-test" ] &&
   [ "$(cat "$CODEX_HOME/skills/vmodel-test")" = 'USER FILE' ]; then
    ok 'plain file preserved'
else
    fail 'plain file was destroyed'
fi
echo "$out" | grep -q 'preserved' && ok "reports 'preserved'" || fail "no 'preserved' in output"

echo "5. a user's own skill directory is never destroyed"
fresh
mkdir -p "$CODEX_HOME/skills/vmodel-test"
printf 'mine\n' > "$CODEX_HOME/skills/vmodel-test/SKILL.md"
printf 'keep\n' > "$CODEX_HOME/skills/vmodel-test/notes.md"
run --codex >/dev/null
if [ "$(cat "$CODEX_HOME/skills/vmodel-test/SKILL.md")" = 'mine' ] &&
   [ -f "$CODEX_HOME/skills/vmodel-test/notes.md" ]; then
    ok 'custom skill and its extra files preserved'
else
    fail 'custom skill was overwritten'
fi

echo '6. exit codes'
fresh
run --codex >/dev/null && ok 'apply exits 0' || fail 'apply exited non-zero'
if sh "$installer" --bogus >/dev/null 2>&1; then
    fail 'unknown option should exit non-zero'
else
    ok 'unknown option exits non-zero'
fi

echo
if [ "$fails" -eq 0 ]; then
    echo 'all checks passed'
else
    echo "$fails check(s) failed"
    exit 1
fi
