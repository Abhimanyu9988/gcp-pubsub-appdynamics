#!/bin/bash

# GCP Pub/Sub Destroy Script
# Deletes all created Pub/Sub resources and cleans up files

set -e

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
TOPIC_NAME=${TOPIC_NAME:-"appdynamics-monitoring-topic"}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME:-"appdynamics-monitoring-subscription"}
FORCE=${FORCE:-"false"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        log_error "No project ID found. Set GCP_PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    log_success "Prerequisites check passed. Using project: $PROJECT_ID"
}

# Show what will be deleted
show_deletion_plan() {
    echo ""
    log_warning "🗑️  DESTRUCTION PLAN"
    echo "=================================="
    echo ""
    echo "Project: $PROJECT_ID"
    echo ""
    
    echo "Resources to be DELETED:"
    
    # Check topic
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        echo "  ✅ Topic: $TOPIC_NAME (EXISTS - will be deleted)"
        
        # Check how many messages might be lost
        local sub_count=$(gcloud pubsub topics list-subscriptions "$TOPIC_NAME" --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | wc -l)
        if [ "$sub_count" -gt 0 ]; then
            echo "     └─ $sub_count subscription(s) attached"
        fi
    else
        echo "  ❌ Topic: $TOPIC_NAME (not found)"
    fi
    
    # Check subscription
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" &>/dev/null; then
        echo "  ✅ Subscription: $SUBSCRIPTION_NAME (EXISTS - will be deleted)"
        echo "     └─ All unprocessed messages will be lost"
    else
        echo "  ❌ Subscription: $SUBSCRIPTION_NAME (not found)"
    fi
    
    # Check log files
    if [ -f "/tmp/pubsub_custom_metrics.log" ]; then
        echo "  ✅ Metrics log: /tmp/pubsub_custom_metrics.log (EXISTS - will be deleted)"
    else
        echo "  ❌ Metrics log: /tmp/pubsub_custom_metrics.log (not found)"
    fi
    
    # Check other temp files
    local temp_files=("/tmp/topic_info.json" "/tmp/sub_info.json")
    local temp_found=0
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            temp_found=$((temp_found + 1))
        fi
    done
    
    if [ $temp_found -gt 0 ]; then
        echo "  ✅ Temporary files: $temp_found file(s) (will be cleaned)"
    else
        echo "  ❌ Temporary files: none found"
    fi
    
    echo ""
    log_warning "⚠️  WARNING: This action is IRREVERSIBLE!"
    echo "• All messages in the topic/subscription will be permanently lost"
    echo "• Historical metrics data in Cloud Monitoring will remain (retention policy applies)"
    echo "• You will need to re-run the creation script to recreate resources"
}

# Confirm deletion
confirm_deletion() {
    if [ "$FORCE" = "true" ]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "═══════════════════════════════════"
    read -p "❓ Are you absolutely sure you want to DELETE these resources? (type 'yes' to confirm): " -r
    echo "═══════════════════════════════════"
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user"
        echo ""
        echo "💡 To see what would be deleted without confirmation, run:"
        echo "   FORCE=true $0"
        echo ""
        exit 0
    fi
}

# Delete subscription
delete_subscription() {
    log_info "Deleting subscription: $SUBSCRIPTION_NAME"
    
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" &>/dev/null; then
        if gcloud pubsub subscriptions delete "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" --quiet; then
            log_success "✅ Deleted subscription: $SUBSCRIPTION_NAME"
        else
            log_error "❌ Failed to delete subscription: $SUBSCRIPTION_NAME"
            return 1
        fi
    else
        log_warning "⚠️  Subscription $SUBSCRIPTION_NAME not found (may already be deleted)"
    fi
}

# Delete topic
delete_topic() {
    log_info "Deleting topic: $TOPIC_NAME"
    
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        if gcloud pubsub topics delete "$TOPIC_NAME" --project="$PROJECT_ID" --quiet; then
            log_success "✅ Deleted topic: $TOPIC_NAME"
        else
            log_error "❌ Failed to delete topic: $TOPIC_NAME"
            return 1
        fi
    else
        log_warning "⚠️  Topic $TOPIC_NAME not found (may already be deleted)"
    fi
}

