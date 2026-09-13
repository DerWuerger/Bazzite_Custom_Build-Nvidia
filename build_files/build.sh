#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

chmod 0755 /usr/bin/bazzite-custom-firststart
chmod 0644 /usr/lib/systemd/system/bazzite-custom-firststart.service
chmod 0644 /usr/lib/systemd/system/bazzite-custom-firststart.timer

# Bazzite leaves terra-mesa disabled after composing the NVIDIA image; keep it
# disabled so bootc-image-builder does not try to resolve its file:// GPG key.
dnf5 -y config-manager setopt "terra-mesa".enabled=0 || true
for repo_file in /etc/yum.repos.d/*.repo; do
  if grep -q '^\[terra-mesa\]' "$repo_file"; then
    awk '
      /^\[terra-mesa\]$/ { section = 1; saw_enabled = 0; print; next }
      /^\[/ {
        if (section && !saw_enabled) {
          print "enabled=0"
        }
        section = 0
      }
      section && /^enabled=/ { print "enabled=0"; saw_enabled = 1; next }
      section && /^gpgcheck=/ { print "gpgcheck=0"; next }
      section && /^gpgkey=/ { print "# " $0; next }
      { print }
      END {
        if (section && !saw_enabled) {
          print "enabled=0"
        }
      }
    ' "$repo_file" >"${repo_file}.tmp"
    mv -f "${repo_file}.tmp" "$repo_file"
  fi
done

systemctl enable bazzite-custom-firststart.timer
