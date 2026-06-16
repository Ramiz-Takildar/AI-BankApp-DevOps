# AI BankApp Deployment Guide - Production Ready (2026)

**Based on actual successful deployment session - June 2026**

This guide documents the exact steps used to successfully deploy AI BankApp on AWS EKS with ArgoCD GitOps.

---

## 📋 Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5.7
- kubectl installed
- Helm 3 installed
- Docker with buildx support
- DockerHub account
- Domain name with DNS management access

---

## 🚀 Deployment Steps

### 1️⃣ Provision AWS Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

**What gets created:**
- VPC with public/private subnets (3 AZs)
- EKS cluster with 8 x t3.small nodes
- EBS CSI driver
- ArgoCD pre-installed

**Time:** ~15 minutes

### 2️⃣ Configure kubectl Access

```bash
aws eks update-kubeconfig --name bankapp-eks --region us-west-2
kubectl get nodes
```

Expected: 8 nodes in Ready state

### 3️⃣ Install Gateway API CRDs

```bash
kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

kubectl get crd | grep gateway
```

**Critical:** Use `--server-side` to avoid conflicts

### 4️⃣ Install Envoy Gateway

```bash
# Install Envoy Gateway (skip Gateway API CRDs, no --wait to avoid hanging)
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.2.6 \
  -n envoy-gateway-system \
  --create-namespace \
  --skip-crds

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=gateway-helm \
  -n envoy-gateway-system --timeout=60s

# Create GatewayClass resource
cat > /tmp/gatewayclass.yaml << 'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
kubectl apply -f /tmp/gatewayclass.yaml

# Verify installation
kubectl get pods -n envoy-gateway-system
kubectl get gatewayclass eg
```

**Expected Output:**
- Pod `envoy-gateway-*` should be Running
- GatewayClass `eg` should show `Accepted: True`

### 5️⃣ Install cert-manager

```bash
# Install cert-manager using kubectl (Helm has hanging issues)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager --timeout=60s

# Verify installation
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager
```

**Expected Output:**
- All 3 pods (cert-manager, cainjector, webhook) should be Running
- 6 CRDs should be installed

### 6️⃣ Update Kubernetes Manifests

**⚠️ Do this BEFORE building the Docker image!**

**File: k8s/bankapp-deployment.yml**
```yaml
# Change image line to:
image: YOUR_DOCKERHUB_USERNAME/ai-bankapp-eks:latest
```

**File: k8s/gateway.yml**
```yaml
# Change hostname to your domain:
hostname: bankapp.yourdomain.com
```

**Commit and push:**
```bash
git add k8s/bankapp-deployment.yml k8s/gateway.yml
git commit -m "Update image and domain configuration"
git push origin feat/gitops
```

### 7️⃣ Build and Push Docker Image

**⚠️ CRITICAL for Apple Silicon (M1/M2/M3):**

```bash
# Navigate to project root
cd /path/to/AI-BankApp-DevOps

# Build for amd64 architecture (EKS nodes are amd64)
# Use the SAME image name you specified in Step 6
docker buildx build --platform linux/amd64 \
  -t YOUR_DOCKERHUB_USERNAME/ai-bankapp-eks:latest \
  --push .
```

**Example:**
```bash
docker buildx build --platform linux/amd64 \
  -t ramiztakildar/ai-bankapp-eks:latest \
  --push .
```

**Verify image was pushed:**
```bash
docker pull YOUR_DOCKERHUB_USERNAME/ai-bankapp-eks:latest
```

### 8️⃣ Deploy via ArgoCD

```bash
# Apply ArgoCD application from project root
kubectl apply -f argocd/application.yml

# Watch deployment progress
kubectl get application bankapp -n argocd -w
```

**Expected Status:**
- SYNC STATUS: **Synced** ✅
- HEALTH STATUS: **Degraded** ⚠️ (This is NORMAL at this stage)

**Why "Degraded"?**
The Gateway's HTTPS listener will show: `Secret bankapp/bankapp-tls does not exist`

This is **expected behavior** because:
- ✅ HTTP listener (port 80) is working
- ✅ All bankapp pods are Running
- ⚠️ TLS certificate hasn't been issued yet (requires DNS configuration first)

The health status will automatically change to **Healthy** after:
1. DNS A record is configured (Step 10)
2. DNS propagates (Step 11)
3. cert-manager issues the TLS certificate
4. Secret `bankapp/bankapp-tls` is created

**Continue to next step** - the application is ready for DNS configuration!

### 9️⃣ Get LoadBalancer IP Address

