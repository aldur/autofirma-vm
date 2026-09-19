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
    a dedicated ChromeOS folder before it starts Firefox: ${cfg.filesDir}.
    Create Downloads/AutoFirma in the Files app and put cert.p12 there.
    With this VM running, open crosh (Ctrl+Alt+T) and run:

        vmc share autofirma Downloads/AutoFirma

    Shares are per VM. The Files app's "Share with Linux" targets the
    default `termina` VM, not this separate `autofirma` VM. Both can run
    at once. Repeat the share command after restarting this VM.
    If you previously shared all of Downloads, stop/start the VM first
    to clear that broader share.
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

    /home, /tmp, /var/tmp and /var/log are tmpfs mounts. Their contents,
    including the Firefox profile and imported key, disappear on a full
    VM reboot or stop/start. Suspend and closing Firefox do not clear them.
    Save signed documents in the shared folder; files there persist on
    ChromeOS. The root disk also persists. This is not a secure erase.
    Sudo is disabled. The imported key remains accessible to this user
    during the session, and ChromeOS is trusted to control the VM.

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
    # Share only the signing directory, not all of ChromeOS Downloads.
    filesDir = "/mnt/chromeos/MyFiles/Downloads/AutoFirma";
    filesHelp = ''
      <ol>
        <li>Create <code>Downloads/AutoFirma</code> in ChromeOS and put
          <code>cert.p12</code> there.</li>
        <li>With this VM running, open crosh (Ctrl+Alt+T) and run
          <code>vmc share autofirma Downloads/AutoFirma</code>.
          Repeat after each VM restart. If all of Downloads was already
          shared, stop/start the VM first to clear that broader share.</li>
        <li>Start "Firefox (AutoFirma)" again, or run
          <code>autofirma-vm-firefox</code> in <code>vsh</code>.</li>
      </ol>
      <p>Shares are per VM. The Files app's "Share with Linux" targets the
        default <code>termina</code> VM, not the separate <code>autofirma</code>
        VM. Both VMs can remain running.</p>
      <p>The home directory, temporary files and guest logs disappear on a
        full VM reboot or stop/start. Files in the shared folder persist on
        ChromeOS. Save signed documents there before stopping the VM.</p>
    '';
  };

  networking.hostName = "autofirma-baguette";
  system.stateVersion = "26.05";

  # -- Size -------------------------------------------------------------------
  # CI builds replacements. The Baguette root disk persists between boots;
  # the session directories below are volatile. No rebuild from inside.
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
    # Retain the graphics access needed by sommelier, without wheel.
    extraGroups = lib.mkForce [ "video" "render" ];
  };
  users.users.root.hashedPassword = lib.mkForce "!";
  security.sudo.enable = false;
  security.sudo-rs.enable = false;
  security.doas.enable = false;
  security.polkit.enable = false;
  security.pam.services.su.requireWheel = true;
  # User applications do not need to write to the persistent Nix store.
  nix.settings.allowed-users = [ "root" ];
  # `vsh` opens a shell without a password.
  users.allowNoPasswordLogin = true;

  # ChromeOS may append `disk` and `sudo` to the account at startup through
  # maitred. Keep the raw disks root-only regardless of those memberships.
  services.udev.extraRules = ''
    SUBSYSTEM=="block", OWNER:="root", GROUP:="root", MODE:="0600"
  '';

  # Only these session directories are volatile; the root disk persists.
  # Do not use noexec: Firefox/Java may load native libraries from tmpfs.
  swapDevices = lib.mkForce [ ];
  zramSwap.enable = false;
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "1G";
  fileSystems."/tmp".options = [ "nosuid" "nodev" ];
  fileSystems."/var/tmp" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "size=1G" "mode=1777" "nosuid" "nodev" ];
  };
  fileSystems."/var/log" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "size=64M" "mode=755" "nosuid" "nodev" ];
  };
  services.journald.storage = "volatile";
  services.journald.extraConfig = lib.mkForce ''
    RuntimeMaxUse=32M
    ForwardToConsole=no
    ForwardToKMsg=no
    ForwardToSyslog=no
    ForwardToWall=no
  '';

  # Disabling systemd-coredump alone falls back to core files in the cwd.
  # An empty pattern with core_uses_pid=0 disables that fallback too.
  systemd.coredump.enable = false;
  boot.kernel.sysctl = {
    "kernel.core_pattern" = "";
    "kernel.core_uses_pid" = 0;
    "fs.suid_dumpable" = 0;
  };
  systemd.settings.Manager.DefaultLimitCORE = "0:0";
  systemd.user.extraConfig = "DefaultLimitCORE=0:0";
  security.pam.loginLimits = [
    { domain = "*"; type = "-"; item = "core"; value = "0"; }
  ];
  environment.sessionVariables.MOZ_CRASHREPORTER_DISABLE = "1";

  fileSystems."/home" = {
    device = "none";
    fsType = "tmpfs";
    options = [
      "defaults"
      "size=4G"
      "mode=755"
      "nosuid"
      "nodev"
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
