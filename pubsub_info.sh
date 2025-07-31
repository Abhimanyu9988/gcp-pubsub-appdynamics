#!/bin/bash

# GCP Pub/Sub Info Script
# Shows status, metrics info, and help for Pub/Sub resources

set -e

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
TOPIC_NAME=${TOPIC_NAME:-"appdynamics-monitoring-topic"}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME:-"appdynamics-monitoring-subscription"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites for status commands
check_prerequisites() {
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        return 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q . 2>/dev/null; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        return 1
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        log_error "No project ID found. Set GCP_PROJECT_ID environment variable."
        return 1
    fi
    
    return 0
}

# Show current resource status
show_status() {
    echo "=================================="
    echo "🔍 GCP Pub/Sub Resources Status"
    echo "=================================="
    echo ""
    
    if ! check_prerequisites; then
        echo ""
        log_error "Cannot check status - prerequisites not met"
        return 1
    fi
    
    echo -e "${CYAN}Project:${NC} $PROJECT_ID"
    echo ""
    
    # Check topic
    echo -e "${PURPLE}📋 Topic: $TOPIC_NAME${NC}"
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" --format="json" > /tmp/topic_check.json 2>/dev/null; then
        echo "   ✅ Status: EXISTS"
        
        # Get topic details
        if command -v jq &> /dev/null; then
            local topic_full_name=$(jq -r '.name' /tmp/topic_check.json 2>/dev/null)
            echo "   📍 Full name: $(basename "$topic_full_name")"
        fi
        
        # Get subscriptions count
        local sub_count=0
        if gcloud pubsub topics list-subscriptions "$TOPIC_NAME" --project="$PROJECT_ID" --format="value(name)" > /tmp/topic_subs.txt 2>/dev/null; then
            sub_count=$(wc -l < /tmp/topic_subs.txt 2>/dev/null || echo 0)
        fi
        echo "   🔗 Subscriptions: $sub_count"
        
        # Show subscription names if any exist
        if [ "$sub_count" -gt 0 ]; then
            echo "   📝 Subscription list:"
            while read -r sub_path; do
                if [ -n "$sub_path" ]; then
                    echo "      • $(basename "$sub_path")"
                fi
            done < /tmp/topic_subs.txt
        fi
        
        rm -f /tmp/topic_check.json /tmp/topic_subs.txt
    else
        echo "   ❌ Status: NOT FOUND"
    fi
    
    echo ""
    
    # Check subscription
    echo -e "${PURPLE}📥 Subscription: $SUBSCRIPTION_NAME${NC}"
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" --format="json" > /tmp/sub_check.json 2>/dev/null; then
        echo "   ✅ Status: EXISTS"
        
        if command -v jq &> /dev/null; then
            local ack_deadline=$(jq -r '.ackDeadlineSeconds // "unknown"' /tmp/sub_check.json 2>/dev/null)
            local topic_path=$(jq -r '.topic // "unknown"' /tmp/sub_check.json 2>/dev/null)
            
            echo "   ⏱️  Ack deadline: $ack_deadline seconds"
            echo "   🎯 Connected to topic: $(basename "$topic_path")"
        fi
        
        rm -f /tmp/sub_check.json
    else
        echo "   ❌ Status: NOT FOUND"
    fi
    
    echo ""
    
    # Check custom metrics log
    echo -e "${PURPLE}📊 Custom Metrics Log${NC}"
    local metrics_file="/tmp/pubsub_custom_metrics.log"
    if [ -f "$metrics_file" ]; then
        echo "   ✅ Status: EXISTS ($metrics_file)"
        local line_count=$(wc -l < "$metrics_file" 2>/dev/null || echo 0)
        echo "   📏 Entries: $line_count"
        
        if [ "$line_count" -gt 0 ]; then
            echo "   🕒 Recent entries:"
            tail -3 "$metrics_file" | while read -r line; do
                echo "      $line"
            done
        fi
    else
        echo "   ❌ Status: NOT FOUND"
    fi
    
    echo ""
    
    # Show all Pub/Sub resources in project
    echo -e "${PURPLE}🌐 All Pub/Sub Resources in Project${NC}"
    echo ""
    echo "Topics:"
    if gcloud pubsub topics list --project="$PROJECT_ID" --format="table(name:label=TOPIC_NAME)" 2>/dev/null | tail -n +2 | grep -v "^$" | head -10; then
        :
    else
        echo "   No topics found or error accessing project"
    fi
    
    echo ""
    echo "Subscriptions:"
    if gcloud pubsub subscriptions list --project="$PROJECT_ID" --format="table(name:label=SUBSCRIPTION_NAME,topic:label=TOPIC)" 2>/dev/null | tail -n +2 | grep -v "^$" | head -10; then
        :
    else
        echo "   No subscriptions found or error accessing project"
    fi
}

