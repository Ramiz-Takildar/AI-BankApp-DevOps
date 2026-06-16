#!/bin/bash

# AI BankApp Automated Deployment Script
# Steps 3-16 from DEPLOYMENT_GUIDE_2026.md
# Author: Ramiz Takildar
# Date: June 2026

set -e  # Exit on error

# Checkpoint file to track progress
CHECKPOINT_FILE="/tmp/bankapp-deploy-checkpoint.txt"

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
            return 0  # Step completed
        fi
    fi
    return 1  # Step not completed
}

# Function to get last completed step
get_last_checkpoint() {
    if [ -f "$CHECKPOINT_FILE" ]; then
        cat "$CHECKPOINT_FILE"
    else
        echo "0"
    fi
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

# Function to wait for user confirmation
wait_for_confirmation() {
    local message=$1
    echo -e "${YELLOW}$message${NC}"
    read -p "Type 'done' to continue: " response
    while [ "$response" != "done" ]; do
        echo -e "${RED}Please type 'done' to continue${NC}"
        read -p "Type 'done' to continue: " response
    done
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

# Check prerequisites
print_step "Checking Prerequisites"
command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed. Aborting."; exit 1; }
command -v helm >/dev/null 2>&1 || { print_error "helm is required but not installed. Aborting."; exit 1; }
command -v dig >/dev/null 2>&1 || { print_error "dig is required but not installed. Aborting."; exit 1; }

kubectl cluster-info >/dev/null 2>&1 || { print_error "Cannot connect to Kubernetes cluster. Aborting."; exit 1; }
print_success "All prerequisites met"

# Show resume information if checkpoint exists
LAST_CHECKPOINT=$(get_last_checkpoint)
if [ "$LAST_CHECKPOINT" != "0" ]; then
    print_info "Resuming from checkpoint: Step $LAST_CHECKPOINT completed"
    print_info "Skipping completed steps..."
fi

# Step 3: Install Gateway API CRDs
if is_step_completed 3; then
    print_info "Step 3 already completed, skipping..."
else
    print_step "Step 3: Installing Gateway API CRDs"
    kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
    sleep 5
    kubectl get crd | grep gateway
    print_success "Gateway API CRDs installed"
    save_checkpoint 3
fi

# Step 4: Install Envoy Gateway
if is_step_completed 4; then
    print_info "Step 4 already completed, skipping..."
else
    print_step "Step 4: Installing Envoy Gateway"

    # Check if Envoy Gateway is already installed
    if helm list -n envoy-gateway-system 2>/dev/null | grep -q "^eg"; then
        print_info "Envoy Gateway already installed, skipping..."
    else
        print_info "Installing Envoy Gateway..."
        helm install eg oci://docker.io/envoyproxy/gateway-helm \
          --version v1.2.6 \
          -n envoy-gateway-system \
          --create-namespace \
          --skip-crds
    fi

    wait_for_pods "envoy-gateway-system" "app.kubernetes.io/name=gateway-helm" 60

    # Create GatewayClass
    cat > /tmp/gatewayclass.yaml << 'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
    kubectl apply -f /tmp/gatewayclass.yaml

    # Install complete Envoy Gateway CRDs (skip if already applied to avoid annotation size error)
    print_info "Installing complete Envoy Gateway CRDs..."
    kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.2.6/install.yaml 2>&1 | grep -v "metadata.annotations: Too long" || true

    kubectl get gatewayclass eg
    print_success "Envoy Gateway installed"
    save_checkpoint 4
fi

# Step 5: Install cert-manager
if is_step_completed 5; then
    print_info "Step 5 already completed, skipping..."
else
    print_step "Step 5: Installing cert-manager"

    # Check if cert-manager is already installed
    if kubectl get namespace cert-manager >/dev/null 2>&1; then
        print_info "cert-manager already installed, skipping installation..."
    else
        print_info "Installing cert-manager..."
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml
        wait_for_pods "cert-manager" "app.kubernetes.io/instance=cert-manager" 120
    fi
    save_checkpoint 5
fi

# Enable Gateway API support (check if already enabled)
print_info "Checking Gateway API support in cert-manager..."
GATEWAY_API_ENABLED=$(kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -c "enable-gateway-api" || echo "0")

if [ "$GATEWAY_API_ENABLED" -eq "0" ]; then
    print_info "Enabling Gateway API support in cert-manager..."
    kubectl patch deployment cert-manager -n cert-manager --type='json' \
      -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--enable-gateway-api"}]'
    
    print_info "Waiting for cert-manager to restart (60 seconds)..."
    sleep 10
    
    # Wait for old pods to terminate
    kubectl wait --for=delete pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=60s 2>/dev/null || true
    
    # Wait for new pods to be ready
    print_info "Waiting for new cert-manager pods to be ready..."
    for i in {1..12}; do
        if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cert-manager -n cert-manager --timeout=10s 2>/dev/null; then
            print_success "cert-manager pods are ready"
            break
        fi
        if [ $i -eq 12 ]; then
            print_error "Timeout waiting for cert-manager pods. Checking status..."
            kubectl get pods -n cert-manager
            print_info "You can re-run this script - it will skip completed steps"
            exit 1
        fi
        echo "Attempt $i/12: Waiting for pods..."
        sleep 5
    done
else
    print_success "Gateway API support already enabled in cert-manager"
fi

kubectl get pods -n cert-manager
print_success "cert-manager installed with Gateway API support"

# Step 6-7: Reminder for manual steps
if is_step_completed 7; then
    print_info "Steps 6-7 already completed, skipping..."
else
    print_step "Step 6-7: Manual Steps Required"
    print_info "Before proceeding, ensure you have:"
    echo "  1. Updated k8s/bankapp-deployment.yml with your DockerHub username"
    echo "  2. Updated k8s/gateway.yml with your domain"
    echo "  3. Updated k8s/certificate.yml with your domain"
    echo "  4. Built and pushed Docker image to DockerHub"
    echo ""
    wait_for_confirmation "Have you completed steps 6-7 (updated manifests and pushed Docker image)?"
    save_checkpoint 7
fi

# Step 8: Deploy via ArgoCD
if is_step_completed 8; then
    print_info "Step 8 already completed, skipping..."
else
    print_step "Step 8: Deploying via ArgoCD"
    kubectl apply -f argocd/application.yml

    print_info "Waiting for ArgoCD to sync (30 seconds)..."
    sleep 30

    kubectl get application bankapp -n argocd
    print_success "ArgoCD application deployed"

    # Wait for namespace and pods
    print_info "Waiting for bankapp namespace and pods to be created..."
    for i in {1..30}; do
        if kubectl get namespace bankapp >/dev/null 2>&1; then
            print_success "Namespace bankapp created"
            break
        fi
        sleep 2
    done

    print_info "Waiting for pods to start (this may take 2-3 minutes)..."
    sleep 60
    save_checkpoint 8
fi

# Step 9: Get LoadBalancer IP
if is_step_completed 9; then
    print_info "Step 9 already completed, retrieving LoadBalancer IP..."
    LB_HOSTNAME=$(kubectl get gateway bankapp-gateway -n bankapp -o jsonpath='{.status.addresses[0].value}')
    LB_IP=$(dig +short "$LB_HOSTNAME" | head -n 1)
    print_success "LoadBalancer Primary IP: $LB_IP"
else
    print_step "Step 9: Getting LoadBalancer IP Address"
    print_info "Waiting for Gateway to be created..."
    for i in {1..30}; do
        if kubectl get gateway bankapp-gateway -n bankapp >/dev/null 2>&1; then
            print_success "Gateway created"
            break
        fi
        sleep 2
    done

    print_info "Waiting for LoadBalancer to be provisioned (this takes 2-3 minutes)..."
    sleep 90

    LB_HOSTNAME=$(kubectl get gateway bankapp-gateway -n bankapp -o jsonpath='{.status.addresses[0].value}')
    print_info "LoadBalancer Hostname: $LB_HOSTNAME"

    print_info "Resolving LoadBalancer IP address..."
    LB_IP=$(dig +short "$LB_HOSTNAME" | head -n 1)

    if [ -z "$LB_IP" ]; then
        print_error "Could not resolve LoadBalancer IP. Waiting 30 more seconds..."
        sleep 30
        LB_IP=$(dig +short "$LB_HOSTNAME" | head -n 1)
    fi

    if [ -z "$LB_IP" ]; then
        print_error "Failed to get LoadBalancer IP. Please check manually."
        exit 1
    fi

    print_success "LoadBalancer Primary IP: $LB_IP"
    save_checkpoint 9
fi

# Step 10: Configure DNS A Record
if is_step_completed 10; then
    print_info "Step 10 already completed, skipping DNS configuration prompt..."
else
    print_step "Step 10: Configure DNS A Record"
    echo ""
    echo -e "${YELLOW}=================================================${NC}"
    echo -e "${YELLOW}ACTION REQUIRED: Configure DNS A Record${NC}"
    echo -e "${YELLOW}=================================================${NC}"
    echo ""
    echo -e "${GREEN}LoadBalancer IP from Step 9: ${BLUE}$LB_IP${NC}"
    echo -e "${GREEN}LoadBalancer Hostname: ${BLUE}$LB_HOSTNAME${NC}"
    echo ""
    echo "In your DNS provider (GoDaddy, Cloudflare, Route53, etc.):"
    echo ""
    echo -e "  ${GREEN}Type:${NC} A"
    echo -e "  ${GREEN}Name:${NC} bankapp (or your subdomain)"
    echo -e "  ${GREEN}Value:${NC} ${BLUE}$LB_IP${NC} ${RED}<-- USE THIS IP${NC}"
    echo -e "  ${GREEN}TTL:${NC} 300 (5 minutes)"
    echo ""
    echo "Example for domain 'bankapp.yourdomain.com':"
    echo -e "  Type: ${GREEN}A${NC}"
    echo -e "  Name: ${GREEN}bankapp${NC}"
    echo -e "  Value: ${BLUE}$LB_IP${NC}"
    echo -e "  TTL: ${GREEN}300${NC}"
    echo ""
    wait_for_confirmation "Have you configured the DNS A record?"
    save_checkpoint 10
fi

# Step 11: Wait for DNS Propagation
if is_step_completed 11; then
    print_info "Step 11 already completed, retrieving domain..."
    # Try to get domain from previous run (stored in temp file)
    if [ -f "/tmp/bankapp-domain.txt" ]; then
        DOMAIN=$(cat /tmp/bankapp-domain.txt)
        print_success "Using domain: $DOMAIN"
    else
        print_info "Enter your domain (e.g., bankapp.yourdomain.com):"
        read -p "Domain: " DOMAIN
        echo "$DOMAIN" > /tmp/bankapp-domain.txt
    fi
else
    print_step "Step 11: Waiting for DNS Propagation"
    print_info "Enter your domain (e.g., bankapp.yourdomain.com):"
    read -p "Domain: " DOMAIN
    echo "$DOMAIN" > /tmp/bankapp-domain.txt

    print_info "Checking DNS propagation (this may take 5-15 minutes)..."
    DNS_PROPAGATED=false
    for i in {1..30}; do
        echo -n "Attempt $i/30: "
        RESOLVED_IP=$(dig +short "$DOMAIN" @8.8.8.8 | head -n 1)
        if [ "$RESOLVED_IP" == "$LB_IP" ]; then
            print_success "DNS propagated! $DOMAIN resolves to $LB_IP"
            DNS_PROPAGATED=true
            break
        else
            echo "Not yet propagated (got: $RESOLVED_IP, expected: $LB_IP)"
            sleep 30
        fi
    done

    if [ "$DNS_PROPAGATED" = false ]; then
        print_error "DNS not fully propagated yet. You may need to wait longer."
        print_info "You can continue, but certificate issuance may take longer."
        wait_for_confirmation "Continue anyway?"
    fi

    # Verify across multiple DNS servers
    print_info "Verifying DNS across multiple servers..."
    echo "Google DNS (8.8.8.8): $(dig +short "$DOMAIN" @8.8.8.8)"
    echo "Cloudflare DNS (1.1.1.1): $(dig +short "$DOMAIN" @1.1.1.1)"
    echo "Quad9 DNS (9.9.9.9): $(dig +short "$DOMAIN" @9.9.9.9)"
    save_checkpoint 11
fi

# Step 12: Wait for Certificate Issuance
if is_step_completed 12; then
    print_info "Step 12 already completed, skipping certificate wait..."
else
    print_step "Step 12: Waiting for TLS Certificate Issuance"
    print_info "Monitoring certificate creation (this may take 1-2 minutes)..."

    # Restart cert-manager to clear any stale connections
    print_info "Restarting cert-manager for fresh connection..."
    kubectl delete pod -n cert-manager -l app.kubernetes.io/name=cert-manager
    wait_for_pods "cert-manager" "app.kubernetes.io/name=cert-manager" 60

    print_info "Waiting for certificate to be issued..."
    CERT_READY=false
    for i in {1..60}; do
        CERT_STATUS=$(kubectl get certificate bankapp-tls -n bankapp -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        if [ "$CERT_STATUS" == "True" ]; then
            print_success "Certificate issued successfully!"
            CERT_READY=true
            break
        fi
        echo -n "."
        sleep 5
    done
    echo ""

    if [ "$CERT_READY" = false ]; then
        print_error "Certificate not ready after 5 minutes. Attempting recovery..."
        
        # Check if challenge is stuck
        CHALLENGE_STATE=$(kubectl get challenge -n bankapp -o jsonpath='{.items[0].status.state}' 2>/dev/null || echo "")
        if [ "$CHALLENGE_STATE" == "pending" ]; then
            print_info "Challenge stuck in pending state. Recreating certificate..."
            kubectl delete certificate bankapp-tls -n bankapp
            sleep 5
            kubectl apply -f k8s/certificate.yml
            
            print_info "Waiting for new certificate issuance (30 seconds)..."
            sleep 30
            
            CERT_STATUS=$(kubectl get certificate bankapp-tls -n bankapp -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            if [ "$CERT_STATUS" == "True" ]; then
                print_success "Certificate issued successfully after retry!"
                CERT_READY=true
            else
                print_error "Certificate still not ready. Manual intervention may be required."
                kubectl describe certificate bankapp-tls -n bankapp
                kubectl get challenge -n bankapp
                print_info "You can re-run this script to retry from this step"
                exit 1
            fi
        else
            print_error "Certificate not ready. Checking status..."
            kubectl describe certificate bankapp-tls -n bankapp
            kubectl get challenge -n bankapp
            print_info "Certificate issuance may take longer. Check ArgoCD and cert-manager logs."
            print_info "You can re-run this script to retry from this step"
            exit 1
        fi
    fi

    # Trigger ArgoCD sync
    print_info "Triggering ArgoCD sync..."
    kubectl patch application bankapp -n argocd --type merge \
      -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

    sleep 30
    save_checkpoint 12
fi

# Step 13: Verify Application Access
if is_step_completed 13; then
    print_info "Step 13 already completed, skipping verification..."
else
    print_step "Step 13: Verifying Application Access"
    print_info "Testing HTTP endpoint..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://$DOMAIN/" || echo "000")
    echo "HTTP Response: $HTTP_CODE"

    print_info "Testing HTTPS endpoint..."
    HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$DOMAIN/" || echo "000")
    echo "HTTPS Response: $HTTPS_CODE"

    if [ "$HTTP_CODE" == "302" ] && [ "$HTTPS_CODE" == "302" ]; then
        print_success "Application is accessible!"
    else
        print_error "Application may not be fully ready. HTTP: $HTTP_CODE, HTTPS: $HTTPS_CODE"
    fi
    save_checkpoint 13
fi

# Step 14: Application Ready
print_step "Step 14: Application Deployed Successfully"
print_success "Your AI BankApp is now live!"
echo ""
echo "Application URL: https://$DOMAIN"
echo ""
save_checkpoint 14

# Step 15: Install Monitoring Stack
if is_step_completed 15; then
    print_info "Step 15 already completed, skipping monitoring installation..."
    INSTALL_MONITORING="n"
else
    print_step "Step 15: Installing kube-prometheus-stack (Optional)"
    read -p "Do you want to install monitoring stack (Grafana/Prometheus)? (y/n): " INSTALL_MONITORING

    if [ "$INSTALL_MONITORING" == "y" ] || [ "$INSTALL_MONITORING" == "Y" ]; then
        print_info "Adding Prometheus Helm repository..."
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
        helm repo update prometheus-community

        # Check if monitoring stack is already installed
        if helm list -n monitoring 2>/dev/null | grep -q "^kube-prometheus"; then
            print_info "Monitoring stack already installed, skipping..."
        else
            print_info "Installing kube-prometheus-stack (this takes 2-3 minutes)..."
            helm install kube-prometheus prometheus-community/kube-prometheus-stack \
              -n monitoring \
              --create-namespace \
              --set grafana.service.type=LoadBalancer \
              --timeout=10m
        fi

        wait_for_pods "monitoring" "release=kube-prometheus" 300

        # Step 16: Access Grafana
        print_step "Step 16: Grafana Dashboard Access"
        GRAFANA_URL=$(kubectl get svc kube-prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        GRAFANA_PASSWORD=$(kubectl get secret kube-prometheus-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)

        print_success "Monitoring stack installed!"
        echo ""
        echo "Grafana URL: http://$GRAFANA_URL"
        echo "Username: admin"
        echo "Password: $GRAFANA_PASSWORD"
        echo ""
        save_checkpoint 16
    else
        print_info "Skipping monitoring stack installation"
        save_checkpoint 15
    fi
fi

# Final Summary
print_step "Deployment Complete!"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Deployment Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "✅ Application: https://$DOMAIN"
echo "✅ LoadBalancer IP: $LB_IP"
echo ""
echo "ArgoCD Access:"
ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d)
echo "  URL: http://$ARGOCD_URL"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo ""

if [ "$INSTALL_MONITORING" == "y" ] || [ "$INSTALL_MONITORING" == "Y" ]; then
    echo "Grafana Access:"
    echo "  URL: http://$GRAFANA_URL"
    echo "  Username: admin"
    echo "  Password: $GRAFANA_PASSWORD"
    echo ""
fi

echo -e "${GREEN}========================================${NC}"
echo ""
print_success "All steps completed successfully! 🎉"
echo ""
print_info "Checkpoint saved. To start fresh, run: rm $CHECKPOINT_FILE"
