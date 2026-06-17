#!/bin/bash

# AI BankApp PRODUCTION Deployment Script
# Uses Let's Encrypt PRODUCTION environment
# Issues TRUSTED certificates - RATE LIMITED (5 per week)
# Domain: aibankapp.aicloudops.in
# Author: Ramiz Takildar
# Date: June 2026

set -e  # Exit on error

# Production configuration
PROD_DOMAIN="aibankapp.aicloudops.in"
CHECKPOINT_FILE="/tmp/bankapp-prod-deploy-checkpoint.txt"

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
echo -e "${BLUE}   AI BankApp PRODUCTION Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
print_warning "This script uses Let's Encrypt PRODUCTION environment"
print_warning "Rate Limited: 5 certificates per week per domain"
print_warning "Use ONLY for final production deployment!"
echo ""
read -p "Are you sure you want to proceed with PRODUCTION deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    print_info "Deployment cancelled. Use deploy-test.sh for testing."
    exit 0
fi

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

# Step 4: Apply PRODUCTION ClusterIssuer
if is_step_completed 4; then
    print_info "Step 4 already completed, skipping..."
else
    print_step "Step 4: Applying PRODUCTION ClusterIssuer"
    kubectl apply -f k8s/cert-manager.yml
    print_success "Production ClusterIssuer applied"
    save_checkpoint 4
fi

# Step 5: Update production configuration and push to git
if is_step_completed 5; then
    print_info "Step 5 already completed, skipping..."
else
    print_step "Step 5: Updating Configuration Files for Production Domain"
print_info "Production domain: $PROD_DOMAIN"

# Backup current files
print_info "Creating backup of current configuration..."
cp k8s/gateway.yml k8s/gateway.yml.backup
cp k8s/certificate.yml k8s/certificate.yml.backup

# Update gateway.yml with production domain
print_info "Updating k8s/gateway.yml..."
sed -i.tmp "s/hostname: .*/hostname: $PROD_DOMAIN/" k8s/gateway.yml
sed -i.tmp "s/- .*\.aicloudops\.in/- $PROD_DOMAIN/" k8s/gateway.yml
rm -f k8s/gateway.yml.tmp

# Update certificate.yml with production domain and production issuer
print_info "Updating k8s/certificate.yml..."
sed -i.tmp "s/name: letsencrypt-staging/name: letsencrypt-prod/" k8s/certificate.yml
sed -i.tmp "s/- .*\.aicloudops\.in/- $PROD_DOMAIN/" k8s/certificate.yml
rm -f k8s/certificate.yml.tmp

# Commit and push changes
print_info "Committing changes to git..."
git add k8s/gateway.yml k8s/certificate.yml
git commit -m "Update to production environment: $PROD_DOMAIN with production certificates" || {
    print_info "No changes to commit (already up to date)"
}

print_info "Pushing changes to git..."
CURRENT_BRANCH=$(git branch --show-current)
git push origin "$CURRENT_BRANCH" || {
    print_warning "Failed to push to git. Continuing with local changes..."
}

    print_success "Configuration files updated and pushed to git"
    save_checkpoint 5
fi

# Step 6: Docker Image Confirmation
if is_step_completed 6; then
    print_info "Step 6 already completed, skipping..."
else
    print_step "Step 6: Docker Image Confirmation"
    print_info "Before proceeding, ensure you have:"
echo "  1. Updated k8s/bankapp-deployment.yml with your DockerHub username"
echo "  2. Built Docker image: docker build -t <username>/bankapp:latest ."
echo "  3. Pushed to DockerHub: docker push <username>/bankapp:latest"
echo ""
read -p "Have you built and pushed the Docker image? (yes/no): " docker_confirm
if [ "$docker_confirm" != "yes" ]; then
    print_error "Please build and push Docker image before continuing"
    exit 1
fi
    print_success "Docker image confirmation received"
    save_checkpoint 6
fi

# Step 7: Get ArgoCD Access Information
if is_step_completed 7; then
    print_info "Step 7 already completed, skipping..."
else
    print_step "Step 7: ArgoCD Access Information"
    if kubectl get svc argocd-server -n argocd >/dev/null 2>&1; then
    ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "pending")
    
    echo ""
    echo -e "${GREEN}ArgoCD Access:${NC}"
    echo -e "  URL: ${BLUE}http://$ARGOCD_URL${NC}"
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}$ARGOCD_PASSWORD${NC}"
    echo ""
    print_success "ArgoCD credentials retrieved"
    else
        print_warning "ArgoCD not found in cluster"
    fi
    save_checkpoint 7
fi

# Step 8: Deploy via ArgoCD or kubectl
if is_step_completed 8; then
    print_info "Step 8 already completed, skipping..."
else
    print_step "Step 8: Deploying Application"
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

    print_success "Application deployed with production configuration"
    save_checkpoint 8
fi

