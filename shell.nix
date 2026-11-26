{ pkgs ? import <nixpkgs> { } }:

import ../remya-core/nix/flutter-shell.nix {
  inherit pkgs;
  extraPackages = pkgs: with pkgs; [
    dbus
    gtk-layer-shell
    wayland
    wayland-scanner
  ];
}
