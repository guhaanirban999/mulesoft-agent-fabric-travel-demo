# Travel Agent Broker — Architecture & API Reference

## Overview

The Travel Agent Broker is a **MuleSoft Agent Fabric** (V1) deployment that orchestrates flight and hotel bookings using AI. It uses the **Agent-to-Agent (A2A) Protocol v0.3.0** for communication and **OpenAI's Responses API** (`gpt-5.4-mini`) for intelligent request classification and routing.

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                  CLIENT (curl / Slack / App)                      │
└────────────────────────┬─────────────────────────────────────────┘
                         │ A2A JSON-RPC 2.0
                         │ POST /travel-agent-broker
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│          TRAVEL AGENT BROKER  (CloudHub 2.0, US East 2)          │
│  travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │              Mule Agent Fabric Runtime                     │  │
│  │  1. Receive A2A message/send request                      │  │
│  │  2. Classify intent via OpenAI gpt-5.4-mini               │  │
│  │     → flight_only | hotel_only | both                     │  │
│  │  3. Route to appropriate sub-agent(s)                     │  │
│  │  4. Return completed task with booking details            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────┐   ┌──────────────────────────────────┐ │
│  │  Omni Gateway (Egress)│   │  Mule Application               │ │
│  │                       │   │  model: gpt-5.4-mini            │ │
│  │  openaiConnection     │   │  apiKey: - (gateway handles)    │ │
│  │  ├─ openai-transcoding│   │                                 │ │
│  │  │  -policy (auth)   │   │                                 │ │
│  │  flightBookingAgent   │   │                                 │ │
│  │  hotelBookingAgent    │   │                                 │ │
│  │  ├─ a-two-a-agent-card│   │                                 │ │
│  └──────────────────────┘   └──────────────────────────────────┘ │
└──────────────┬────────────────────────────┬─────────────────────┘
               │                            │
               ▼                            ▼
┌──────────────────────┐    ┌───────────────────────────────────┐
│  OpenAI API           │    │  Sub-Agents (Render.com)          │
│  api.openai.com/v1    │    │                                   │
│  gpt-5.4-mini         │    │  Flight Booking Agent             │
│  /v1/responses        │    │  flight-booking-agent-bq9s.onren  │
│                       │    │  Routes: SFO↔JFK, JFK↔LHR        │
│                       │    │          SFO↔NRT, LHR↔CDG        │
│                       │    │                                   │
│                       │    │  Hotel Booking Agent              │
│                       │    │  hotel-booking-agent-cr9b.onren   │
│                       │    │  Cities: New York, London         │
│                       │    │          Tokyo, San Francisco     │
└──────────────────────┘    └───────────────────────────────────┘
```

---

## Technology Stack

| Component | Technology |
|---|---|
| Agent Fabric Runtime | MuleSoft Agent Fabric V1 (`schemaVersion: 1.0.0`) |
| Mule Runtime | Mule 4.12.0:10e-java17 |
| Deployment | CloudHub 2.0 (US East 2) |
| LLM | OpenAI gpt-5.4-mini (Responses API) |
| LLM Protocol | OpenAI Responses API (`/v1/responses`) |
| Agent Communication | A2A Protocol v0.3.0 (JSON-RPC 2.0) |
| Sub-Agents | Render.com (Node.js demo agents) |
| Gateway | Omni Gateway (CloudHub 2.0 managed) |
| LLM Auth Policy | `openai-transcoding-policy v1.0.3` |
| Agent Card Policy | `a-two-a-agent-card v1.0.3` |

---

## Deployment Details

| Property | Value |
|---|---|
| **Broker URL** | `https://travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io` |
| **A2A Endpoint** | `POST /travel-agent-broker` |
| **Application ID** | `0e58a12a-5204-43e2-b992-047abe3be25a` |
| **Environment** | Sandbox |
| **Group ID** | `558f5f35-75da-47bd-a55e-d24c28b56326` |
| **Asset Version** | `1.0.0` |
| **Flight Agent** | `https://flight-booking-agent-bq9s.onrender.com` |
| **Hotel Agent** | `https://hotel-booking-agent-cr9b.onrender.com` |

---

## Configuration Properties

| Property | Description |
|---|---|
| `openai.url` | OpenAI API base URL: `https://api.openai.com/v1` |
| `openai.apiKey` | OpenAI API key (`sk-proj-...`) |
| `flightBookingAgent.url` | `https://flight-booking-agent-bq9s.onrender.com` |
| `hotelBookingAgent.url` | `https://hotel-booking-agent-cr9b.onrender.com` |
| `ingressgw.url` | Ingress gateway URL |

---

## Demo Inventory

### Flights
| Route | Flights Available |
|---|---|
| San Francisco (SFO) → New York (JFK) | AF101 08:00–16:25 $312, AF102 13:30–21:55 $358 |
| New York (JFK) → London (LHR) | Available |
| San Francisco (SFO) → Tokyo (NRT) | Available |
| London (LHR) → Paris (CDG) | Available |

