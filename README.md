# Splunk Add-on for Cisco ESA — Extension

An extension to the official [Splunk Add-on for Cisco ESA](https://splunkbase.splunk.com/app/1761)
(Splunkbase app 1761). The base add-on parses raw Cisco Email Security Appliance
(ESA) logs into the `cisco:esa:textmail` sourcetype and extracts the fields used
below. **This extension adds a scheduled saved search that periodically rolls
those raw, multi-line log events up into complete per-message transaction
summaries and stores them in a summary index.**

## Why this exists

A single email handled by a Cisco ESA is not logged as one event. Its lifecycle
is spread across many log lines that are correlated only by a set of connection
and message identifiers:

- **ICID** — Injection Connection ID (the inbound SMTP connection).
- **MID** — Message ID (the message itself).
- **DCID** — Delivery Connection ID (the outbound delivery connection).

Reconstructing "what happened to this message" therefore requires stitching many
raw events together at search time, which is expensive to do repeatedly for
reporting and dashboards.

This add-on runs that correlation on a schedule and writes one consolidated
event per message into a **summary index**. Downstream searches, reports, and
dashboards can then query compact, pre-joined transaction records instead of
re-crunching raw logs every time.

## What the scheduled search does

The saved search **`Generate Cisco ESA Email Summary`** (`default/savedsearches.conf`):

1. Reads recent `cisco:esa:textmail` events from the raw index.
2. Correlates the ICID / MID / DCID tuples belonging to the same message.
3. Aggregates per-message details — subject, sender, recipient(s), vendor
   action, reason, attachments, antivirus status, virus category — and enriches
   them with the originating connection's `src_host` / `src_ip` (joined via ICID).
4. Writes the resulting one-row-per-message summary into the summary index using
   `collect`, stamping each summary event with the message's start time.

Key settings:

| Setting | Value | Notes |
| --- | --- | --- |
| `cron_schedule` | `*/5 * * * *` | Runs every 5 minutes. |
| `dispatch.earliest_time` / `dispatch.latest_time` | `-7m@m` / `now` | Overlapping window so in-flight transactions are captured. |
| `disabled` | `true` | **Disabled by default** — enable it after configuring the indexes (see below). |

## Sample events

[`samples/cisco_esa_textmail_single_transaction.log`](samples/cisco_esa_textmail_single_transaction.log)
contains the raw `cisco:esa:textmail` log lines for **one complete message
transaction**, illustrating how a single email is spread across many events tied
together by the connection and message identifiers:

- **ICID `123456`** — the inbound SMTP connection (`New SMTP ICID ...`), carrying
  the source host/IP.
- **MID `654321`** — the message (`Start MID ... ICID ...`), carrying subject,
  sender, recipient, attachment, and antivirus verdict.
- **DCID `78901`** — the outbound delivery connection
  (`New SMTP DCID ... MID ...`).

Ingesting this sample into your raw index and running the scheduled search
produces a single summarized event for MID `654321` in the summary index.

[`samples/cisco_esa_summary_output.csv`](samples/cisco_esa_summary_output.csv)
shows exactly that resulting summary event (headers + one row) — how the many
raw log lines above collapse into a single per-message record written to the
summary index:

| Summary field | Value | Derived from |
| --- | --- | --- |
| `_time` / `mid_start` | `2026-08-31 10:00:01` | Earliest event time for the MID (`Start MID`). |
| `mid` | `654321` | `internal_message_id`. |
| `icid` / `icid_start` | `123456` / `2026-08-31 10:00:00` | Injection connection and its start time. |
| `dcid` | `78901` | Delivery connection. |
| `src_host` / `src_ip` | `mail.partner.example` / `203.0.113.10` | `New SMTP ICID` line (joined via ICID). |
| `sender` / `recipient` | `alice@partner.example` / `bob@company.example` | `From:` / `To:` lines. |
| `message_subject` | `Quarterly report Q3` | `Subject` line. |
| `attachments` | `quarterly_report.pdf` | `file_name . "." . attachment_type`. |
| `antivirus_status` | `negative` | `antivirus` verdict line. |
| `vendor_action`, `reason`, `virus_vendor_category` | (single/empty here) | Multi-value fields joined with `\|`. |

> Note: field extraction is performed by the base
> [Splunk Add-on for Cisco ESA](https://splunkbase.splunk.com/app/1761), so the
> exact set and formatting of values depends on its parsing. In this sample
> `attachment_type` and `virus_vendor_category` are not present in the raw logs,
> so those derived fields are empty.

## Contents

| File | Purpose |
| --- | --- |
| `default/savedsearches.conf` | The `Generate Cisco ESA Email Summary` scheduled search. |
| `default/macros.conf` | Index name macros used by the search (see [Configuration](#configuration)). |
| `default/app.conf` | Add-on metadata and reload triggers. |
| `metadata/default.meta` | Default object permissions (globally shared). |

## Prerequisites

- **Splunk Enterprise / Cloud** with the
  [Splunk Add-on for Cisco ESA](https://splunkbase.splunk.com/app/1761)
  installed — it provides the `cisco:esa:textmail` sourcetype and the field
  extractions (`icid`, `internal_message_id`, `dcid`, `message_subject`,
  `sender`, `recipient`, `vendor_action`, `reason`, `file_name`,
  `attachment_type`, `antivirus_status`, `virus_vendor_category`, `src_host`,
  `src_ip`) this search relies on.
- A **raw index** receiving Cisco ESA logs (default: `cisco_email_proxy`).
- A **summary index** to hold the generated summaries
  (default: `cisco_email_proxy_summary`). Create it if it does not exist, e.g.
  in `indexes.conf`:

  ```ini
  [cisco_email_proxy_summary]
  homePath   = $SPLUNK_DB/cisco_email_proxy_summary/db
  coldPath   = $SPLUNK_DB/cisco_email_proxy_summary/colddb
  thawedPath = $SPLUNK_DB/cisco_email_proxy_summary/thaweddb
  ```

## Configuration

Index names are not hard-coded in the search; they are provided by two macros in
`default/macros.conf` so you can point the add-on at your own indexes without
editing the search:

| Macro | Default definition | Meaning |
| --- | --- | --- |
| `` `cisco_esa` `` | `cisco_email_proxy` | Raw Cisco ESA mail index. |
| `` `cisco_esa_summary` `` | `cisco_email_proxy_summary` | Destination summary index. |

To use different index names, override the definitions in a **`local/macros.conf`**
(preferred, so upgrades don't overwrite your changes):

```ini
[cisco_esa]
definition = your_raw_index

[cisco_esa_summary]
definition = your_summary_index
```

Then **enable** the scheduled search (it ships disabled) in
Settings → Searches, reports, and alerts, or via `local/savedsearches.conf`:

```ini
[Generate Cisco ESA Email Summary]
disabled = false
```

## Installation

1. Install the [Splunk Add-on for Cisco ESA](https://splunkbase.splunk.com/app/1761).
2. Copy this add-on to `$SPLUNK_HOME/etc/apps/TA_cisco_esa_extension`.
3. Ensure the summary index exists and the macros point at the correct indexes.
4. Restart Splunk (or reload the relevant configs) and enable the saved search.

## License / support

Community add-on maintained by the author (`tomik.moser@gmail.com`). Provided
as-is; test in a non-production environment before deploying.
