#!/bin/bash

# AI BankApp TEST Deployment Script
# Uses Let's Encrypt STAGING environment - NO RATE LIMITS
# Issues UNTRUSTED certificates (browser warnings expected)
# Author: Ramiz Takildar
# Date: June 2026

set -e  # Exit on error

# Test configuration
TEST_DOMAIN="test.aicloudops.in"
CHECKPOINT_FILE="/tmp/bankapp-test-deploy-checkpoint.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to save checkpoint
save_checkpoint() {
    echo "$1" > "$CHECKPOINT_FILE"
}

# Function to check if step is completed
is_step_completed() {
    local step=$1
    if [ -f "$CHECKPOINT_FILE" ]; then
        local completed_step=$(cat "$CHECKPOINT_FILE")
        if [ "$completed_step" -ge "$step" ]; then
            return 0
        fi
    fi
    return 1
}

# Function to print colored output
print_step() {
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}===================================================${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}
    
    print_info "Waiting for pods in namespace $namespace with label $label to be ready..."
    kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s" || {
        print_error "Timeout waiting for pods"
        return 1
    }
    print_success "Pods are ready"
}

# Banner
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   AI BankApp TEST Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
print_warning "This script uses Let's Encrypt STAGING environment"
print_warning "Certificates will be UNTRUSTED (browser warnings)"
print_warning "Use for testing only - NO RATE LIMITS!"
echo ""

# Check prerequisites
print_step "Checking Prerequisites"
command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed. Aborting."; exit 1; }
command -v helm >/dev/null 2>&1 || { print_error "helm is required but not installed. Aborting."; exit 1; }
command -v dig >/dev/null 2>&1 || { print_error "dig is required but not installed. Aborting."; exit 1; }

kubectl cluster-info >/dev/null 2>&1 || { print_error "Cannot connect to Kubernetes cluster. Aborting."; exit 1; }
print_success "All prerequisites met"

# Step 1: Install Gateway API CRDs
if is_step_completed 1; then
    print_info "Step 1 already completed, skipping..."
else
    print_step "Step 1: Installing Gateway API CRDs"
    kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
    sleep 5
    print_success "Gateway API CRDs installed"
    save_checkpoint 1
fi

# Step 2: Install Envoy Gateway
if is_step_completed 2; then
    print_info "Step 2 already completed, skipping..."
else
    print_step "Step 2: Installing Envoy Gateway"
    
    if helm list -n envoy-gateway-system 2>/dev/null | grep -q "^eg"; then
        print_info "Envoy Gateway already installed"
    else
        helm install eg oci://docker.io/envoyproxy/gateway-helm \
          --version v1.2.6 \
          -n envoy-gateway-system \
          --create-namespace \
          --skip-crds
    fi
    
    wait_for_pods "envoy-gateway-system" "app.kubernetes.io/name=gateway-helm" 60
    print_success "Envoy Gateway installed"
    save_checkpoint 2
fi

# Step 3: Install cert-manager
if is_step_completed 3; then
    print_info "Step 3 already completed, skipping..."
else
    print_step "Step 3: Installing cert-manager"
    
    if kubectl get namespace cert-manager >/dev/null 2>&1; then
        print_info "cert-manager already installed"
    else
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
        wait_for_pods "cert-manager" "app.kubernetes.io/instance=cert-manager" 120
    fi
    
    # Enable Gateway API support
    print_info "Enabling Gateway API support in cert-manager..."
    kubectl patch deployment cert-manager -n cert-manager --type='json' \
      -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--enable-gateway-api"}]' 2>/dev/null || true
    
    kubectl rollout status deployment/cert-manager -n cert-manager --timeout=120s
    print_success "cert-manager installed with Gateway API support"
    save_checkpoint 3
fi

# Step 4: Apply STAGING ClusterIssuer
print_step "Step 4: Applying STAGING ClusterIssuer"
kubectl apply -f k8s/cert-manager-staging.yml
print_success "Staging ClusterIssuer applied"

# Step 5: Update test configuration and push to git
print_step "Step 5: Updating Configuration Files for Test Domain"
print_info "Test domain: $TEST_DOMAIN"

