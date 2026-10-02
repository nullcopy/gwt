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
  gwt init [<dir>]                 Create an empty workspace
  gwt clone <url> [<dir>]          Clone a repo into a new workspace
  gwt switch <branch>              cd to a worktree, creating it if needed
  gwt switch -c <new> [<start>]    Create a branch and its worktree; cd to it
  gwt add <branch>                 Like switch, but stay where you are
  gwt add -c <new> [<start>]
  gwt remove [-f] <branch>         Remove a worktree, keeping its branch
  gwt help                         Show this help
  gwt <other> [<args>...]          Passed through to `git worktree`
                                   (list, move, prune, repair, lock, ...)

Commands:
  init    Creates <dir>/.bare, a .git file pointing at it, and a worktree
          for the initial branch, with no remote. <dir> defaults to the
          current directory.

  clone   Creates <dir>/.bare, a .git file pointing at it, and a worktree
          for the default branch. <dir> defaults to the repo name.

  switch  Changes directory to <root>/<branch>. If <branch> has no
          worktree, creates it first, resolving the name as `git switch`
          does: the local branch if it exists; otherwise the remote
          branch, given as <remote>/<branch> or found on exactly one
          remote, as a new local branch that tracks it. Fails if there
          is no such branch. Never fetches. Works from anywhere in the
          workspace.

          With -c, creates the branch <new> and its worktree, like
          `git switch -c`. <new> starts at <start>, or at the current
          HEAD. Fails if <new> already exists.

  add     Takes the same arguments as switch and creates the same
          worktree, without changing directory. Fails if the worktree
          already exists.

  remove  Removes <root>/<branch> with `git worktree remove`, which
          refuses if the worktree has uncommitted changes or untracked
          files. With -f, removes it anyway and those changes are lost.
          The branch is kept: delete it with `git branch -d`, or get the
          worktree back with `gwt switch`.

Layout:
  <root>/
    .bare/       git data; its HEAD names the default branch
    .git         file pointing at .bare
    main/        one directory per branch
    <branch>/

Completion:
  switch   worktrees, and branches without a worktree
  add      branches without a worktree
  remove   worktrees

Examples:
  gwt clone git@github.com:user/repo.git
  gwt switch -c fix-parser
  gwt switch jimmys-fork/jimmys-feature
  gwt add release-1.2
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

# switch and add: $1 is which. Both make sure the worktree exists; only
# switch changes directory, and only switch accepts an existing worktree.
_gwt_switch() {
  local cmd="$1" create='' max=1 branch root start
  shift
  case ${1-} in -c|--create) create=1 max=2; shift ;; esac
  branch=${1-}
  [ -n "$branch" ] && [ "${branch#-}" = "$branch" ] && [ $# -le "$max" ] ||
    _gwt_err "usage: gwt $cmd (<branch> | -c <new> [<start>])" || return 1
  root=$(_gwt_root) || return 1
  if [ -n "$create" ]; then
    shift
    # No -C: like `git switch -c`, the new branch starts at the current HEAD,
    # and <start> means what it means in the current worktree.
    git worktree add -b "$branch" "$root/$branch" "$@" || return 1
  elif [ -e "$root/$branch/.git" ]; then
    [ "$cmd" = switch ] ||
      _gwt_err "worktree already exists: $root/$branch" || return 1
  # Resolve the name as `git switch` would: local branch, then remote branch.
  elif git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$root" worktree add "$root/$branch" "$branch" || return 1
  else
    if git -C "$root" show-ref --verify --quiet "refs/remotes/$branch"; then
      start=$branch branch=${branch#*/}
    else
      start=$(git -C "$root" for-each-ref --format='%(refname:lstrip=2)' "refs/remotes/*/$branch")
      case $start in
        '') _gwt_err "no branch '$branch' (to create it: gwt $cmd -c $branch)"; return 1 ;;
        *[[:space:]]*) _gwt_err "'$branch' is on several remotes; use <remote>/$branch"; return 1 ;;
      esac
    fi
    git -C "$root" worktree add --track -b "$branch" "$root/$branch" "$start" || return 1
  fi
  [ "$cmd" = switch ] || return 0
  builtin cd "$root/$branch"
}

_gwt_remove() {
  local branch='' count=0 arg root wt inside=''
  for arg in "$@"; do
    case $arg in -f|--force) ;; *) branch=$arg; count=$((count + 1)) ;; esac
  done
  [ "$count" -eq 1 ] && [ -n "$branch" ] && [ "${branch#-}" = "$branch" ] ||
    _gwt_err "usage: gwt remove [-f] <branch>" || return 1
  root=$(_gwt_root) || return 1
  wt=$root/$branch
  [ -e "$wt/.git" ] || _gwt_err "no worktree for '$branch'" || return 1
  # Hand git the same arguments, with the branch replaced by its worktree.
  for arg in "$@"; do
    shift
    case $arg in -f|--force) set -- "$@" "$arg" ;; *) set -- "$@" "$wt" ;; esac
  done
  case "$(pwd -P)/" in "$wt"/*) inside=1 ;; esac
  git -C "$root" worktree remove "$@" || return 1
  [ -z "$inside" ] || builtin cd "$root" || return 1
  while [ "${branch%/*}" != "$branch" ]; do # parents of a slash-named branch
    branch=${branch%/*}
    command rmdir "$root/$branch" 2>/dev/null || break
  done
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

# Branches without a worktree, local or on any remote.
_gwt_branches() {
  local root ref
  root=$(_gwt_root 2>/dev/null) || return 1
  git -C "$root" for-each-ref --format='%(refname)' refs/heads refs/remotes |
    while IFS= read -r ref; do
      case $ref in
        refs/heads/*) ref=${ref#refs/heads/} ;;
        *) ref=${ref#refs/remotes/*/} ;;
      esac
      [ "$ref" = HEAD ] || [ -e "$root/$ref" ] || printf '%s\n' "$ref"
    done | sort -u
}

gwt() {
  local cmd="${1-help}"
  case $cmd in
    help|-h|--help) _gwt_help ;;
    init|clone|remove) shift; "_gwt_$cmd" "$@" ;;
    add|switch) _gwt_switch "$@" ;;
    *) git worktree "$@" ;;
  esac
}
