# QEMU uses the shared appliance desktop and imports certificate files
# through fw_cfg (modules/nixos/qemu-vm-files.nix).
{ inputs, lib, ... }:
{
  imports = [
    "${inputs.self}/base_hosts/appliance/desktop.nix"
    ./guest.nix
  ];

  networking.hostName = "autofirma-vm";

  # Keep both store mounts available until systemd-shutdown pivots to its
  # ramfs. Unmounting either during umount.target strands the late helpers.
  systemd.units = lib.genAttrs [ "nix-store.mount" "nix-.ro\\x2dstore.mount" ] (_: {
    overrideStrategy = "asDropin";
    text = ''
      [Unit]
      DefaultDependencies=no
    '';
  });

  aldur.autofirma = {
    filesDir = "/run/qemu-vm-files";
    filesHelp = ''
      <ol>
        <li>Stop the VM. Start it again with your certificate:
          <code>autofirma-vm --gui --file cert.p12=/path/to/cert.p12</code></li>
        <li>Type the certificate password in the dialog that opens.</li>
      </ol>
    '';
  };
}