### Hotels
| City | Hotels |
|---|---|
| New York | The Gotham Grand (4⭐ Midtown $289/night), Liberty Suites (3⭐ Downtown $215/night) |
| London | 2 hotels available |
| Tokyo | 1 hotel available |
| San Francisco | 1 hotel available |

---

## Curl Commands — All Tested Requests & Responses

### ⚠️ Warm Up Render.com Agents First

Render.com free-tier apps sleep after 15 minutes of inactivity. Always warm them up before testing the broker to avoid 504 Gateway Timeout errors:

```bash
echo "Warming up Flight Booking Agent..." && \
curl -s "https://flight-booking-agent-bq9s.onrender.com/.well-known/agent-card.json" | jq '.name' && \
echo "Warming up Hotel Booking Agent..." && \
curl -s "https://hotel-booking-agent-cr9b.onrender.com/.well-known/agent-card.json" | jq '.name' && \
echo "Both agents are warm ✅"
```

**Expected output:**
```
Warming up Flight Booking Agent...
"Flight Booking Agent"
Warming up Hotel Booking Agent...
"Hotel Booking Agent"
Both agents are warm ✅
```

> The first warm-up call may take 30–60 seconds if the agents are sleeping. Subsequent calls will be fast.

---

### Base URL
```
https://travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io/travel-agent-broker
```

### A2A Request Format (JSON-RPC 2.0)
```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "method": "message/send",
  "params": {
    "message": {
      "kind": "message",
      "role": "user",
      "messageId": "msg-1",
      "parts": [{"kind": "text", "text": "<YOUR TRAVEL REQUEST>"}]
    }
  }
}
```

> **Multi-turn conversations:** Add `"contextId": "<previous-contextId>"` to continue a conversation.

---

### Test 1 — Flight Search: Route Not Found

**Request:**
```bash
curl -s -X POST \
  "https://travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io/travel-agent-broker" \
  -H "Content-Type: application/json" \
  --max-time 180 \
  -d '{"jsonrpc":"2.0","id":"req-1","method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"msg-1","parts":[{"kind":"text","text":"find me flights from toronto to new delhi on june 28th 2027"}]}}}' | jq .
```

**Response:** `state: completed`
```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "result": {
    "id": "7df683e3-ec1b-44d3-a57d-e272282d4bc0",
    "contextId": "dee741cb-f45a-40c6-9a58-9c99654490d2",
    "status": {
      "state": "completed",
      "timestamp": "2026-06-28T07:39:46.307549042Z"
    },
    "artifacts": [
      {
        "artifactId": "0b6616aa-b9c0-4597-b630-0b25199fdbb7",
        "parts": [
          {
            "text": "I couldn't find any flights from Toronto to New Delhi for June 28, 2027 in the available demo inventory. The inventory only includes routes like SFO↔JFK, JFK↔LHR, SFO↔NRT, and LHR↔CDG.\n\nIf you want, I can help you look at one of those available routes instead.",
            "kind": "text"
          }
        ]
      }
    ],
    "history": [],
    "kind": "task"
  }
}
```

---

### Test 2 — Flight Search: SFO → JFK ✅

**Request:**
```bash
curl -s -X POST \
  "https://travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io/travel-agent-broker" \
  -H "Content-Type: application/json" \
  --max-time 180 \
  -d '{"jsonrpc":"2.0","id":"req-1","method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"msg-1","parts":[{"kind":"text","text":"find me flights from San Francisco to New York on June 28th 2027"}]}}}' | jq .
```

**Response:** `state: completed`
```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "result": {
    "id": "8c6acca8-1dc7-49f3-80d0-10c378dc932d",
    "contextId": "a3a8e0bb-fb5f-44b0-9344-bd33552a1908",
    "status": {
      "state": "completed",
      "timestamp": "2026-06-28T07:44:30.621734531Z"
    },
    "artifacts": [
      {
        "artifactId": "47ce4392-2bfd-4ce6-b40f-d950a7d7969a",
        "parts": [
          {
            "text": "I found 2 available flights from San Francisco (SFO) to New York (JFK) on June 28, 2027:\n\n1. AF101 — 08:00 to 16:25 — Economy — $312\n2. AF102 — 13:30 to 21:55 — Economy — $358\n\nIf you'd like, I can help you choose one and book it.",
            "kind": "text"
          }
        ]
      }
    ],
    "history": [],
    "kind": "task"
  }
}
```

---

### Test 3 — Hotel Search: New York ✅

