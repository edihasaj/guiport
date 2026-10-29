---
summary: "Landing site: GitHub Pages deploy, self-hosted Umami analytics, IndexNow key injection."
read_when:
  - Changing files under docs/ or the landing page.
  - Changing .github/workflows/pages.yml or Pages/IndexNow settings.
  - Adding analytics, a canonical, or a new public page to the site.
---

# Website ops

`docs/` **is** the public site. GitHub Pages serves it at `https://guiport.dev/`
via `docs/CNAME`; DNS is authoritative at Cloudflare and the records are
**unproxied**, pointing straight at GitHub Pages.

## Deploy

`.github/workflows/pages.yml` builds on pushes touching `docs/**` (or the
workflow itself) and publishes the `docs/` directory. It is Linux-only and
adds no native CI. Pages must be set to **GitHub Actions** as the build source
(Settings → Pages → Build source), not "Deploy from a branch".

Before the artifact is uploaded, the workflow writes the IndexNow ownership key
file into the site root from the `COMPASS_INDEXNOW_KEY` repository secret. The
key value never enters the repository or the logs, and the job **fails closed**
when the secret is missing or malformed rather than publishing an
un-noticeable site. Because the DNS records are unproxied, Cloudflare's
exact-key ownership route is unavailable; the key file has to be served by
GitHub Pages at `https://guiport.dev/<key>.txt`, which is why it is injected
into the deployed artifact instead of committed. Rotating the key in Compass
needs no change here.

## Analytics

Website analytics is self-hosted Umami at `https://insights.applifyer.com`.
Both `docs/index.html` and `docs/privacy.html` load the same snippet:

```html
<script async defer src="https://insights.applifyer.com/insights.js"
  data-website-id="9ee0c7ad-a914-47f7-b442-d1bafbe05b5f"
  data-domains="guiport.dev,www.guiport.dev"
  data-do-not-track="true"
  data-exclude-search="true"
  data-exclude-hash="true"></script>
```

Only pageviews are collected; the site deliberately configures **no custom
events** (no `data-umami-event-*` attributes), so click tracking never fires.
`data-domains` keeps the counts to the two real hostnames,
`data-do-not-track` respects a browser Do Not Track signal, and
The fleet tracker keeps only the five standard UTM attribution fields when
`data-exclude-search` is enabled; other query parameters are removed.
`data-exclude-hash` removes URL fragments. Attribute names were checked
against the script that `insights.applifyer.com` actually serves.

Add any new public page with the same snippet, its own
`<link rel="canonical">`, and a `docs/sitemap.xml` entry. `docs/robots.txt`
already allows all crawlers and advertises the sitemap. `docs/privacy.html` is
the visitor-facing disclosure linked from the footer; if the snippet changes,
update it there too.

## Website analytics is not app telemetry

The snippet lives only in the landing-page HTML. Nothing in this section
changes what the `guiport` CLI, MCP server, or the shipped binaries send. Do
not read website pageviews as product telemetry, and do not add app-side
reporting under this heading without a separate decision from Edi.
