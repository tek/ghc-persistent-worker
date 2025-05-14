{util}:
name:
{script ? null, build ? "buck build -v 2,stderr //$package/...", simple ? false}: let

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
    if script != null
    then script
    else default build
    ;

in util.zscript "buck-test-${name}" test
