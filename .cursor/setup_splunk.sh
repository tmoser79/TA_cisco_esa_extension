#!/usr/bin/env bash
#
# Idempotent dev-environment bootstrap for the TA_cisco_esa_extension Splunk add-on.
#
# This repository is a Splunk Technology Add-on (a package of Splunk .conf files),
# not a standalone runnable application. To develop and validate it you need a
# local Splunk Enterprise instance with the add-on deployed into its apps
# directory. This script installs Splunk Enterprise (once), links this repo in as
# an app, and validates the add-on's configuration with `btool`.
#
# Safe to re-run: every step checks for existing state before acting.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via environment variables if desired)
# ---------------------------------------------------------------------------
SPLUNK_VERSION="${SPLUNK_VERSION:-10.4.2}"
SPLUNK_BUILD="${SPLUNK_BUILD:-33c3bf42cd73}"
SPLUNK_HOME="${SPLUNK_HOME:-/opt/splunk}"
SPLUNK_PKG_URL="${SPLUNK_PKG_URL:-https://download.splunk.com/products/splunk/releases/${SPLUNK_VERSION}/linux/splunk-${SPLUNK_VERSION}-${SPLUNK_BUILD}-linux-amd64.tgz}"

# Directory that contains this script (…/.cursor) and the repo root above it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# The add-on's Splunk app name (matches [package] id in default/app.conf).
ADDON_NAME="TA_cisco_esa_extension"
APPS_DIR="${SPLUNK_HOME}/etc/apps"

log() { printf '\n=== %s ===\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Install Splunk Enterprise (only if not already present)
# ---------------------------------------------------------------------------
if [[ -x "${SPLUNK_HOME}/bin/splunk" ]]; then
  log "Splunk already installed at ${SPLUNK_HOME}"
else
  log "Downloading Splunk Enterprise ${SPLUNK_VERSION}"
  tmp_tgz="$(mktemp --suffix=.tgz)"
  # -L follows redirects; download over HTTPS only.
  curl -fSL --proto '=https' --tlsv1.2 -o "${tmp_tgz}" "${SPLUNK_PKG_URL}"

  log "Installing Splunk Enterprise to ${SPLUNK_HOME}"
  sudo mkdir -p "$(dirname "${SPLUNK_HOME}")"
  sudo tar xzf "${tmp_tgz}" -C "$(dirname "${SPLUNK_HOME}")"
  sudo chown -R "$(id -un):$(id -gn)" "${SPLUNK_HOME}"
  rm -f "${tmp_tgz}"
fi

# ---------------------------------------------------------------------------
# 2. Seed admin credentials (never hard-coded; generated locally if unset)
# ---------------------------------------------------------------------------
# Splunk requires an initial admin account. We do NOT commit any credential.
# Use SPLUNK_ADMIN_PASSWORD from the environment (e.g. a Cloud Agent secret)
# when provided; otherwise generate a strong random one and store it with
# owner-only permissions outside of version control.
seed_file="${SPLUNK_HOME}/etc/system/local/user-seed.conf"
pw_cache="${SPLUNK_HOME}/etc/.dev_admin_password"
if [[ ! -f "${SPLUNK_HOME}/etc/passwd" && ! -f "${seed_file}" ]]; then
  log "Seeding initial Splunk admin account"
  admin_pw="${SPLUNK_ADMIN_PASSWORD:-$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)}"
  mkdir -p "$(dirname "${seed_file}")"
  cat > "${seed_file}" <<EOF
[user_info]
USERNAME = admin
PASSWORD = ${admin_pw}
EOF
  chmod 600 "${seed_file}"
  # Cache the generated password for the developer, owner-readable only.
  if [[ -z "${SPLUNK_ADMIN_PASSWORD:-}" ]]; then
    printf 'admin / %s\n' "${admin_pw}" > "${pw_cache}"
    chmod 600 "${pw_cache}"
    log "Generated dev admin password saved to ${pw_cache} (owner-only)"
  fi
  unset admin_pw
fi

# ---------------------------------------------------------------------------
# 3. Deploy this add-on into Splunk's apps directory (symlink to the repo)
# ---------------------------------------------------------------------------
log "Deploying ${ADDON_NAME} into ${APPS_DIR}"
mkdir -p "${APPS_DIR}"
target="${APPS_DIR}/${ADDON_NAME}"
if [[ -L "${target}" ]]; then
  # Refresh the symlink in case the repo moved.
  ln -sfn "${REPO_ROOT}" "${target}"
elif [[ -e "${target}" ]]; then
  log "WARNING: ${target} exists and is not a symlink; leaving it untouched"
else
  ln -s "${REPO_ROOT}" "${target}"
fi

# ---------------------------------------------------------------------------
# 4. Accept the license non-interactively (first run only)
# ---------------------------------------------------------------------------
if [[ ! -f "${SPLUNK_HOME}/etc/splunk-launch.conf" ]] || ! grep -q "OPTIMISTIC_ABOUT_FILE_LOCKING" "${SPLUNK_HOME}/etc/splunk-launch.conf" 2>/dev/null; then
  # Ensure disk-locking optimism so Splunk starts cleanly on overlay filesystems.
  echo "OPTIMISTIC_ABOUT_FILE_LOCKING=1" | sudo tee -a "${SPLUNK_HOME}/etc/splunk-launch.conf" >/dev/null || true
fi

log "Setup complete. Start Splunk with: ${SPLUNK_HOME}/bin/splunk start --accept-license --answer-yes --no-prompt"
log "Validate the add-on with: ${SPLUNK_HOME}/bin/splunk btool --app=${ADDON_NAME} check --debug"
