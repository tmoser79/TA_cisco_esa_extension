# TA_cisco_esa_extension

Splunk Add-on for Cisco ESA — Extension. This is a Splunk **Technology Add-on (TA)**:
a package of Splunk configuration (`.conf`) files, not a standalone runnable
application. It is deployed into a Splunk Enterprise instance under
`$SPLUNK_HOME/etc/apps/`.

## Contents

- `default/app.conf` — add-on metadata and reload triggers.
- `default/savedsearches.conf` — the scheduled search that populates the
  `cisco_email_proxy_summary` index with ICID/MID/DCID transaction tuples.
- `metadata/default.meta` — default object permissions.

## Development environment

Because a TA only runs inside Splunk, the dev environment installs a local
Splunk Enterprise instance and deploys this repository into it as an app.

Run the bootstrap script (idempotent):

```bash
bash .cursor/setup_splunk.sh
```

This will:

1. Install Splunk Enterprise to `/opt/splunk` (downloaded once).
2. Seed an initial admin account. No credential is committed to the repo — set
   `SPLUNK_ADMIN_PASSWORD` in the environment to choose one, otherwise a random
   password is generated and written (owner-only) to
   `/opt/splunk/etc/.dev_admin_password`.
3. Symlink this repository into `/opt/splunk/etc/apps/TA_cisco_esa_extension`.

Start Splunk and validate the add-on:

```bash
# Start Splunk (Web UI on :8000, management API on :8089)
/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt

# Validate the add-on's configuration merges cleanly
/opt/splunk/bin/splunk btool --app=TA_cisco_esa_extension check --debug

# Confirm the saved search is registered
/opt/splunk/bin/splunk btool savedsearches list --app=TA_cisco_esa_extension
```

When running as a Cursor Cloud Agent, `.cursor/environment.json` performs the
install automatically and starts Splunk on boot.
