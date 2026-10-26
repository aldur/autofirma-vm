# `autofirma` VM guest

A NixOS guest for [AutoFirma][0], the signing tool of the Spanish
government, with Firefox. It runs as a QEMU VM with an XFCE desktop, or as
a [ChromeOS Baguette][2] image.

AutoFirma talks to the browser over a TLS WebSocket on `127.0.0.1`. To make
the browser trust that socket, its installer adds a self-made root CA to the
system trust store. In this VM, the CA stays in `/etc/Autofirma` and in the
guest Firefox. The host trust store does not change.

The packages come from [autofirma-nix][1]. `guest.nix` holds what runs.
`desktop.nix` holds the QEMU VM: its XFCE session and its settings.
`baguette.nix` holds the Baguette image.

This repository holds only what is specific to AutoFirma. The `qemu-vm`
launcher and shared hardened appliance modules come from [aldur's dotfiles][3].
The Baguette image build and its boot
tests come from [nixos-crostini][2].

## Quick start

```bash
# On the Mac, or on any host with the qemu-vm package
nix run github:aldur/autofirma-vm -- \
  --gui --file cert.p12=/path/to/cert.p12
```

The guest logs `aldur` in. A dialog asks for the certificate password.
Firefox then opens on a start page with links to the usual sedes. The
serial console stays on the terminal. The QEMU monitor is on a unix
socket; the launcher prints the `nc -U` command for it.

## Sessions

Both guests use a fresh root at each boot and a read-only Nix store. No
home directories are preserved under `/state`, so the Firefox profile,
cookies, imported signing key and AutoFirma root CA disappear on a full
restart. Suspend and closing Firefox keep the current session.

QEMU also discards disk writes at exit by default. `--file` brings the
certificate in each time through firmware config. `--persistent` keeps the
backing disk under `~/.local/share/autofirma-vm`; session files still reset
at boot. Files explicitly written to `/state` persist when the backing disk
is kept; files in a ChromeOS share persist on the host.
This is not a secure erase. The host controls the VM and must be trusted.

SSH, sudo, swap, core dumps and the Nix daemon are disabled. The home has
mode `0700`. Guest logs and temporary files use RAM.

Close Firefox before stopping the VM. For QEMU, connect to the printed
monitor socket with `nc -U SOCKET`, issue `system_powerdown`, and wait for
QEMU to exit. For Baguette, stop the VM through ChromeOS.

To skip the password dialog, pass the password as a file too:
`--file cert.password=/path/to/password`.

## Certificate by hand

For QEMU, pass the certificate with `--file`. SSH and host clipboard
sharing are disabled in the appliance.

In a guest terminal, run `import-certificate cert.p12`, enter the certificate
password when prompted, and start Firefox. The import command creates the
profile and certificate database if needed, without opening a browser
window. If Firefox is already running, restart it after importing.

### Copy/paste through the terminal

On Baguette, this works without a shared folder. On a machine
that has the certificate (including your existing `termina` Linux
environment), encode it and copy the output:

```bash
base64 < cert.p12 | fold -w 64
```

In the target guest's terminal (`vsh autofirma penguin` from crosh for
Baguette), run:

```bash
umask 077
base64 --decode > "$HOME/cert.p12"
```

Paste the base64 text, press Enter if needed to finish the last line, then
Ctrl+D on an empty line to finish input. Once the shell prompt returns:

```bash
import-certificate "$HOME/cert.p12"
```

Enter the certificate password when prompted, then start Firefox (or
restart it if already running). No initial Firefox launch is needed.
Repeat the transfer and import after restarting an ephemeral guest.

## Baguette

The workflow `baguette-image.yml` builds the arm64 image on demand
(`workflow_dispatch`) and keeps it as the artifact
`autofirma-baguette-arm64` for a few days. The push pipeline builds the ARM
system closure and runs the x86 runtime checks on KVM. The image artifact
contains a read-only base and a separate state image. The workflow attests
both images and their resolved inputs. Download both artifacts and verify
them:

