#!/usr/bin/env bash
# Tests for gwt. Runs offline against a throwaway remote in a temp directory.
# Run under both shells:  zsh test.sh && bash test.sh

here=$(cd "$(dirname "$0")" && pwd) || exit 1
tmp=$(mktemp -d) || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# Isolate git from the real environment, and give it a global config that
# changes the defaults gwt must not depend on.
unset GIT_DIR GIT_WORK_TREE XDG_CONFIG_HOME
export LC_ALL=C HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
mkdir "$HOME"
git config --global user.name 'gwt test'
git config --global user.email 'gwt@example.invalid'
git config --global init.defaultBranch not-the-default
git config --global branch.autoSetupMerge false
git config --global worktree.guessRemote true
git config --global status.showUntrackedFiles no

pass=0 fail=0

_result() { # _result <status> <wanted: 0 for success, 1 for failure> <description>
  if { [ "$1" -eq 0 ] && [ "$2" -eq 0 ]; } || { [ "$1" -ne 0 ] && [ "$2" -ne 0 ]; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n' "$3"
    sed 's/^/    /' "$tmp/out"
  fi
}

ok() { # ok <description> <command...>: the command must succeed
  local desc="$1"; shift
  "$@" >"$tmp/out" 2>&1
  _result $? 0 "$desc"
}

no() { # no <description> <command...>: the command must fail
  local desc="$1"; shift
  "$@" >"$tmp/out" 2>&1
  _result $? 1 "$desc"
}

is() { # is <description> <actual> <expected>
  printf 'expected: %s\n  actual: %s\n' "$3" "$2" >"$tmp/out"
  [ "$2" = "$3" ]
  _result $? 0 "$1"
}

said() { # said <text>: the last ok/no command printed <text>
  if grep -qF -- "$1" "$tmp/out"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: expected output containing: %s\n' "$1"
    sed 's/^/    /' "$tmp/out"
  fi
}

commit() { # commit <worktree> <file>: commit a new file
  echo "$2" >"$1/$2" && git -C "$1" add "$2" && git -C "$1" commit -q -m "add $2"
}

kept() { # kept <branch>: its worktree and local branch both still exist
  ok "$1: worktree kept" [ -e "$ws/$1/.git" ]
  ok "$1: branch kept" git -C "$ws" show-ref --verify --quiet "refs/heads/$1"
}

gone() { # gone <branch>: its worktree and local branch are both gone
  no "$1: worktree removed" [ -e "$ws/$1" ]
  no "$1: branch deleted" git -C "$ws" show-ref --verify --quiet "refs/heads/$1"
}

# --- two remotes. origin's default branch is `trunk` (so nothing can assume
# `main`); it also has on-remote, spare, feat/remote and shared. fork has
# forked and shared. $seed is a plain repository used to push to both.
remote=$tmp/remote.git fork=$tmp/fork.git seed=$tmp/seed ws=$tmp/remote
git init -q --bare -b trunk "$remote"
git init -q --bare -b trunk "$fork"
git init -q -b trunk "$seed"
git -C "$seed" remote add origin "$remote"
commit "$seed" one
git -C "$seed" branch spare
git -C "$seed" branch feat/remote
git -C "$seed" branch shared
git -C "$seed" switch -q -c on-remote
commit "$seed" two
git -C "$seed" switch -q trunk
git -C "$seed" push -q origin trunk spare feat/remote shared on-remote
git -C "$seed" push -q "$fork" trunk shared trunk:forked

# --- sourcing: an existing `gwt` alias is replaced by the function
[ -z "${BASH_VERSION-}" ] || shopt -s expand_aliases
alias gwt='git worktree'
. "$here/gwt.sh"
no "the gwt alias is removed" alias gwt
ok "sourcing twice works" . "$here/gwt.sh"

# --- help
help=$(gwt help)
is "help: first line" "${help%%
*}" "gwt - git worktree wrappers for the .bare workspace layout"
is "help: last line" "${help##*
}" "  gwt list"
is "help: bare gwt" "$(gwt)" "$help"
is "help: -h" "$(gwt -h)" "$help"
is "help: --help" "$(gwt --help)" "$help"

# --- outside a workspace
cd "$tmp" || exit 1
no "add outside a repo fails" gwt add x
said "not in a gwt workspace"
cd "$seed" || exit 1
no "add in a plain repo fails" gwt add x
said "not in a gwt workspace"
no "switch in a plain repo fails" gwt switch trunk
said "not in a gwt workspace"
no "rm in a plain repo fails" gwt rm trunk
said "not in a gwt workspace"
is "no worktree candidates outside a workspace" "$(_gwt_worktrees 2>&1)" ""
is "no branch candidates outside a workspace" "$(_gwt_remote_branches 2>&1)" ""

