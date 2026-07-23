#!/usr/bin/env bash
# =============================================================================
# deploy-to-org.sh
# Deploy the travel-agent-broker Agent Network (V1, schemaVersion: 1.0.0)
# to a DIFFERENT Anypoint Platform org.
#
# Asset     : travel-agent-broker-network  (classifier: agent-network)
# Version   : 1.0.0
# Brokers   : travel-agent-broker
# Agents    : flightBookingAgent (A2A), hotelBookingAgent (A2A)
# LLM       : openai (gpt-5.4-mini)
#
# Prerequisites:
#   npm install -g anypoint-cli-v4
#   brew install jq python3
#   source deploy.env   (fill in deploy.env.template first)
# =============================================================================

set -euo pipefail

# ── ANSI colours ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"; }

# =============================================================================
# CONFIGURATION  –  all values come from environment variables.
# Source deploy.env or export them manually before running this script.
# =============================================================================

# ── Required: Target org credentials (Connected App) ─────────────────────────
: "${TARGET_CLIENT_ID:?     ERROR: export TARGET_CLIENT_ID first}"
: "${TARGET_CLIENT_SECRET:? ERROR: export TARGET_CLIENT_SECRET first}"

# ── Required: Target org identity ────────────────────────────────────────────
: "${TARGET_ORG_ID:?        ERROR: export TARGET_ORG_ID first}"
: "${TARGET_ENV_NAME:?      ERROR: export TARGET_ENV_NAME first}"

# ── Required: Flex Gateway / Private Space in target org ─────────────────────
: "${TARGET_FLEX_GW_NAME:?  ERROR: export TARGET_FLEX_GW_NAME first}"
: "${TARGET_PRIVATE_SPACE:? ERROR: export TARGET_PRIVATE_SPACE first}"

# ── Required: Runtime connection values ──────────────────────────────────────
# These populate the ${...} placeholders in agent-network.yaml
: "${INGRESSGW_URL:?          ERROR: export INGRESSGW_URL first}"
: "${OPENAI_URL:?              ERROR: export OPENAI_URL first}"
: "${OPENAI_API_KEY:?          ERROR: export OPENAI_API_KEY first}"
: "${FLIGHT_BOOKING_AGENT_URL:? ERROR: export FLIGHT_BOOKING_AGENT_URL first}"
: "${HOTEL_BOOKING_AGENT_URL:?  ERROR: export HOTEL_BOOKING_AGENT_URL first}"

# ── Optional overrides ────────────────────────────────────────────────────────
VERSION_GROUP="${VERSION_GROUP:-v1}"
ASSET_ID="travel-agent-broker-network"
ASSET_VERSION="${ASSET_VERSION:-1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$SCRIPT_DIR}"
ANYPOINT_CLI="${ANYPOINT_CLI:-anypoint-cli-v4}"

# =============================================================================
# STEP 1 – Prerequisites
# =============================================================================
check_prerequisites() {
    header "Step 1 / 6  –  Checking prerequisites"

    local missing=0

    if ! command -v "$ANYPOINT_CLI" &>/dev/null; then
        error "anypoint-cli-v4 not found. Run:  npm install -g anypoint-cli-v4"
        missing=1
    else
        success "anypoint-cli-v4 : $("$ANYPOINT_CLI" --version 2>&1 | head -1)"
    fi

    if ! command -v jq &>/dev/null; then
        error "jq not found. Run:  brew install jq"
        missing=1
    else
        success "jq : $(jq --version)"
    fi

    if ! command -v python3 &>/dev/null; then
        error "python3 not found. Run:  brew install python3"
        missing=1
    else
        success "python3 : $(python3 --version)"
    fi

    for f in agent-network.yaml exchange.json brokers/travel-agent-broker.agent; do
        if [[ ! -f "$PROJECT_PATH/$f" ]]; then
            error "Missing required file: $PROJECT_PATH/$f"
            missing=1
        else
            success "Found $f"
        fi
    done

    [[ $missing -ne 0 ]] && { error "Fix the errors above, then retry."; exit 1; }
}

# =============================================================================
# STEP 2 – Validate YAML syntax
# =============================================================================
validate_project() {
    header "Step 2 / 6  –  Validating agent-network.yaml"

    if python3 -c "
import yaml, sys
with open('$PROJECT_PATH/agent-network.yaml') as f:
    doc = yaml.safe_load(f)
sv = doc.get('schemaVersion','?')
brokers = list(doc.get('brokers',{}).keys())
agents  = list(doc.get('agents', {}).keys())
print(f'  schemaVersion : {sv}')
print(f'  brokers       : {brokers}')
print(f'  agents        : {agents}')
" 2>&1; then
        success "agent-network.yaml is valid YAML"
    else
        error "agent-network.yaml has syntax errors. Fix them before deploying."
        exit 1
    fi
}

# =============================================================================
# STEP 3 – Authenticate to target org
# =============================================================================
login_target_org() {
    header "Step 3 / 6  –  Authenticating to target org ($TARGET_ORG_ID)"

    "$ANYPOINT_CLI" conf host https://anypoint.mulesoft.com 2>/dev/null || true

    "$ANYPOINT_CLI" auth login \
        --client_id     "$TARGET_CLIENT_ID" \
        --client_secret "$TARGET_CLIENT_SECRET" \
        --organization  "$TARGET_ORG_ID"

    success "Authenticated to Anypoint Platform"
}

