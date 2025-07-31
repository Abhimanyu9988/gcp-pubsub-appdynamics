#!/bin/bash

# Clean AppDynamics Pub/Sub Metrics Collector
# Prerequisites: Run prerequisites installer script first
# This script only collects and outputs metrics

set -e

# ============================================================================
# CONFIGURATION - UPDATE THESE VALUES
# ============================================================================

# GCP Project Configuration
PROJECT_ID="your-project-id"  # UPDATE THIS
TOPIC_NAMES="appdynamics-monitoring-topic"  # Comma-separated
SUBSCRIPTION_NAMES="appdynamics-monitoring-subscription"  # Comma-separated

# Service Account JSON Key - Choose ONE method:

# Method 1: Use existing JSON file (recommended)
SERVICE_ACCOUNT_KEY_FILE="/opt/appdynamics/pubsub-monitor-service-account.json"

# Method 2: Inline JSON (paste your JSON key below if not using file method)
SERVICE_ACCOUNT_JSON=''

# AppDynamics Configuration
METRIC_PREFIX="Custom Metrics|PubSub"

# ============================================================================
# SCRIPT LOGIC - NO CHANGES NEEDED BELOW THIS LINE
# ============================================================================

# Fixed paths (installed by prerequisites script)
GCLOUD_PATH="/opt/google-cloud-sdk/bin/gcloud"
TEMP_KEY_FILE="/tmp/gcp_service_account_$.json"

# Output metric in AppDynamics format
output_metric() {
    local metric_name="$1"
    local value="$2"
    local unit="$3"
    
    if [ -n "$unit" ]; then
        echo "name=${METRIC_PREFIX}|${metric_name}, value=${value}, unit=${unit}"
    else
        echo "name=${METRIC_PREFIX}|${metric_name}, value=${value}"
    fi
}

# Setup authentication using file or inline JSON
setup_authentication() {
    # Method 1: Use existing JSON file
    if [ -n "$SERVICE_ACCOUNT_KEY_FILE" ] && [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
        # Use the existing file directly
        $GCLOUD_PATH auth activate-service-account --key-file="$SERVICE_ACCOUNT_KEY_FILE" --quiet 2>/dev/null
        return $?
    fi
    
    # Method 2: Use inline JSON
    if [ -n "$SERVICE_ACCOUNT_JSON" ]; then
        # Create temporary key file
        echo "$SERVICE_ACCOUNT_JSON" > "$TEMP_KEY_FILE"
        chmod 600 "$TEMP_KEY_FILE"
        
        # Activate service account
        $GCLOUD_PATH auth activate-service-account --key-file="$TEMP_KEY_FILE" --quiet 2>/dev/null
        return $?
    fi
    
    # No valid authentication method
    return 1
}

# Check prerequisites
check_prerequisites() {
    local errors=0
    
    # Check gcloud
    if [ ! -f "$GCLOUD_PATH" ]; then
        output_metric "Setup Error|gcloud Missing" "1"
        errors=$((errors + 1))
    fi
    
    # Check if we have authentication method
    local has_auth=0
    if [ -n "$SERVICE_ACCOUNT_KEY_FILE" ] && [ -f "$SERVICE_ACCOUNT_KEY_FILE" ]; then
        has_auth=1
    elif [ -n "$SERVICE_ACCOUNT_JSON" ]; then
        has_auth=1
    fi
    
    if [ $has_auth -eq 0 ]; then
        output_metric "Setup Error|No Credentials" "1"
        errors=$((errors + 1))
    fi
    
    # Setup authentication
    if ! setup_authentication; then
        output_metric "Setup Error|Authentication Failed" "1"
        errors=$((errors + 1))
    fi
    
    return $errors
}

# Test GCP connectivity
test_connectivity() {
    if $GCLOUD_PATH projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        output_metric "Connectivity|GCP Access" "1"
        return 0
    else
        output_metric "Connectivity|GCP Access" "0"
        return 1
    fi
}

# Check topics
check_topics() {
    local total_topics=0
    local accessible_topics=0
    
    for topic in $(echo "$TOPIC_NAMES" | tr ',' ' '); do
        topic=$(echo "$topic" | xargs)
        if [ -n "$topic" ]; then
            total_topics=$((total_topics + 1))
            
            if $GCLOUD_PATH pubsub topics describe "$topic" --project="$PROJECT_ID" >/dev/null 2>&1; then
                output_metric "Topic|${topic}|Status" "1"
                accessible_topics=$((accessible_topics + 1))
                
                # Get subscription count
                local sub_count
                sub_count=$($GCLOUD_PATH pubsub topics list-subscriptions "$topic" --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | wc -l)
                output_metric "Topic|${topic}|Subscriptions" "$sub_count"
            else
                output_metric "Topic|${topic}|Status" "0"
            fi
        fi
    done
    
    output_metric "Topics|Total Configured" "$total_topics"
    output_metric "Topics|Accessible" "$accessible_topics"
    
    if [ $total_topics -gt 0 ]; then
        local success_rate=$(( (accessible_topics * 100) / total_topics ))
        output_metric "Topics|Success Rate" "$success_rate"
    fi
}

# Check subscriptions
check_subscriptions() {
    local total_subscriptions=0
    local accessible_subscriptions=0
    
    for subscription in $(echo "$SUBSCRIPTION_NAMES" | tr ',' ' '); do
        subscription=$(echo "$subscription" | xargs)
        if [ -n "$subscription" ]; then
            total_subscriptions=$((total_subscriptions + 1))
            
            if $GCLOUD_PATH pubsub subscriptions describe "$subscription" --project="$PROJECT_ID" --format="json" >/tmp/sub_$$.json 2>/dev/null; then
                output_metric "Subscription|${subscription}|Status" "1"
                accessible_subscriptions=$((accessible_subscriptions + 1))
                
                # Get ack deadline if jq available
                if command -v jq >/dev/null 2>&1; then
                    local ack_deadline
                    ack_deadline=$(jq -r '.ackDeadlineSeconds // 0' /tmp/sub_$$.json 2>/dev/null || echo 0)
                    output_metric "Subscription|${subscription}|Ack Deadline" "$ack_deadline"
                fi
                
                rm -f /tmp/sub_$$.json
            else
                output_metric "Subscription|${subscription}|Status" "0"
            fi
        fi
    done
    
    output_metric "Subscriptions|Total Configured" "$total_subscriptions"
    output_metric "Subscriptions|Accessible" "$accessible_subscriptions"
    
    if [ $total_subscriptions -gt 0 ]; then
        local success_rate=$(( (accessible_subscriptions * 100) / total_subscriptions ))
        output_metric "Subscriptions|Success Rate" "$success_rate"
    fi
}

# Get monitoring API status
check_monitoring_api() {
    if $GCLOUD_PATH services list --enabled --filter="name:monitoring.googleapis.com" --project="$PROJECT_ID" >/dev/null 2>&1; then
        output_metric "Monitoring|API Status" "1"
    else
        output_metric "Monitoring|API Status" "0"
    fi
}

# Get custom metrics from log file
get_custom_metrics() {
    local custom_metrics_file="/tmp/pubsub_custom_metrics.log"
    local custom_metrics_found=0
    
    if [ -f "$custom_metrics_file" ]; then
        while IFS= read -r line; do
            if [[ $line =~ \[([^\]]+)\]\ CUSTOM_METRIC\ ([^\ ]+)\ ([0-9\.]+) ]]; then
                local metric_name="${BASH_REMATCH[2]}"
                local metric_value="${BASH_REMATCH[3]}"
                
                # Convert to AppDynamics format
                local display_name=$(echo "$metric_name" | sed 's/_/ /g' | sed 's/\b\w/\U&/g')
                output_metric "Custom|${display_name}" "$metric_value"
                
                custom_metrics_found=$((custom_metrics_found + 1))
            fi
        done < "$custom_metrics_file"
        
        # File age
        local file_mtime
        file_mtime=$(stat -c %Y "$custom_metrics_file" 2>/dev/null || echo 0)
        local current_time=$(date +%s)
        local file_age=$((current_time - file_mtime))
        
        output_metric "Custom Metrics|File Age" "$file_age"
        output_metric "Custom Metrics|Entries Found" "$custom_metrics_found"
    else
        output_metric "Custom Metrics|File Status" "0"
        output_metric "Custom Metrics|Entries Found" "0"
    fi
}

