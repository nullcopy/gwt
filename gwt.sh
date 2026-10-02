# gwt - git worktree wrappers for the .bare workspace layout.
# Source this file from zsh or bash. See README.md, or run `gwt help`.

# oh-my-zsh's git plugin aliases gwt to `git worktree`. An alias would shadow
# the function; the pass-through in gwt() keeps the alias's behavior working.
unalias gwt 2>/dev/null

# Print an error and return 1, so callers can write: check || _gwt_err ... || return 1
_gwt_err() { printf 'gwt: %s\n' "$*" >&2; return 1; }

_gwt_help() {
  printf '%s\n' 'gwt - git worktree wrappers for the .bare workspace layout

Usage:
  gwt init [<dir>]           Create an empty workspace
  gwt clone <url> [<dir>]    Clone a repo into a new workspace
  gwt add <branch>           Create a worktree for <branch>
  gwt remove [-f] <branch>   Remove a worktree and delete its branch
  gwt switch <branch>        cd to a worktree
  gwt help                   Show this help
  gwt <other> [<args>...]    Passed through to `git worktree`
                             (list, move, prune, repair, lock, ...)

Commands:
  init    Creates <dir>/.bare, a .git file pointing at it, and a worktree
          for the initial branch, with no remote. <dir> defaults to the
          current directory.

  clone   Creates <dir>/.bare, a .git file pointing at it, and a worktree
          for the default branch. <dir> defaults to the repo name.

  add     Creates <root>/<branch>. Checks out the local branch if it
          exists; otherwise the remote branch, given as <remote>/<branch>
          or found on exactly one remote; otherwise creates <branch> from
          the current HEAD. Never fetches. Works from anywhere in the
          workspace.

  remove  Removes the worktree and deletes its local branch. Refuses if
          the worktree has uncommitted changes, or the branch is not
          merged into its upstream (into the default branch, if it has no
          upstream). With -f, removes anyway and that work is lost. Never
          removes the default branch.

  switch  Changes directory to <root>/<branch>.

Layout:
  <root>/
    .bare/       git data; its HEAD names the default branch
    .git         file pointing at .bare
    main/        one directory per branch
    <branch>/

Completion:
  switch, remove   existing worktrees
  add              remote branches without a worktree

Examples:
  gwt clone git@github.com:user/repo.git
  gwt add fix-parser
  gwt add jimmys-fork/jimmys-feature
  gwt switch fix-parser
  gwt remove fix-parser
  gwt list'
}

# Print the workspace root: the parent of the shared .bare directory.
_gwt_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  case $common in
    */.bare) printf '%s\n' "${common%/.bare}" ;;
    *) _gwt_err "not in a gwt workspace" ;;
  esac
}

# Print the default branch of the workspace rooted at $1: .bare's HEAD.
_gwt_default() {
  local ref
  ref=$(git -C "$1" symbolic-ref --quiet HEAD) && printf '%s\n' "${ref#refs/heads/}"
}

# Create the workspace skeleton in $1: .bare, and the .git file pointing at it.
_gwt_bare() {
  git init --quiet --bare "$1/.bare" && printf 'gitdir: ./.bare\n' >"$1/.git"
}

