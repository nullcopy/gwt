{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "gwt";
  version = "0.1.0";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/gwt gwt.sh gwt.plugin.zsh
    install -Dm644 -t $out/share/zsh/site-functions completions/_gwt
    # gwt.plugin.zsh looks for the completion in ./completions
    ln -s ../zsh/site-functions $out/share/gwt/completions
    runHook postInstall
  '';

  meta = {
    description = "Git worktree wrappers for the .bare workspace layout";
    homepage = "https://github.com/nullcopy/gwt";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
