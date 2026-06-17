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
print_step "Step 4: Applying PRODUCTION ClusterIssuer"
kubectl apply -f k8s/cert-manager.yml
print_success "Production ClusterIssuer applied"

# Step 5: Update production configuration
print_step "Step 5: Configuring Production Domain"
print_info "Production domain: $PROD_DOMAIN"

# Create temporary production certificate
cat > /tmp/prod-certificate.yml << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: bankapp-tls
  namespace: bankapp
spec:
  secretName: bankapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - $PROD_DOMAIN
EOF

# Create temporary production gateway
cat > /tmp/prod-gateway.yml << EOF
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
      hostname: $PROD_DOMAIN
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
    - $PROD_DOMAIN
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
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: bankapp-session
  namespace: bankapp
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: bankapp-route
  loadBalancer:
    type: ConsistentHash
    consistentHash:
      type: Cookie
      cookie:
        name: BANKAPP_AFFINITY
        ttl: 3600s
EOF

print_success "Production configuration created"

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

# Step 7: Apply production gateway and certificate
print_step "Step 7: Applying Production Gateway and Certificate"
kubectl apply -f /tmp/prod-gateway.yml
kubectl apply -f /tmp/prod-certificate.yml
print_success "Production resources applied"

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
echo -e "${GREEN}Domain:${NC} $PROD_DOMAIN"
echo -e "${GREEN}LoadBalancer IP:${NC} ${BLUE}$LB_IP${NC}"
echo ""
echo "In your DNS provider, create:"
echo -e "  Type: ${GREEN}A${NC}"
echo -e "  Name: ${GREEN}aibankapp${NC}"
echo -e "  Value: ${BLUE}$LB_IP${NC}"
echo -e "  TTL: ${GREEN}300${NC}"
echo ""
read -p "Press Enter after configuring DNS..."

# Step 10: Wait for DNS
print_step "Step 10: Waiting for DNS Propagation"
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

# Step 11: Wait for Certificate
print_step "Step 11: Waiting for PRODUCTION Certificate"
print_warning "This uses your rate limit quota (5 per week)"
print_info "Monitoring certificate (1-2 minutes)..."

CERT_READY=false
RATE_LIMITED=false
for i in {1..60}; do
    CERT_STATUS=$(kubectl get certificate bankapp-tls -n bankapp -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$CERT_STATUS" == "True" ]; then
        print_success "PRODUCTION certificate issued!"
        CERT_READY=true
        break
    fi
    
    # Check for rate limit
    CERT_MESSAGE=$(kubectl get certificate bankapp-tls -n bankapp -o jsonpath='{.status.conditions[?(@.type=="Issuing")].message}' 2>/dev/null || echo "")
    if echo "$CERT_MESSAGE" | grep -qi "rateLimited\|429.*too many certificates"; then
        RATE_LIMITED=true
        RETRY_AFTER=$(echo "$CERT_MESSAGE" | grep -Eo 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | sed 's/retry after //')
        break
    fi
    
    echo -n "."
    sleep 5
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

# Step 12: Verify Application
print_step "Step 12: Verifying Application Access"
print_info "Testing HTTPS endpoint..."
sleep 10
HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$PROD_DOMAIN/" || echo "000")
echo "HTTPS Response: $HTTPS_CODE"

if [ "$HTTPS_CODE" == "302" ] || [ "$HTTPS_CODE" == "200" ]; then
    print_success "Application is accessible!"
else
    print_warning "Application may not be fully ready yet (got $HTTPS_CODE)"
fi

# Final Summary
print_step "PRODUCTION Deployment Complete!"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Production Deployment Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "✅ Production URL: https://$PROD_DOMAIN"
echo -e "✅ LoadBalancer IP: $LB_IP"
echo -e "✅ Certificate: PRODUCTION (trusted)"
echo ""

# Check remaining quota
CERT_EVENTS=$(kubectl describe certificate bankapp-tls -n bankapp 2>/dev/null | grep -c "Successfully issued" || echo "1")
REMAINING=$((5 - CERT_EVENTS))
echo -e "${YELLOW}Rate Limit Status:${NC}"
echo -e "  Used: $CERT_EVENTS/5 certificates"
echo -e "  Remaining: $REMAINING certificates"
echo ""

print_success "Production deployment successful! 🎉"
echo ""
print_info "Monitor: kubectl get certificate,gateway,httproute -n bankapp"
print_info "To reset: rm $CHECKPOINT_FILE"
