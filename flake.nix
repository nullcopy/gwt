{
  description = "gwt - git worktree wrappers for the .bare workspace layout";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        gwt = pkgs.callPackage ./package.nix { };
        default = gwt;
      });

      homeModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.gwt;
          init = "source ${cfg.package}/share/gwt/gwt.sh\n";
        in
        {
          options.programs.gwt = {
            enable = lib.mkEnableOption "gwt, git worktree wrappers for the .bare workspace layout";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "gwt.packages.\${system}.default";
              description = "The gwt package to use.";
            };
          };

          config = lib.mkIf cfg.enable {
            # Puts the zsh completion on fpath via share/zsh/site-functions.
            home.packages = [ cfg.package ];
            programs.zsh.initContent = init;
            programs.bash.initExtra = init;
          };
        };

      checks = forAllSystems (pkgs: {
        tests =
          pkgs.runCommand "gwt-tests"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.gitMinimal
                pkgs.zsh
              ];
            }
            ''
              zsh ${self}/test.sh
              bash ${self}/test.sh
              touch $out
            '';
      });
    };
}
