# Why Claude LLM Was Not Working — Root Cause Analysis

This document explains the technical reasons why the Anthropic Claude LLM (`claude-opus-4-5`) failed in the Travel Agent Broker demo, and why the project was migrated to OpenAI (`gpt-5.4-mini`) in commit `c836af0`.

---

## Background

The original implementation (commit `a80d184`) configured Anthropic's Claude as the LLM for the Travel Agent Broker. It was subsequently replaced with OpenAI in commit `c836af0` after Claude failed to work end-to-end within the MuleSoft Agent Fabric V1 runtime.

---

## Root Causes

### 1. `kind: "OpenAI"` Was Used for the Claude LLM Entry

In `brokers/travel-agent-broker.agent`, the Claude LLM was declared as:

```yaml
llm:
  claude:
    target: "llm://claudeLlmConnection"
    kind: "OpenAI"          # ← WRONG: forces OpenAI wire format
    model: "claude-opus-4-5"
```

The `kind: "OpenAI"` field instructs the MuleSoft Agent Fabric runtime to serialize all LLM requests in **OpenAI's API format** (e.g., the `/v1/responses` or `/v1/chat/completions` request schema). Anthropic's API uses a completely different request/response format (`/v1/messages` with a different body structure), so every outbound call was malformed.

There was **no `kind: "Anthropic"` option available** in Agent Fabric V1 at the time of development.

---

### 2. `metadata.platform: OpenAI` Was Set for the Claude LLM Provider

In `agent-network.yaml`, the LLM provider was declared as:

```yaml
llmProviders:
  claude:
    label: Claude (Anthropic)
    description: Claude LLM via Anthropic API (OpenAI-compatible endpoint)
    metadata:
      platform: OpenAI    # ← WRONG: applies the wrong gateway policy
```

Despite the label correctly identifying the provider as Anthropic, `platform: OpenAI` caused the Omni Gateway to apply the `openai-transcoding-policy`. This policy:

- Injects the API key as `Authorization: Bearer <apiKey>` — but Anthropic requires `x-api-key: <apiKey>` and `anthropic-version: <version>` headers
- Transforms the outgoing request body into OpenAI format, not Anthropic's `/v1/messages` format
- Routes to OpenAI-style API paths

Every request to Claude's API was therefore **rejected at the Anthropic endpoint** due to incorrect authentication headers and request format.

---

### 3. No Anthropic-Specific Transcoding Policy Existed

The broker relied on `openai-transcoding-policy v1.0.3` as its LLM auth and transcoding policy. At the time of building this demo, there was **no `anthropic-transcoding-policy`** available in Anypoint Exchange, meaning there was no supported mechanism to use Claude natively within Agent Fabric V1's Omni Gateway policy model.

---

### 4. API URL Path Mismatch

Even if authentication had been correct, the `openai-transcoding-policy` would POST to `/v1/responses` or `/v1/chat/completions` at the `https://api.anthropic.com/v1` base URL. Anthropic's native endpoint is `/v1/messages` — a different path with a different request and response schema.

---

## Summary Table

| Issue | Detail |
|---|---|
| Wrong `kind` in `.agent` file | `kind: "OpenAI"` forced OpenAI wire format for Anthropic's API |
| Wrong `metadata.platform` | `platform: OpenAI` applied the OpenAI transcoding policy to Claude calls |
| Wrong auth header format | `openai-transcoding-policy` injected `Authorization: Bearer` instead of `x-api-key` + `anthropic-version` |
| No Anthropic transcoding policy | Agent Fabric V1 had no built-in support for Anthropic's native API format |
| API path mismatch | Policy routed to OpenAI-style paths; Anthropic uses `/v1/messages` |

---

## The Fix

Commit `c836af0` replaced Anthropic Claude with OpenAI throughout the project:

| File | Change |
|---|---|
| `agent-network.yaml` | Renamed `llmProviders.claude` → `llmProviders.openai`; changed model to `gpt-5.4-mini` |
| `brokers/travel-agent-broker.agent` | Changed `default_llm`, `target`, and all `llm:` references from `claude` → `openai` |
| `exchange.json` | Renamed connection variables from `claude.*` → `openai.*` |

With `platform: OpenAI` and `kind: "OpenAI"` now correctly aligned to an actual OpenAI endpoint, the `openai-transcoding-policy` functioned as designed and the broker worked end-to-end.

---

## Lessons Learned

- MuleSoft Agent Fabric V1's LLM integration is currently **OpenAI-native**. The `kind` and `metadata.platform` values must match the actual LLM provider's API contract.
- If Anthropic Claude support is required in future, a dedicated `anthropic-transcoding-policy` would need to be available in Anypoint Exchange, or a custom policy/proxy would need to handle auth header transformation (`Authorization: Bearer` → `x-api-key` + `anthropic-version`) and request body translation before forwarding to `https://api.anthropic.com/v1/messages`.
- Never set `metadata.platform: OpenAI` for a non-OpenAI LLM provider, even if the provider claims partial OpenAI compatibility.