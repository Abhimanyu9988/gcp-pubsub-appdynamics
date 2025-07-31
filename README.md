# GCP Pub/Sub Monitoring with AppDynamics Machine Agent

A comprehensive solution for monitoring Google Cloud Pub/Sub topics and subscriptions using AppDynamics Machine Agent. This toolkit provides end-to-end automation for creating Pub/Sub resources, generating metrics, and monitoring them through AppDynamics.

## 🎯 Features

- **Complete Pub/Sub Lifecycle Management**: Create, monitor, and clean up Pub/Sub resources
- **Comprehensive Metrics Collection**: 50+ metrics covering topics, subscriptions, APIs, and project health
- **Multi-Platform Support**: Works on Amazon Linux 2/2023, Ubuntu, RHEL/CentOS, Rocky Linux
- **AppDynamics Integration**: Native Machine Agent extension with proper metric formatting
- **Security-First**: Service account authentication with minimal required permissions
- **Production Ready**: Error handling, logging, and robust configuration validation

## 📊 Metrics Collected

### Topic Metrics
- Topic status and accessibility
- Subscription counts per topic
- Message retention configuration
- IAM policy accessibility

### Subscription Metrics
- Subscription status and configuration
- Acknowledgment deadline settings
- Push vs Pull subscription detection
- Dead letter policy configuration
- Retry policy status
- Message filtering capabilities
- Message retention settings

### API & Service Health
- Pub/Sub API availability
- Monitoring API status
- Operational capabilities
- Overall health scoring

### Project-Level Insights
- Total topics and subscriptions
- Configuration validation
- Custom metrics integration

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GCP Pub/Sub   │    │  Metrics Script  │    │   AppDynamics   │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │   Topics    │◄┼────┼─│    gcloud    │ │    │ │   Machine   │ │
│ └─────────────┘ │    │ │     CLI      │ │    │ │    Agent    │ │
│                 │    │ └──────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │        │        │
│ │Subscriptions│◄┼────┼─│ Metrics      │─┼────┼────────┘        │
│ └─────────────┘ │    │ │ Collector    │ │    │                 │
│                 │    │ └──────────────┘ │    │ ┌─────────────┐ │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ │ Controller  │ │
│ │   Metrics   │◄┼────┼─│    JSON      │ │    │ │ Dashboard   │ │
│ └─────────────┘ │    │ │    Auth      │ │    │ └─────────────┘ │
└─────────────────┘    │ └──────────────┘ │    └─────────────────┘
                       └──────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- GCP Project with billing enabled
- Service account with Pub/Sub Viewer permissions
- AppDynamics Machine Agent installed
- Linux system (Amazon Linux 2/2023, Ubuntu, RHEL/CentOS)

### 1. Install Prerequisites
```bash
# Run the multi-platform installer
sudo ./ec2-pre-req.sh
```

### 2. Create GCP Service Account (One-time)
```bash
# On your local machine with gcloud setup
./create_service_account.sh
```

### 3. Create Pub/Sub Resources
```bash
# Set your project ID
export GCP_PROJECT_ID="your-project-id"

# Create topics and subscriptions with sample data
./pubsub_create.sh
```

### 4. Configure Metrics Collection
```bash
# Edit the main script with your credentials
vi script.sh

# Update these values:
PROJECT_ID="your-project-id"
SERVICE_ACCOUNT_KEY_FILE="/path/to/your/service-account.json"
```

### 5. Test Metrics Collection
```bash
./script.sh
```

### 6. Install AppDynamics Extension
```bash
# Copy files to Machine Agent
sudo cp script.sh /opt/appdynamics/machine-agent/monitors/PubSubMonitor/
sudo cp monitor.xml /opt/appdynamics/machine-agent/monitors/PubSubMonitor/

# Restart Machine Agent
sudo systemctl restart appdynamics-machine-agent
```

## 📁 File Structure

```
├── README.md                           # This file
├── script.sh                          # Main metrics collector
├── ec2-pre-req.sh                      # Prerequisites installer
├── monitor.xml                         # AppDynamics monitor configuration
├── create_service_account.sh           # GCP service account creation
├── delete_service_account.sh           # GCP service account cleanup
├── pubsub_create.sh                    # Pub/Sub resource creation
├── pubsub_destroy.sh                   # Pub/Sub resource cleanup
├── pubsub_info.sh                      # Resource status and information
└── examples/
    ├── sample-output.txt               # Example metrics output
    └── appd-dashboard.json             # Sample AppDynamics dashboard
```

## ⚙️ Configuration

