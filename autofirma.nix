{ inputs, ... }:
{
  imports = [
    inputs.self.nixosModules.qemu-guest
    ./desktop.nix
  ];

  # The host key of the qemu-vm template. The guest only uses it with the
  # host, so both guests can share it: one known_hosts entry for
  # localhost:2222.
  aldur.qemuGuest.sshHostKeyDir = "${inputs.self}/base_hosts/qemu";

  virtualisation.graphics = true;
}
