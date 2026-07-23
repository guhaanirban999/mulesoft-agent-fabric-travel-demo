# Travel Agent Broker — Cross-Org Migration Guide

This document records the complete steps taken to migrate the **Travel Agent Broker** ecosystem from the source org to a new Anypoint Platform organisation (`bd24f01a-ad0a-454e-93cc-28a98abdcf2c`).

---

## Migration Overview

| Component | Source Org | Target Org (New) |
|---|---|---|
| **Agent Network** | `travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io` | `omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io` |
| **Mule Slack App** | `mule-slack-travel-8u1hpn.5sc6y6-4.usa-e2.cloudhub.io` | `mule-slack-s5er51.5sc6y6-3.usa-e2.cloudhub.io` |
| **Flex Gateway** | CloudHub 2.0 managed (source org) | `omni-demo-gateway` (CloudHub 2.0 US East 2) |
| **Mule Runtime** | 4.12.0:10e-java17 | 4.12.1:4e-java17 (latest) |
| **Org ID** | `558f5f35-75da-47bd-a55e-d24c28b56326` | `bd24f01a-ad0a-454e-93cc-28a98abdcf2c` |
| **Environment** | Sandbox | Sandbox |

---

## Prerequisites (Target Org)

Before migrating, ensure the target org has:

| Requirement | Details |
|---|---|
| **Flex Gateway** | Registered as a Managed gateway in Runtime Manager (`omni-demo-gateway`) |
| **CloudHub 2.0 Private Space** | Available in US East 2 region |
| **Flight Booking Agent** | Running at `https://flight-booking-agent-bq9s.onrender.com` |
| **Hotel Booking Agent** | Running at `https://hotel-booking-agent-cr9b.onrender.com` |
| **OpenAI API Key** | `sk-proj-...` with access to `gpt-5.4-mini` |

---

## Step 1 — Identify the Flex Gateway Ingress URL

The `ingressgw.url` variable in `agent-network.yaml` must point to the **public HTTPS hostname** of the Flex Gateway in the target org.

**How to find it:**
1. Anypoint Platform → **Runtime Manager → Flex Gateways**
2. Click on the gateway name (`omni-demo-gateway`)
3. Copy the **public hostname**

| Property | Value |
|---|---|
| **Gateway Name** | `omni-demo-gateway` |
| **Public Ingress URL** | `https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io` |
| **Internal URL** | `http://omni-demo-gateway:8082` |
| **Org ID** (in path) | `bd24f01a-ad0a-454e-93cc-28a98abdcf2c` |

---

## Step 2 — Remove Deploy Scripts from Repository

The legacy deployment scripts (`deploy-to-org.sh`, `deploy.env.template`, `DEPLOY.md`) were removed from the repository as they are no longer needed — deployment is handled via Anypoint Code Builder (VS Code MCP tools).

```bash
git rm -f DEPLOY.md deploy-to-org.sh deploy.env.template
git commit -m "chore: remove deploy scripts (DEPLOY.md, deploy-to-org.sh, deploy.env.template)"
git push origin main
```

**Files removed:**
- `DEPLOY.md` — deployment instructions for CLI-based approach
- `deploy-to-org.sh` — bash script for 6-step CLI deployment
- `deploy.env.template` — environment variable template

> **Security note:** `deploy.env` (containing real credentials) was already in `.gitignore` and was never committed.

---

## Step 3 — Publish Agent Network to Exchange

Using **Anypoint Code Builder** (VS Code):

1. Open the `travel-agent-broker` project in VS Code
2. Use the **Deploy Agent Network** panel (MCP tool: `deploy_agent_network`)
3. The panel publishes the `travel-agent-broker-network` asset to Anypoint Exchange in the target org

**Exchange asset details:**
| Property | Value |
|---|---|
| Asset ID | `travel-agent-broker-network` |
| Classifier | `agent-network` |
| Group ID | `bd24f01a-ad0a-454e-93cc-28a98abdcf2c` |
| Version | `1.0.0` |
| Version Group | `v1` |