```bash
gh run download --repo aldur/autofirma-vm --name autofirma-baguette-arm64
gh run download --repo aldur/autofirma-vm --name autofirma-baguette-arm64-subject
gh attestation verify inputs.json --repo aldur/autofirma-vm \
  --signer-workflow aldur/autofirma-vm/.github/workflows/baguette-image.yml
gh attestation verify baguette_rootfs.img.zst --repo aldur/autofirma-vm \
  --signer-workflow aldur/autofirma-vm/.github/workflows/baguette-image.yml
gh attestation verify baguette_state.img.zst --repo aldur/autofirma-vm \
  --signer-workflow aldur/autofirma-vm/.github/workflows/baguette-image.yml
```

Decompress the verified base before use. The ARM64 disk sandbox in ChromeOS
156 blocks `pread64`, which crosvm uses to read the compressed base:

```bash
zstd --decompress --keep baguette_rootfs.img.zst
```

Copy `baguette_rootfs.img` and `baguette_state.img.zst` to ChromeOS Downloads.
Create a new VM in `crosh` (`Ctrl+Alt+T`). Use a new name if `autofirma`
already exists:

```text
vmc create --vm-type BAGUETTE --size 10G \
  --source /home/chronos/user/MyFiles/Downloads/baguette_state.img.zst \
  autofirma
vmc start --vm-type BAGUETTE \
  --rootfs /home/chronos/user/MyFiles/Downloads/baguette_rootfs.img \
  autofirma
```

Repeat the full start command after each VM stop or ChromeOS login. The app
launcher does not retain `--rootfs`; use it only after the VM starts. Keep
the base image outside directories shared with Linux.

To build the image yourself:

```bash
nix build .#baguette-zimage
```

ChromeOS shows the Firefox window through sommelier. There is no desktop in
the guest. Start "Firefox (AutoFirma)" from the launcher, or run
`autofirma-vm-firefox` in `vsh autofirma penguin`. A `README.md` in the
home of the guest repeats these steps. The wrapper imports `cert.p12`
from `/mnt/chromeos/MyFiles/Downloads/AutoFirma`.

Create `Downloads/AutoFirma` in ChromeOS and put `cert.p12` there. With
`autofirma` running, open crosh (`Ctrl+Alt+T`) and share that directory:

```bash
vmc share autofirma Downloads/AutoFirma
```

`Downloads/AutoFirma` is relative to ChromeOS My Files. Shares are per VM:
the Files app's "Share with Linux" targets the default `termina` VM, so it does not
share the folder with a separate VM named `autofirma`. Both VMs can remain
running. Repeat `vmc share autofirma Downloads/AutoFirma` after restarting
the VM, then start "Firefox (AutoFirma)" again to import the certificate. If all
of Downloads was previously shared, stop/start the VM to clear that share.
Only share this signing directory: guest applications can access its files.

Inside `autofirma`, check the share with:

```bash
ls -la /mnt/chromeos/MyFiles/Downloads/AutoFirma
```

