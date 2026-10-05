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

gone() { # gone <branch>: its worktree is gone, and its local branch is kept
  no "$1: worktree removed" [ -e "$ws/$1" ]
  ok "$1: branch kept" git -C "$ws" show-ref --verify --quiet "refs/heads/$1"
}

# --- two remotes. origin's default branch is `trunk` (so nothing can assume
# `main`); it also has on-remote, spare, via-switch, feat/remote and shared. fork has
# forked and shared. $seed is a plain repository used to push to both.
remote=$tmp/remote.git fork=$tmp/fork.git seed=$tmp/seed ws=$tmp/remote
git init -q --bare -b trunk "$remote"
git init -q --bare -b trunk "$fork"
git init -q -b trunk "$seed"
git -C "$seed" remote add origin "$remote"
commit "$seed" one
git -C "$seed" branch spare
git -C "$seed" branch via-switch
git -C "$seed" branch feat/remote
git -C "$seed" branch shared
git -C "$seed" switch -q -c on-remote
commit "$seed" two
git -C "$seed" switch -q trunk
git -C "$seed" push -q origin trunk spare via-switch feat/remote shared on-remote
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
no "remove in a plain repo fails" gwt remove trunk
said "not in a gwt workspace"
is "no worktree candidates outside a workspace" "$(_gwt_worktrees 2>&1)" ""
is "no branch candidates outside a workspace" "$(_gwt_branches 2>&1)" ""

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
no "add: a name that is not a branch fails" gwt add new
said "gwt add -c new"
no "add: a name that is not a branch creates nothing" [ -e "$ws/new" ]
ok "add -c: new branch, inside a worktree" gwt add -c new
is "add -c: does not cd" "$PWD" "$ws/on-remote"
is "add -c: new branch starts at that worktree's HEAD" \
  "$(git -C "$ws" rev-parse new)" "$(git -C "$ws" rev-parse on-remote)"
no "add -c: new branch has no upstream" \
  git -C "$ws" rev-parse --verify --quiet 'new@{upstream}'
ok "add -c <new> <start>" gwt add -c started trunk
is "add -c <new> <start>: new branch starts there" \
  "$(git -C "$ws" rev-parse started)" "$(git -C "$ws" rev-parse trunk)"
ok "add --create" gwt add --create long-flag 'HEAD'
is "add --create: <start> is resolved in the current worktree" \
  "$(git -C "$ws" rev-parse long-flag)" "$(git -C "$ws" rev-parse on-remote)"
cd "$ws" || exit 1
ok "add -c: new branch, at the workspace root" gwt add -c from-root
is "add -c: new branch starts at the default branch" \
  "$(git -C "$ws" rev-parse from-root)" "$(git -C "$ws" rev-parse trunk)"
no "add -c: existing branch fails" gwt add -c on-remote
said "already exists"
no "add -c: no name" gwt add -c
no "add: -c after the branch" gwt add other -c
no "add: too many arguments" gwt add -c other trunk extra
no "add: unknown flag" gwt add -x other
no "add: bad arguments create nothing" [ -e "$ws/other" ]

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

# --- switch: an existing worktree
cd "$ws/trunk/sub" || exit 1
no "switch -: fails before any switch" gwt switch -
said "no previous worktree"
ok "switch" gwt switch on-remote
is "switch: changes directory" "$PWD" "$ws/on-remote"
no "switch: a name that is not a branch fails" gwt switch nope
said "gwt add nope"
is "switch: stays put on failure" "$PWD" "$ws/on-remote"
no "switch: a name that is not a branch creates nothing" [ -e "$ws/nope" ]
no "switch: no arguments" gwt switch
no "switch: too many arguments" gwt switch trunk late
is "switch: stays put on bad arguments" "$PWD" "$ws/on-remote"

# --- switch: a branch without a worktree is not given one
no "switch: branch without a worktree fails" gwt switch via-switch
said "gwt add via-switch"
no "switch: branch without a worktree creates nothing" [ -e "$ws/via-switch" ]
no "switch: branch without a worktree creates no local branch" \
  git -C "$ws" show-ref --verify --quiet refs/heads/via-switch
is "switch: stays put when there is no worktree" "$PWD" "$ws/on-remote"
no "switch -c" gwt switch -c created
no "switch -c: creates nothing" [ -e "$ws/created" ]
cd "$ws" || exit 1
ok "switch: from the workspace root" gwt switch trunk
is "switch: from the workspace root, directory" "$PWD" "$ws/trunk"

