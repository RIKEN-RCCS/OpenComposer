# Open Composer OOD embed — admin deployment & review checklist

A short, self-contained guide for an Open OnDemand administrator deploying the
embed (Open Composer rendered inside OOD's own page). For the full
explanation see [`README.md`](README.md); for configuration see
[`dashboard.env.example`](dashboard.env.example).

## What it does (one paragraph)

It adds a small reverse-proxy controller to OOD's dashboard, mounted at
`/pun/sys/dashboard/oc`. Clicking the Open Composer tile lands there; the
controller fetches the real Open Composer app (`/pun/sys/<app>`) over the
loopback **as the requesting user** (it forwards that user's session cookie),
rewrites Open Composer's URL prefix so navigation stays wrapped, and renders the
result inside OOD's normal dashboard layout — so the live OOD navbar and footer
surround it.

## Prerequisites — confirm before installing

- [ ] **OOD 3.x or later**, dashboard serving **Bootstrap 5** (the embed lets
      OOD's Bootstrap style Open Composer; Bootstrap 4 portals are not supported).
- [ ] **Auth is `mod_auth_openidc`** and its session cookie reaches the dashboard
      on `/pun` (stock `ood-portal.conf` only strips it on `/node` and `/rnode`).
- [ ] Open Composer is installed as a **sys app** and you know its directory
      name (the `<app>` in `/pun/sys/<app>`).
- [ ] You may add a custom initializer under
      `/etc/ood/config/apps/dashboard/initializers/` (see security review below).

## Security review — what to scrutinise

- [ ] **Runs as the user, not as a service account.** Each proxied request
      carries the requesting user's own OIDC session cookie, so Apache
      authenticates and authorizes it exactly as a direct request would. The
      proxy cannot reach anything the user could not already reach directly.
- [ ] **Not an open proxy.** The upstream host/port are admin-set constants and
      the path is confined to the configured `/pun/sys/<app>` prefix; the user
      cannot redirect the proxy to an arbitrary destination.
- [ ] **Loopback TLS uses `verify_mode = VERIFY_NONE`.** This applies only to
      the in-host call to OOD's own Apache (typically a self-signed/internal
      cert); it is not external certificate trust.
- [ ] **CSRF protection is skipped on the proxy controller** (`skip_forgery_protection`).
      Open Composer posts its own forms without Rails tokens; the requests are
      forwarded verbatim under the user's session, i.e. the same trust boundary
      as using Open Composer directly.
- [ ] Source to review: [`initializers/opencomposer_embed.rb`](initializers/opencomposer_embed.rb)
      (controller + route) and [`views/apps/opencomposer_embed.html.erb`](views/apps/opencomposer_embed.html.erb)
      (layout wrapper). ~200 lines total, no external gems beyond what the
      dashboard already bundles (`net/http`, `nokogiri`).

## Install

- [ ] Copy the two files into the dashboard config:

      sudo mkdir -p /etc/ood/config/apps/dashboard/initializers
      sudo mkdir -p /etc/ood/config/apps/dashboard/views/apps
      sudo cp ood_integration/initializers/opencomposer_embed.rb \
              /etc/ood/config/apps/dashboard/initializers/
      sudo cp ood_integration/views/apps/opencomposer_embed.html.erb \
              /etc/ood/config/apps/dashboard/views/apps/

- [ ] Set the app name (and any upstream overrides) in the dashboard env file
      `/etc/ood/config/apps/dashboard/env` — see `dashboard.env.example`:

      OC_EMBED_APP_NAME=<your Open Composer sys-app directory name>

- [ ] In Open Composer's `manifest.yml`, set `new_window: false` so the tile
      opens in the same tab.
- [ ] (Optional) Pin Open Composer on the dashboard home page via `pinned_apps`.
- [ ] (Optional, recommended) In Open Composer's `conf.yml.erb`, hide the
      elements OOD already provides: `show_home_directory`, `show_shell_access`,
      `show_open_ondemand`, `show_footer` → `false`.
- [ ] Restart the web server: **Help → Restart Web Server**, or
      `sudo systemctl reload httpd`.

## Configuration (env file)

| Variable | Default | Set it when |
| --- | --- | --- |
| `OC_EMBED_APP_NAME` | `opencomposer` | Always — to your install directory name |
| `OC_EMBED_UPSTREAM_HOST` | request host | OOD is behind a load balancer / different internal host |
| `OC_EMBED_UPSTREAM_PORT` | request port | The portal vhost listens on a non-standard internal port |
| `OC_EMBED_UPSTREAM_SCHEME` | request scheme | e.g. plain HTTP behind a TLS-terminating proxy |
| `OC_EMBED_UPSTREAM_IP` | `127.0.0.1` | Bind to a specific IP, or set empty to resolve via DNS |

The defaults work for a standard single-host portal serving HTTPS on 443. Only
touch `OC_EMBED_UPSTREAM_*` if a load balancer or unusual front end sits in front
of OOD.

## Validate after install

- [ ] Click the Open Composer tile → it opens embedded, with OOD's navbar and
      footer around it (no new tab).
- [ ] OOD navbar **dropdowns** open (Files/Jobs/Clusters/Help/user menu).
- [ ] Navigate inside Open Composer (All Templates, History, Nodes, an app form)
      — each page stays wrapped in OOD's chrome.
- [ ] **Submit a real job** through the embedded form and confirm it reaches the
      scheduler and shows in History.
- [ ] **Two different users** log in concurrently and each sees their own Open
      Composer (templates, history, home directory).

## Performance note

Every Open Composer response — including CSS/JS/images/fonts — is proxied through
the dashboard Ruby process. This is fine for normal interactive use; if you
expect heavy concurrent load, account for the extra dashboard traffic.

## Rollback

Remove the two files and restart the web server; Open Composer reverts to opening
as a normal app.

      sudo rm /etc/ood/config/apps/dashboard/initializers/opencomposer_embed.rb
      sudo rm /etc/ood/config/apps/dashboard/views/apps/opencomposer_embed.html.erb
      sudo systemctl reload httpd
