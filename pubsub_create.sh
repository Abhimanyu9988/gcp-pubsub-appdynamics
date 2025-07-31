#!/bin/bash

# GCP Pub/Sub Deployment and Metrics Generation Script
# This script creates Pub/Sub topics, subscriptions, and generates metrics using gcloud CLI

set -e

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
TOPIC_NAME=${TOPIC_NAME:-"appdynamics-monitoring-topic"}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME:-"appdynamics-monitoring-subscription"}
MESSAGE_COUNT=${MESSAGE_COUNT:-100}
RUN_SIMULATION=${RUN_SIMULATION:-"false"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check project ID
    if [ -z "$PROJECT_ID" ]; then
        log_error "No project ID found. Set GCP_PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    log_success "Prerequisites check passed. Using project: $PROJECT_ID"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    gcloud services enable pubsub.googleapis.com --project="$PROJECT_ID" --quiet
    gcloud services enable monitoring.googleapis.com --project="$PROJECT_ID" --quiet
    
    log_success "APIs enabled successfully"
}

# Create Pub/Sub topic
create_topic() {
    log_info "Creating Pub/Sub topic: $TOPIC_NAME"
    
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Topic $TOPIC_NAME already exists"
    else
        gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID" --quiet
        log_success "Created topic: $TOPIC_NAME"
    fi
}

# Create Pub/Sub subscription
create_subscription() {
    log_info "Creating Pub/Sub subscription: $SUBSCRIPTION_NAME"
    
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Subscription $SUBSCRIPTION_NAME already exists"
    else
        gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
            --topic="$TOPIC_NAME" \
            --ack-deadline=60 \
            --project="$PROJECT_ID" \
            --quiet
        log_success "Created subscription: $SUBSCRIPTION_NAME"
    fi
}

# Generate sample message
generate_message() {
    local message_id=$1
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    local priority_options=("low" "medium" "high")
    local category_options=("order" "inventory" "customer" "payment")
    
    local priority=${priority_options[$((RANDOM % 3))]}
    local category=${category_options[$((RANDOM % 4))]}
    local data_size=$((RANDOM % 1000 + 10))
    local padding=$(printf 'x%.0s' $(seq 1 $data_size))
    
    cat << EOF
{
    "id": $message_id,
    "timestamp": "$timestamp",
    "data": "Sample message $message_id $padding",
    "priority": "$priority",
    "category": "$category",
    "source": "metrics-generator"
}
EOF
}