_gwt_init() {
  local dir="${1-.}" default
  [ $# -le 1 ] && [ -n "$dir" ] || _gwt_err "usage: gwt init [<dir>]" || return 1
  [ ! -e "$dir/.git" ] && [ ! -e "$dir/.bare" ] ||
    _gwt_err "'$dir' already contains .git or .bare" || return 1
  _gwt_bare "$dir" && default=$(_gwt_default "$dir") &&
    git -C "$dir" worktree add --orphan -b "$default" "$default"
}

_gwt_clone() {
  local url="${1-}" dir="${2-}" default
  [ -n "$dir" ] || { dir=${url%/}; dir=${dir%/.git}; dir=${dir%.git}; dir=${dir##*[/:]}; }
  [ -n "$dir" ] && [ $# -le 2 ] || _gwt_err "usage: gwt clone <url> [<dir>]" || return 1
  [ ! -e "$dir" ] || _gwt_err "'$dir' already exists" || return 1
  # A relative local path would otherwise be resolved from inside <dir>.
  case $url in /*) ;; *) [ ! -e "$url" ] || url=$PWD/$url ;; esac
  # Not `git clone --bare`: it omits the fetch refspec for remote-tracking
  # branches and creates a local branch for every remote branch.
  _gwt_bare "$dir" &&
    git -C "$dir" remote add origin "$url" &&
    git -C "$dir" fetch origin &&
    git -C "$dir" remote set-head origin --auto &&
    default=$(git -C "$dir" symbolic-ref --quiet refs/remotes/origin/HEAD) &&
    default=${default#refs/remotes/origin/} &&
    git -C "$dir" symbolic-ref HEAD "refs/heads/$default" &&
    git -C "$dir" worktree add --track -b "$default" "$default" "origin/$default" &&
    return 0
  command rm -rf -- "$dir"
  _gwt_err "clone failed"
}

_gwt_add() {
  local branch="${1-}" root start=''
  [ $# -eq 1 ] && [ -n "$branch" ] || _gwt_err "usage: gwt add [<remote>/]<branch>" || return 1
  root=$(_gwt_root) || return 1
  # Resolve the name as `git switch` would: local branch, then remote branch.
  if ! git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
    if git -C "$root" show-ref --verify --quiet "refs/remotes/$branch"; then
      start=$branch branch=${branch#*/}
    else
      start=$(git -C "$root" for-each-ref --format='%(refname:lstrip=2)' "refs/remotes/*/$branch")
      case $start in *[[:space:]]*)
        _gwt_err "'$branch' is on several remotes; use <remote>/$branch"; return 1 ;;
      esac
    fi
  fi
  [ ! -e "$root/$branch" ] || _gwt_err "worktree already exists: $root/$branch" || return 1
  if [ -n "$start" ]; then
    git -C "$root" worktree add --track -b "$branch" "$root/$branch" "$start"
  elif git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$root" worktree add "$root/$branch" "$branch"
  else
    # No -C: like `git switch -c`, the new branch starts at the current HEAD.
    git worktree add -b "$branch" "$root/$branch"
  fi
}

_gwt_remove() {
  local force='' branch='' count=0 arg root wt target why=''
  for arg in "$@"; do
    case $arg in -f|--force) force=1 ;; *) branch=$arg; count=$((count + 1)) ;; esac
  done
  [ "$count" -eq 1 ] && [ -n "$branch" ] && [ "${branch#-}" = "$branch" ] ||
    _gwt_err "usage: gwt remove [-f] <branch>" || return 1
  root=$(_gwt_root) || return 1
  wt=$root/$branch
  [ "$branch" != "$(_gwt_default "$root")" ] ||
    _gwt_err "refusing to remove the default branch '$branch'" || return 1
  [ -e "$wt/.git" ] || _gwt_err "no worktree for '$branch'" || return 1
  if [ -z "$force" ]; then
    # The checks `git worktree remove` and `git branch -d` would make, run
    # up front so that either both are removed or neither is.
    target=$(git -C "$root" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null) ||
      target=$(_gwt_default "$root")
    if [ "$(git -C "$wt" symbolic-ref --quiet HEAD)" != "refs/heads/$branch" ]; then
      why="the worktree does not have '$branch' checked out"
    elif [ -n "$(git -C "$wt" status --porcelain --untracked-files=normal 2>&1)" ]; then
      why="the worktree has uncommitted changes or untracked files"
    elif ! git -C "$root" merge-base --is-ancestor "refs/heads/$branch" "$target" 2>/dev/null; then
      why="the branch is not fully merged into '$target'"
    fi
    [ -z "$why" ] || _gwt_err "not removing '$branch': $why" \
      "(to remove it anyway and lose that work: gwt remove -f $branch)" || return 1
  fi
  case "$(pwd -P)/" in "$wt"/*) builtin cd "$root" || return 1 ;; esac
  git -C "$root" worktree remove ${force:+--force} "$wt" &&
    git -C "$root" branch -d ${force:+--force} "$branch" || return 1
  while [ "${branch%/*}" != "$branch" ]; do # parents of a slash-named branch
    branch=${branch%/*}
    command rmdir "$root/$branch" 2>/dev/null || break
  done
}

_gwt_switch() {
  local root
  [ $# -eq 1 ] || _gwt_err "usage: gwt switch <branch>" || return 1
  root=$(_gwt_root) || return 1
  [ -e "$root/$1/.git" ] || _gwt_err "no worktree for '$1'" || return 1
  builtin cd "$root/$1"
}

# Completion candidates, one per line, for any shell's completion to use.
# They never fetch, and print nothing outside a workspace.
_gwt_worktrees() {
  local root line
  root=$(_gwt_root 2>/dev/null) || return 1
  git -C "$root" worktree list --porcelain | while IFS= read -r line; do
    case $line in
      "worktree $root/.bare") ;;
      "worktree $root/"*) printf '%s\n' "${line#"worktree $root/"}" ;;
    esac
  done
}

_gwt_remote_branches() {
  local root ref
  root=$(_gwt_root 2>/dev/null) || return 1
  git -C "$root" for-each-ref --format='%(refname:lstrip=3)' refs/remotes |
    while IFS= read -r ref; do
      [ "$ref" = HEAD ] || [ -e "$root/$ref" ] || printf '%s\n' "$ref"
    done
}

gwt() {
  local cmd="${1-help}"
  case $cmd in
    help|-h|--help) _gwt_help ;;
    init|clone|add|remove|switch) shift; "_gwt_$cmd" "$@" ;;
    *) git worktree "$@" ;;
  esac
}
