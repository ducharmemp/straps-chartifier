{
  description = "straps-chartifier — a show_chart tool and prompt layer so a straps agent hands numeric results over as charts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    straps.url = "git+ssh://git@github.com/ducharmemp/straps";
    straps.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, straps }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      mkChartifier = pkgs: pkgs.vimUtils.buildVimPlugin {
        pname = "straps-chartifier";
        version = self.shortRev or self.dirtyShortRev or "dev";
        src = self;
        meta = {
          description = "Text charts in a split for straps.nvim agents";
          license = nixpkgs.lib.licenses.mit;
        };
      };
    in
    {
      packages = forAllSystems (pkgs: rec {
        straps-chartifier = mkChartifier pkgs;
        default = straps-chartifier;
      });

      overlays.default = final: prev: {
        vimPlugins = prev.vimPlugins // { straps-chartifier = mkChartifier final; };
      };

      # Import alongside the straps module:
      #   imports = [ straps.nixvimModules.default straps-chartifier.nixvimModules.default ];
      #   plugins.straps.enable = true;
      #   plugins.straps-chartifier.enable = true;
      # setup() runs after straps' own setup (lib.mkAfter), which the prompt
      # layer needs: it registers only once straps' layers exist, so it lands
      # after them in the prompt.
      nixvimModules = rec {
        straps-chartifier = { lib, config, pkgs, ... }:
          let
            cfg = config.plugins.straps-chartifier;
          in
          {
            options.plugins.straps-chartifier = {
              enable = lib.mkEnableOption "straps-chartifier, charts for straps agents";
              package = lib.mkOption {
                type = lib.types.package;
                default = mkChartifier pkgs;
                defaultText = lib.literalExpression ''straps-chartifier.packages.''${system}.default'';
                description = "The straps-chartifier plugin package.";
              };
              settings = lib.mkOption {
                type = with lib.types; attrsOf anything;
                default = { };
                example = {
                  max_width = 80;
                  split = "horizontal";
                };
                description = ''
                  Passed verbatim to require("straps_chartifier").setup(). See the
                  config table in lua/straps_chartifier/init.lua for every key.
                '';
              };
            };
            config = lib.mkIf cfg.enable {
              extraPlugins = [ cfg.package ];
              extraConfigLua = lib.mkAfter ''
                require("straps_chartifier").setup(${lib.generators.toLua { } cfg.settings})
              '';
            };
          };
        default = straps-chartifier;
      };

      checks = forAllSystems (pkgs: {
        tests = pkgs.stdenvNoCC.mkDerivation {
          name = "straps-chartifier-tests";
          src = self;
          nativeBuildInputs = [
            pkgs.neovim
            pkgs.luajitPackages.busted pkgs.luajitPackages.nlua
          ];
          dontBuild = true;
          doCheck = true;
          checkPhase = ''
            export HOME=$TMPDIR
            export XDG_DATA_HOME=$TMPDIR/data XDG_STATE_HOME=$TMPDIR/state XDG_CACHE_HOME=$TMPDIR/cache
            export STRAPS_ROOT=${straps}
            fail=0
            for t in tests/*_spec.lua; do
              echo "== $t"
              busted "$t" || fail=1
            done
            [ "$fail" = 0 ]
          '';
          installPhase = "touch $out";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.neovim
            pkgs.luajitPackages.busted pkgs.luajitPackages.nlua
          ];
          shellHook = ''
            export STRAPS_ROOT=''${STRAPS_ROOT:-${straps}}
          '';
        };
      });
    };
}