# Clean up files
cleanup_files() {
    log_info "Cleaning up local files..."
    
    local files_cleaned=0
    local cleanup_files=(
        "/tmp/pubsub_custom_metrics.log"
        "/tmp/topic_info.json"
        "/tmp/sub_info.json"
    )
    
    for file in "${cleanup_files[@]}"; do
        if [ -f "$file" ]; then
            if rm -f "$file"; then
                log_success "✅ Removed: $file"
                files_cleaned=$((files_cleaned + 1))
            else
                log_error "❌ Failed to remove: $file"
            fi
        fi
    done
    
    if [ $files_cleaned -eq 0 ]; then
        log_info "ℹ️  No temporary files found to clean"
    else
        log_success "✅ Cleaned $files_cleaned temporary file(s)"
    fi
}

# Verify deletion
verify_deletion() {
    log_info "Verifying deletion..."
    
    local errors=0
    
    # Check topic
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_error "❌ Topic $TOPIC_NAME still exists!"
        errors=$((errors + 1))
    else
        log_success "✅ Topic $TOPIC_NAME successfully deleted"
    fi
    
    # Check subscription
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" --project="$PROJECT_ID" &>/dev/null; then
        log_error "❌ Subscription $SUBSCRIPTION_NAME still exists!"
        errors=$((errors + 1))
    else
        log_success "✅ Subscription $SUBSCRIPTION_NAME successfully deleted"
    fi
    
    # Check files
    if [ -f "/tmp/pubsub_custom_metrics.log" ]; then
        log_error "❌ Metrics log file still exists!"
        errors=$((errors + 1))
    else
        log_success "✅ Metrics log file successfully removed"
    fi
    
    return $errors
}

# Main execution
main() {
    echo "=================================="
    echo "GCP Pub/Sub Destroy Script"
    echo "=================================="
    
    check_prerequisites
    show_deletion_plan
    confirm_deletion
    
    echo ""
    log_info "🚀 Starting destruction process..."
    echo ""
    
    # Delete in correct order (subscription first, then topic)
    local delete_errors=0
    
    delete_subscription || delete_errors=$((delete_errors + 1))
    delete_topic || delete_errors=$((delete_errors + 1))
    cleanup_files
    
    echo ""
    log_info "🔍 Verifying deletion..."
    if verify_deletion; then
        echo ""
        log_success "🎉 DESTRUCTION COMPLETED SUCCESSFULLY!"
        echo ""
        echo "✅ All resources have been deleted:"
        echo "   • Topic: $TOPIC_NAME"
        echo "   • Subscription: $SUBSCRIPTION_NAME"
        echo "   • Local files cleaned up"
        echo ""
        echo "📝 Note: Historical metrics in Cloud Monitoring remain (subject to retention policy)"
        echo "🔄 To recreate resources, run the creation script"
    else
        echo ""
        log_error "❌ DESTRUCTION COMPLETED WITH ERRORS!"
        echo ""
        echo "Some resources may still exist. Check the errors above."
        echo "You may need to manually delete remaining resources."
        exit 1
    fi
}

# Handle interruption
trap 'log_error "Destruction interrupted! Some resources may be partially deleted."; exit 1' INT TERM

# Show usage if help requested
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    echo "GCP Pub/Sub Destroy Script"
    echo ""
    echo "This script deletes all Pub/Sub resources created by the creation script."
    echo ""
    echo "Usage: $0"
    echo ""
    echo "Environment Variables:"
    echo "  GCP_PROJECT_ID    - GCP project ID (required)"
    echo "  TOPIC_NAME        - Topic name to delete (default: appdynamics-monitoring-topic)"
    echo "  SUBSCRIPTION_NAME - Subscription name to delete (default: appdynamics-monitoring-subscription)"
    echo "  FORCE             - Skip confirmation (default: false)"
    echo ""
    echo "Examples:"
    echo "  export GCP_PROJECT_ID='my-project'"
    echo "  $0                           # Interactive deletion with confirmation"
    echo "  FORCE=true $0               # Force deletion without confirmation"
    echo ""
    echo "⚠️  WARNING: This permanently deletes resources and data!"
    exit 0
fi

# Run main function
main