```bash
# Get LoadBalancer hostname
kubectl get gateway bankapp-gateway -n bankapp \
  -o jsonpath='{.status.addresses[0].value}'

# Example output: a5f49b68eaa524ebfb2b43c72f775e43-1422997363.us-west-2.elb.amazonaws.com

# Resolve to IP addresses
dig +short <LOADBALANCER_HOSTNAME>

# Example output:
# 44.232.219.193  ← Use this PRIMARY IP
# 54.191.22.131
```

**⚠️ IMPORTANT:** AWS NLB returns multiple IPs. Always use the **FIRST IP** (primary) for DNS configuration.

### 🔟 Configure DNS A Record

In your DNS provider (GoDaddy, Cloudflare, Route53, etc.):

**Create A Record:**
- **Type:** A
- **Name:** bankapp (or your subdomain)
- **Value:** `44.232.219.193` (your primary LoadBalancer IP)
- **TTL:** 300 (5 minutes)

**Example Configuration:**
```
Type: A
Name: bankapp.aicloudops.in
Value: 44.232.219.193
TTL: 300
```

### 1️⃣1️⃣ Wait for DNS Propagation

DNS propagation takes 5-15 minutes. Monitor:

```bash
# Check from Google DNS
dig +short bankapp.yourdomain.com @8.8.8.8

# Check from Cloudflare DNS
dig +short bankapp.yourdomain.com @1.1.1.1

# Check from Quad9 DNS
dig +short bankapp.yourdomain.com @9.9.9.9
```

All should return your LoadBalancer IP.

### 1️⃣2️⃣ Verify Application Access

```bash
# Test HTTP response
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://bankapp.yourdomain.com/

# Expected: HTTP 302 (redirect to /login)

# Verbose test
curl -v http://bankapp.yourdomain.com/
```

**Expected Response:**
```
HTTP/1.1 302 Found
location: http://bankapp.yourdomain.com/login
```

### 1️⃣3️⃣ Access Your Application

Open browser: `http://bankapp.yourdomain.com`

You should see the login page! 🎉

---

## 🔍 Verification Checklist

```bash
# Check all pods are Running
kubectl get pods -n bankapp

# Check Gateway status
kubectl get gateway -n bankapp

# Check HTTPRoute
kubectl get httproute -n bankapp

# Check ArgoCD application
kubectl get application bankapp -n argocd
```

**Success Criteria:**
- ✅ 3 bankapp pods in Running state
- ✅ Gateway has LoadBalancer address
- ✅ DNS resolves to correct IP
- ✅ Application returns HTTP 302
- ✅ Login page accessible

---

## 🐛 Troubleshooting

### Issue 1: DNS Cache Shows Old IP

**Symptom:** Browser shows 404, but `dig @8.8.8.8` shows correct IP

**Cause:** Local DNS cache stuck on old IP

**Solution:**

**Mac:**
```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

**Windows:**
```cmd
ipconfig /flushdns
```

**Linux:**
```bash
sudo systemd-resolve --flush-caches
```

**Temporary Fix (add to /etc/hosts):**
```
44.232.219.193 bankapp.yourdomain.com
```

### Issue 2: ImagePullBackOff Error

**Symptom:** Pods show `ImagePullBackOff` or `ErrImagePull`

**Causes & Solutions:**

1. **Image doesn't exist on DockerHub**
   - Verify: `docker pull YOUR_USERNAME/ai-bankapp-eks:latest`

2. **Wrong architecture (Apple Silicon)**
   - Rebuild with: `--platform linux/amd64`

3. **Wrong image name in manifest**
   - Check `k8s/bankapp-deployment.yml` matches DockerHub

### Issue 3: Application Returns 404

**Symptom:** Domain returns 404 Not Found

**Causes & Solutions:**

1. **Wrong DNS IP**
   ```bash
   dig +short bankapp.yourdomain.com
   # Should match LoadBalancer primary IP
   ```

2. **HTTPRoute not configured**
   ```bash
   kubectl get httproute -n bankapp
   kubectl describe httproute bankapp-route -n bankapp
   ```

3. **Gateway not ready**
   ```bash
   kubectl describe gateway bankapp-gateway -n bankapp
   ```

### Issue 4: Envoy Gateway Installation Stuck

**Symptom:** Helm install hangs with `--wait` flag, or shows `STATUS: pending-install`

**Cause:** The `--wait` flag can cause Helm to hang indefinitely waiting for resources

**Solution:**
```bash
# 1. Uninstall stuck release
helm uninstall eg -n envoy-gateway-system

# 2. Reinstall without --wait flag
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.2.6 \
  -n envoy-gateway-system \
  --create-namespace \
  --skip-crds

