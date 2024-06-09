# vim:ts=2:sts=2:sw=2:et
{
  description = "Nix flake for creating Minecraft datapacks.";
  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  # nathan writing a flake without flake-utils‽
  outputs = {
    self,
    nixpkgs,
  }: let
    inherit
      (nixpkgs.lib)
      genAttrs
      attrNames
      evalModules
      mkOption
      types
      ;
    pkgsFor = system: import nixpkgs {inherit system;};
    perSystem = genAttrs (attrNames nixpkgs.legacyPackages);
    perSystemWithPkgs = f: perSystem (system: f (pkgsFor system));
    ident = types.stringMatching "[0-9a-z_.-]+:[0-9a-z_/.-]+";
  in rec {
    formatter = perSystemWithPkgs (pkgs: pkgs.alejandra);
    datapackBaseModule = {
      options = {
        name = mkOption {
          type = types.string;
          default = "datapack";
          description = "Used as part of the derivation name.";
        };
        format = mkOption {
          type = types.ints.positive;
          default = 18; # 1.20.2
          description = "The https://minecraft.fandom.com/wiki/Data_pack#Pack_formatpack format to be used for the datapack.";
        };
        description = mkOption {
          type = types.lines;
          example = "Example Pack";
          description = "Description for the generated pack.";
        };
        pkgs = mkOption (
          {
            type = with types; coercedTo string pkgsFor pkgs;
            example = builtins.currentSystem or "x86_64-linux";
            description = "Nixpkgs for building the system, or a system name to use the bundled nixpkgs.";
          }
          // (
            if builtins ? currentSystem
            then {default = builtins.currentSystem;}
            else {}
          )
        );
        files = mkOption {
          type = with types;
            attrsOf (
              attrsOf (
                unique {message = "Cannot define a file more than once.";} (
                  coercedTo (oneOf [
                    attrs
                    (listOf anything)
                  ])
                  builtins.toJSON
                  string
                )
              )
            );
          example = {
            mypack."recipes/fire_charge_with_redstone.json" = {
              type = "crafting_shapeless";
              ingredients = [
                {item = "minecraft:redstone";}
                {item = "minecraft:blaze_powder";}
                [
                  {item = "minecraft:coal";}
                  {item = "minecraft:charcoal";}
                ]
              ];
              result.item = "minecraft:fire_charge";
              result.count = 3;
            };
          };
        };
      };
    };
    datapackRecipeModule = {config, ...}: let
      inherit (config.pkgs.lib) mapAttrs mapAttrs';
    in {
      options.recipes = mkOption {
        type = with types; attrsOf (attrsOf (addCheck attrs (a: a ? type)));
        default = {};
      };
      config.files = mapAttrs (_: v:
        mapAttrs' (n: w: {
          name = "recipes/${n}.json";
          value = w;
        })
        v)
      config.recipes;
    };
    mkDatapack = module: let
      inherit
        (
          (evalModules {
            modules = [
              datapackBaseModule
              datapackRecipeModule
              module
            ];
          })
          .config
        )
        name
        format
        description
        pkgs
        files
        ;
      inherit (pkgs) runCommand lib;
      inherit (lib) escapeShellArg attrsToList;
      inherit (builtins) baseNameOf dirOf toFile;
      concatMapLines = f: a: pkgs.lib.concatLines (builtins.map f a);
      packMcMeta = pkgs.writers.writeJSON "${name}-pack.mcmeta" {
        pack.pack_format = format;
        pack.description = description;
      };
      packDataDir = runCommand "${name}-data" {} (
        (
          /*
          bash
          */
          ''
            set -ex;
            mkdir $out;
          ''
        )
        + concatMapLines (
          p:
            concatMapLines (
              q:
              /*
              bash
              */
              ''
                mkdir -p $out/${escapeShellArg (p.name + "/" + dirOf q.name)}
                ln -s ${toFile (baseNameOf q.name) q.value} $out/${
                  escapeShellArg (p.name + "/" + q.name)
                }''
            ) (attrsToList p.value)
        ) (attrsToList files)
      );
      packRoot = runCommand name {} ''
        set -ex
        mkdir $out
        ln -s ${packMcMeta} $out/pack.mcmeta
        ln -s ${packDataDir} $out/data
      '';
    in
      packRoot;
    defaultPackage = perSystem (
      system:
        mkDatapack {
          pkgs = system;
          description = "Sample pack for mkDatapack.";
          recipes.mypack."fire_charge_with_redstone" = {
            type = "crafting_shapeless";
            ingredients = [
              {item = "minecraft:redstone";}
              {item = "minecraft:blaze_powder";}
              [
                {item = "minecraft:coal";}
                {item = "minecraft:charcoal";}
              ]
            ];
            result.item = "minecraft:fire_charge";
            result.count = 3;
          };
        }
    );
  };
}