# --- clone
cd "$tmp" || exit 1
ok "clone" gwt clone "$remote"
is "clone: does not cd" "$PWD" "$tmp"
ok "clone: .bare holds the git data" [ -f "$ws/.bare/HEAD" ]
is "clone: .git file" "$(cat "$ws/.git")" "gitdir: ./.bare"
is "clone: fetch refspec" "$(git -C "$ws" config --get-all remote.origin.fetch)" \
  "+refs/heads/*:refs/remotes/origin/*"
is "clone: origin/HEAD" "$(git -C "$ws" symbolic-ref refs/remotes/origin/HEAD)" \
  "refs/remotes/origin/trunk"
is "clone: .bare's HEAD is the default branch" \
  "$(git -C "$ws" symbolic-ref HEAD)" "refs/heads/trunk"
ok "clone: remote-tracking branches exist" \
  git -C "$ws" show-ref --verify --quiet refs/remotes/origin/on-remote
is "clone: the only local branch is the default" \
  "$(git -C "$ws" for-each-ref --format='%(refname)' refs/heads)" "refs/heads/trunk"
is "clone: default branch upstream" \
  "$(git -C "$ws" rev-parse --abbrev-ref 'trunk@{upstream}')" "origin/trunk"
is "clone: default branch checked out at <dir>/<default>" \
  "$(git -C "$ws/trunk" symbolic-ref HEAD)" "refs/heads/trunk"
ok "clone: worktree has files" [ -f "$ws/trunk/one" ]
no "clone: fails if <dir> exists" gwt clone "$remote"
said "already exists"
ok "clone <url> <dir>" gwt clone "$remote" "$tmp/named"
ok "clone <url> <dir>: worktree" [ -f "$tmp/named/trunk/one" ]
ok "clone: relative path" gwt clone remote.git relative
ok "clone: relative path still fetches" git -C "$tmp/relative/trunk" fetch -q origin
no "clone: bad url fails" gwt clone "$tmp/missing.git" bad
no "clone: bad url leaves nothing behind" [ -e "$tmp/bad" ]
no "clone: no arguments" gwt clone

# --- add, from a subdirectory of a worktree
git -C "$seed" switch -q -c late
commit "$seed" late-file
git -C "$seed" switch -q trunk
git -C "$seed" push -q origin late
mkdir "$ws/trunk/sub"
cd "$ws/trunk/sub" || exit 1
ok "add: branch on one remote" gwt add on-remote
is "add: does not cd" "$PWD" "$ws/trunk/sub"
ok "add: remote branch checked out" [ -f "$ws/on-remote/two" ]
is "add: remote branch is tracked" \
  "$(git -C "$ws" rev-parse --abbrev-ref 'on-remote@{upstream}')" "origin/on-remote"
no "add: existing worktree fails" gwt add on-remote
said "already exists"
no "add: does not fetch" git -C "$ws" show-ref --verify --quiet refs/remotes/origin/late
git -C "$ws" fetch -q origin
ok "add: branch fetched by the user" gwt add late
ok "add: fetched branch checked out" [ -f "$ws/late/late-file" ]
is "add: fetched branch is tracked" \
  "$(git -C "$ws" rev-parse --abbrev-ref 'late@{upstream}')" "origin/late"

# A new branch starts at the current HEAD, like `git switch -c`.
cd "$ws/on-remote" || exit 1
ok "add: new branch, inside a worktree" gwt add new
is "add: new branch starts at that worktree's HEAD" \
  "$(git -C "$ws" rev-parse new)" "$(git -C "$ws" rev-parse on-remote)"
no "add: new branch has no upstream" \
  git -C "$ws" rev-parse --verify --quiet 'new@{upstream}'
cd "$ws" || exit 1
ok "add: new branch, at the workspace root" gwt add from-root
is "add: new branch starts at the default branch" \
  "$(git -C "$ws" rev-parse from-root)" "$(git -C "$ws" rev-parse trunk)"

git -C "$ws" branch --no-track local-only origin/on-remote
ok "add: existing local branch" gwt add local-only
is "add: existing local branch is checked out as it was" \
  "$(git -C "$ws/local-only" rev-parse HEAD)" "$(git -C "$ws" rev-parse origin/on-remote)"
is "add: existing local branch is on the branch" \
  "$(git -C "$ws/local-only" symbolic-ref HEAD)" "refs/heads/local-only"
no "add: no arguments" gwt add

# --- add with a second remote
git -C "$ws" remote add fork "$fork"
git -C "$ws" fetch -q fork
ok "add: <remote>/<branch>" gwt add fork/forked
ok "add: <remote>/<branch> lives at <root>/<branch>" [ -e "$ws/forked/.git" ]
is "add: <remote>/<branch> tracks that remote" \
  "$(git -C "$ws" rev-parse --abbrev-ref 'forked@{upstream}')" "fork/forked"