**Request:**
```bash
curl -s -X POST \
  "https://travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io/travel-agent-broker" \
  -H "Content-Type: application/json" \
  --max-time 180 \
  -d '{"jsonrpc":"2.0","id":"req-2","method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"msg-2","parts":[{"kind":"text","text":"I need a hotel in New York for 3 nights starting June 28th 2027"}]}}}' | jq .
```

**Response:** `state: input-required` (asks which hotel to book)
```json
{
  "jsonrpc": "2.0",
  "id": "req-2",
  "result": {
    "id": "1bfa5316-4405-4ac9-aa2a-d3f72d7fa6fd",
    "contextId": "c716eddd-3072-4b50-8642-df4bc9c972b2",
    "status": {
      "state": "input-required",
      "message": {
        "role": "agent",
        "parts": [
          {
            "text": "I found 2 hotel options in New York for June 28–July 1, 2027:\n\n1. The Gotham Grand — $289/night, $867 total\n2. Liberty Suites — $215/night, $645 total\n\nPlease tell me which hotel you'd like me to book.",
            "kind": "text"
          }
        ],
        "messageId": "ca13773a-c148-4c74-b091-e0580f6abbf6",
        "taskId": "1bfa5316-4405-4ac9-aa2a-d3f72d7fa6fd",
        "kind": "message"
      },
      "timestamp": "2026-06-28T07:46:46.075706326Z"
    },
    "artifacts": [],
    "history": [],
    "kind": "task"
  }
}
```

---

### Test 4 — Hotel Booking: Gotham Grand, New York (single-turn) ✅

**Request:**
```bash
curl -s -X POST \
  "https://travel-agent-broker-network-8u1hpn.5sc6y6-2.usa-e2.cloudhub.io/travel-agent-broker" \
  -H "Content-Type: application/json" \
  --max-time 180 \
  -d '{"jsonrpc":"2.0","id":"req-1","method":"message/send","params":{"message":{"kind":"message","role":"user","messageId":"msg-1","parts":[{"kind":"text","text":"Book The Gotham Grand hotel in New York, check-in June 28th 2027, check-out July 1st 2027"}]}}}' | jq .
```

**Response:** `state: completed` — booking confirmed!
```json
{
  "jsonrpc": "2.0",
  "id": "req-1",
  "result": {
    "id": "41553b28-c215-4e0b-ae47-cbbaa69920a5",
    "contextId": "011330c3-9fdd-4f8b-b144-b4b360392435",
    "status": {
      "state": "completed",
      "timestamp": "2026-06-28T07:48:38.96620419Z"
    },
    "artifacts": [
      {
        "artifactId": "299b5eb7-6419-407a-99a7-cbfe381c2b4f",
        "parts": [
          {
            "text": "Your hotel booking is confirmed.\n\n- Hotel: The Gotham Grand, New York (Midtown)\n- Check-in: June 28, 2027\n- Check-out: July 1, 2027\n- Stay: 3 nights\n- Rate: $289/night\n- Total: $867\n- Amenities: WiFi, gym, breakfast\n- Confirmation code: HB-7M2QKX",
            "kind": "text"
          }
        ]
      }
    ],
    "history": [],
    "kind": "task"
  }
}
```

---

## Slack Integration

### App Manifest
See [`slack-app-manifest.yaml`](./slack-app-manifest.yaml) for the Slack App manifest.

### Integration Architecture
```
Slack User          Slack API          Mule Integration App    Travel Agent Broker
    │                   │                       │                      │
    │  /travel <req>    │                       │                      │
    │──────────────────>│                       │                      │
    │                   │  POST /slack/travel   │                      │
    │                   │──────────────────────>│                      │
    │                   │  HTTP 200 "Searching" │                      │
    │                   │<──────────────────────│                      │
    │  ⏳ Searching...  │                       │  POST /travel-agent  │
    │<──────────────────│                       │──────────────────────>
    │                   │                       │  result: completed   │
    │                   │                       │<──────────────────────
    │                   │  POST response_url    │                      │
    │                   │<──────────────────────│                      │
    │  ✈️ AF101 $312    │                       │                      │
    │<──────────────────│                       │                      │
```

### Setup Steps
1. Create a Slack App at [api.slack.com/apps](https://api.slack.com/apps) using `slack-app-manifest.yaml`
2. Install to workspace → copy **Bot Token** (`xoxb-...`)
3. Build a Mule integration app with async Slack response pattern
4. Replace `<YOUR_MULE_APP_URL>` in the manifest with your Mule app's CloudHub URL
5. Reinstall the Slack app to update the slash command URL

### Example Slack Usage
```
/travel find me flights from San Francisco to New York on June 28th 2027
/travel book The Gotham Grand hotel in New York, check-in June 28th 2027, check-out July 1st 2027
/travel I need a full trip to Tokyo with flight and hotel
```

---

## Repository

- **GitHub:** https://github.com/guhaanirban999/mulesoft-agent-fabric-travel-demo
- **Branch:** main
- **License:** MIT
