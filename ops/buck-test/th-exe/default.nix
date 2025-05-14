# Test executing an external program from a splice.
{...}: {
  build = ''
  buck build //$package:th-exe-run -j12 -v 2,stderr
  buck build //$package:th-exe-use -j12 -v 2,stderr
  '';
}