ok "add: bare name on exactly one of two remotes" gwt add spare
is "add: bare name tracks the remote that has it" \
  "$(git -C "$ws" rev-parse --abbrev-ref 'spare@{upstream}')" "origin/spare"
no "add: bare name on several remotes fails" gwt add shared
said "several remotes"
no "add: ambiguous name creates nothing" [ -e "$ws/shared" ]
ok "add: qualified name resolves the ambiguity" gwt add fork/shared
is "add: qualified name tracks the named remote" \
  "$(git -C "$ws" rev-parse --abbrev-ref 'shared@{upstream}')" "fork/shared"

# --- switch
cd "$ws/trunk/sub" || exit 1
ok "switch" gwt switch on-remote
is "switch: changes directory" "$PWD" "$ws/on-remote"
no "switch: unknown branch fails" gwt switch nope
is "switch: stays put on failure" "$PWD" "$ws/on-remote"
cd "$ws" || exit 1
ok "switch: from the workspace root" gwt switch trunk
is "switch: from the workspace root, directory" "$PWD" "$ws/trunk"

# --- rm: clean branches, by `git branch -d`'s rule
ok "rm: no upstream, merged into the default branch" gwt rm from-root
gone from-root
ok "rm: equal to its upstream" gwt rm late
gone late
ok "rm: equal to its upstream on another remote" gwt rm forked
gone forked
ok "rm: remaining tracking branches" eval 'gwt rm spare && gwt rm shared'
gone spare
gone shared
# `new` started at on-remote, which is ahead of trunk, and has no upstream.
no "rm: refuses no upstream, not merged into the default branch" gwt rm new
said "gwt rm -f new"
kept new
ok "rm -f: not merged" gwt rm -f new
gone new

# --- rm: uncommitted changes, run from inside the worktree
ok "add dirty" gwt add dirty
cd "$ws/dirty" || exit 1
echo change >>one
no "rm: refuses uncommitted changes" gwt rm dirty
said "gwt rm -f dirty"
kept dirty
is "rm: refusal does not cd" "$PWD" "$ws/dirty"
ok "rm -f: uncommitted changes" gwt rm -f dirty
gone dirty
is "rm: from inside the worktree, ends at the root" "$PWD" "$ws"

# --- rm: untracked files
ok "add untracked" gwt add untracked
echo new >"$ws/untracked/new-file"
no "rm: refuses untracked files" gwt rm untracked
said "gwt rm -f untracked"
kept untracked
ok "rm <branch> -f: untracked files" gwt rm untracked -f
gone untracked

# --- rm: unmerged commits, no upstream
ok "add unmerged" gwt add unmerged
commit "$ws/unmerged" work
no "rm: refuses unmerged commits" gwt rm unmerged
said "gwt rm -f unmerged"
kept unmerged
ok "rm --force: unmerged commits" gwt rm --force unmerged
gone unmerged

# --- rm: pushed to its upstream but not merged into the default branch
ok "add pushed" gwt add pushed
commit "$ws/pushed" work
git -C "$ws/pushed" push -q -u origin pushed
commit "$ws/pushed" more
no "rm: refuses commits ahead of the upstream" gwt rm pushed
kept pushed
git -C "$ws/pushed" push -q origin pushed
ok "rm: pushed to its upstream" gwt rm pushed
gone pushed

# --- rm: no upstream, so only a merge into the default branch counts
ok "add merged" gwt add merged
commit "$ws/merged" merged-file
git -C "$ws/merged" push -q origin merged
no "rm: pushed without an upstream is still unmerged" gwt rm merged
kept merged
git -C "$ws/trunk" merge -q --ff-only merged
ok "rm: merged into the default branch, inside the worktree" \
  eval 'mkdir "$ws/merged/deep" && cd "$ws/merged/deep" && gwt rm merged'
gone merged
is "rm: from a subdirectory of the worktree, ends at the root" "$PWD" "$ws"

# --- rm: the default branch, and bad arguments
no "rm: refuses the default branch" gwt rm trunk
said "default branch"
no "rm -f: refuses the default branch" gwt rm -f trunk
said "default branch"
kept trunk
no "rm: unknown branch fails" gwt rm nope
no "rm: no arguments" gwt rm
no "rm: unknown flag" gwt rm -x on-remote
kept on-remote

# --- rm: a worktree that has another branch checked out
ok "add moved" gwt add moved
git -C "$ws/moved" switch -q --detach
no "rm: refuses a worktree that is not on its branch" gwt rm moved
said "gwt rm -f moved"
kept moved
ok "rm -f: worktree not on its branch" gwt rm -f moved
gone moved

