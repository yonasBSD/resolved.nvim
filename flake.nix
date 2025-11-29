{
  description = "resolved.nvim - Surface stale issue/PR references in code comments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      perSystem = {pkgs, ...}: {
        devShells.default = pkgs.mkShell {
          name = "resolved.nvim";

          packages = with pkgs; [
            # Lua tooling
            luajit
            stylua
            lua-language-server
            luajitPackages.luacheck

            # Testing
            neovim

            # GitHub CLI (required dependency)
            gh

            # Git
            git
          ];

          shellHook = ''
            echo "resolved.nvim development environment"
            echo ""
            echo "Available commands:"
            echo "  luacheck lua/ --globals vim    - Lint Lua files"
            echo "  stylua --check lua/ plugin/    - Check formatting"
            echo "  stylua lua/ plugin/            - Format code"
            echo ""
            echo "Make sure gh is authenticated: gh auth status"
          '';
        };

        # Formatter for nix files
        formatter = pkgs.alejandra;
      };
    };
}
