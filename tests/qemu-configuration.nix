# Guard the production settings that the signing scenario does not need to
# change. The driver, local HTTPS fixture and input devices remain explicit
# test instrumentation; they must not replace storage or application setup.
{
  pkgs,
  lib,
  production,
  tested,
}:
let
  select = c: {
    inherit (c) mainUser;
    inherit (c.virtualisation) writableStore sharedDirectories;
    storage = lib.getAttrs [ "/" "/state" "/var/tmp" "/var/log" ] c.virtualisation.fileSystems;
    storeMounts = lib.mapAttrs (_: unit: unit.text) (
      lib.getAttrs [ "nix-store.mount" "nix-.ro\\x2dstore.mount" ] c.systemd.units
    );
    inherit (c.environment) loginShellInit sessionVariables;
    inherit (c.hardware.graphics) enable;
    inherit (c.aldur.autofirma) filesDir;
    user = {
      inherit (c.users.users.${c.mainUser})
        uid
        home
        homeMode
        extraGroups
        ;
    };
    kernel = c.boot.kernelPackages.kernel.drvPath;
    initrd = c.boot.initrd.enable;
    firefox = c.programs.firefox.finalPackage.drvPath;
    autofirma = c.programs.autofirma.finalPackage.drvPath;
    logrotate = c.services.logrotate.enable;
    nixPath = c.nix.nixPath;
    manager = c.systemd.settings.Manager;
    userManager = c.systemd.user.extraConfig;
    stateDirectories = c.aldur.appliance.state.directories;
    inherit (c.hardening) foreignKernel;
    nix = c.nix.enable;
    ssh = c.services.openssh.enable;
    clipboard = c.services.spice-vdagentd.enable;
    firewall = c.networking.firewall.enable;
  };
  expected = select production;
  actual = select tested;
  differences = lib.filter (key: expected.${key} != actual.${key}) (lib.attrNames expected);
in
assert !production.virtualisation.writableStore;
assert production.aldur.appliance.state.directories == [ ];
assert !production.nix.enable && !production.services.openssh.enable;
assert !production.services.spice-vdagentd.enable;
assert tested.virtualisation.fileSystems."/nix/.ro-store".fsType == "erofs";
assert lib.assertMsg (
  differences == [ ]
) "AutoFirma signing test differs from production: ${lib.concatStringsSep ", " differences}";
pkgs.runCommand "autofirma-qemu-configuration" { } ''
  touch "$out"
''
