#!/bin/bash

# Real-time log monitoring script with formatting
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

LOG_FILE="${1:-log/instrumentation.log}"

echo -e "${BLUE}=== ThrottleMachines Log Monitor ===${NC}"
echo "Monitoring: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""

# Function to format and colorize log entries
format_log_entry() {
    while IFS= read -r line; do
        if [[ $line =~ \[INFO\][[:space:]]+(.+)$ ]]; then
            json_part="${BASH_REMATCH[1]}"
            
            # Try to parse key information
            if command -v jq >/dev/null 2>&1; then
                # Use jq if available for better parsing
                timestamp=$(echo "$json_part" | jq -r '.timestamp // empty' 2>/dev/null)
                event=$(echo "$json_part" | jq -r '.event // empty' 2>/dev/null)
                key=$(echo "$json_part" | jq -r '.payload.key // empty' 2>/dev/null)
                allowed=$(echo "$json_part" | jq -r '.payload.allowed // empty' 2>/dev/null)
                remaining=$(echo "$json_part" | jq -r '.payload.remaining // empty' 2>/dev/null)
                retry_after=$(echo "$json_part" | jq -r '.payload.retry_after // empty' 2>/dev/null)
                
                if [[ -n "$event" ]]; then
                    # Format based on event type
                    case "$event" in
                        *rate_limit.allowed*)
                            echo -e "${timestamp} ${GREEN}✅ ALLOWED${NC} ${CYAN}$key${NC} (${remaining} remaining)"
                            ;;
                        *rate_limit.throttled*)
                            echo -e "${timestamp} ${RED}🛑 THROTTLED${NC} ${CYAN}$key${NC} (retry in ${retry_after}s)"
                            ;;
                        *rate_limit.checked*)
                            if [[ "$allowed" == "true" ]]; then
                                echo -e "${timestamp} ${YELLOW}🔍 CHECKED${NC} ${CYAN}$key${NC} → ${GREEN}allowed${NC}"
                            else
                                echo -e "${timestamp} ${YELLOW}🔍 CHECKED${NC} ${CYAN}$key${NC} → ${RED}denied${NC}"
                            fi
                            ;;
                        *circuit_breaker*)
                            state=$(echo "$json_part" | jq -r '.event' | sed 's/.*\.//')
                            case "$state" in
                                opened) echo -e "${timestamp} ${RED}🔴 CIRCUIT OPENED${NC} ${CYAN}$key${NC}" ;;
                                closed) echo -e "${timestamp} ${GREEN}🟢 CIRCUIT CLOSED${NC} ${CYAN}$key${NC}" ;;
                                half_opened) echo -e "${timestamp} ${YELLOW}🟡 CIRCUIT HALF-OPEN${NC} ${CYAN}$key${NC}" ;;
                                *) echo -e "${timestamp} ${BLUE}⚡ CIRCUIT${NC} ${CYAN}$key${NC} → $state" ;;
                            esac
                            ;;
                        *)
                            echo -e "${timestamp} ${BLUE}📊 EVENT${NC} $event"
                            ;;
                    esac
                else
                    # Fallback to raw line if parsing fails
                    echo "$line"
                fi
            else
                # Simple parsing without jq
                if [[ $json_part == *"rate_limit.allowed"* ]]; then
                    echo -e "$(date '+%H:%M:%S') ${GREEN}✅ RATE LIMIT ALLOWED${NC}"
                elif [[ $json_part == *"rate_limit.throttled"* ]]; then
                    echo -e "$(date '+%H:%M:%S') ${RED}🛑 RATE LIMIT THROTTLED${NC}"
                elif [[ $json_part == *"rate_limit"* ]]; then
                    echo -e "$(date '+%H:%M:%S') ${YELLOW}🔍 RATE LIMIT CHECK${NC}"
                elif [[ $json_part == *"circuit_breaker"* ]]; then
                    echo -e "$(date '+%H:%M:%S') ${BLUE}⚡ CIRCUIT BREAKER EVENT${NC}"
                else
                    echo "$line"
                fi
            fi
        else
            # Non-JSON line, print as-is
            echo "$line"
        fi
    done
}

# Check if log file exists
if [[ ! -f "$LOG_FILE" ]]; then
    echo -e "${YELLOW}⚠️  Log file not found: $LOG_FILE${NC}"
    echo "Creating log file and waiting for events..."
    touch "$LOG_FILE"
fi

# Start monitoring
echo -e "${GREEN}Monitoring started...${NC}"
tail -f "$LOG_FILE" | format_log_entry