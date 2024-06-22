# vim: ts=2 sts=2 sw=2 et
let
  inherit (builtins) typeOf listToAttrs attrNames concatMap map trace deepSeq filter isNull;
  stripNulls = attrs:
    if builtins.isAttrs attrs
    then
      listToAttrs (concatMap (k:
        if attrs.${k} == null
        then []
        else
          builtins.break [
            {
              name = k;
              value = stripNulls attrs.${k};
            }
          ])
      (attrNames attrs))
    else if builtins.isList attrs
    then map stripNulls (filter (a: a != null) attrs)
    else if attrs == null
    then throw "stripped null at root"
    else attrs;
  force = a: deepSeq a a;
  testIn = stripNulls {
    a = 2;
    b = null;
    c.d = null;
    e = [null {f = null;}];
  };
  testOut = {
    a = 2;
    c = {};
    e = [{}];
  };
in
  if stripNulls testIn == testOut
  then stripNulls
  else
    throw (trace (force {
      input = testIn;
      expected = testOut;
      received = stripNulls testIn;
    }) "stripNulls failed")
