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
gwt init [<dir>]           Create an empty workspace
gwt clone <url> [<dir>]    Clone a repo into a new workspace
gwt add <branch>           Create a worktree for <branch>
gwt remove [-f] <branch>   Remove a worktree, keeping its branch
gwt switch <branch>        cd to a worktree
gwt help                   Show this help
gwt <other> [<args>...]    Passed through to `git worktree`
                           (list, move, prune, repair, lock, ...)
```

`gwt help` has the details. In short:

- `add` resolves its argument the way `git switch` does: a local branch if
  there is one, otherwise a remote branch, otherwise a new branch from the
  current HEAD. A remote branch can be named as `<remote>/<branch>`, or
  just `<branch>` when exactly one remote has it. Fetch first if you want
  the latest remote branches.
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
