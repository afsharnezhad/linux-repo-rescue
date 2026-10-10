# Troubleshooting notes: ExpressVPN install blocked by `ryoku.db`

## Incident

The ExpressVPN `.run` installer detected `pacman` and listed these Arch package dependencies in its embedded `install.sh`:

```bash
core_packages["pacman"]="libnl iptables psmisc gcc-libs brotli iproute2 ca-certificates"
gui_packages["pacman"]="libxkbcommon mesa xterm"
INSTALL_CMD="pacman -Sy --noconfirm"
CHECK_CMD="pacman -Q"
```

Most dependencies were already installed, but `xterm` was missing. `pacman` could not install it because the configured `ryoku` repository database failed to download.

The repository was configured in `/etc/pacman.conf`:

```ini
[ryoku]
SigLevel = Required
Server = https://repo.ryoku.dev/stable/$arch
```

## Resolution used

1. Backed up the configuration:

   ```bash
   sudo cp /etc/pacman.conf /etc/pacman.conf.backup
   ```

2. Temporarily commented out the Ryoku section in the **actual** config file:

   ```bash
   sudo sed -i '/^\[ryoku\]/,/^Server = /s/^/#/' /etc/pacman.conf
   ```

3. Refreshed package databases and installed `xterm`:

   ```bash
   sudo pacman -Syy
   sudo pacman -S xterm
   ```

4. Ran the installer:

   ```bash
   cd ~/Downloads
   sudo ./expressvpn-linux-universal-14.3.1.15429_release.run
   ```

5. Re-enabled the repository:

   ```bash
   sudo sed -i '/^#\[ryoku\]/,/^#Server = /s/^#//' /etc/pacman.conf
   ```

The user reported that ExpressVPN installed successfully.

## Important lessons

- Editing `/etc/pacman.conf.backup` does not change the live configuration.
- `pacman -Q` can check local package installation without downloading package files, though a missing database may still produce a warning.
- A `.run` file may still call the system package manager to install dependencies; “local installer” does not always mean fully offline.
- Disabling a third-party repository is a workaround, not a fix for the underlying network failure.
- Prefer a full system upgrade (`pacman -Syu`) on Arch; partial upgrades are unsupported.
