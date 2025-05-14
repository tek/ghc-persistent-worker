{util}:
name:
{script ? null, build ? null, simple ? false}: let

  inherit (util) pkgs;

  default = cmds: ''
  #!${pkgs.runtimeShell}
  set -e

  dir=$(mktemp -d --tmpdir=$PWD buck-${name}-XXX)
  package=''${dir##*/}

  cleanup()
  {
    rm -rf $dir
  }
  trap cleanup EXIT

  mkdir -p $dir
  ${pkgs.rsync}/bin/rsync -rlt ops/buck-test/${name}/project/ $dir/
  ln -s $dir $package

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

in pkgs.writeScript "buck-test-${name}" test