### Environment Variables
```bash
# Required
export GCP_PROJECT_ID="your-project-id"

# Optional
export TOPIC_NAMES="topic1,topic2,topic3"                    # Default: appdynamics-monitoring-topic
export SUBSCRIPTION_NAMES="sub1,sub2,sub3"                   # Default: appdynamics-monitoring-subscription
export METRIC_PREFIX="Custom Metrics|PubSub"                 # AppDynamics metric path
```

### Service Account Permissions
Minimum required IAM roles:
- `roles/pubsub.viewer` - View Pub/Sub resources
- `roles/monitoring.viewer` - Access monitoring data
- `roles/serviceusage.serviceUsageViewer` - View enabled APIs

### Machine Agent Configuration
```xml
<monitor>
    <n>PubSubMonitor</n>
    <type>managed</type>
    <description>GCP Pub/Sub Monitoring Extension</description>
    <monitor-configuration>
        <execution-style>periodic</execution-style>
        <execution-frequency-in-seconds>60</execution-frequency-in-seconds>
    </monitor-configuration>
</monitor>
```

## 📊 Sample Output

```
name=Custom Metrics|PubSub|Topic|my-topic|Status, value=1
name=Custom Metrics|PubSub|Topic|my-topic|Subscription Count, value=3
name=Custom Metrics|PubSub|Subscription|my-sub|Status, value=1
name=Custom Metrics|PubSub|Subscription|my-sub|Ack Deadline, value=60
name=Custom Metrics|PubSub|Subscription|my-sub|Dead Letter Enabled, value=1
name=Custom Metrics|PubSub|API|PubSub Enabled, value=1
name=Custom Metrics|PubSub|Project|Total Topics, value=5
name=Custom Metrics|PubSub|Health|Collection Success, value=1
```

## 🔧 Management Commands

### Resource Management
```bash
# Create Pub/Sub resources with sample data
./pubsub_create.sh

# Check resource status
./pubsub_info.sh status

# View available metrics
./pubsub_info.sh metrics

# Clean up resources
./pubsub_destroy.sh
```

### Service Account Management
```bash
# Create service account (run on machine with gcloud setup)
./create_service_account.sh

# Delete service account and cleanup
./delete_service_account.sh
```

### Troubleshooting
```bash
# Test metrics collection manually
./script.sh

# View detailed resource information
./pubsub_info.sh status

# Check prerequisites
sudo ./ec2-pre-req.sh
```

## 🌐 Platform Support

### Tested Operating Systems
- ✅ Amazon Linux 2
- ✅ Amazon Linux 2023  
- ✅ Ubuntu 18.04/20.04/22.04
- ✅ RHEL/CentOS 7/8/9
- ✅ Rocky Linux 8/9
- ✅ AlmaLinux 8/9

### Cloud Platforms
- ✅ AWS EC2
- ✅ Google Cloud Compute Engine
- ✅ Azure Virtual Machines
- ✅ On-premises Linux

## 🔐 Security Best Practices

1. **Service Account Keys**: Store in secure location with 600 permissions
2. **Minimal Permissions**: Use least-privilege IAM roles
3. **Key Rotation**: Rotate service account keys periodically
4. **Environment Isolation**: Use separate service accounts per environment
5. **Monitoring**: Enable audit logging for service account usage

## 🚨 Troubleshooting

### Common Issues

**Authentication Errors**
```bash
# Check service account file exists and is valid JSON
ls -la /path/to/service-account.json
jq empty /path/to/service-account.json

# Test authentication manually
gcloud auth activate-service-account --key-file=/path/to/service-account.json
```

**Permission Denied**
```bash
# Verify service account has required roles
gcloud projects get-iam-policy your-project-id --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:your-service-account@project.iam.gserviceaccount.com"
```

**No Metrics Appearing**
```bash
# Check Machine Agent logs
tail -f /opt/appdynamics/machine-agent/logs/machine-agent.log

# Test script manually
cd /opt/appdynamics/machine-agent/monitors/PubSubMonitor
./script.sh
```

### Debug Mode
Enable debug logging by setting:
```bash
# In script.sh, add this line at the top:
DEBUG="true"
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup
```bash
# Clone repository
git clone https://github.com/your-username/gcp-pubsub-appdynamics.git
cd gcp-pubsub-appdynamics

# Set up test environment
export GCP_PROJECT_ID="your-test-project"
sudo ./ec2-pre-req.sh

# Run tests
./script.sh
```

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- AppDynamics Community for Machine Agent extension patterns
- Google Cloud Platform for comprehensive APIs
- Open source community for shell scripting best practices

## 📞 Support

- Create an [Issue](https://github.com/Abhimanyu9988/gcp-pubsub-appdynamics/issues) for bug reports
- Start a [Discussion](https://github.com/Abhimanyu9988/gcp-pubsub-appdynamics/discussions) for questions
- Check existing documentation and troubleshooting guides

---

**⭐ If this project helped you, please give it a star!**