# Show metrics information
show_metrics() {
    echo "=================================="
    echo "📊 GCP Pub/Sub Metrics Information"
    echo "=================================="
    echo ""
    
    echo -e "${CYAN}What the creation script generates:${NC}"
    echo ""
    
    echo -e "${PURPLE}1. 🏗️  Infrastructure Metrics${NC}"
    echo "   Available immediately after creation:"
    echo "   • Topic existence and accessibility status"
    echo "   • Number of subscriptions per topic"
    echo "   • Subscription configuration (ack timeout, etc.)"
    echo ""
    
    echo -e "${PURPLE}2. 📈 GCP Built-in Metrics${NC}"
    echo "   Available in Google Cloud Monitoring:"
    echo "   • pubsub.googleapis.com/topic/send_message_operation_count"
    echo "     └─ Number of publish operations performed"
    echo "   • pubsub.googleapis.com/topic/send_request_count"
    echo "     └─ Number of publish requests made"
    echo "   • pubsub.googleapis.com/subscription/pull_request_count"
    echo "     └─ Number of pull requests from subscribers"
    echo "   • pubsub.googleapis.com/subscription/pull_message_operation_count"
    echo "     └─ Number of messages pulled by subscribers"
    echo "   • pubsub.googleapis.com/subscription/num_undelivered_messages"
    echo "     └─ Current backlog size (unprocessed messages)"
    echo "   • pubsub.googleapis.com/subscription/oldest_unacked_message_age"
    echo "     └─ Age of oldest unacknowledged message"
    echo ""
    
    echo -e "${PURPLE}3. 🎯 Custom Application Metrics${NC}"
    echo "   Created by the script and logged to /tmp/pubsub_custom_metrics.log:"
    echo "   • messages_published_rate - Messages published per second"
    echo "   • average_message_size - Average size of messages in bytes"
    echo "   • total_published_count - Total successful message publishes"
    echo "   • total_failed_count - Total failed message publishes"
    echo "   • batch_success_rate - Success rate as percentage"
    echo ""
    
    echo -e "${PURPLE}4. 📋 Generated Message Characteristics${NC}"
    echo "   Sample messages include:"
    echo "   • Message attributes: priority (low/medium/high), category (order/inventory/customer/payment)"
    echo "   • JSON content with: id, timestamp, data payload, priority, category, source"
    echo "   • Variable message sizes: 10-1000 characters of random padding"
    echo "   • Timestamp in ISO 8601 format"
    echo ""
    
    echo -e "${PURPLE}5. 🔄 Workload Simulation Patterns${NC}"
    echo "   When RUN_SIMULATION=true:"
    echo "   • Batch publishing: 10-50 messages per batch"
    echo "   • Random delays: 5-15 seconds between batches"
    echo "   • Configurable duration (default 10 minutes)"
    echo "   • Rate limiting: 100ms delay every 10 messages"
    echo ""
    
    # Show current metrics if available
    local metrics_file="/tmp/pubsub_custom_metrics.log"
    if [ -f "$metrics_file" ]; then
        echo -e "${PURPLE}6. 📊 Current Custom Metrics${NC}"
        echo "   From: $metrics_file"
        echo ""
        cat "$metrics_file" | while read -r line; do
            if [[ $line =~ \[([^\]]+)\]\ CUSTOM_METRIC\ ([^\ ]+)\ ([0-9\.]+) ]]; then
                local timestamp="${BASH_REMATCH[1]}"
                local metric_name="${BASH_REMATCH[2]}"
                local metric_value="${BASH_REMATCH[3]}"
                echo "   📈 $metric_name: $metric_value (at $timestamp)"
            fi
        done
        echo ""
    fi
    
    echo -e "${CYAN}How to view these metrics:${NC}"
    echo ""
    echo "🌐 Google Cloud Console:"
    echo "   • Go to Monitoring > Metrics Explorer"
    echo "   • Search for 'pubsub' to see built-in metrics"
    echo "   • Filter by resource type 'pubsub_topic' or 'pubsub_subscription'"
    echo ""
    echo "💻 gcloud CLI:"
    echo "   • List metrics: gcloud monitoring metrics list --filter='metric.type:pubsub'"
    echo "   • Describe metric: gcloud monitoring metrics describe METRIC_TYPE"
    echo ""
    echo "🔧 AppDynamics (with monitoring script):"
    echo "   • Metrics appear as: Custom Metrics|PubSub|[MetricName]"
    echo "   • Visible in Machine Agent metrics view"
    echo "   • Dashboard and alerting available"
}