# --- switch -: the worktree that the last switch left
cd "$ws/trunk/sub" || exit 1
ok "switch: leaving a subdirectory" gwt switch on-remote
ok "switch -" gwt switch -
is "switch -: goes to the root of the previous worktree" "$PWD" "$ws/trunk"
ok "switch -: twice" gwt switch -
is "switch -: twice returns" "$PWD" "$ws/on-remote"
ok "switch: to the current worktree" gwt switch on-remote
ok "switch -: after a switch that went nowhere" gwt switch -
is "switch -: a switch that went nowhere is not remembered" "$PWD" "$ws/trunk"
no "switch: failing" gwt switch nope
ok "switch -: after a failed switch" gwt switch -
is "switch -: a failed switch is not remembered" "$PWD" "$ws/on-remote"
cd "$ws/late" || exit 1
ok "switch -: after a plain cd" gwt switch -
is "switch -: a plain cd is not remembered" "$PWD" "$ws/trunk"
ok "switch -: remembers the worktree a plain cd went to" gwt switch -
is "switch -: back to where the cd went" "$PWD" "$ws/late"
cd "$ws" || exit 1
ok "switch -: from the workspace root" gwt switch -
is "switch -: from the workspace root, directory" "$PWD" "$ws/trunk"
ok "switch: a new worktree is remembered" \
  eval 'gwt add -c fleeting && gwt switch fleeting && gwt switch -'
is "switch -: back from a new worktree" "$PWD" "$ws/trunk"
ok "switch -: to the new worktree" gwt switch -
git -C "$ws" worktree remove "$ws/trunk"
no "switch -: the previous worktree is gone" gwt switch -
said "is gone"
is "switch -: stays put when it is gone" "$PWD" "$ws/fleeting"
git -C "$ws" worktree add -q "$ws/trunk" trunk 2>/dev/null
mkdir "$ws/trunk/sub"
no "add -c -" gwt add -c -
no "switch - <extra>" gwt switch - trunk
no "add -" gwt add -
ok "switch: back to the default branch" gwt switch trunk

# --- remove: the worktree goes, the branch stays
ok "remove" gwt remove from-root
gone from-root
ok "remove: several in a row" \
  eval 'gwt remove started && gwt remove long-flag && gwt remove fleeting'
gone started
gone long-flag
gone fleeting
ok "remove: tracking branches" \
  eval 'gwt remove late && gwt remove forked && gwt remove spare && gwt remove shared'
gone late
gone forked
gone spare
gone shared

# --- remove: unmerged commits are not a reason to refuse; they stay on the branch
commit "$ws/new" work
work=$(git -C "$ws" rev-parse new)
ok "remove: unmerged commits, inside the worktree" \
  eval 'mkdir "$ws/new/deep" && cd "$ws/new/deep" && gwt remove new'
gone new
is "remove: from a subdirectory of the worktree, ends at the root" "$PWD" "$ws"
is "remove: the branch keeps its commits" "$(git -C "$ws" rev-parse new)" "$work"
ok "remove: add brings the worktree back" gwt add new
ok "remove: the worktree is back with its commits" [ -f "$ws/new/work" ]
ok "remove: again" gwt remove new
gone new

# --- remove: uncommitted changes, run from inside the worktree
ok "add dirty" gwt add -c dirty
cd "$ws/dirty" || exit 1
echo change >>one
no "remove: refuses uncommitted changes" gwt remove dirty
said "--force"
kept dirty
is "remove: refusal does not cd" "$PWD" "$ws/dirty"
ok "remove -f: uncommitted changes" gwt remove -f dirty
gone dirty
is "remove: from inside the worktree, ends at the root" "$PWD" "$ws"

# --- remove: untracked files
ok "add untracked" gwt add -c untracked
echo new >"$ws/untracked/new-file"
no "remove: refuses untracked files" gwt remove untracked
said "--force"
kept untracked
ok "remove <branch> --force: untracked files" gwt remove untracked --force
gone untracked

# --- remove: a locked worktree needs -f twice, as in git
ok "add locked" gwt add -c locked
git -C "$ws" worktree lock "$ws/locked"
no "remove: refuses a locked worktree" gwt remove locked
no "remove -f: refuses a locked worktree" gwt remove -f locked
kept locked
ok "remove -f -f: a locked worktree" gwt remove -f -f locked
gone locked

