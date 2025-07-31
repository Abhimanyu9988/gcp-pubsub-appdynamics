#!/bin/bash

# Create GCP Service Account for Pub/Sub Monitoring
# Run this on your Mac where gcloud is already set up

set -e

# Configuration
PROJECT_ID=${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
SERVICE_ACCOUNT_NAME="pubsub-monitor"
SERVICE_ACCOUNT_ID="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE_NAME="pubsub-monitor-service-account.json"

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

# Create service account
create_service_account() {
    log_info "Creating service account: $SERVICE_ACCOUNT_NAME"
    
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Service account already exists: $SERVICE_ACCOUNT_ID"
    else
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --project="$PROJECT_ID" \
            --display-name="Pub/Sub Monitor" \
            --description="Service account for monitoring GCP Pub/Sub from AppDynamics"
        
        log_success "Created service account: $SERVICE_ACCOUNT_ID"
    fi
}

# Assign IAM roles
assign_roles() {
    log_info "Assigning IAM roles to service account..."
    
    # Required roles for Pub/Sub monitoring
    local roles=(
        "roles/pubsub.viewer"           # View Pub/Sub topics and subscriptions
        "roles/monitoring.viewer"       # View Cloud Monitoring metrics
        "roles/serviceusage.serviceUsageViewer"  # View enabled APIs
    )
    
    for role in "${roles[@]}"; do
        log_info "Assigning role: $role"
        
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT_ID" \
            --role="$role" \
            --quiet
        
        log_success "✅ Assigned: $role"
    done
}

# Create and download key file
create_key_file() {
    log_info "Creating service account key file..."
    
    # Create key file in current directory
    gcloud iam service-accounts keys create "$KEY_FILE_NAME" \
        --iam-account="$SERVICE_ACCOUNT_ID" \
        --project="$PROJECT_ID"
    
    if [ -f "$KEY_FILE_NAME" ]; then
        log_success "✅ Service account key created: $KEY_FILE_NAME"
        
        # Show file info
        local file_size=$(ls -lh "$KEY_FILE_NAME" | awk '{print $5}')
        log_info "File size: $file_size"
        log_info "File location: $(pwd)/$KEY_FILE_NAME"
        
        # Set secure permissions
        chmod 600 "$KEY_FILE_NAME"
        log_info "File permissions set to 600 (owner read/write only)"
        
    else
        log_error "Failed to create key file"
        exit 1
    fi
}

# Verify service account
verify_service_account() {
    log_info "Verifying service account setup..."
    
    # Check if service account can list topics
    log_info "Testing Pub/Sub access..."
    if gcloud pubsub topics list --project="$PROJECT_ID" --impersonate-service-account="$SERVICE_ACCOUNT_ID" >/dev/null 2>&1; then
        log_success "✅ Service account can access Pub/Sub"
    else
        log_warning "⚠️  Service account may not have proper Pub/Sub access"
    fi
    
    # Check monitoring access
    log_info "Testing Monitoring access..."
    if gcloud services list --enabled --project="$PROJECT_ID" --impersonate-service-account="$SERVICE_ACCOUNT_ID" >/dev/null 2>&1; then
        log_success "✅ Service account can access project services"
    else
        log_warning "⚠️  Service account may not have proper project access"
    fi
}

# Show final instructions
show_instructions() {
    echo ""
    echo "🎉 Service Account Setup Complete!"
    echo "=================================="
    echo ""
    echo "📋 Created:"
    echo "   Service Account: $SERVICE_ACCOUNT_ID"
    echo "   Key File: $(pwd)/$KEY_FILE_NAME"
    echo ""
    echo "🔐 Assigned Roles:"
    echo "   • roles/pubsub.viewer"
    echo "   • roles/monitoring.viewer" 
    echo "   • roles/serviceusage.serviceUsageViewer"
    echo ""
    echo "📦 Transfer to AWS Linux 2:"
    echo "   # Secure copy to your AWS instance"
    echo "   scp -i your-key.pem $KEY_FILE_NAME ec2-user@your-instance-ip:~/"
    echo ""
    echo "   # Or copy file content and paste on AWS Linux 2"
    echo "   cat $KEY_FILE_NAME"
    echo ""
    echo "🔧 On AWS Linux 2, set up authentication:"
    echo "   sudo mkdir -p /opt/gcp-credentials"
    echo "   sudo mv $KEY_FILE_NAME /opt/gcp-credentials/service-account.json"
    echo "   sudo chmod 600 /opt/gcp-credentials/service-account.json"
    echo "   sudo chown \$(whoami):\$(whoami) /opt/gcp-credentials/service-account.json"
    echo ""
    echo "   export GOOGLE_APPLICATION_CREDENTIALS=\"/opt/gcp-credentials/service-account.json\""
    echo "   export GCP_PROJECT_ID=\"$PROJECT_ID\""
    echo ""
    echo "🧪 Test on AWS Linux 2:"
    echo "   gcloud auth activate-service-account --key-file=/opt/gcp-credentials/service-account.json"
    echo "   gcloud projects describe $PROJECT_ID"
    echo "   gcloud pubsub topics list --project=$PROJECT_ID"
    echo ""
    echo "⚠️  Security Note:"
    echo "   • Keep this key file secure"
    echo "   • Don't commit it to version control"
    echo "   • Consider rotating keys periodically"
}

# Main execution
main() {
    echo "============================================"
    echo "GCP Service Account Creation for Pub/Sub Monitoring"
    echo "============================================"
    echo ""
    
    check_prerequisites
    create_service_account
    assign_roles
    create_key_file
    verify_service_account
    show_instructions
    
    echo ""
    log_success "🚀 Ready to transfer $KEY_FILE_NAME to your AWS Linux 2 instance!"
}

# Handle interruption
trap 'echo ""; log_error "Setup interrupted"; exit 1' INT TERM

# Run main function
main "$@"