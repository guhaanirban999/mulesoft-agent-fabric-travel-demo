# Deploying travel-agent-broker to Another Anypoint Org

This guide explains how to deploy the **travel-agent-broker** Agent Network (`schemaVersion: 1.0.0`) to a different Anypoint Platform organisation.

| Field | Value |
|-------|-------|
| Asset ID | `travel-agent-broker-network` |
| Classifier | `agent-network` |
| Version | `1.0.0` |
| Broker | `travel-agent-broker` |
| Downstream agents | `flightBookingAgent` (A2A), `hotelBookingAgent` (A2A) |
| LLM | OpenAI `gpt-5.4-mini` |

---

## Files produced

| File | Purpose |
|------|---------|
| `deploy-to-org.sh` | Main deployment script (6 automated steps) |
| `deploy.env.template` | Template for all required environment variables |
| `DEPLOY.md` | This guide |

---

## Prerequisites

### Tools

| Tool | Install |
|------|---------|
| Anypoint CLI v4 | `npm install -g anypoint-cli-v4` |
| jq | `brew install jq` |
| python3 + PyYAML | `pip3 install pyyaml` |
| curl | pre-installed on macOS/Linux |

Verify:

```bash
anypoint-cli-v4 --version
jq --version
python3 -c "import yaml; print(yaml.__version__)"
```

### Target org setup (do this first)

Before running the script, ensure the target org has:

1. **A Flex Gateway** — registered as a Managed gateway in Runtime Manager.
   - `Anypoint Platform → Runtime Manager → Flex Gateways`
2. **A Private Space** — (CloudHub 2.0) or Runtime Fabric space where the gateway runs.
3. **A Connected App** — with client-credentials grant type and the scopes listed in `deploy.env.template`.
   - `Anypoint Platform → Access Management → Connected Apps → Create App`
4. **Both downstream A2A agents deployed** — the Flight Booking Agent and Hotel Booking Agent must be live in the target org before you run this script, because their endpoint URLs are required as connection variables.

---

## Quick start

```bash
# 1. Clone / copy the project to your machine
git clone https://github.com/guhaanirban999/mulesoft-agent-fabric-travel-demo.git
cd mulesoft-agent-fabric-travel-demo

# 2. Create your env file from the template
cp deploy.env.template deploy.env

# 3. Fill in every placeholder in deploy.env (see section below)
vi deploy.env

# 4. Source the env file and run the script
source deploy.env
chmod +x deploy-to-org.sh
./deploy-to-org.sh
```

---

## Filling in deploy.env

### Section 1 – Connected App credentials

```bash
export TARGET_CLIENT_ID="abc123..."
export TARGET_CLIENT_SECRET="def456..."
```

> Create the app in: **Access Management → Connected Apps → Create App**
> Required scopes: Exchange Contributor, Exchange Viewer, API Manager Environment Administrator, General Profile Access

### Section 2 – Target org & environment

```bash
export TARGET_ORG_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export TARGET_ENV_NAME="Sandbox"
```

> Find your org ID: **Access Management → Organisation Settings → Organisation ID**

### Section 3 – Flex Gateway & Private Space

```bash
export TARGET_FLEX_GW_NAME="my-flex-gw"
export TARGET_PRIVATE_SPACE="my-private-space"
```

> Find the gateway name: **Runtime Manager → Flex Gateways**

### Section 4 – Connection variables (the 5 `${...}` placeholders)

These populate the runtime connection values declared in `exchange.json` → `metadata.variables`:

| Variable | env var | Example |
|----------|---------|---------|
| `ingressgw.url` | `INGRESSGW_URL` | `https://my-flex-gw.us-e2.cloudhub.io` |
| `openai.url` | `OPENAI_URL` | `https://api.openai.com/v1` |
| `openai.apiKey` | `OPENAI_API_KEY` | `sk-proj-…` |
| `flightBookingAgent.url` | `FLIGHT_BOOKING_AGENT_URL` | `https://flight-agent.us-e2.cloudhub.io/flight-booking-agent` |
| `hotelBookingAgent.url` | `HOTEL_BOOKING_AGENT_URL` | `https://hotel-agent.us-e2.cloudhub.io/hotel-booking-agent` |

> **Tip:** `INGRESSGW_URL` is the base URL of your Flex Gateway ingress. The broker
> card will be accessible at `<INGRESSGW_URL>/travel-agent-broker`.

---

## What the script does (6 steps)

| Step | Action |
|------|--------|
| 1 | Checks that `anypoint-cli-v4`, `jq`, and `python3` are installed and all project files exist |
| 2 | Validates `agent-network.yaml` with a YAML parser and prints schema version, brokers, and agents |
| 3 | Authenticates to the target org using the Connected App client credentials |
| 4 | Patches `exchange.json` with the target org's `groupId` / `organizationId`, publishes the asset to Exchange, then restores the original file |
| 5 | Deploys the agent network to the target environment via Flex Gateway, passing all 5 connection variables |
| 6 | Smoke-tests the A2A agent card endpoint (`GET <INGRESSGW_URL>/travel-agent-broker`) |

---

## Key detail: groupId patching

The source `exchange.json` contains:

```json
"groupId": "558f5f35-75da-47bd-a55e-d24c28b56326",
"organizationId": "558f5f35-75da-47bd-a55e-d24c28b56326"
```

These are the **source org** IDs. The script automatically replaces them with
`TARGET_ORG_ID` before publishing and restores the original after publication.
**Do not manually edit these fields in `exchange.json`** — the script handles it.

---

## Post-deployment checklist

After the script completes:

- [ ] Verify the asset in Exchange: `https://anypoint.mulesoft.com/exchange/<TARGET_ORG_ID>/travel-agent-broker-network/`
- [ ] Open **Agent Builder** in the target org → confirm the broker is listed
- [ ] Send a test message: `"Book me a flight to New York on July 10th"` → expect flight booking response
- [ ] Send a test message: `"I need a hotel in Paris for 3 nights"` → expect hotel booking response
- [ ] Send a test message: `"Book me a full trip to Tokyo with flight and hotel"` → expect both agents invoked

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ERROR: export TARGET_CLIENT_ID first` | env vars not loaded | Run `source deploy.env` before the script |
| `401 Unauthorized` on auth step | Wrong client ID/secret or missing scopes | Recreate the Connected App with all required scopes |
| Exchange publish fails with `409 Conflict` | Asset version already exists in target org | Increment `ASSET_VERSION` in `deploy.env` (e.g. `1.0.1`) |
| Smoke test returns `404` | Broker not yet routed by Flex Gateway | Wait ~60 s and retry: `curl -s $INGRESSGW_URL/travel-agent-broker` |
| Smoke test returns `502` / `503` | Downstream A2A agents unreachable | Verify `FLIGHT_BOOKING_AGENT_URL` and `HOTEL_BOOKING_AGENT_URL` are correct and the agents are running |
| `anypoint-cli-v4: command not found` | CLI not installed | `npm install -g anypoint-cli-v4` |

---

## Reference

- [Anypoint Agent Network documentation](https://docs.mulesoft.com/general/)
- [Anypoint CLI v4](https://docs.mulesoft.com/anypoint-cli/latest/)
- [Flex Gateway — Managed Mode](https://docs.mulesoft.com/gateway/latest/flex-gateway-getting-started)
- [Connected Apps](https://docs.mulesoft.com/access-management/connected-apps-overview)