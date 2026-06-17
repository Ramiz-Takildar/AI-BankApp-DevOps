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

# Step 5: Update test configuration
print_step "Step 5: Configuring Test Domain"
print_info "Test domain: $TEST_DOMAIN"

# Create temporary test certificate
cat > /tmp/test-certificate.yml << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: bankapp-tls
  namespace: bankapp
spec:
  secretName: bankapp-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
    - $TEST_DOMAIN
EOF

# Create temporary test gateway
cat > /tmp/test-gateway.yml << EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: bankapp-gateway
  namespace: bankapp
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      hostname: $TEST_DOMAIN
      tls:
        mode: Terminate
        certificateRefs:
          - group: ""
            kind: Secret
            name: bankapp-tls
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: bankapp-route
  namespace: bankapp
spec:
  hostnames:
    - $TEST_DOMAIN
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: bankapp-gateway
      sectionName: https
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: bankapp-gateway
      sectionName: http
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - group: ""
          kind: Service
          name: bankapp-service
          port: 8080
          weight: 1
EOF

print_success "Test configuration created"

# Step 6: Deploy via ArgoCD or kubectl
print_step "Step 6: Deploying Application"
if kubectl get application bankapp -n argocd >/dev/null 2>&1; then
    print_info "Using ArgoCD deployment..."
    kubectl patch application bankapp -n argocd --type merge \
      -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
    sleep 30
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

# Step 7: Apply test gateway and certificate
print_step "Step 7: Applying Test Gateway and Certificate"
kubectl apply -f /tmp/test-gateway.yml
kubectl apply -f /tmp/test-certificate.yml
print_success "Test resources applied"

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
print_step "Step 9: Configure DNS A Record"
echo ""
echo -e "${YELLOW}=================================================${NC}"
echo -e "${YELLOW}ACTION REQUIRED: Configure DNS A Record${NC}"
echo -e "${YELLOW}=================================================${NC}"
echo ""
echo -e "${GREEN}Domain:${NC} $TEST_DOMAIN"
echo -e "${GREEN}LoadBalancer IP:${NC} ${BLUE}$LB_IP${NC}"
echo ""
echo "In your DNS provider, create:"
echo -e "  Type: ${GREEN}A${NC}"
echo -e "  Name: ${GREEN}test${NC}"
echo -e "  Value: ${BLUE}$LB_IP${NC}"
echo -e "  TTL: ${GREEN}300${NC}"
echo ""
read -p "Press Enter after configuring DNS..."

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
print_warning "Browser will show security warning - this is expected!"
print_warning "Click 'Advanced' and 'Proceed' to access the application"
echo ""
print_success "Test deployment successful! 🎉"
echo ""
print_info "To clean up: kubectl delete certificate,gateway,httproute -n bankapp --all"
print_info "To reset: rm $CHECKPOINT_FILE"