Alternatively, use the [terminal copy/paste method](#copypaste-through-the-terminal)
above. The root uses a fresh overlay at boot. The profile, pasted
certificate and imported key do not survive `vmc stop`. Save signed
documents in the shared signing directory before stopping the VM.

The image uses the shared appliance base: no Home Manager, SSH server,
Nix daemon, rebuild tools or documentation. Baguette boots the ChromeOS
kernel and uses its sommelier tools for display integration. Firefox renders
in software; the guest does not include Mesa. Firefox omits ffmpeg,
PipeWire, GStreamer and speech synthesis, and AutoFirma uses a trimmed JRE.
The image is compressed with Zstandard; QEMU uses an EROFS store with LZ4HC.

Read `/etc/appliance-release` for the resolved build inputs and source date.
VMs are replaced with new builds rather than upgraded in place. Dependabot
proposes input updates on the 1st and 15th of each month; CI runs the signing
checks before merging. Build a new image after updates and urgent fixes.
Restarting an old VM keeps its old software. On Baguette, create the new
image under a new VM name and import the certificate again.

## Test

`nix flake check` runs `tests/sign-via-websocket.nix`. The test boots the
QEMU guest with a self-signed certificate passed the way `--file` does. The
session wrapper imports it into Firefox. Then the test opens a local HTTPS
page that uses AutoScript and clicks its button. It asserts that AutoFirma
returns a signature over the WebSocket. The test needs KVM.

```bash
nix build .#checks.x86_64-linux.sign-via-websocket -L
```

The test captures a desktop screenshot when waiting for the signing result,
including when that wait fails. Signing errors and timeouts fail the check.

The Baguette smoke check boots the distributed compressed root image through
the shipped ephemeral-root entry point, without an initrd, using the
representative Termina kernel from nixos-crostini. It observes user-manager startup before any user
command and never enables lingering or changes render-node permissions.
It requires garcon and all four sommelier instances, runs the production
Firefox wrapper with its user-manager environment, and signs using the
imported Firefox key. The signature must verify against the test signer;
tampered content must fail verification. A second boot on the same disk
checks that the previous session files and Firefox key store are gone.
CLI signing here complements the QEMU WebSocket scenario; it does not test
ChromeOS protocol dispatch.

```bash
nix build .#checks.x86_64-linux.baguette-boot -L
nix build .#checks.x86_64-linux.qemu-configuration -L
```

`qemu-configuration` checks that
the signing test retains production storage, application packages/policies,
user configuration, environment, hardening and service timeouts. The QEMU
scenario imports `desktop.nix` and boots the shared compressed-store test
fixture. It checks isolation and verifies after a full restart that the old
profile is gone and the supplied certificate is imported again. Its local
HTTPS server and the NixOS test driver remain explicit instrumentation.

The nixos-crostini smoke harness uses a fixture ext4 tools disk with
nixpkgs sommelier/Xwayland/Mesa, a headless Weston compositor, and stand-ins
for the host integration daemons. Test certificate files stand in for the
ChromeOS share at its configured guest path. These fixtures do not validate
ChromeOS registration, host file sharing, password dialogs or suspend/resume.
The kernel is representative, not the exact Chromebook build. VM failures,
timeouts, failed probes and shutdown errors fail the check.

CI executes both AutoFirma runtime scenarios and configuration checks on
x86 KVM runners. ARM image builds and configuration evaluation do not prove
ARM boot behavior. Follow the [normal-crosh device test][4] of the dotfiles for actual
ChromeOS startup and lifecycle validation.

## Maven dependencies

`maven-lock.json` pins each downloaded JAR and POM by its versioned Maven
Central URL and SHA-256 hash. The repository metadata needed to resolve
plugins and transitive version ranges is stored in the lock as well.
`locked-maven.nix` replaces the three upstream dependency fetchers with
these repositories; AutoFirma and its supporting libraries compile offline.
New releases or changes to Central's metadata cannot change a build's
dependency selection.

Refresh the lock deliberately when changing Maven or the upstream source
revisions. Build the three dependency repositories with the unmodified
`autofirma-nix` fetchers and the intended nixpkgs/Maven version, then run:

```bash
python3 update-maven-lock.py --upstream /path/to/autofirma-nix \
  --maven-version 3.9.12 \
  /nix/store/...-jmulticard-dependencies \
  /nix/store/...-clienteafirma-external-dependencies \
  /nix/store/...-autofirma-dependencies
```

Review the artifact/version changes and rebuild `.#autofirma-vm`. The
generator excludes Maven's SHA-1 sidecars because Nix verifies SHA-256,
and rejects snapshots and inconsistent metadata between repositories.

## Notes

- QEMU has no shared folder. Supply input files with `--file`.
- Both runtime checks require x86-64 Linux with KVM. ChromeOS host
  registration and display integration still need a device test.

[0]: https://firmaelectronica.gob.es/Home/Descargas.html
[1]: https://github.com/nix-community/autofirma-nix
[2]: https://github.com/aldur/nixos-crostini
[3]: https://github.com/aldur/dotfiles
[4]: https://github.com/aldur/dotfiles/blob/master/base_hosts/crostini/tests/device-boot.md