# Show creation script information
show_create_info() {
    echo "=================================="
    echo "🚀 Creation Script Information"
    echo "=================================="
    echo ""
    
    echo -e "${CYAN}What the creation script does:${NC}"
    echo ""
    
    echo -e "${PURPLE}📋 Prerequisites Check:${NC}"
    echo "   • Verifies gcloud CLI is installed"
    echo "   • Checks GCP authentication status"
    echo "   • Validates project ID configuration"
    echo ""
    
    echo -e "${PURPLE}🔧 API Enablement:${NC}"
    echo "   • Enables Pub/Sub API (pubsub.googleapis.com)"
    echo "   • Enables Cloud Monitoring API (monitoring.googleapis.com)"
    echo ""
    
    echo -e "${PURPLE}🏗️  Resource Creation:${NC}"
    echo "   • Creates Pub/Sub topic: $TOPIC_NAME"
    echo "   • Creates subscription: $SUBSCRIPTION_NAME"
    echo "   • Sets acknowledgment deadline: 60 seconds"
    echo "   • Handles existing resources gracefully"
    echo ""
    
    echo -e "${PURPLE}📊 Data Generation:${NC}"
    echo "   • Publishes sample messages (default: 100)"
    echo "   • Creates messages with random attributes"
    echo "   • Generates variable-sized payloads"
    echo "   • Logs custom metrics to /tmp/pubsub_custom_metrics.log"
    echo ""
    
    echo -e "${PURPLE}🔄 Optional Simulation:${NC}"
    echo "   • Continuous workload when RUN_SIMULATION=true"
    echo "   • Batch processing with random timing"
    echo "   • Configurable duration"
    echo ""
    
    echo -e "${CYAN}Environment Variables:${NC}"
    echo "   GCP_PROJECT_ID    - Your GCP project (required)"
    echo "   TOPIC_NAME        - Topic name (default: $TOPIC_NAME)"
    echo "   SUBSCRIPTION_NAME - Subscription name (default: $SUBSCRIPTION_NAME)"
    echo "   MESSAGE_COUNT     - Number of initial messages (default: 100)"
    echo "   RUN_SIMULATION    - Enable continuous simulation (default: false)"
    echo ""
    
    echo -e "${CYAN}Usage Examples:${NC}"
    echo "   export GCP_PROJECT_ID='my-project'"
    echo "   ./pubsub_create.sh                     # Basic creation"
    echo "   MESSAGE_COUNT=500 ./pubsub_create.sh   # More initial messages"
    echo "   RUN_SIMULATION=true ./pubsub_create.sh # With simulation"
}

# Show destroy script information
show_destroy_info() {
    echo "=================================="
    echo "🗑️  Destroy Script Information"
    echo "=================================="
    echo ""
    
    echo -e "${CYAN}What the destroy script does:${NC}"
    echo ""
    
    echo -e "${PURPLE}📋 Prerequisites Check:${NC}"
    echo "   • Verifies gcloud CLI is installed" 
    echo "   • Checks GCP authentication status"
    echo "   • Validates project ID configuration"
    echo ""
    
    echo -e "${PURPLE}🔍 Deletion Plan:${NC}"
    echo "   • Shows exactly what will be deleted"
    echo "   • Checks existence of each resource"
    echo "   • Warns about data loss"
    echo ""
    
    echo -e "${PURPLE}✋ Safety Confirmation:${NC}"
    echo "   • Requires typing 'yes' to confirm (unless FORCE=true)"
    echo "   • Shows clear warnings about irreversible actions"
    echo "   • Allows cancellation at any point"
    echo ""
    
    echo -e "${PURPLE}🗑️  Resource Deletion:${NC}"
    echo "   • Deletes subscription first (required order)"
    echo "   • Deletes topic second"
    echo "   • Cleans up local temporary files"
    echo "   • Removes custom metrics log"
    echo ""
    
    echo -e "${PURPLE}✅ Verification:${NC}"
    echo "   • Confirms each resource is deleted"
    echo "   • Reports any failures"
    echo "   • Provides final status summary"
    echo ""
    
    echo -e "${RED}⚠️  WARNING - PERMANENT DATA LOSS:${NC}"
    echo "   • All messages in topic/subscription are lost forever"
    echo "   • Subscriptions cannot be recovered"
    echo "   • Topics cannot be recovered"
    echo "   • Custom metrics logs are deleted"
    echo ""
    
    echo -e "${CYAN}Environment Variables:${NC}"
    echo "   GCP_PROJECT_ID    - Your GCP project (required)"
    echo "   TOPIC_NAME        - Topic to delete (default: $TOPIC_NAME)"
    echo "   SUBSCRIPTION_NAME - Subscription to delete (default: $SUBSCRIPTION_NAME)"
    echo "   FORCE             - Skip confirmation (default: false)"
    echo ""
    
    echo -e "${CYAN}Usage Examples:${NC}"
    echo "   export GCP_PROJECT_ID='my-project'"
    echo "   ./pubsub_destroy.sh        # Interactive deletion"
    echo "   FORCE=true ./pubsub_destroy.sh  # Skip confirmation"
}

