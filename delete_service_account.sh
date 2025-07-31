#!/bin/bash

# Delete GCP Service Account for Pub/Sub Monitoring
# Run this on your Mac where gcloud is already set up

set -e

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
SERVICE_ACCOUNT_NAME="pubsub-monitor"
SERVICE_ACCOUNT_ID="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE_NAME="pubsub-monitor-service-account.json"
FORCE=${FORCE:-"false"}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [ -z "$PROJECT_ID" ]; then
        log_error "No project ID found. Run 'gcloud config set project YOUR_PROJECT_ID'"
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Using project: $PROJECT_ID"
    log_success "Current user: $(gcloud auth list --filter=status:ACTIVE --format="value(account)")"
}

# Show deletion plan
show_deletion_plan() {
    echo ""
    log_warning "🗑️  DELETION PLAN"
    echo "=================================="
    echo ""
    echo "Project: $PROJECT_ID"
    echo ""
    
    echo "Resources to be DELETED:"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
        echo "  ✅ Service Account: $SERVICE_ACCOUNT_ID (EXISTS - will be deleted)"
        
        # List keys
        local key_count=$(gcloud iam service-accounts keys list --iam-account="$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" --format="value(name)" | wc -l)
        echo "     └─ $key_count key(s) will be deleted"
        
        # List IAM bindings
        echo "  ✅ IAM Policy Bindings (will be removed):"
        echo "     • roles/pubsub.viewer"
        echo "     • roles/monitoring.viewer"
        echo "     • roles/serviceusage.serviceUsageViewer"
        
    else
        echo "  ❌ Service Account: $SERVICE_ACCOUNT_ID (not found)"
    fi
    
    # Check local key file
    if [ -f "$KEY_FILE_NAME" ]; then
        echo "  ✅ Local Key File: $(pwd)/$KEY_FILE_NAME (EXISTS - will be deleted)"
    else
        echo "  ❌ Local Key File: $KEY_FILE_NAME (not found)"
    fi
    
    echo ""
    log_warning "⚠️  WARNING: This action is IRREVERSIBLE!"
    echo "• The service account and all its keys will be permanently deleted"
    echo "• Any applications using this service account will lose access"
    echo "• You will need to recreate the service account if needed again"
}

# Confirm deletion
confirm_deletion() {
    if [ "$FORCE" = "true" ]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "═══════════════════════════════════"
    read -p "❓ Are you absolutely sure you want to DELETE this service account? (type 'yes' to confirm): " -r
    echo "═══════════════════════════════════"
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        echo ""
        echo "💡 To delete without confirmation, run:"
        echo "   FORCE=true $0"
        echo ""
        exit 0
    fi
}

# Delete service account keys
delete_service_account_keys() {
    log_info "Deleting service account keys..."
    
    if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Service account not found: $SERVICE_ACCOUNT_ID"
        return 0
    fi
    
    # Get all keys for the service account
    local keys=$(gcloud iam service-accounts keys list --iam-account="$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" --format="value(name)" 2>/dev/null)
    
    if [ -n "$keys" ]; then
        local key_count=0
        while IFS= read -r key_id; do
            if [ -n "$key_id" ] && [[ ! "$key_id" =~ projects/.*/serviceAccounts/.*/keys/[0-9a-f]{40}$ ]]; then
                # Skip the default key (40-character hex), only delete user-created keys
                log_info "Deleting key: $(basename "$key_id")"
                if gcloud iam service-accounts keys delete "$(basename "$key_id")" --iam-account="$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" --quiet; then
                    log_success "✅ Deleted key: $(basename "$key_id")"
                    key_count=$((key_count + 1))
                else
                    log_error "❌ Failed to delete key: $(basename "$key_id")"
                fi
            fi
        done <<< "$keys"
        
        if [ $key_count -eq 0 ]; then
            log_info "No user-created keys found to delete"
        else
            log_success "Deleted $key_count service account key(s)"
        fi
    else
        log_info "No keys found for service account"
    fi
}

# Remove IAM policy bindings
remove_iam_bindings() {
    log_info "Removing IAM policy bindings..."
    
    # Roles that were assigned
    local roles=(
        "roles/pubsub.viewer"
        "roles/monitoring.viewer"
        "roles/serviceusage.serviceUsageViewer"
    )
    
    local removed_count=0
    for role in "${roles[@]}"; do
        log_info "Removing role: $role"
        
        if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT_ID" \
            --role="$role" \
            --quiet >/dev/null 2>&1; then
            log_success "✅ Removed: $role"
            removed_count=$((removed_count + 1))
        else
            log_warning "⚠️  Could not remove role (may not exist): $role"
        fi
    done
    
    log_success "Removed $removed_count IAM policy binding(s)"
}

