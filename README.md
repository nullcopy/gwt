# gwt

A thin wrapper around `git worktree` for one workspace layout: a bare
repository in `.bare`, and one directory per branch next to it.

```
<root>/
  .bare/       git data
  .git         file pointing at .bare
  main/        one directory per branch
  <branch>/
```

`gwt` is a shell function, not an executable, because `gwt switch` changes
the directory of your shell. It works in zsh and bash and depends only on
git (2.31 or newer; `gwt init` needs 2.42). It does not expect a remote:
a workspace can have none, one, or several, and gwt never fetches outside
of `gwt clone`.

## Usage

```
gwt init [<dir>]                 Create an empty workspace
gwt clone <url> [<dir>]          Clone a repo into a new workspace
gwt switch <branch>              cd to a worktree, creating it if needed
gwt switch -c <new> [<start>]    Create a branch and its worktree; cd to it
gwt switch -                     cd to the previous worktree
gwt add <branch>                 Like switch, but stay where you are
gwt add -c <new> [<start>]
gwt remove [-f] <branch>         Remove a worktree, keeping its branch
gwt help                         Show this help
gwt <other> [<args>...]          Passed through to `git worktree`
                                 (list, move, prune, repair, lock, ...)
```

`gwt help` has the details. In short:

- `switch` follows `git switch`, with a worktree in place of a checkout. It
  changes directory to the branch's worktree, creating the worktree first
  if the branch exists but has none: a local branch if there is one,
  otherwise a remote branch, named as `<remote>/<branch>` or just
  `<branch>` when exactly one remote has it. Fetch first if you want the
  latest remote branches. A name that is not a branch is an error;
  `switch -c` creates a new branch, from the current HEAD unless given a
  start point. `switch -` goes back to the worktree that the last
  `gwt switch` in this shell left.
- `add` takes the same arguments and creates the same worktree, but does
  not change directory.
- `remove` runs `git worktree remove` on `<root>/<branch>`, so it refuses
  a worktree with uncommitted changes or untracked files unless given
  `-f`. It never deletes the branch; use `git branch -d` for that.
- The default branch is the one `.bare`'s `HEAD` points at.
- A branch named `feat/foo` lives at `<root>/feat/foo`.

## Install

### zsh

Clone the repository, then add this to `~/.zshrc`:

```zsh
fpath+=(~/src/gwt/completions)   # before compinit
source ~/src/gwt/gwt.sh
```

With a plugin manager, load `nullcopy/gwt`; `gwt.plugin.zsh` sources the
function and registers the completion.

Sourcing `gwt.sh` replaces any existing `gwt` alias, so load it after
anything that defines one.

### bash

Add this to `~/.bashrc`:

```bash
source ~/src/gwt/gwt.sh
```

There is no bash completion yet.

### Nix

The flake provides a package and a home-manager module:

```nix
{
  inputs.gwt.url = "github:nullcopy/gwt";
  inputs.gwt.inputs.nixpkgs.follows = "nixpkgs";
}
```

```nix
{
  imports = [ inputs.gwt.homeModules.default ];
  programs.gwt.enable = true;
}
```

The module sources the function in zsh and bash and installs the zsh
completion. It needs home-manager 25.05 or newer.

Without home-manager, source
`${inputs.gwt.packages.${system}.default}/share/gwt/gwt.sh` from your shell
configuration; the zsh completion is in `share/zsh/site-functions`.

## Tests

```sh
zsh test.sh && bash test.sh
```

or `nix flake check`, which runs the same script under both shells. The
tests are offline and work in a temporary directory.

## License

MIT