# Show complete help
show_help() {
    echo "=================================="
    echo "🚀 GCP Pub/Sub Scripts Help"
    echo "=================================="
    echo ""
    
    echo -e "${CYAN}Available Scripts:${NC}"
    echo ""
    echo "📁 pubsub_create.sh  - Creates Pub/Sub resources and generates metrics"
    echo "📁 pubsub_destroy.sh - Deletes all created resources (PERMANENT)"
    echo "📁 pubsub_info.sh    - Shows status, metrics info, and help (this script)"
    echo ""
    
    echo -e "${CYAN}Quick Start Guide:${NC}"
    echo ""
    echo "1. 🔧 Setup:"
    echo "   export GCP_PROJECT_ID='your-project-id'"
    echo "   gcloud auth login  # if not already authenticated"
    echo ""
    echo "2. 🚀 Create resources:"
    echo "   ./pubsub_create.sh"
    echo ""
    echo "3. 📊 Check status:"
    echo "   ./pubsub_info.sh status"
    echo ""
    echo "4. 🗑️  Clean up:"
    echo "   ./pubsub_destroy.sh"
    echo ""
    
    echo -e "${CYAN}Info Script Commands:${NC}"
    echo ""
    echo "  status   - Show current resource status"
    echo "  metrics  - Show detailed metrics information"
    echo "  create   - Show creation script information"
    echo "  destroy  - Show destroy script information"
    echo "  help     - Show this help message"
    echo ""
    
    echo -e "${CYAN}Common Environment Variables:${NC}"
    echo ""
    echo "  GCP_PROJECT_ID    - Your GCP project ID (required)"
    echo "  TOPIC_NAME        - Topic name (default: appdynamics-monitoring-topic)"
    echo "  SUBSCRIPTION_NAME - Subscription name (default: appdynamics-monitoring-subscription)"
    echo ""
    
    echo -e "${CYAN}Prerequisites:${NC}"
    echo ""
    echo "  ✅ Google Cloud SDK (gcloud) installed"
    echo "  ✅ Authenticated with GCP (gcloud auth login)"
    echo "  ✅ Project ID configured or set in environment"
    echo "  ✅ Billing enabled on the project"
    echo "  ✅ jq installed (optional, for better formatting)"
    echo ""
    
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo ""
    echo "🔍 Check authentication:"
    echo "   gcloud auth list"
    echo ""
    echo "🔍 Check project:"
    echo "   gcloud config get-value project"
    echo ""
    echo "🔍 Test API access:"
    echo "   gcloud pubsub topics list --project=YOUR_PROJECT_ID"
    echo ""
    echo "📝 Common issues:"
    echo "   • 'Project not found' → Check project ID and billing"
    echo "   • 'Permission denied' → Check IAM roles (Pub/Sub Editor)"
    echo "   • 'API not enabled' → Run creation script to enable APIs"
}

# Main execution
main() {
    local command=${1:-"help"}
    
    case $command in
        "status"|"list"|"check")
            show_status
            ;;
        "metrics"|"metric"|"data")
            show_metrics
            ;;
        "create"|"creation"|"install")
            show_create_info
            ;;
        "destroy"|"delete"|"remove"|"cleanup")
            show_destroy_info
            ;;
        "help"|"-h"|"--help"|*)
            show_help
            ;;
    esac
}

# Show usage if no arguments
if [ $# -eq 0 ]; then
    echo -e "${YELLOW}💡 Usage: $0 [COMMAND]${NC}"
    echo ""
    echo "Commands: status, metrics, create, destroy, help"
    echo ""
    echo "Examples:"
    echo "  $0 status   # Show current resource status"
    echo "  $0 metrics  # Show metrics information" 
    echo "  $0 help     # Show complete help"
    echo ""
    exit 0
fi

# Run main function with all arguments
main "$@"