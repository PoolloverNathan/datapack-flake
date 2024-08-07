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
      mkMerge
      types
      splitString
      ;
    pkgsFor = system: import nixpkgs {inherit system;};
    perSystem = genAttrs (attrNames nixpkgs.legacyPackages);
    perSystemWithPkgs = f: perSystem (system: f (pkgsFor system));
    ident = types.strMatching "[0-9a-z_.-]+:[0-9a-z_/.-]+";
    splitIdent = s: let
      res = splitString ":" s;
    in
      assert builtins.length res == 2; {
        namespace = builtins.elemAt res 0;
        path = builtins.elemAt res 1;
      };
    stripNulls = import ./strip-nulls.nix;
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
        zip = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to produce a zip file instead of a directory.";
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
                  (a: builtins.deepSeq a (builtins.toJSON (stripNulls a)))
                  string
                )
              )
            );
          default = {};
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
      prePost48 = pre: post:
        if config.format >= 48
        then post
        else pre;
    in {
      options.recipes = mkOption {
        type = with types; attrsOf (attrsOf (addCheck attrs (a: a ? type)));
        default = {};
      };
      config.files =
        mapAttrs (
          _: v:
            mapAttrs' (n: w: {
              name = "${prePost48 "recipes" "recipe"}/${n}.json";
              value = w;
            })
            v
        )
        config.recipes;
    };
    datapackTagsModule = {config, ...}: let
      inherit
        (config.pkgs.lib)
        mapAttrs
        mapAttrs'
        attrsToList
        listToAttrs
        concatMap
        length
        filter
        showDefs
        ;
    in {
      options.tags = mkOption {
        type = with types;
          attrsOf (
            attrsOf (
              attrsOf (
                coercedTo (listOf string)
                (values: {
                  replace = false;
                  inherit values;
                })
                (submodule {
                  options.replace = mkOption {
                    type = types.bool;
                    default = false;
                  };
                  options.values = mkOption {
                    type = with types; listOf string;
                    default = [];
                  };
                })
                // {
                  merge = loc: defs: let
                    replacers = filter (x: x.value.replace) defs;
                  in
                    if length replacers >= 2
                    then throw "Cannot have multiple tag definitions with replace = true\nDefinition values:${showDefs defs}"
                    else {
                      replace = length replacers == 1;
                      values = concatMap (x: x.value.values) defs;
                    };
                }
              )
            )
          );
        default = {};
      };
      config.files =
        mapAttrs (
          _: v:
            listToAttrs (
              concatMap (
                p:
                  builtins.map (q: {
                    name = "tags/${p.name}/${q.name}.json";
                    inherit (q) value;
                  }) (attrsToList p.value)
              ) (attrsToList v)
            )
        )
        config.tags;
    };
    datapackFunctionModule = {config, ...}: let
      inherit (config) format;
      inherit (builtins) map;
      inherit (config.pkgs.lib) concatMap concatLines attrsToList;
      prePost48 = pre: post:
        if format >= 48
        then post
        else pre;
    in {
      options.functions = mkOption {
        type = with types;
          attrsOf (
            attrsOf (
              coercedTo (listOf singleLineStr) (commands: {inherit commands;}) (submodule {
                options.commands = mkOption {type = listOf singleLineStr;};
                options.addToTags = mkOption {
                  type = listOf ident;
                  default = [];
                };
              })
            )
          );
        default = {};
      };
      # config = mkMerge (
      #   concatMap (
      #     p:
      #     map (q: {
      #       files.${p.name}."${prePost48 "functions" "function"}/${q.name}.mcfunction" = concatLines q.value.commands;
      #       tags = mkMerge (
      #         map (
      #           t:
      #           let
      #             inherit (splitIdent t) namespace path;
      #           in
      #           {
      #             tags.functions.${namespace}.${path} = [ "${p.name}:${q.name}" ];
      #           }
      #         ) q.value.addToTags
      #       );
      #     }) (attrsToList p.value)
      #   ) (attrsToList config.functions)
      # );
      config.files = mkMerge (
        concatMap (
          p:
            map (q: {
              ${p.name}."${prePost48 "functions" "function"}/${q.name}.mcfunction" = concatLines q.value.commands;
            }) (attrsToList p.value)
        ) (attrsToList config.functions)
      );
      config.tags = mkMerge (
        concatMap (
          p:
            concatMap (
              q:
                map (
                  t: let
                    inherit (splitIdent t) namespace path;
                  in {
                    ${namespace}.functions.${path} = ["${p.name}:${q.name}"];
                  }
                )
                q.value.addToTags
            ) (attrsToList p.value)
        ) (attrsToList config.functions)
      );
    };
    datapackOriginsModule = {config, ...}: {
      options.origins.origins = mkOption {
        type = with types;
          attrsOf (
            attrsOf (submodule {
              options = {
                icon = mkOption {type = ident;};
                impact = mkOption {
                  type = enum [
                    0
                    1
                    2
                    3
                  ];
                };
                order = mkOption {
                  type = int;
                  default = 0;
                };
                powers = mkOption {
                  type = listOf ident;
                  default = [];
                };
                loading_priority = mkOption {
                  type = int;
                  default = 0;
                };
                unchoosable = mkOption {
                  type = bool;
                  default = false;
                };
                name = mkOption {
                  type = nullOr string;
                  default = null;
                };
                description = mkOption {
                  type = nullOr string;
                  default = null;
                };
                upgrades = mkOption {
                  type = listOf (submodule {
                    options.condition = mkOption {type = ident;};
                    options.origin = mkOption {type = ident;};
                    options.announcement = mkOption {type = string;};
                  });
                  default = [];
                };
              };
            })
          );
        default = {};
      };
      options.origins.layers = mkOption {
        type = with types;
          attrsOf (
            attrsOf (
              coercedTo (listOf ident) (origins: {inherit origins;}) (submodule {
                options = {
                  replace = mkOption {
                    type = types.bool;
                    default = false;
                  };
                  order = mkOption {
                    type = types.nullOr types.int;
                    default = null;
                  };
                  origins = mkOption {
                    type = with types;
                      listOf (either ident (submodule {
                        options.origins = mkOption {
                          type = listOf ident;
                        };
                        options.condition = mkOption {
                          type = attrs;
                        };
                      }));
                    default = [];
                  };
                  enabled = mkOption {
                    type = types.nullOr types.bool;
                    default = null;
                  };
                  name = mkOption {
                    type = types.nullOr types.string;
                    default = null;
                  };
                };
              })
            )
          );
        default = {};
      };
      options.origins.powers = mkOption {type = with types; attrsOf (attrsOf attrs);};
      config.files = mkMerge (
        nixpkgs.lib.concatMap (
          p:
            map (q: {${p.name}."origin_layers/${q.name}.json" = q.value;}) (nixpkgs.lib.attrsToList p.value)
        ) (nixpkgs.lib.attrsToList config.origins.layers)
        ++ nixpkgs.lib.concatMap (
          p: map (q: {${p.name}."origins/${q.name}.json" = q.value;}) (nixpkgs.lib.attrsToList p.value)
        ) (nixpkgs.lib.attrsToList config.origins.origins)
        ++ nixpkgs.lib.concatMap (
          p: map (q: {${p.name}."powers/${q.name}.json" = q.value;}) (nixpkgs.lib.attrsToList p.value)
        ) (nixpkgs.lib.attrsToList config.origins.powers)
      );
    };
    mkDatapack = module: let
      inherit
        (
          (evalModules {
            modules = [
              datapackBaseModule
              datapackRecipeModule
              datapackTagsModule
              datapackFunctionModule
              datapackOriginsModule
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
        zip
        ;
      inherit (pkgs) runCommand lib;
      inherit (lib) escapeShellArg attrsToList;
      inherit (builtins) baseNameOf dirOf toFile;
      concatMapLines = f: a: pkgs.lib.concatLines (builtins.map f a);
      packMcMeta = pkgs.writers.writeJSON "${name}-pack.mcmeta" {
        pack.pack_format = format;
        pack.description = description;
      };
      zipStr = if zip then "true" else "false";
      packDataDir = runCommand "${name}-data" {} (
        (
          # bash
          ''
            set -ex;
            mkdir $out;
          ''
        )
        + concatMapLines (
          p:
            concatMapLines (
              q:
              # bash
              ''
                mkdir -p $out/${escapeShellArg (p.name + "/" + dirOf q.name)}
                cat <<<${escapeShellArg q.value} > $out/${
                  escapeShellArg (p.name + "/" + q.name)
                }''
            ) (attrsToList p.value)
        ) (attrsToList files)
      );
      packRoot = runCommand (name + ".zip") {} ''
        set -ex
        trap '''''' EXIT
        if ! ${zipStr}; then
          mkdir $out
          cd $out
        fi
        cp ${packMcMeta} pack.mcmeta
        cp -r ${packDataDir} data
        if ${zipStr}; then
          ${pkgs.zip}/bin/zip $out -r data pack.mcmeta
        fi
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
          tags.mypack.items.foo = [
            "minecraft:a"
            "mypack:b"
          ];
          tags.mypack.items.bar = {
            replace = true;
            values = [
              "minecraft:c"
              "mypack:d"
            ];
          };
          functions.mypack.foo = {
            commands = ["function mypack:bar"];
            addToTags = ["minecraft:tick"];
          };
          functions.mypack.bar = ["effect give @a water_breathing 1 2 true"];
          origins.layers.origins.origin = ["mypack:origin"];
          origins.origins.mypack.origin = {
            name = "Origin";
            description = "Hello, world!";
            icon = "minecraft:dirt";
            impact = 2;
            powers = ["mypack:power"];
          };
          origins.powers.mypack.power = {
            type = "origins:multiple";
            name = "Foo";
          };
        }
    );
  };
}
