# AutoFirma VM

A NixOS VM with [AutoFirma](https://firmaelectronica.gob.es/Home/Descargas.html)
and Firefox, for QEMU or ChromeOS Baguette. AutoFirma's local root CA stays
inside the guest. The host trust store does not change.

See the [shared appliance guide][appliance] for VM operation, state, backups
and updates. The packages come from [autofirma-nix][autofirma-nix].

AutoFirma keeps no application data under `/state`. A full restart clears
the Firefox profile, cookies and imported signing key. Import the certificate
again after each restart. Suspend and closing Firefox keep the current session.

## QEMU

```bash
nix run github:aldur/autofirma-vm -- \
  --gui --file cert.p12=/path/to/cert.p12
```

The guest logs in as `aldur`, asks for the certificate password and opens
Firefox. To supply the password as a file, also pass
`--file cert.password=/path/to/password`.

## ChromeOS Baguette

Build on ARM Linux with `nix build .#baguette-zimage`, or run
[baguette-image.yml][image-workflow]. Download and verify the CI artifacts:

```bash
gh run download --repo aldur/autofirma-vm --name autofirma-baguette-arm64
gh run download --repo aldur/autofirma-vm --name autofirma-baguette-arm64-subject
for file in inputs.json baguette_rootfs.img.zst baguette_state.img.zst; do
  gh attestation verify "$file" --repo aldur/autofirma-vm \
    --signer-workflow aldur/autofirma-vm/.github/workflows/baguette-image.yml
done
```

Decompress the verified base:

```bash
zstd --decompress --keep baguette_rootfs.img.zst
```

Copy `baguette_rootfs.img` and `baguette_state.img.zst` to ChromeOS
`Downloads/autofirma`. Open crosh (`Ctrl+Alt+T`), create the VM once, then start it:

```text
vmc create --vm-type BAGUETTE --size 10G \
  --source /home/chronos/user/MyFiles/Downloads/autofirma/baguette_state.img.zst \
  autofirma
vmc start --vm-type BAGUETTE \
  --rootfs /home/chronos/user/MyFiles/Downloads/autofirma/baguette_rootfs.img \
  autofirma
```

Repeat the full start command after each VM stop. The state image starts empty;
its download can be deleted after creation. Keep `baguette_rootfs.img`.
See the [shared VM setup guide][baguette] for details.

Create `Downloads/AutoFirma` in ChromeOS and put `cert.p12` there. With the
VM running, share that directory from crosh:

```text
vmc share autofirma Downloads/AutoFirma
```

Repeat the share command after each VM restart. Shares are per VM; the
Files app's “Share with Linux” targets `termina`. Share only this signing
folder. Keep the base image outside it.

Start “Firefox (AutoFirma)” from the launcher, or open a guest shell with
`vsh autofirma penguin` and run `autofirma-vm-firefox`. This wrapper imports
the certificate before Firefox starts. A `cert.password` file beside the
certificate skips the password dialog.

Save signed documents in the shared folder before stopping the VM.

## Certificate import without a share

On a machine with the certificate, encode it and copy the output:

```bash
base64 < cert.p12 | fold -w 64
```

In the guest terminal:

```bash
umask 077
base64 --decode > "$HOME/cert.p12"
```

Paste the text, press Enter to finish the last line, then Ctrl+D on an empty
line. After the shell prompt returns, import the certificate:

```bash
import-certificate "$HOME/cert.p12"
```

Enter the certificate password, then start or restart Firefox. The import
command also works with an existing file; no initial Firefox launch is needed.

## Development

`guest.nix` configures AutoFirma and certificate import. `desktop.nix` and
`baguette.nix` select the shared QEMU and Baguette modules from the dotfiles.
[nixos-crostini][crostini] supplies the Baguette image builder and boot tests.

Run the signing and session-reset checks on x86-64 Linux with KVM:

```bash
nix build .#checks.x86_64-linux.sign-via-websocket -L
nix build .#checks.x86_64-linux.baguette-boot -L
nix build .#checks.x86_64-linux.qemu-configuration -L
```

These check WebSocket signing, Baguette CLI signing and agreement with the
production QEMU configuration. ChromeOS registration, display and lifecycle
still need a [device test][device-test].

`maven-lock.json` pins Maven artifacts and metadata by URL and SHA-256.
`locked-maven.nix` uses these to build offline. When changing upstream sources
or Maven, build the three dependency repositories with the unmodified
`autofirma-nix` fetchers, then update the lock:

```bash
python3 update-maven-lock.py --upstream /path/to/autofirma-nix \
  --maven-version 3.9.12 \
  /nix/store/...-jmulticard-dependencies \
  /nix/store/...-clienteafirma-external-dependencies \
  /nix/store/...-autofirma-dependencies
```

Review the lock changes and rebuild the VM.

[appliance]: https://github.com/aldur/dotfiles/blob/master/base_hosts/appliance/README.md
[baguette]: https://github.com/aldur/dotfiles/blob/master/base_hosts/appliance/README.md#start-the-vm
[autofirma-nix]: https://github.com/nix-community/autofirma-nix
[image-workflow]: https://github.com/aldur/autofirma-vm/actions/workflows/baguette-image.yml
[crostini]: https://github.com/aldur/nixos-crostini
[device-test]: https://github.com/aldur/dotfiles/blob/master/base_hosts/crostini/tests/device-boot.md