# --- branch names with slashes
cd "$ws/trunk" || exit 1
ok "slash: add remote branch" gwt add feat/remote
is "slash: remote branch is tracked" \
  "$(git -C "$ws" rev-parse --abbrev-ref 'feat/remote@{upstream}')" "origin/feat/remote"
ok "slash: add new branch" gwt add feat/new
ok "slash: worktree path is the branch name" [ -e "$ws/feat/new/.git" ]
ok "slash: switch" gwt switch feat/new
is "slash: switch directory" "$PWD" "$ws/feat/new"
ok "slash: rm from inside" gwt rm feat/new
gone feat/new
ok "slash: rm keeps a parent that is still in use" [ -e "$ws/feat/remote/.git" ]
is "slash: worktree candidates" "$(_gwt_worktrees | sort)" \
  "$(printf '%s\n' feat/remote local-only on-remote trunk)"
ok "slash: rm the last one" gwt rm feat/remote
gone feat/remote
no "slash: rm removes the empty parent" [ -e "$ws/feat" ]
ok "slash: add nested" gwt add a/b/c
ok "slash: rm nested" gwt rm a/b/c
no "slash: rm removes all empty parents" [ -e "$ws/a" ]

# --- pass-through
cd "$ws" || exit 1
is "pass-through: list" "$(gwt list)" "$(git worktree list)"
ok "pass-through: arguments" gwt lock --reason testing on-remote
is "pass-through: took effect" \
  "$(git worktree list --porcelain | grep -c '^locked testing$')" "1"
ok "pass-through: unlock" gwt unlock on-remote
no "pass-through: git's own failure" gwt no-such-subcommand

# --- completion candidates
cd "$ws/trunk/sub" || exit 1
is "candidates: worktrees" "$(_gwt_worktrees | sort)" \
  "$(printf '%s\n' local-only on-remote trunk)"
git -C "$seed" push -q origin trunk:unfetched
is "candidates: branches of every remote without a worktree, without fetching" \
  "$(_gwt_remote_branches | sort -u)" \
  "$(printf '%s\n' feat/remote forked late merged pushed shared spare)"

# --- init: a workspace with no remote at all
cd "$tmp" || exit 1
ws=$tmp/local
ok "init <dir>" gwt init "$ws"
is "init: does not cd" "$PWD" "$tmp"
ok "init: .bare holds the git data" [ -f "$ws/.bare/HEAD" ]
is "init: .git file" "$(cat "$ws/.git")" "gitdir: ./.bare"
is "init: no remote" "$(git -C "$ws" remote)" ""
ok "init: worktree for git's initial branch" [ -e "$ws/not-the-default/.git" ]
no "init: refuses an existing workspace" gwt init "$ws"
no "init: too many arguments" gwt init a b
mkdir "$tmp/here"
cd "$tmp/here" || exit 1
ok "init: current directory" gwt init
ok "init: current directory, worktree" [ -e "$tmp/here/not-the-default/.git" ]
ok "init: add before the first commit" gwt add second
ok "init: add before the first commit, worktree" [ -e "$tmp/here/second/.git" ]

cd "$ws/not-the-default" || exit 1
commit "$ws/not-the-default" first
ok "no remote: add" gwt add topic
is "no remote: new branch starts at the current HEAD" \
  "$(git -C "$ws" rev-parse topic)" "$(git -C "$ws" rev-parse not-the-default)"
ok "no remote: switch" gwt switch topic
is "no remote: switch directory" "$PWD" "$ws/topic"
commit "$ws/topic" work
no "no remote: rm refuses an unmerged branch" gwt rm topic
said "gwt rm -f topic"
kept topic
git -C "$ws/not-the-default" merge -q --ff-only topic
ok "no remote: rm a merged branch" gwt rm topic
gone topic
is "no remote: rm from inside ends at the root" "$PWD" "$ws"
no "no remote: rm -f refuses the default branch" gwt rm -f not-the-default
said "default branch"
is "no remote: worktree candidates" "$(_gwt_worktrees)" "not-the-default"
is "no remote: no remote branch candidates" "$(_gwt_remote_branches)" ""

# --- zsh only: the completion file and the plugin entry point
if [ -n "${ZSH_VERSION-}" ]; then
  ok "zsh: completion file parses" zsh -n "$here/completions/_gwt"
  ok "zsh: plugin defines gwt and adds the completion to fpath" zsh -f -c \
    'source "$1/gwt.plugin.zsh" && (( $+functions[gwt] )) && (( ${fpath[(Ie)$1/completions]} ))' \
    zsh "$here"
fi

printf '%s: %d passed, %d failed\n' "${ZSH_VERSION:+zsh}${BASH_VERSION:+bash}" "$pass" "$fail"
[ "$fail" -eq 0 ]