# Backup current files
print_info "Creating backup of current configuration..."
cp k8s/gateway.yml k8s/gateway.yml.backup
cp k8s/certificate.yml k8s/certificate.yml.backup

# Update gateway.yml with test domain
print_info "Updating k8s/gateway.yml..."
sed -i.tmp "s/hostname: .*/hostname: $TEST_DOMAIN/" k8s/gateway.yml
sed -i.tmp "s/- bankapp.*\.aicloudops\.in/- $TEST_DOMAIN/" k8s/gateway.yml
rm -f k8s/gateway.yml.tmp

# Update certificate.yml with test domain and staging issuer
print_info "Updating k8s/certificate.yml..."
sed -i.tmp "s/name: letsencrypt-prod/name: letsencrypt-staging/" k8s/certificate.yml
sed -i.tmp "s/- bankapp.*\.aicloudops\.in/- $TEST_DOMAIN/" k8s/certificate.yml
rm -f k8s/certificate.yml.tmp

# Commit and push changes
print_info "Committing changes to git..."
git add k8s/gateway.yml k8s/certificate.yml
git commit -m "Update to test environment: $TEST_DOMAIN with staging certificates" || {
    print_info "No changes to commit (already up to date)"
}

print_info "Pushing changes to git..."
CURRENT_BRANCH=$(git branch --show-current)
git push origin "$CURRENT_BRANCH" || {
    print_warning "Failed to push to git. Continuing with local changes..."
}

print_success "Configuration files updated and pushed to git"

# Step 6: Deploy via ArgoCD or kubectl
print_step "Step 6: Deploying Application"
if kubectl get application bankapp -n argocd >/dev/null 2>&1; then
    print_info "Using ArgoCD deployment..."
    print_info "Waiting for ArgoCD to detect changes (30 seconds)..."
    sleep 30
    kubectl patch application bankapp -n argocd --type merge \
      -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
    print_info "Waiting for ArgoCD sync to complete..."
    sleep 60
else
    print_info "ArgoCD not found, using kubectl..."
    kubectl apply -f k8s/namespace.yml
    kubectl apply -f k8s/
fi

# Wait for namespace
for i in {1..30}; do
    if kubectl get namespace bankapp >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

print_success "Application deployed with test configuration"

# Step 8: Get LoadBalancer IP
print_step "Step 8: Getting LoadBalancer IP"
print_info "Waiting for LoadBalancer (2-3 minutes)..."
sleep 90

