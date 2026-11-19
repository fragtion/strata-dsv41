# Security

## Reporting a vulnerability

Please report anything that should not be public until it is fixed **privately**, through GitHub's private
vulnerability reporting: the repository's **Security** tab, **Report a vulnerability**
([direct link](https://github.com/fragtion/strata-dsv41/security/advisories/new)). Say what you found, how to reproduce it
(the request, the config keys involved, the commit), and what an attacker gains. We answer there, fix it, and credit you in the advisory unless you ask us not to.

Ordinary hardening ideas and findings that are safe to discuss in public are welcome as an
[issue](https://github.com/fragtion/strata-dsv41/issues) or as a pull request, which we
review like our own code.

Supported: the latest commit on `main`.

## What the server exposes

The server (`terminal/serve/server.py`) serves the model over HTTP. Out of the box it is reachable from this PC only.

- **Where it listens.** `127.0.0.1` by default. `--host 0.0.0.0` (or `"host"` in the run config) opens it to
  your network, and the server then warns when no API key is set.
- **API key.** `"api_key"` in the run config (or `STRATA_API_KEY`) is required on `/v1/*` and on every endpoint
  that shows the model's state, requests or answers (`/status`, `/metrics`, `/metrics/prometheus`, `/settings`,
  `/mcp`, `/props`, `/slots`, `/api/requests`, `/config`) and on every `POST`. It is compared in constant time.
  Set one before you open the
  server to your network or put a tunnel in front of it.
- **Host check (DNS rebinding, 0.1.38).** Without an API key the server answers only requests whose `Host` is a name
  it knows (`localhost`, an IP address, the address it listens on and, when it listens beyond this PC, this PC's
  name). Others get 403. `"allowed_hosts"` adds names; with an API key the key decides.
- **Origin check (0.1.38).** Without an API key, a browser `POST` to `/v1/*` from another web site's page (it carries
  an `Origin` header) gets 403 unless that origin is the server's own page, `localhost`, an allowed host, or listed in
  `"trusted_origins"` / `"cors_origins"`. Changing settings (`/settings`, and `/config`: the few run config keys the
  page's Model settings may change - never the network, key, MCP or program keys), `/load` and `/unload` and the
  MCP tools are accepted only as JSON from the server's own page (or `"trusted_origins"`), so a page elsewhere cannot
  change settings or run tools.
- **CORS** is off unless `"cors_origins"` lists origins, and then only for `/v1/*`.
- **MCP tools** are opt-in: only the servers you put in the run config, only for requests from the server's own page
  that ask for them. They run with your user's rights, and the model decides when to call them.
- **The request monitor** (`/api-monitor`, which keeps the last prompts and answers in memory) is off unless
  `"api_monitor": true` is set. Apart from it, the server keeps in its process memory the text and tokens of its
  last few prompts, whatever `"api_monitor"` says, to encode the next turn faster; no endpoint shows them, and they
  are gone when the server stops.

## What this repository does not have

This repository has no installer, no update feed, no desktop app and no Terminal: it downloads nothing on its own.
You build the engine from source and start the server yourself. The server fetches only what a request names (an image
URL) and starts only the MCP servers you list in the run config; `--offline` turns both off.

No outside security audit has been done.