# Step 9: Get LoadBalancer IP
if is_step_completed 9; then
    print_info "Step 9 already completed, retrieving LoadBalancer IP..."
    if kubectl get namespace bankapp >/dev/null 2>&1 && kubectl get gateway bankapp-gateway -n bankapp >/dev/null 2>&1; then
        LB_HOSTNAME=$(kubectl get gateway bankapp-gateway -n bankapp -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
        if [ -n "$LB_HOSTNAME" ]; then
            LB_IP=$(dig +short "$LB_HOSTNAME" | head -n 1)
            print_success "LoadBalancer IP: $LB_IP"
        else
            print_warning "Gateway not ready, will retrieve in next step"
        fi
    else
        print_warning "Namespace or gateway not found (cleanup was run?), will retrieve in next step"
    fi
else
    print_step "Step 9: Getting LoadBalancer IP"
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
    save_checkpoint 9
fi

# Step 10: DNS Configuration
if is_step_completed 10; then
    print_info "Step 10 already completed, skipping DNS configuration prompt..."
else
    print_step "Step 10: Configure DNS A Record"
    echo ""
    echo -e "${YELLOW}=================================================${NC}"
    echo -e "${YELLOW}ACTION REQUIRED: Create DNS A Record${NC}"
    echo -e "${YELLOW}=================================================${NC}"
    echo ""
    echo -e "${GREEN}Create A Record:${NC}"
    echo ""
    echo -e "  ${GREEN}Type:${NC}  A"
    echo -e "  ${GREEN}Name:${NC}  aibankapp"
    echo -e "  ${GREEN}Value:${NC} ${BLUE}$LB_IP${NC} ${YELLOW}(your LoadBalancer IP)${NC}"
    echo -e "  ${GREEN}TTL:${NC}   300 ${YELLOW}(5 minutes)${NC}"
    echo ""
    echo -e "${GREEN}Example Configuration:${NC}"
    echo ""
    echo -e "  ${GREEN}Type:${NC}  A"
    echo -e "  ${GREEN}Name:${NC}  aibankapp.aicloudops.in"
    echo -e "  ${GREEN}Value:${NC} ${BLUE}$LB_IP${NC}"
    echo -e "  ${GREEN}TTL:${NC}   300"
    echo ""
    echo -e "${RED}IMPORTANT: Wait for the DNS record to be saved before continuing!${NC}"
    echo -e "${YELLOW}⚠️  WARNING: This will use 1 of your 5 weekly production certificates!${NC}"
    echo ""
    read -p "Press Enter ONLY after you have added the DNS record in GoDaddy: " confirm
    print_success "DNS record configuration confirmed"
    save_checkpoint 10
fi

# Step 11: Wait for DNS
if is_step_completed 11; then
    print_info "Step 11 already completed, skipping..."
else
    print_step "Step 11: Waiting for DNS Propagation"
    print_info "Checking DNS (may take 5-15 minutes)..."
    DNS_PROPAGATED=false
    for i in {1..30}; do
        RESOLVED_IP=$(dig +short "$PROD_DOMAIN" @8.8.8.8 | head -n 1)
        if [ "$RESOLVED_IP" == "$LB_IP" ]; then
            print_success "DNS propagated!"
            DNS_PROPAGATED=true
            break
        fi
        echo "Attempt $i/30: Not yet (got: $RESOLVED_IP, expected: $LB_IP)"
        sleep 30
    done

    if [ "$DNS_PROPAGATED" = false ]; then
        print_warning "DNS not fully propagated. Certificate issuance may take longer."
    fi
    save_checkpoint 11
fi

# Step 12: Wait for Certificate with Rate Limit Detection
if is_step_completed 12; then
    print_info "Step 12 already completed, skipping..."
else
    print_step "Step 12: Waiting for PRODUCTION Certificate"
    print_warning "This uses your rate limit quota (5 per week)"
    print_info "Monitoring certificate (1-2 minutes)..."

    CERT_READY=false
    RATE_LIMITED=false
    RETRY_COUNT=0
    MAX_RETRIES=2
    
    while [ $RETRY_COUNT -le $MAX_RETRIES ]; do
        for i in {1..60}; do
            CERT_STATUS=$(kubectl get certificate bankapp-tls -n bankapp -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            if [ "$CERT_STATUS" == "True" ]; then
                print_success "PRODUCTION certificate issued!"
                CERT_READY=true
                break 2
            fi
            
            # Check for rate limit
            CERT_MESSAGE=$(kubectl get certificate bankapp-tls -n bankapp -o jsonpath='{.status.conditions[?(@.type=="Issuing")].message}' 2>/dev/null || echo "")
            if echo "$CERT_MESSAGE" | grep -qi "rateLimited\|429.*too many certificates"; then
                RATE_LIMITED=true
                RETRY_AFTER=$(echo "$CERT_MESSAGE" | grep -Eo 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | sed 's/retry after //')
                break 2
            fi
            
            # Check for failed order (but not rate limit)
            ORDER_STATE=$(kubectl get order -n bankapp -o jsonpath='{.items[0].status.state}' 2>/dev/null || echo "")
            if [ "$ORDER_STATE" == "errored" ] && [ "$RATE_LIMITED" = false ]; then
                print_warning "Certificate order failed. Cleaning up and retrying..."
                kubectl delete certificate bankapp-tls -n bankapp 2>/dev/null || true
                kubectl delete certificaterequest,order,challenge -n bankapp --all 2>/dev/null || true
                sleep 10
                kubectl apply -f k8s/certificate.yml
                RETRY_COUNT=$((RETRY_COUNT + 1))
                print_info "Retry attempt $RETRY_COUNT of $MAX_RETRIES..."
                sleep 20
                break
            fi
            
            echo -n "."
            sleep 5
        done
        
        if [ "$CERT_READY" = true ] || [ "$RATE_LIMITED" = true ]; then
            break
        fi
        
        if [ $RETRY_COUNT -gt $MAX_RETRIES ]; then
            break
        fi
    done
    echo ""

if [ "$RATE_LIMITED" = true ]; then
    print_error "Let's Encrypt Rate Limit Hit!"
    echo ""
    if [ -n "$RETRY_AFTER" ]; then
        print_info "Rate limit expires: $RETRY_AFTER UTC"
    fi
    echo ""
    print_info "Solutions:"
    echo "1. Wait until rate limit expires"
    echo "2. Use deploy-test.sh with a different subdomain for testing"
    echo "3. Contact support if this is urgent"
    echo ""
    kubectl describe certificate bankapp-tls -n bankapp
    exit 1
fi

    if [ "$CERT_READY" = false ]; then
        print_error "Certificate not ready. Checking status..."
        kubectl describe certificate bankapp-tls -n bankapp
        kubectl get certificaterequest,order,challenge -n bankapp
        exit 1
    fi
    save_checkpoint 12
fi

# Step 13: Verify Application Access
if is_step_completed 13; then
    print_info "Step 13 already completed, skipping..."
else
    print_step "Step 13: Verifying Application Access"
    print_info "Testing HTTPS endpoint..."
    sleep 10
    HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$PROD_DOMAIN/" || echo "000")
    echo "HTTPS Response: $HTTPS_CODE"

    if [ "$HTTPS_CODE" == "302" ] || [ "$HTTPS_CODE" == "200" ]; then
        print_success "Application is accessible!"
    else
        print_warning "Application may not be fully ready yet (got $HTTPS_CODE)"
    fi
    save_checkpoint 13
fi

# Step 14: Install Monitoring Stack (Optional)
if is_step_completed 14; then
    print_info "Step 14 already completed, skipping..."
else
    print_step "Step 14: Installing kube-prometheus-stack (Optional)"
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
    save_checkpoint 14
fi

# Final Summary
print_step "PRODUCTION Deployment Complete!"
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Production Deployment Summary                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🚀 Application Access:${NC}"
echo -e "   ${GREEN}URL:${NC}              https://$PROD_DOMAIN"
echo -e "   ${GREEN}LoadBalancer IP:${NC}  $LB_IP"
echo -e "   ${GREEN}Certificate:${NC}      PRODUCTION (trusted by browsers)"
echo ""

# ArgoCD Access
if kubectl get svc argocd-server -n argocd >/dev/null 2>&1; then
    ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "pending")
    
    echo -e "${BLUE}🔧 ArgoCD Dashboard:${NC}"
    echo -e "   ${GREEN}URL:${NC}      http://$ARGOCD_URL"
    echo -e "   ${GREEN}Username:${NC} admin"
    echo -e "   ${GREEN}Password:${NC} $ARGOCD_PASSWORD"
    echo ""
fi

# Monitoring Access (check if monitoring is installed)
if kubectl get namespace monitoring >/dev/null 2>&1; then
    GRAFANA_URL=$(kubectl get svc kube-prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    GRAFANA_PASSWORD=$(kubectl get secret kube-prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo "pending")
    
    if [ -n "$GRAFANA_URL" ] && [ "$GRAFANA_URL" != "pending" ]; then
        echo -e "${BLUE}📊 Grafana Monitoring:${NC}"
        echo -e "   ${GREEN}URL:${NC}      http://$GRAFANA_URL"
        echo -e "   ${GREEN}Username:${NC} admin"
        echo -e "   ${GREEN}Password:${NC} $GRAFANA_PASSWORD"
        echo ""
    fi
fi

# Check remaining quota
CERT_EVENTS=$(kubectl describe certificate bankapp-tls -n bankapp 2>/dev/null | grep -c "Successfully issued" || echo "1")
REMAINING=$((5 - CERT_EVENTS))
echo -e "${BLUE}📋 Let's Encrypt Rate Limit Status:${NC}"
echo -e "   ${GREEN}Used:${NC}      $CERT_EVENTS/5 certificates this week"
echo -e "   ${GREEN}Remaining:${NC} $REMAINING certificates available"
echo ""

print_success "Production deployment successful! 🎉"
echo ""
print_info "Monitor: kubectl get certificate,gateway,httproute -n bankapp"
print_info "To reset: rm $CHECKPOINT_FILE"
