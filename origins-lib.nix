pkgs: lib:
pkgs.lib
// rec {
  andActions =
    actions:
    assert builtins.isList actions;
    {
      type = "origins:and";
      inherit actions;
    };
  andConds =
    conditions:
    assert builtins.isList conditions;
    {
      type = "origins:and";
      inherit conditions;
    };
  invertCond =
    condition@{
      inverted ? false,
      ...
    }:
    condition // { inverted = !inverted; };
  orConds =
    conditions:
    assert builtins.isList conditions;
    {
      type = "origins:or";
      inherit conditions;
    };
  command =
    command:
    assert builtins.isString command;
    {
      type = "origins:execute_command";
      command = "${command}";
    };
  commands = commands: lib.andActions (builtins.map lib.command commands);
  mkPower =
    name:
    assert builtins.isString name || name == null;
    type:
    assert builtins.isString type;
    description:
    assert builtins.isString description || (name == null && description == null);
    data: data // { inherit name type description; };
  mkHiddenPower =
    type:
    assert builtins.isString type;
    data:
    data
    // {
      inherit type;
      hidden = true;
    };
  mkMulti =
    name:
    assert builtins.isString name;
    desc:
    assert builtins.isString desc;
    data: mkPower name "origins:multiple" desc (data mkSubpower);
  mkSubmulti = data: mkSubpower "origins:multiple" (data mkSubpower);
  mkHiddenMulti = data: mkHiddenPower "origins:multiple" (data mkSubpower);
  mkSimple = name: desc: mkPower name "origins:simple" desc { };
  mkHiddenSimple = mkHiddenPower "origins:simple" { };
  mkSubpower = type: data: data // { inherit type; };
  mkTooltip =
    sprite:
    assert builtins.isString sprite;
    text:
    assert builtins.isString text;
    {
      type = "origins:tooltip";
      inherit sprite text;
    };
  withTooltipPower =
    {
      text,
      order ? null,
      item_condition ? null,
    }@data:
    body: body "origins:tooltip" data;
  scaleTo = chan: value: command "scale set pehkui:${chan} ${builtins.toString value}";
  mkPehkui =
    name: description: scales:
    mkPower name "origins:action_on_callback" description {
      entity_action_added = andActions (lib.mapAttrsToList scaleTo scales);
      entity_action_removed = lib.command "scale reset";
    };
}