# --- remove: a worktree that has another branch checked out
ok "add moved" gwt add -c moved
git -C "$ws/moved" switch -q --detach
ok "remove: a worktree that is not on its branch" gwt remove moved
gone moved

# --- remove: the default branch is a worktree like any other
ok "remove: the default branch" gwt remove trunk
gone trunk
ok "remove: add the default branch back" gwt add trunk
kept trunk
mkdir "$ws/trunk/sub"

# --- remove: bad arguments
no "remove: unknown branch fails" gwt remove nope
said "no worktree for 'nope'"
no "remove: no arguments" gwt remove
no "remove: unknown flag" gwt remove -x on-remote
kept on-remote

# --- branch names with slashes
cd "$ws/trunk" || exit 1
ok "slash: add remote branch" gwt add feat/remote
is "slash: remote branch is tracked" \
  "$(git -C "$ws" rev-parse --abbrev-ref 'feat/remote@{upstream}')" "origin/feat/remote"
ok "slash: add new branch" gwt add -c feat/new
ok "slash: worktree path is the branch name" [ -e "$ws/feat/new/.git" ]
ok "slash: switch" gwt switch feat/new
is "slash: switch directory" "$PWD" "$ws/feat/new"
ok "slash: switch - away and back" eval 'gwt switch - && gwt switch -'
is "slash: switch - directory" "$PWD" "$ws/feat/new"
ok "slash: remove from inside" gwt remove feat/new
gone feat/new
ok "slash: remove keeps a parent that is still in use" [ -e "$ws/feat/remote/.git" ]
is "slash: worktree candidates" "$(_gwt_worktrees | sort)" \
  "$(printf '%s\n' feat/remote local-only on-remote trunk)"
ok "slash: remove the last one" gwt remove feat/remote
gone feat/remote
no "slash: remove removes the empty parent" [ -e "$ws/feat" ]
ok "slash: add nested" gwt add -c a/b/c
ok "slash: remove nested" gwt remove a/b/c
no "slash: remove removes all empty parents" [ -e "$ws/a" ]

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
is "candidates: branches without a worktree, local or on a remote, without fetching" \
  "$(_gwt_branches)" \
  "$(printf '%s\n' a/b/c dirty feat/new feat/remote fleeting forked from-root \
    late locked long-flag moved new shared spare started untracked via-switch)"

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
ok "init: add before the first commit" gwt add -c second
ok "init: add before the first commit, worktree" [ -e "$tmp/here/second/.git" ]

cd "$ws/not-the-default" || exit 1
commit "$ws/not-the-default" first
no "no remote: switch - does not go to another workspace" gwt switch -
said "no previous worktree"
ok "no remote: add" gwt add -c topic
is "no remote: new branch starts at the current HEAD" \
  "$(git -C "$ws" rev-parse topic)" "$(git -C "$ws" rev-parse not-the-default)"
ok "no remote: switch" gwt switch topic
is "no remote: switch directory" "$PWD" "$ws/topic"
commit "$ws/topic" work
ok "no remote: remove" gwt remove topic
gone topic
is "no remote: remove from inside ends at the root" "$PWD" "$ws"
is "no remote: worktree candidates" "$(_gwt_worktrees)" "not-the-default"
is "no remote: branch candidates" "$(_gwt_branches)" "topic"
ok "no remote: add brings the worktree back" eval 'gwt add topic && gwt switch topic'
is "no remote: switch to a local branch, directory" "$PWD" "$ws/topic"
ok "no remote: the worktree is back with its commits" [ -f "$ws/topic/work" ]

# --- zsh only: the completion file and the plugin entry point
if [ -n "${ZSH_VERSION-}" ]; then
  ok "zsh: completion file parses" zsh -n "$here/completions/_gwt"
  ok "zsh: plugin defines gwt and adds the completion to fpath" zsh -f -c \
    'source "$1/gwt.plugin.zsh" && (( $+functions[gwt] )) && (( ${fpath[(Ie)$1/completions]} ))' \
    zsh "$here"
fi

printf '%s: %d passed, %d failed\n' "${ZSH_VERSION:+zsh}${BASH_VERSION:+bash}" "$pass" "$fail"
[ "$fail" -eq 0 ]