# =============================================================================
# STEP 4 – Patch exchange.json groupId for target org, then publish
# =============================================================================
publish_to_exchange() {
    header "Step 4 / 6  –  Publishing to Anypoint Exchange (target org)"

    # The source exchange.json has groupId = source-org ID.
    # We must replace it with the target org ID before publishing.
    EXCHANGE_JSON="$PROJECT_PATH/exchange.json"
    EXCHANGE_JSON_BACKUP="$PROJECT_PATH/exchange.json.bak"

    cp "$EXCHANGE_JSON" "$EXCHANGE_JSON_BACKUP"
    info "Backed up exchange.json → exchange.json.bak"

    # Update groupId and organizationId in exchange.json
    local tmp
    tmp=$(mktemp)
    jq --arg gid "$TARGET_ORG_ID" \
       '.groupId = $gid | .organizationId = $gid' \
       "$EXCHANGE_JSON" > "$tmp"
    mv "$tmp" "$EXCHANGE_JSON"
    success "exchange.json patched: groupId / organizationId → $TARGET_ORG_ID"

    info "Publishing asset: $ASSET_ID  version: $ASSET_VERSION  versionGroup: $VERSION_GROUP"

    # anypoint-cli-v4 exchange asset publish
    # The CLI reads exchange.json from the project root automatically.
    "$ANYPOINT_CLI" exchange asset publish \
        --organization "$TARGET_ORG_ID" \
        "$PROJECT_PATH"

    success "Asset published to Exchange in target org"

    # Restore original exchange.json so the source stays clean
    mv "$EXCHANGE_JSON_BACKUP" "$EXCHANGE_JSON"
    info "Restored original exchange.json"
}

# =============================================================================
# STEP 5 – Deploy agent network to target environment
# =============================================================================
deploy_agent_network() {
    header "Step 5 / 6  –  Deploying agent network to '$TARGET_ENV_NAME'"

    info "Flex Gateway   : $TARGET_FLEX_GW_NAME"
    info "Private Space  : $TARGET_PRIVATE_SPACE"
    info "Ingress GW URL : $INGRESSGW_URL"
    info "Flight Agent   : $FLIGHT_BOOKING_AGENT_URL"
    info "Hotel Agent    : $HOTEL_BOOKING_AGENT_URL"

    # Connection variable overrides – these satisfy the ${...} placeholders
    # declared in exchange.json metadata.variables and used in agent-network.yaml
    "$ANYPOINT_CLI" agent-network deploy \
        --project        "$PROJECT_PATH" \
        --environment    "$TARGET_ENV_NAME" \
        --organization   "$TARGET_ORG_ID" \
        --flex-gateway   "$TARGET_FLEX_GW_NAME" \
        --private-space  "$TARGET_PRIVATE_SPACE" \
        --var "ingressgw.url=$INGRESSGW_URL" \
        --var "openai.url=$OPENAI_URL" \
        --var "openai.apiKey=$OPENAI_API_KEY" \
        --var "flightBookingAgent.url=$FLIGHT_BOOKING_AGENT_URL" \
        --var "hotelBookingAgent.url=$HOTEL_BOOKING_AGENT_URL"

    success "Agent network deployed to '$TARGET_ENV_NAME'"
}

# =============================================================================
# STEP 6 – Smoke test (A2A card endpoint)
# =============================================================================
smoke_test() {
    header "Step 6 / 6  –  Smoke test"

    local card_url="${INGRESSGW_URL}/travel-agent-broker"
    info "Fetching A2A agent card: GET $card_url"

    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Accept: application/json" \
        "$card_url" 2>/dev/null || echo "000")

    if [[ "$http_status" == "200" ]]; then
        success "Agent card endpoint responded HTTP 200 ✓"
    elif [[ "$http_status" == "000" ]]; then
        warn "Could not reach $card_url (network or DNS issue). Verify manually."
    else
        warn "Agent card returned HTTP $http_status — the gateway may still be starting up."
        warn "Try again in ~60 s:  curl -s $card_url"
    fi
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
    header "Deployment Summary"
    echo -e "  ${BOLD}Asset${RESET}          : $ASSET_ID  v$ASSET_VERSION"
    echo -e "  ${BOLD}Target Org${RESET}     : $TARGET_ORG_ID"
    echo -e "  ${BOLD}Environment${RESET}    : $TARGET_ENV_NAME"
    echo -e "  ${BOLD}Flex Gateway${RESET}   : $TARGET_FLEX_GW_NAME"
    echo -e "  ${BOLD}Private Space${RESET}  : $TARGET_PRIVATE_SPACE"
    echo -e "  ${BOLD}Broker URL${RESET}     : $INGRESSGW_URL/travel-agent-broker"
    echo -e "  ${BOLD}Version Group${RESET}  : $VERSION_GROUP"
    echo ""
    success "All steps complete!"
    echo -e "\n${CYAN}  Post-deployment checklist:${RESET}"
    echo -e "  [ ] Verify asset in Exchange: https://anypoint.mulesoft.com/exchange/$TARGET_ORG_ID/$ASSET_ID/"
    echo -e "  [ ] Open Agent Builder in target org and confirm broker is listed"
    echo -e "  [ ] Test flight booking:  'Book me a flight to New York on July 10th'"
    echo -e "  [ ] Test hotel booking:   'I need a hotel in Paris for 3 nights'"
    echo -e "  [ ] Test full trip:       'Book me a full trip to Tokyo with flight and hotel'"
}

# =============================================================================
# MAIN
# =============================================================================
header "travel-agent-broker-network  →  Cross-Org Deployment"
echo -e "  Started : $(date)"
echo -e "  Source  : ${SCRIPT_DIR}"

check_prerequisites
validate_project
login_target_org
publish_to_exchange
deploy_agent_network
smoke_test
print_summary