LB_HOSTNAME=$(kubectl get gateway bankapp-gateway -n bankapp -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
if [ -z "$LB_HOSTNAME" ]; then
    print_error "LoadBalancer not ready yet. Waiting 30 more seconds..."
    sleep 30
    LB_HOSTNAME=$(kubectl get gateway bankapp-gateway -n bankapp -o jsonpath='{.status.addresses[0].value}')
fi

LB_IP=$(dig +short "$LB_HOSTNAME" | head -n 1)
print_success "LoadBalancer IP: $LB_IP"

# Step 9: DNS Configuration
print_step "Step 9: Configure DNS A Record in GoDaddy"
echo ""
echo -e "${YELLOW}=================================================${NC}"
echo -e "${YELLOW}ACTION REQUIRED: Add DNS A Record in GoDaddy${NC}"
echo -e "${YELLOW}=================================================${NC}"
echo ""
echo -e "${GREEN}Domain:${NC} $TEST_DOMAIN"
echo -e "${GREEN}LoadBalancer IP:${NC} ${BLUE}$LB_IP${NC}"
echo ""
echo -e "${YELLOW}Steps to add DNS record in GoDaddy:${NC}"
echo ""
echo "1. Go to https://dcc.godaddy.com/manage/aicloudops.in/dns"
echo "2. Click 'Add New Record'"
echo "3. Select Type: ${GREEN}A${NC}"
echo "4. Enter Name: ${GREEN}test${NC}"
echo "5. Enter Value: ${BLUE}$LB_IP${NC}"
echo "6. Set TTL: ${GREEN}600 seconds (10 minutes)${NC}"
echo "7. Click 'Save'"
echo ""
echo -e "${RED}IMPORTANT: Wait for the DNS record to be saved before continuing!${NC}"
echo ""
read -p "Press Enter ONLY after you have added the DNS record in GoDaddy: " confirm
print_success "DNS record configuration confirmed"

# Step 10: Wait for DNS
print_step "Step 10: Waiting for DNS Propagation"
print_info "Checking DNS (may take 5-10 minutes)..."
for i in {1..30}; do
    RESOLVED_IP=$(dig +short "$TEST_DOMAIN" @8.8.8.8 | head -n 1)
    if [ "$RESOLVED_IP" == "$LB_IP" ]; then
        print_success "DNS propagated!"
        break
    fi
    echo "Attempt $i/30: Not yet (got: $RESOLVED_IP, expected: $LB_IP)"
    sleep 30
done

# Step 11: Wait for Certificate
print_step "Step 11: Waiting for STAGING Certificate"
print_warning "This will issue an UNTRUSTED certificate"
print_info "Monitoring certificate (1-2 minutes)..."

for i in {1..60}; do
    CERT_STATUS=$(kubectl get certificate bankapp-tls -n bankapp -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$CERT_STATUS" == "True" ]; then
        print_success "STAGING certificate issued!"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

if [ "$CERT_STATUS" != "True" ]; then
    print_error "Certificate not ready. Checking status..."
    kubectl describe certificate bankapp-tls -n bankapp
    exit 1
fi

# Step 12: Verify Application Access
print_step "Step 12: Verifying Application Access"
print_info "Testing HTTPS endpoint..."
sleep 10
HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$TEST_DOMAIN/" 2>/dev/null || echo "000")
echo "HTTPS Response: $HTTPS_CODE"

if [ "$HTTPS_CODE" == "302" ] || [ "$HTTPS_CODE" == "200" ]; then
    print_success "Application is accessible!"
else
    print_warning "Application may not be fully ready yet (got $HTTPS_CODE)"
fi

# Step 13: Install Monitoring Stack (Optional)
print_step "Step 13: Installing kube-prometheus-stack (Optional)"
read -p "Do you want to install monitoring stack (Grafana/Prometheus)? (y/n): " INSTALL_MONITORING

if [ "$INSTALL_MONITORING" == "y" ] || [ "$INSTALL_MONITORING" == "Y" ]; then
    print_info "Adding Prometheus Helm repository..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update prometheus-community

    if helm list -n monitoring 2>/dev/null | grep -q "^kube-prometheus"; then
        print_info "Monitoring stack already installed"
    else
        print_info "Installing kube-prometheus-stack (2-3 minutes)..."
        helm install kube-prometheus prometheus-community/kube-prometheus-stack \
          -n monitoring \
          --create-namespace \
          --set grafana.service.type=LoadBalancer \
          --timeout=10m
    fi

    wait_for_pods "monitoring" "release=kube-prometheus" 300

    GRAFANA_URL=$(kubectl get svc kube-prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    GRAFANA_PASSWORD=$(kubectl get secret kube-prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "pending")

    print_success "Monitoring stack installed!"
fi

# Final Summary
print_step "TEST Deployment Complete!"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Test Deployment Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "✅ Test URL: https://$TEST_DOMAIN"
echo -e "✅ LoadBalancer IP: $LB_IP"
echo -e "⚠️  Certificate: STAGING (untrusted)"
echo ""

# ArgoCD Access
if kubectl get svc argocd-server -n argocd >/dev/null 2>&1; then
    echo "ArgoCD Access:"
    ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "pending")
    echo "  URL: http://$ARGOCD_URL"
    echo "  Username: admin"
    echo "  Password: $ARGOCD_PASSWORD"
    echo ""
fi

# Monitoring Access
if [ "$INSTALL_MONITORING" == "y" ] || [ "$INSTALL_MONITORING" == "Y" ]; then
    echo "Grafana Access:"
    echo "  URL: http://$GRAFANA_URL"
    echo "  Username: admin"
    echo "  Password: $GRAFANA_PASSWORD"
    echo ""
fi

print_warning "Browser will show security warning - this is expected!"
print_warning "Click 'Advanced' and 'Proceed' to access the application"
echo ""
print_success "Test deployment successful! 🎉"
echo ""
print_info "To clean up: kubectl delete certificate,gateway,httproute -n bankapp --all"
print_info "To reset: rm $CHECKPOINT_FILE"
