# actions-demo

GitHub Actions runners can make arbitrary outbound requests. A compromised
dependency, a malicious build step, or a prompt injection can exfiltrate
secrets, phone home, or open a reverse shell — and most teams have zero
visibility into what's leaving their CI jobs.

This demo shows how [iron-proxy](https://github.com/ironsh/iron-proxy) locks
that down. It spins up a GitHub Actions self-hosted runner behind iron-proxy
so that every outbound request is default-deny, audited, and secrets are
swapped at the network boundary.

## What the demo does

One command sets everything up:

```bash
git clone https://github.com/ironsh/actions-demo && cd actions-demo
./run-demo.sh
```

This will:

1. Fork the repo to your GitHub account (if needed)
2. Generate a CA certificate for TLS interception
3. Start iron-proxy and a self-hosted runner in Docker
4. Register the runner, trigger a GitHub Actions workflow, and stream
   every egress request to your terminal in real time
5. Print a summary of allowed requests, denied requests, and secret swaps

The demo workflow checks out the repo, installs Node.js, makes an allowed
request to the GitHub API, sends a request with a proxy token that gets
swapped for a real secret at the boundary, and attempts two requests to
blocked domains.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated
- [jq](https://jqlang.github.io/jq/)

## How it works

The setup runs two containers on a shared Docker network:

- **iron-proxy** sits at a fixed IP and acts as both DNS server and
  HTTPS proxy. The runner's DNS points at the proxy, so all hostname
  lookups resolve to the proxy IP and traffic routes through it
  automatically.

- **runner** is an ephemeral GitHub Actions self-hosted runner. It
  trusts the proxy's CA certificate for TLS interception. It only
  has access to a proxy token — never the real secret.

Iron-proxy enforces two transforms on every request:

- **Allowlist** — only domains needed for GitHub Actions and the demo
  are permitted. Everything else gets a `403 Forbidden`.
- **Secrets** — the runner sends a proxy token in the `Authorization`
  header. Iron-proxy swaps it for the real secret before forwarding
  upstream. If the runner is compromised, the attacker only gets a
  token that's worthless outside the proxy.

See [`proxy.yaml`](proxy.yaml) for the full configuration.

## Learn more

- [iron-proxy](https://github.com/ironsh/iron-proxy) — the egress proxy
- [iron.sh](https://iron.sh) — enterprise features for teams running this at scale