---

## Step 4 — Deploy Agent Network to Flex Gateway

> **Critical:** Publishing to Exchange only registers the asset in the catalog. The **Deploy** step is what creates API Manager instances and registers Flex Gateway routing policies.

Using the **Deploy Agent Network** panel in VS Code, configure:

| Variable | Value |
|---|---|
| `ingressgw.url` | `https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io` |
| `openai.url` | `https://api.openai.com/v1` |
| `openai.apiKey` | `sk-proj-...` (your OpenAI API key) |
| `flightBookingAgent.url` | `https://flight-booking-agent-bq9s.onrender.com` |
| `hotelBookingAgent.url` | `https://hotel-booking-agent-cr9b.onrender.com` |

**Deployment result:**
| Property | Value |
|---|---|
| Application ID | `6f408cf3-e812-495b-953f-88b3cce235f6` |
| Status | `RUNNING` |
| Runtime | `4.12.1:4e-java17` |
| Broker endpoint | `https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io/travel-agent-broker` |

**Verify the broker is live:**
```bash
curl -v --max-time 30 \
  "https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io/travel-agent-broker"
# Expected: HTTP 200 (agent card JSON) or HTTP 405 (GET not allowed — broker is up)
```

---

## Step 5 — Update mule-slack Broker Host

The Mule Slack integration app (`mule-slack-travel`) had the broker host hardcoded to the **source org** URL. This must be updated to the new org's gateway.

**File:** `src/main/resources/config.yaml`

```yaml
# Before (source org)
broker:
  host: "travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io"
  port: "443"

# After (target org)
broker:
  host: "omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io"
  port: "443"
```

Commit and push:
```bash
cd /path/to/mule-slack-travel
git add src/main/resources/config.yaml
git commit -m "config: update broker.host to new org gateway (omni-demo-gateway)"
git push origin main
```

---

## Step 6 — Deploy mule-slack to CloudHub 2.0

Deploy the Mule Slack integration app to the target org using Anypoint Code Builder (MCP tool: `deploy_mule_application`):

| Property | Value |
|---|---|
| Project | `mule-slack-travel` |
| App Name | `mule-slack` |
| Environment | Sandbox |
| Org ID | `bd24f01a-ad0a-454e-93cc-28a98abdcf2c` |
| Runtime | `4.12.1:4e-java17` (latest) |
| Target | CloudHub 2.0 US East 2 |
| vCores | 0.1 |

**Deployment result:**
| Property | Value |
|---|---|
| Deployment ID | `2f7e9bd7-6eaf-4c96-b190-00215416146f` |
| Status | `RUNNING` |
| Public URL | `https://mule-slack-s5er51.5sc6y6-3.usa-e2.cloudhub.io` |
| Slack endpoint | `https://mule-slack-s5er51.5sc6y6-3.usa-e2.cloudhub.io/slack/travel` |

---

## Step 7 — Update Slack App Manifest

**File:** `slack-app-manifest.yaml`

```yaml
# Before (source org)
slash_commands:
  - command: /travel
    url: https://mule-slack-travel-8u1hpn.5sc6y6-4.usa-e2.cloudhub.io/slack/travel

# After (target org)
slash_commands:
  - command: /travel
    url: https://mule-slack-s5er51.5sc6y6-3.usa-e2.cloudhub.io/slack/travel
```

**Apply to Slack:**
1. Go to **https://api.slack.com/apps**
2. Select **Travel Agent Broker** app (or create new from manifest)
3. **App Manifest** tab → paste updated YAML → **Save Changes**
4. **Install App** → reinstall to workspace to apply the new slash command URL

---

## Final Architecture (Target Org)

```
Slack Workspace
      │  /travel <request>
      ▼
https://mule-slack-s5er51.5sc6y6-3.usa-e2.cloudhub.io/slack/travel
      │  (ACK immediately, async broker call)
      ▼
https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io/travel-agent-broker
      │  (A2A JSON-RPC 2.0, gpt-5.4-mini routing)
      ├──▶ Flight Booking Agent (https://flight-booking-agent-bq9s.onrender.com)
      └──▶ Hotel Booking Agent  (https://hotel-booking-agent-cr9b.onrender.com)
```

