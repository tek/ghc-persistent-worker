{...}: {
  build = ''
  buck build //$package/... -j12 -v 2,stderr
  '';
}