# 3. Wait for pod manually
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=gateway-helm \
  -n envoy-gateway-system --timeout=60s

# 4. Create GatewayClass if missing
cat > /tmp/gatewayclass.yaml << 'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
kubectl apply -f /tmp/gatewayclass.yaml

# 5. Verify
kubectl get gatewayclass eg
```

### Issue 5: cert-manager Installation Stuck

**Symptom:** Helm install hangs with `--wait` flag, or shows `STATUS: pending-install`

**Cause:** Helm `--wait` flag can hang indefinitely, similar to Envoy Gateway issue

**Solution:**
```bash
# 1. Clean up stuck installation
helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager

# 2. Use kubectl apply instead of Helm
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml

# 3. Wait for pods manually
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager \
  -n cert-manager --timeout=60s

# 4. Verify
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager
```

### Issue 6: Certificate Not Issuing

**Symptom:** `kubectl get certificate -n bankapp` shows `Ready: False`

**Solution:**
```bash
# Check certificate status
kubectl describe certificate bankapp-tls -n bankapp

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Verify DNS propagated
dig +short bankapp.yourdomain.com @8.8.8.8
```

---

## 🧹 Cleanup (Destroy Everything)

**⚠️ ORDER MATTERS!** Delete Helm resources before Terraform.

```bash
# 1. Delete ArgoCD application
kubectl delete -f argocd/application.yml

# 2. Uninstall Helm releases
helm uninstall cert-manager -n cert-manager
helm uninstall eg -n envoy-gateway-system

# 3. Delete Gateway API CRDs
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# 4. Wait for LoadBalancers to terminate
echo "Waiting 60 seconds for AWS resources to clean up..."
sleep 60

# 5. Verify no LoadBalancers remain
aws elbv2 describe-load-balancers --region us-west-2 \
  --query 'LoadBalancers[*].LoadBalancerName'

# 6. Destroy Terraform infrastructure
cd terraform
terraform destroy -auto-approve
```

**If VPC deletion fails:**
```bash
# Find orphaned security groups
aws ec2 describe-security-groups --region us-west-2 \
  --filters Name=vpc-id,Values=<VPC_ID> \
  --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]'

# Delete them
aws ec2 delete-security-group --group-id <SG_ID> --region us-west-2

# Delete VPC
aws ec2 delete-vpc --vpc-id <VPC_ID> --region us-west-2

# Re-run terraform destroy
terraform destroy -auto-approve
```

---

## 📝 Key Learnings from This Deployment

### What Changed from Original Guide:

1. **Removed Ollama** - t3.small nodes insufficient memory (2Gi requirement)
2. **Custom Docker Image** - Using `ramiztakildar/ai-bankapp-eks:latest`
3. **Domain** - Using `bankapp.aicloudops.in`
4. **DNS Type** - A record (not CNAME) pointing to LoadBalancer IP
5. **Node Count** - 8 x t3.small nodes

### Critical Notes:

- **Platform Architecture:** Always use `--platform linux/amd64` on Apple Silicon
- **DNS Propagation:** Takes 5-15 minutes; use `dig @8.8.8.8` to check
- **LoadBalancer IPs:** AWS NLB has multiple IPs; use PRIMARY (first) for DNS
- **HTTPRoute Security:** Only accepts requests with correct Host header
- **Session Affinity:** BackendTrafficPolicy prevents login redirect loops

---

## 📊 Access Summary

| Service | Command to Get URL | Credentials |
|---------|-------------------|-------------|
| **BankApp** | `http://bankapp.yourdomain.com` | App-specific |
| **ArgoCD** | `kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` | admin / (Step 3) |

---

## ✅ Final Success Criteria

- ✅ All pods in `bankapp` namespace Running
- ✅ Gateway has LoadBalancer address assigned
- ✅ DNS resolves to correct LoadBalancer IP
- ✅ Application accessible at domain
- ✅ Login page loads (HTTP 302 redirect)
- ✅ ArgoCD shows "Healthy" and "Synced"

---

**🎉 Deployment Complete!**

Your AI BankApp is now running on AWS EKS with GitOps-based continuous deployment via ArgoCD.

**Deployed Configuration:**
- Infrastructure: AWS EKS (8 x t3.small)
- Image: ramiztakildar/ai-bankapp-eks:latest
- Domain: bankapp.aicloudops.in
- Gateway: Envoy Gateway with Gateway API
- TLS: cert-manager with Let's Encrypt
- GitOps: ArgoCD

---

*Last Updated: June 15, 2026*
*Based on actual production deployment session*