---

## Deployed Applications Summary

| App | Status | Runtime | URL |
|---|---|---|---|
| `travel-agent-broker-network` | ✅ RUNNING | 4.12.1:4e-java17 | `omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io/travel-agent-broker` |
| `mule-slack` | ✅ RUNNING | 4.12.1:4e-java17 | `mule-slack-s5er51.5sc6y6-3.usa-e2.cloudhub.io/slack/travel` |

---

## Testing

### Warm up sub-agents (Render.com free tier sleeps after 15 min)
```bash
curl -s "https://flight-booking-agent-bq9s.onrender.com/.well-known/agent-card.json" | jq '.name'
curl -s "https://hotel-booking-agent-cr9b.onrender.com/.well-known/agent-card.json" | jq '.name'
```

### Direct curl tests against the broker

**Test 1 — Flight route not in inventory:**
```bash
curl -s -X POST \
  "https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io/travel-agent-broker" \
  -H "Content-Type: application/json" --max-time 180 \
  -d '{"jsonrpc":"2.0","id":"req-1","method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"msg-1","parts":[{"kind":"text","text":"find me flights from toronto to new delhi on june 28th 2027"}]}}}' | jq .
```

**Test 2 — Flight search SFO → JFK (expect: AF101 $312, AF102 $358):**
```bash
curl -s -X POST \
  "https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io/travel-agent-broker" \
  -H "Content-Type: application/json" --max-time 180 \
  -d '{"jsonrpc":"2.0","id":"req-2","method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"msg-2","parts":[{"kind":"text","text":"find me flights from San Francisco to New York on June 28th 2027"}]}}}' | jq .
```

**Test 3 — Hotel search New York (expect: input-required with 2 options):**
```bash
curl -s -X POST \
  "https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io/travel-agent-broker" \
  -H "Content-Type: application/json" --max-time 180 \
  -d '{"jsonrpc":"2.0","id":"req-3","method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"msg-3","parts":[{"kind":"text","text":"I need a hotel in New York for 3 nights starting June 28th 2027"}]}}}' | jq .
```

**Test 4 — Hotel booking Gotham Grand (expect: completed, confirmation code):**
```bash
curl -s -X POST \
  "https://omni-demo-gateway-s5er51.5sc6y6-1.usa-e2.cloudhub.io/travel-agent-broker" \
  -H "Content-Type: application/json" --max-time 180 \
  -d '{"jsonrpc":"2.0","id":"req-4","method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"msg-4","parts":[{"kind":"text","text":"Book The Gotham Grand hotel in New York, check-in June 28th 2027, check-out July 1st 2027"}]}}}' | jq .
```

### Slack tests
In any Slack channel in your workspace:
```
/travel find me flights from San Francisco to New York on June 28th 2027
/travel I need a hotel in New York for 3 nights starting June 28th 2027
/travel Book The Gotham Grand hotel in New York, check-in June 28th 2027, check-out July 1st 2027
/travel I need a full trip to Tokyo with flight and hotel
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Broker returns `404` | Deploy step not completed (only published) | Re-run Deploy Agent Network from VS Code panel |
| Broker returns `404` after deploy | Flex Gateway routes not yet propagated | Wait 60 s and retry |
| `502`/`503` from broker | Sub-agents on Render.com are sleeping | Warm up agents first (see above) |
| Slack returns "could not be reached" | `mule-slack` app is down or broker host wrong | Check Runtime Manager; verify `config.yaml` broker.host |
| Slack shows "Searching..." but no reply | `response_url` callback failed | Check mule-slack logs in Runtime Manager |

---

## Repository

- **Agent Network:** https://github.com/guhaanirban999/mulesoft-agent-fabric-travel-demo
- **Mule Slack App:** https://github.com/guhaanirban999/mule-slack-travel