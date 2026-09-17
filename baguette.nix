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
    ${cfg.filesDir}. With this VM running, open crosh (Ctrl+Alt+T) and run:

        vmc share autofirma Downloads

    Shares are per VM. The Files app's "Share with Linux" targets the
    default `termina` VM, not this separate `autofirma` VM. Both can run
    at once. Repeat the share command after restarting this VM.
    A file `cert.password` next to it skips the password dialog.

    Alternatively, copy/paste the certificate through the terminal.
    On a machine that has it (including your existing `termina`), run
    `base64 < cert.p12 | fold -w 64` and copy the output. In this shell, run:

        umask 077
        base64 --decode > "$HOME/cert.p12"

    Paste the base64 text, finish the last line with Enter if needed,
    then press Ctrl+D on an empty line. Once the shell prompt returns,
    run `import-certificate "$HOME/cert.p12"`, enter the certificate
    password when prompted, and start Firefox (or restart it if already
    running). The import command creates the profile and certificate
    database if needed, without opening a browser window.

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
    # The Downloads folder of ChromeOS, once shared with this VM.
    filesDir = "/mnt/chromeos/MyFiles/Downloads";
    filesHelp = ''
      <ol>
        <li>Put <code>cert.p12</code> in the Downloads folder of ChromeOS.</li>
        <li>With this VM running, open crosh (Ctrl+Alt+T) and run
          <code>vmc share autofirma Downloads</code>. Repeat after each VM restart.</li>
        <li>Start "Firefox (AutoFirma)" again, or run
          <code>autofirma-vm-firefox</code> in <code>vsh</code>.</li>
      </ol>
      <p>Shares are per VM. The Files app's "Share with Linux" targets the
        default <code>termina</code> VM, not the separate <code>autofirma</code>
        VM. Both VMs can remain running.</p>
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
