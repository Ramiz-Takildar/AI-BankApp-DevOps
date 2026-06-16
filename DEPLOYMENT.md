# AI BankApp Deployment Guide - EKS with ArgoCD GitOps

Complete step-by-step guide based on actual deployment session. Follow in order for successful deployment.

## Prerequisites
- AWS CLI configured
- Terraform >= 1.5.7
- kubectl, Helm 3, Docker
- DockerHub account
- Domain with DNS access

## Quick Start Summary
1. Provision infrastructure (terraform apply)
2. Install Gateway API + Envoy Gateway
3. Install cert-manager
4. Build & push Docker image
5. Update k8s manifests with your image/domain
6. Deploy via ArgoCD
7. Configure DNS A record with LoadBalancer IP
8. Access application

## Detailed Steps

### Step 1: Provision Infrastructure
```bash
cd terraform
terraform init && terraform apply -auto-approve
aws eks update-kubeconfig --name bankapp-eks --region us-west-2
kubectl get nodes  # Verify 8 nodes Ready
```

### Step 2: Install Gateway API CRDs
```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

### Step 3: Install Envoy Gateway
```bash
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.2.6 -n envoy-gateway-system --create-namespace --skip-crds --wait
helm pull oci://docker.io/envoyproxy/gateway-helm --version v1.2.6 --untar -d /tmp/eg-chart
kubectl apply --server-side -f /tmp/eg-chart/gateway-helm/crds/generated/
kubectl rollout restart deployment envoy-gateway -n envoy-gateway-system
```

### Step 4: Install cert-manager
```bash
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true --set config.enableGatewayAPI=true --wait
```

### Step 5: Build Docker Image
```bash
docker buildx build --platform linux/amd64 -t YOUR_DOCKERHUB_USERNAME/ai-bankapp-eks:latest --push .
```

### Step 6: Update Manifests
Edit k8s/bankapp-deployment.yml - change image to your DockerHub image
Edit k8s/gateway.yml - change hostname to your domain
Commit and push to feat/gitops branch

### Step 7: Deploy via ArgoCD
```bash
kubectl apply -f argocd/application.yml
kubectl get application bankapp -n argocd -w
```

### Step 8: Get LoadBalancer IP
```bash
kubectl get gateway bankapp-gateway -n bankapp -o jsonpath='{.status.addresses[0].value}'
dig +short LOADBALANCER_HOSTNAME
```
Use FIRST IP for DNS configuration

### Step 9: Configure DNS
Create A record in your DNS provider:
- Type: A
- Name: bankapp.yourdomain.com
- Value: PRIMARY_LOADBALANCER_IP
- TTL: 300

### Step 10: Verify
```bash
dig +short bankapp.yourdomain.com @8.8.8.8
curl -v http://bankapp.yourdomain.com/
```

## Troubleshooting

### DNS Cache Issue
If browser shows 404 but dig shows correct IP:
```bash
# Mac
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
# Windows
ipconfig /flushdns
# Or add to /etc/hosts temporarily
LOADBALANCER_IP bankapp.yourdomain.com
```

### ImagePullBackOff
- Verify image exists on DockerHub
- If Apple Silicon, rebuild with --platform linux/amd64

## Cleanup
```bash
kubectl delete -f argocd/application.yml
helm uninstall cert-manager -n cert-manager
helm uninstall eg -n envoy-gateway-system
sleep 60
cd terraform && terraform destroy -auto-approve
```

## Key Notes
- Always use --platform linux/amd64 for Docker builds on Apple Silicon
- DNS propagation takes 5-15 minutes
- AWS NLB has multiple IPs - use primary (first) for DNS
- HTTPRoute only accepts requests with correct Host header
- Removed Ollama due to t3.small memory constraints

## Success Criteria
✅ 3 bankapp pods Running
✅ Gateway has LoadBalancer address
✅ DNS resolves to correct IP
✅ Application accessible at domain
✅ Login page loads (HTTP 302)
