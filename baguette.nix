# The guest as a ChromeOS Baguette VM. ChromeOS shows each window through
# sommelier, so the guest has no desktop. The image does not import the
# dotfiles base module: no shell tools, no home-manager, no sshd. `vsh`
# gives a shell.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser;

  # `vsh` lands in this home. The file says how to start Firefox and where
  # the certificate goes. The start page of Firefox says the same.
  homeReadme = pkgs.writeText "README.md" ''
    # AutoFirma guest

    Start Firefox from the ChromeOS launcher: "Firefox (AutoFirma)", under
    the Linux apps. Or run `autofirma-vm-firefox` in this shell. The window
    comes through sommelier; the guest has no desktop.

    Use that entry, not the plain "Firefox" one. It imports `cert.p12` from
    the Downloads folder of ChromeOS before it starts Firefox:
    ${cfg.filesDir}. Share that folder with Linux from the Files app first.
    A file `cert.password` next to it skips the password dialog.

    This home is a tmpfs. Nothing in it survives `vmc stop`: not the
    Firefox profile, not the imported certificate. Keep your files in the
    shared folder.

    The start page of Firefox (file:///etc/autofirma-vm/index.html) has
    links to the usual sedes.
  '';
  cfg = config.aldur.autofirma;
in
{
  imports = [
    inputs.self.nixosModules.baguette-guest
    ./guest.nix
  ];

  aldur.autofirma = {
    # The Downloads folder of ChromeOS, once shared with Linux.
    filesDir = "/mnt/chromeos/MyFiles/Downloads";
    filesHelp = ''
      <ol>
        <li>Put <code>cert.p12</code> in the Downloads folder of ChromeOS.</li>
        <li>In the Files app, right-click Downloads and pick "Share with Linux".</li>
        <li>Start "Firefox (AutoFirma)" again, or run
          <code>autofirma-vm-firefox</code> in <code>vsh</code>.</li>
      </ol>
    '';
  };

  networking.hostName = "autofirma-baguette";
  system.stateVersion = "26.05";

  # -- Size -------------------------------------------------------------------
  # The image is disposable. CI builds a new one. No rebuild from inside.
  # The registry pin alone puts the nixpkgs source (200 MiB) in the image.
  # nixos-rebuild pulls Python (130 MiB).
  nixpkgs.flake = {
    setFlakeRegistry = false;
    setNixPath = false;
  };
  system.tools.nixos-rebuild.enable = false;
  documentation.enable = false;
  # man-db has its own switch. The line above does not reach it.
  documentation.man.enable = false;
  # The unit references gnupg for image signatures.
  systemd.suppressedSystemUnits = [ "systemd-importd.service" ];
  # Userborn replaces the perl activation script.
  services.userborn.enable = true;
  # No /run/opengl-driver. mesa and its LLVM take 800 MiB. Firefox renders
  # in software; the sedes are plain pages. sommelier opens a GBM device at
  # start, but the sommelier of ChromeOS brings its own libraries on the
  # tools disk. The boot test does the same.
  hardware.graphics.enable = false;

  users.users.${user} = {
    # bash is in the closure. fish is not.
    shell = lib.mkForce pkgs.bashInteractive;
  };
  security.sudo.wheelNeedsPassword = false;
  # `vsh` opens a shell without a password.
  users.allowNoPasswordLogin = true;

  # Nothing survives a session, like the QEMU guest: /home is a tmpfs. The
  # certificate comes back in from `filesDir` at each start.
  fileSystems."/home" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=4G"
      "mode=755"
    ];
  };
  # Activation creates the home before systemd mounts the tmpfs over it.
  # The tmpfs is empty at each start, so tmpfiles also puts the README in.
  systemd.tmpfiles.settings.autofirma = {
    "/home/${user}".d = {
      inherit user;
      group = "users";
      mode = "0700";
    };
    "/home/${user}/README.md"."L+".argument = toString homeReadme;
  };

  virtualisation = {
    buildMemorySize = 4096;
    # The closure is under 4 GiB. The VM grows the filesystem to the size
    # of `vmc create --size` at boot.
    diskImageSize = 6144;
  };
}
