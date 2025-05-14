{util}:
name:
{script ? null, build ? null, simple ? false}: let

  inherit (util) pkgs;

  default = cmds: ''
  dir=$(mktemp -d --tmpdir=$PWD buck-${name}-XXX)
  package=''${dir##*/}

  cleanup()
  {
    rm -rf $dir
  }
  trap cleanup EXIT
  trap cleanup INT

  mkdir -p $dir
  ${pkgs.rsync}/bin/rsync -rlt ops/buck-test/${name}/project/ $dir/
  sed -i "s#ops/buck-test/${name}/project/#$package/#g" $dir/**/BUCK

  buck kill
  ${cmds}
  buck kill
  '';

  test =
    if simple
    then default "buck build -v 2,stderr //$package/..."
    else if script == null
    then default build
    else script
    ;

in util.zscript "buck-test-${name}" test