# Get system metrics
get_system_metrics() {
    # Disk space
    local tmp_space
    tmp_space=$(df /tmp | awk 'NR==2 {print $4}' 2>/dev/null || echo 0)
    output_metric "System|Tmp Space Available" "$tmp_space"
    
    # AWS instance check
    local aws_instance=0
    if curl -m 2 -s http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
        aws_instance=1
    fi
    output_metric "System|AWS Instance" "$aws_instance"
    
    # Current timestamp
    output_metric "System|Collection Timestamp" "$(date +%s)"
}

# Main collection function
collect_metrics() {
    local start_time=$(date +%s)
    local errors=0
    
    # Prerequisites check
    if ! check_prerequisites; then
        errors=$((errors + 1))
        output_metric "Collection|Prerequisites Failed" "1"
    else
        output_metric "Collection|Prerequisites Failed" "0"
    fi
    
    # Connectivity test
    if ! test_connectivity; then
        errors=$((errors + 1))
        output_metric "Collection|Total Errors" "$errors"
        return 1
    fi
    
    # Collect all metrics
    check_topics
    check_subscriptions
    check_monitoring_api
    get_custom_metrics
    get_system_metrics
    
    # Collection summary
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    output_metric "Collection|Total Errors" "$errors"
    output_metric "Collection|Total Time" "$total_time"
    output_metric "Collection|Success" "$([[ $errors -eq 0 ]] && echo 1 || echo 0)"
    
    return $errors
}

# Cleanup function
cleanup() {
    rm -f "$TEMP_KEY_FILE" 2>/dev/null || true
    rm -f /tmp/sub_$.json 2>/dev/null || true
}

# Handle interruption
handle_interrupt() {
    output_metric "Collection|Interrupted" "1"
    cleanup
    exit 1
}

trap handle_interrupt INT TERM
trap cleanup EXIT

# Validate configuration
if [ "$PROJECT_ID" = "your-project-id" ]; then
    output_metric "Configuration|Invalid" "1"
    exit 1
fi

# Check if we have any authentication method
if [ ! -f "$SERVICE_ACCOUNT_KEY_FILE" ] && [ -z "$SERVICE_ACCOUNT_JSON" ]; then
    output_metric "Configuration|No Credentials" "1"
    exit 1
fi

output_metric "Configuration|Valid" "1"

# Run collection
collect_metrics
exit_code=$?

# Cleanup and exit
cleanup
exit $exit_code