# Publish messages to generate metrics
publish_messages() {
    local count=$1
    local published=0
    local failed=0
    local total_size=0
    local start_time=$(date +%s)
    
    log_info "Publishing $count messages to $TOPIC_NAME"
    
    for ((i=1; i<=count; i++)); do
        local message=$(generate_message $i)
        local message_size=${#message}
        total_size=$((total_size + message_size))
        
        # Extract attributes for gcloud command
        local priority=$(echo "$message" | jq -r '.priority')
        local category=$(echo "$message" | jq -r '.category')
        
        # Publish message with attributes
        if echo "$message" | gcloud pubsub topics publish "$TOPIC_NAME" \
            --message=- \
            --attribute="priority=$priority,category=$category,source=metrics-generator" \
            --project="$PROJECT_ID" \
            --quiet 2>/dev/null; then
            published=$((published + 1))
        else
            failed=$((failed + 1))
        fi
        
        # Add some delay every 10 messages
        if [ $((i % 10)) -eq 0 ]; then
            sleep 0.1
            echo -n "."
        fi
    done
    
    echo ""
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local rate=0
    if [ $duration -gt 0 ]; then
        rate=$((published / duration))
    fi
    local avg_size=$((total_size / count))
    
    # Output metrics summary
    log_success "Publishing completed:"
    echo "  Total messages: $count"
    echo "  Published successfully: $published"
    echo "  Failed to publish: $failed"
    echo "  Total size: $total_size bytes"
    echo "  Duration: $duration seconds"
    echo "  Messages per second: $rate"
    echo "  Average message size: $avg_size bytes"
    
    # Create custom metrics (if monitoring is enabled)
    create_custom_metrics $rate $avg_size $published $failed
}

# Create custom metrics in Google Cloud Monitoring
create_custom_metrics() {
    local messages_per_second=$1
    local avg_message_size=$2
    local published_count=$3
    local failed_count=$4
    
    log_info "Creating custom metrics in Cloud Monitoring..."
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # Create metrics using gcloud (basic approach)
    # Note: gcloud doesn't have direct custom metrics creation, but we can log metrics
    # that can be picked up by monitoring agents
    
    # Write metrics to a log file that monitoring agents can parse
    local metrics_file="/tmp/pubsub_custom_metrics.log"
    
    cat > "$metrics_file" << EOF
[${timestamp}] CUSTOM_METRIC messages_published_rate ${messages_per_second}
[${timestamp}] CUSTOM_METRIC average_message_size ${avg_message_size}
[${timestamp}] CUSTOM_METRIC total_published_count ${published_count}
[${timestamp}] CUSTOM_METRIC total_failed_count ${failed_count}
[${timestamp}] CUSTOM_METRIC batch_success_rate $(( (published_count * 100) / (published_count + failed_count) ))
EOF
    
    log_success "Custom metrics logged to $metrics_file"
}

# Simulate continuous workload
simulate_workload() {
    local duration_minutes=${1:-5}
    local end_time=$(($(date +%s) + (duration_minutes * 60)))
    
    log_info "Starting workload simulation for $duration_minutes minutes"
    
    local total_published=0
    local total_failed=0
    local batches_completed=0
    
    while [ $(date +%s) -lt $end_time ]; do
        local batch_size=$((RANDOM % 40 + 10))  # 10-50 messages per batch
        
        log_info "Publishing batch $((batches_completed + 1)) with $batch_size messages"
        
        # Publish batch (simplified for continuous operation)
        local batch_published=0
        for ((i=1; i<=batch_size; i++)); do
            local message=$(generate_message $((batches_completed * 100 + i)))
            if echo "$message" | gcloud pubsub topics publish "$TOPIC_NAME" \
                --message=- \
                --project="$PROJECT_ID" \
                --quiet 2>/dev/null; then
                batch_published=$((batch_published + 1))
            fi
        done
        
        total_published=$((total_published + batch_published))
        total_failed=$((total_failed + batch_size - batch_published))
        batches_completed=$((batches_completed + 1))
        
        log_info "Batch $batches_completed completed: $batch_published/$batch_size messages published"
        
        # Wait between batches
        sleep $((RANDOM % 10 + 5))  # 5-15 seconds
    done
    
    log_success "Workload simulation completed:"
    echo "  Total published: $total_published"
    echo "  Total failed: $total_failed"
    echo "  Batches completed: $batches_completed"
}

# Get topic information
get_topic_info() {
    log_info "Getting topic information..."
    
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" --format="json" > /tmp/topic_info.json 2>/dev/null; then
        echo "Topic Details:"
        echo "  Name: $(jq -r '.name' /tmp/topic_info.json)"
        echo "  Message Storage Policy: $(jq -r '.messageStoragePolicy // "default"' /tmp/topic_info.json)"
        
        # Get subscriptions for this topic
        local subscriptions=$(gcloud pubsub topics list-subscriptions "$TOPIC_NAME" --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")
        if [ -n "$subscriptions" ]; then
            echo "  Subscriptions:"
            echo "$subscriptions" | while read -r sub; do
                echo "    - $(basename "$sub")"
            done
        else
            echo "  Subscriptions: None"
        fi
        
        rm -f /tmp/topic_info.json
    else
        log_error "Could not retrieve topic information"
    fi
}

# Get subscription information
get_subscription_info() {
    log_info "Getting subscription information..."
    
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" --format="json" > /tmp/sub_info.json 2>/dev/null; then
        echo "Subscription Details:"
        echo "  Name: $(jq -r '.name' /tmp/sub_info.json)"
        echo "  Topic: $(basename "$(jq -r '.topic' /tmp/sub_info.json)")"
        echo "  Ack Deadline: $(jq -r '.ackDeadlineSeconds' /tmp/sub_info.json) seconds"
        echo "  Message Retention: $(jq -r '.messageRetentionDuration // "7 days"' /tmp/sub_info.json)"
        
        rm -f /tmp/sub_info.json
    else
        log_error "Could not retrieve subscription information"
    fi
}

# Main execution
main() {
    echo "=================================="
    echo "GCP Pub/Sub Deployment Script"
    echo "=================================="
    echo ""
    
    # Check if jq is available (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. Some features may be limited. Install with: brew install jq"
    fi
    
    check_prerequisites
    enable_apis
    
    echo ""
    log_info "Setting up Pub/Sub infrastructure..."
    create_topic
    create_subscription
    
    echo ""
    get_topic_info
    echo ""
    get_subscription_info
    
    echo ""
    log_info "Generating initial metrics..."
    publish_messages $MESSAGE_COUNT
    
    echo ""
    log_success "Setup completed successfully!"
    echo "Topic: $TOPIC_NAME"
    echo "Subscription: $SUBSCRIPTION_NAME"
    echo "Project: $PROJECT_ID"
    
    # Optional continuous simulation
    if [ "$RUN_SIMULATION" = "true" ]; then
        echo ""
        log_info "Starting continuous workload simulation..."
        simulate_workload 10
    else
        echo ""
        log_info "To run continuous simulation, set: export RUN_SIMULATION=true"
        log_info "You can now monitor these resources with AppDynamics"
    fi
    
    echo ""
    echo "🔍 To view your resources:"
    echo "  gcloud pubsub topics list --project=$PROJECT_ID"
    echo "  gcloud pubsub subscriptions list --project=$PROJECT_ID"
    echo ""
    echo "📊 To pull messages (test):"
    echo "  gcloud pubsub subscriptions pull $SUBSCRIPTION_NAME --limit=5 --project=$PROJECT_ID"
    echo ""
}

# Handle script interruption
cleanup() {
    log_info "Script interrupted. Cleaning up..."
    exit 1
}

trap cleanup INT TERM

# Run main function
main "$@"