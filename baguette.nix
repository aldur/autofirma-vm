# ChromeOS shows each window through sommelier. The shared appliance base
# supplies the ephemeral root and hardening; vsh gives a shell.
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

    The root uses a fresh overlay at each boot. No home directories are
    preserved under /state. The Firefox profile and imported key disappear
    on a full VM reboot or stop/start. Suspend and closing Firefox do not
    clear them. Save signed documents in the shared folder; files there
    persist on ChromeOS. This is not a secure erase.
    Sudo is disabled. The imported key remains accessible to this user
    during the session, and ChromeOS is trusted to control the VM.

    The start page of Firefox (file:///etc/autofirma-vm/index.html) has
    links to the usual sedes.
  '';
  cfg = config.aldur.autofirma;
in
{
  imports = [
    "${inputs.self}/base_hosts/appliance/baguette.nix"
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

  # Send host-opened links through the same certificate-import wrapper.
  systemd.user.services.garcon.environment.BROWSER = lib.mkForce (
    lib.getExe config.aldur.appliance.application
  );

  # The home is empty at boot; make the instructions available to vsh.
  systemd.tmpfiles.settings.autofirma = {
    "/home/${user}".d = {
      inherit user;
      group = "users";
      mode = "0700";
    };
    "/home/${user}/README.md"."L+".argument = toString homeReadme;
  };
}