# Delete service account
delete_service_account() {
    log_info "Deleting service account: $SERVICE_ACCOUNT_ID"
    
    if gcloud iam service-accounts delete "$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" --quiet; then
        log_success "✅ Deleted service account: $SERVICE_ACCOUNT_ID"
    else
        log_error "❌ Failed to delete service account: $SERVICE_ACCOUNT_ID"
        return 1
    fi
}

# Delete local key file
delete_local_key_file() {
    log_info "Cleaning up local key file..."
    
    if [ -f "$KEY_FILE_NAME" ]; then
        if rm -f "$KEY_FILE_NAME"; then
            log_success "✅ Deleted local key file: $KEY_FILE_NAME"
        else
            log_error "❌ Failed to delete local key file: $KEY_FILE_NAME"
        fi
    else
        log_info "Local key file not found: $KEY_FILE_NAME"
    fi
    
    # Also check for the file in current directory with different names
    for potential_file in *service-account*.json pubsub-monitor*.json; do
        if [ -f "$potential_file" ] && [ "$potential_file" != "$KEY_FILE_NAME" ]; then
            read -p "Found potential service account key: $potential_file. Delete it? (y/n): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$potential_file"
                log_success "✅ Deleted: $potential_file"
            fi
        fi
    done
}

# Verify deletion
verify_deletion() {
    log_info "Verifying deletion..."
    
    local errors=0
    
    # Check if service account is gone
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "❌ Service account still exists: $SERVICE_ACCOUNT_ID"
        errors=$((errors + 1))
    else
        log_success "✅ Service account successfully deleted"
    fi
    
    # Check if local key file is gone
    if [ -f "$KEY_FILE_NAME" ]; then
        log_error "❌ Local key file still exists: $KEY_FILE_NAME"
        errors=$((errors + 1))
    else
        log_success "✅ Local key file successfully removed"
    fi
    
    return $errors
}

# Show final status
show_final_status() {
    echo ""
    if verify_deletion; then
        log_success "🎉 DELETION COMPLETED SUCCESSFULLY!"
        echo ""
        echo "✅ All resources have been deleted:"
        echo "   • Service Account: $SERVICE_ACCOUNT_ID"
        echo "   • All service account keys"
        echo "   • IAM policy bindings"
        echo "   • Local key file: $KEY_FILE_NAME"
        echo ""
        echo "📝 Note: It may take a few minutes for the deletion to propagate across all GCP services"
        echo ""
        echo "🔄 If you need monitoring again:"
        echo "   • Run the create_service_account.sh script"
        echo "   • Transfer the new key file to AWS Linux 2"
        echo "   • Update your monitoring configuration"
    else
        log_error "❌ DELETION COMPLETED WITH ERRORS!"
        echo ""
        echo "Some resources may still exist. Check the errors above."
        echo "You may need to manually delete remaining resources in the GCP Console."
        exit 1
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "GCP Service Account Deletion Script"
    echo "=========================================="
    
    check_prerequisites
    show_deletion_plan
    confirm_deletion
    
    echo ""
    log_info "🚀 Starting deletion process..."
    echo ""
    
    # Delete in correct order
    delete_service_account_keys
    remove_iam_bindings
    delete_service_account
    delete_local_key_file
    
    echo ""
    show_final_status
}

# Handle interruption
trap 'log_error "Deletion interrupted! Some resources may be partially deleted."; exit 1' INT TERM

# Show usage if help requested
if [[ "${1:-}" =~ ^(-h|--help|help)$ ]]; then
    echo "GCP Service Account Deletion Script"
    echo ""
    echo "This script deletes the Pub/Sub monitoring service account and cleans up all associated resources."
    echo ""
    echo "Usage: $0"
    echo ""
    echo "Environment Variables:"
    echo "  GCP_PROJECT_ID    - GCP project ID (optional, will use gcloud default)"
    echo "  FORCE             - Skip confirmation (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive deletion with confirmation"
    echo "  FORCE=true $0               # Force deletion without confirmation"
    echo "  GCP_PROJECT_ID='my-project' $0  # Use specific project"
    echo ""
    echo "⚠️  WARNING: This permanently deletes the service account and all its keys!"
    echo "             Any applications using this service account will lose access."
    exit 0
fi

# Run main function
main "$@"