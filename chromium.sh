#!/bin/bash

get_int32_property() {
  gdbus call -e \
    -d org.freedesktop.portal.Flatpak \
    -o /org/freedesktop/portal/Flatpak \
    -m org.freedesktop.DBus.Properties.Get \
    org.freedesktop.portal.Flatpak "$1" \
    | awk 'match($0, /uint32 ([0-9]+)/, m){print m[1];}'
}

merge_extensions() {
  (
    shopt -s nullglob
    dest=/app/chromium/extensions/$1
    mkdir -p $dest
    for ext in /app/chromium/${1%/*}/$1/*; do
      ln -s $ext $dest
    done
  )
}

unlink_profiles() {
  local stamp="$XDG_CONFIG_HOME/chromium-profiles-unlinked-stamp"
  if [[ ! -d "$XDG_CONFIG_HOME/chromium" ]]; then
    touch "$stamp"
  elif [[ ! -f "$stamp" ]]; then
    unlink_profiles.py && touch "$stamp"
  fi
}

# Check the portal version & make sure it supports expose-pids.
if [[ $(get_int32_property version) -lt 4 || \
      $(($(get_int32_property supports) & 1)) -eq 0 ]]; then
  zenity --info --title='Chromium Flatpak' --no-wrap \
    --text="$(< /app/share/flatpak-chromium/portal_error.txt)"
  exit 1
fi

# Merge the flags.
if [[ -f "$XDG_CONFIG_HOME/chromium-flags.conf" ]]; then
  IFS=$'\n'
  # Append non-default PipeWire flag for Wayland screen sharing 
  echo "--enable-features=WebRTCPipeWireCapturer" >> "$XDG_CONFIG_HOME/chromium-flags.conf"

  flags=($(grep -v '^#' "$XDG_CONFIG_HOME/chromium-flags.conf"))
  unset IFS

  set -- "${flags[@]}" "$@"
fi

if [[ ! -f /app/chromium/extensions/no-mount-stamp ]]; then
  # Merge all legacy extension points if the symlinks had a tmpfs mounted over
  # them.
  merge_extensions native-messaging-hosts
  merge_extensions policies/managed
  merge_extensions policies/recommended
fi

# Unlink any profiles from the sync keys to avoid any expected deletions.
unlink_profiles

flextop-init

export TMPDIR="$XDG_RUNTIME_DIR/app/$FLATPAK_ID"
export CHROME_WRAPPER=$(readlink -f "$0")
exec /app/chromium/chrome "$@"
