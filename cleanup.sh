#!/bin/bash

# AI BankApp - Complete Cleanup Script
# This script removes all Kubernetes resources deployed after terraform apply
# Run this before 'terraform destroy' to ensure clean infrastructure removal

set -e

echo "=========================================="
echo "AI BankApp - Complete Cleanup Script"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will delete all deployed resources!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to check if resource exists
resource_exists() {
    kubectl get "$1" "$2" -n "$3" &>/dev/null
}

echo ""
echo "=========================================="
echo "Step 1: Delete ArgoCD Application"
echo "=========================================="
if resource_exists "application" "bankapp" "argocd"; then
    kubectl delete -f argocd/application.yml --ignore-not-found=true
    print_status "ArgoCD application deleted"
    sleep 5
else
    print_warning "ArgoCD application not found, skipping"
fi

echo ""
echo "=========================================="
echo "Step 2: Delete Monitoring Stack"
echo "=========================================="
if helm list -n monitoring | grep -q "kube-prometheus"; then
    helm uninstall kube-prometheus -n monitoring
    print_status "kube-prometheus-stack uninstalled"
    sleep 10
else
    print_warning "kube-prometheus-stack not found, skipping"
fi

# Delete monitoring namespace
if kubectl get namespace monitoring &>/dev/null; then
    kubectl delete namespace monitoring --ignore-not-found=true
    print_status "Monitoring namespace deleted"
else
    print_warning "Monitoring namespace not found, skipping"
fi

echo ""
echo "=========================================="
echo "Step 3: Delete BankApp Resources"
echo "=========================================="
if kubectl get namespace bankapp &>/dev/null; then
    kubectl delete namespace bankapp --ignore-not-found=true
    print_status "BankApp namespace deleted"
    sleep 10
else
    print_warning "BankApp namespace not found, skipping"
fi

echo ""
echo "=========================================="
echo "Step 4: Delete cert-manager"
echo "=========================================="
if kubectl get namespace cert-manager &>/dev/null; then
    # Delete cert-manager resources
    kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml --ignore-not-found=true
    print_status "cert-manager deleted"
    sleep 10
else
    print_warning "cert-manager not found, skipping"
fi

echo ""
echo "=========================================="
echo "Step 5: Delete Envoy Gateway"
echo "=========================================="
if helm list -n envoy-gateway-system | grep -q "eg"; then
    helm uninstall eg -n envoy-gateway-system
    print_status "Envoy Gateway uninstalled"
    sleep 10
else
    print_warning "Envoy Gateway not found, skipping"
fi

# Delete envoy-gateway-system namespace
if kubectl get namespace envoy-gateway-system &>/dev/null; then
    kubectl delete namespace envoy-gateway-system --ignore-not-found=true
    print_status "Envoy Gateway namespace deleted"
fi

echo ""
echo "=========================================="
echo "Step 6: Delete Gateway API CRDs"
echo "=========================================="
if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
    kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml --ignore-not-found=true
    print_status "Gateway API CRDs deleted"
    sleep 5
else
    print_warning "Gateway API CRDs not found, skipping"
fi

echo ""
echo "=========================================="
echo "Step 7: Wait for LoadBalancers to Terminate"
echo "=========================================="
print_warning "Waiting 60 seconds for AWS LoadBalancers to terminate..."
sleep 60

echo ""
echo "=========================================="
echo "Step 8: Verify LoadBalancers Cleanup"
echo "=========================================="
echo "Checking for remaining LoadBalancers in us-west-2..."
LBS=$(aws elbv2 describe-load-balancers --region us-west-2 --query 'LoadBalancers[*].LoadBalancerName' --output text 2>/dev/null || echo "")

if [ -z "$LBS" ]; then
    print_status "No LoadBalancers found"
else
    print_warning "Found LoadBalancers: $LBS"
    print_warning "Waiting additional 30 seconds..."
    sleep 30
fi

echo ""
echo "=========================================="
echo "Step 9: Cleanup Complete"
echo "=========================================="
print_status "All Kubernetes resources have been cleaned up"
echo ""
echo "You can now safely run:"
echo "  cd terraform"
echo "  terraform destroy -auto-approve"
echo ""

# Optional: Check for orphaned resources
echo "=========================================="
echo "Checking for Orphaned Resources"
echo "=========================================="

# Check for remaining namespaces
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[?(@.metadata.name!="default" && @.metadata.name!="kube-system" && @.metadata.name!="kube-public" && @.metadata.name!="kube-node-lease" && @.metadata.name!="argocd")].metadata.name}')
if [ -n "$NAMESPACES" ]; then
    print_warning "Found additional namespaces: $NAMESPACES"
else
    print_status "No orphaned namespaces found"
fi

# Check for remaining PVCs
PVCS=$(kubectl get pvc --all-namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$PVCS" ]; then
    print_warning "Found PVCs: $PVCS"
else
    print_status "No orphaned PVCs found"
fi

# Check for remaining PVs
PVS=$(kubectl get pv -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$PVS" ]; then
    print_warning "Found PVs: $PVS"
else
    print_status "No orphaned PVs found"
fi

echo ""
echo "=========================================="
echo "Step 10: Delete Checkpoint Files"
echo "=========================================="
# Delete checkpoint files so deployment scripts start fresh
CHECKPOINT_FILES_DELETED=0

if [ -f "/tmp/bankapp-deploy-checkpoint.txt" ]; then
    rm -f /tmp/bankapp-deploy-checkpoint.txt
    print_status "Deleted deploy-bankapp.sh checkpoint"
    CHECKPOINT_FILES_DELETED=$((CHECKPOINT_FILES_DELETED + 1))
else
    print_warning "deploy-bankapp.sh checkpoint not found (already clean)"
fi

if [ -f "/tmp/bankapp-test-deploy-checkpoint.txt" ]; then
    rm -f /tmp/bankapp-test-deploy-checkpoint.txt
    print_status "Deleted deploy-test.sh checkpoint"
    CHECKPOINT_FILES_DELETED=$((CHECKPOINT_FILES_DELETED + 1))
else
    print_warning "deploy-test.sh checkpoint not found (already clean)"
fi

if [ -f "/tmp/bankapp-production-deploy-checkpoint.txt" ]; then
    rm -f /tmp/bankapp-production-deploy-checkpoint.txt
    print_status "Deleted deploy-production.sh checkpoint"
    CHECKPOINT_FILES_DELETED=$((CHECKPOINT_FILES_DELETED + 1))
else
    print_warning "deploy-production.sh checkpoint not found (already clean)"
fi

if [ -f "/tmp/bankapp-domain.txt" ]; then
    rm -f /tmp/bankapp-domain.txt
    print_status "Deleted domain cache file"
    CHECKPOINT_FILES_DELETED=$((CHECKPOINT_FILES_DELETED + 1))
else
    print_warning "Domain cache file not found (already clean)"
fi

if [ $CHECKPOINT_FILES_DELETED -eq 0 ]; then
    print_status "No checkpoint files found - system already clean"
else
    print_status "Deleted $CHECKPOINT_FILES_DELETED checkpoint file(s)"
fi

echo ""
echo "=========================================="
echo "✅ Cleanup Script Complete!"
echo "=========================================="
echo ""
print_status "All checkpoint files deleted - deployment scripts will start fresh"
