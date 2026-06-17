# AI BankApp Deployment Scripts Guide

## Overview

Two separate deployment scripts are provided to handle different deployment scenarios:

1. **`deploy-test.sh`** - For testing and development (NO rate limits)
2. **`deploy-production.sh`** - For production deployment (Rate limited)

## 📋 Scripts Comparison

| Feature | deploy-test.sh | deploy-production.sh |
|---------|----------------|---------------------|
| **Domain** | test.aicloudops.in | aibankapp.aicloudops.in |
| **Certificate** | Let's Encrypt STAGING | Let's Encrypt PRODUCTION |
| **Trust Level** | Untrusted (browser warnings) | Trusted (no warnings) |
| **Rate Limit** | 30,000/week (unlimited) | 5/week per domain |
| **Use Case** | Testing, development, demos | Final production deployment |
| **Browser Warning** | ⚠️ Yes | ✅ No |

## 🧪 Test Deployment (deploy-test.sh)

### When to Use:
- Testing new configurations
- Development and debugging
- Learning and experimentation
- Demo environments
- CI/CD pipeline testing

### Features:
- Uses Let's Encrypt **STAGING** environment
- Issues **UNTRUSTED** certificates (browser warnings expected)
- **NO rate limits** - deploy as many times as needed
- Domain: `test.aicloudops.in`
- **Auto-retry logic** - Automatically retries failed certificate orders (max 2 attempts)
- **Checkpoint system** - Resume from last successful step if interrupted
- **Enhanced formatting** - Professional output with icons and color coding

### Usage:
```bash
./deploy-test.sh
```

### What to Expect:
1. ✅ Fast deployment (1-2 minutes for certificate)
2. ⚠️ Browser security warning (click "Advanced" → "Proceed")
3. ✅ Full functionality testing
4. ✅ No impact on production quota

### DNS Configuration:
The script will display clear DNS configuration instructions:
```
Create A Record:

  Type:  A
  Name:  test
  Value: [LoadBalancer IP] (your LoadBalancer IP)
  TTL:   300 (5 minutes)

Example Configuration:

  Type:  A
  Name:  test.aicloudops.in
  Value: [LoadBalancer IP]
  TTL:   300
```

## 🚀 Production Deployment (deploy-production.sh)

### When to Use:
- **ONLY** for final production deployment
- After successful testing with deploy-test.sh
- When you need trusted certificates
- For public-facing applications

### Features:
- Uses Let's Encrypt **PRODUCTION** environment
- Issues **TRUSTED** certificates (no browser warnings)
- **Rate Limited:** 5 certificates per week per domain
- Domain: `aibankapp.aicloudops.in`
- Requires confirmation before proceeding
- **Auto-retry logic** - Automatically retries failed certificate orders (max 2 attempts)
- **Rate limit detection** - Warns if rate limit is hit with retry time
- **Checkpoint system** - Resume from last successful step if interrupted
- **Enhanced formatting** - Professional output with icons and color coding

### Usage:
```bash
./deploy-production.sh
```

### What to Expect:
1. ⚠️ Confirmation prompt (type "yes" to proceed)
2. ✅ Trusted certificate issuance (1-2 minutes)
3. ✅ No browser warnings
4. ✅ Production-ready deployment

### DNS Configuration:
The script will display clear DNS configuration instructions:
```
Create A Record:

  Type:  A
  Name:  aibankapp
  Value: [LoadBalancer IP] (your LoadBalancer IP)
  TTL:   300 (5 minutes)

Example Configuration:

  Type:  A
  Name:  aibankapp.aicloudops.in
  Value: [LoadBalancer IP]
  TTL:   300
```

## 🔄 Recommended Workflow

### Step 1: Test First
```bash
# Always start with testing
./deploy-test.sh

# Configure DNS for test.aicloudops.in
# Test thoroughly with browser warnings
# Verify all functionality works
```

### Step 2: Deploy to Production
```bash
# Only after successful testing
./deploy-production.sh

# Configure DNS for aibankapp.aicloudops.in
# Verify trusted certificate
# Monitor application
```

## 📊 Rate Limit Management

### Test Environment (test.aicloudops.in)
- **Limit:** 30,000 certificates/week
- **Current Usage:** 0/30,000
- **Status:** ✅ Unlimited for practical purposes

### Production Environment (aibankapp.aicloudops.in)
- **Limit:** 5 certificates/week
- **Current Usage:** 0/5
- **Status:** ✅ Available for production

### Current Domains Status
- `bankapp.aicloudops.in` - Rate limited until June 18, 2026 4:19 PM IST
- `bankapp2.aicloudops.in` - 1/5 used, 4 remaining
- `test.aicloudops.in` - Unlimited (staging)
- `aibankapp.aicloudops.in` - 0/5 used (ready for production)

## 🛠️ Troubleshooting

### Test Deployment Issues

**Certificate not issued:**
```bash
# Check certificate status
kubectl describe certificate bankapp-tls -n bankapp

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

**DNS not propagating:**
```bash
# Check DNS from multiple servers
dig +short test.aicloudops.in @8.8.8.8
dig +short test.aicloudops.in @1.1.1.1
```

### Production Deployment Issues

**Rate limit hit:**
- Wait until rate limit expires (shown in error message)
- Use deploy-test.sh with different subdomain for testing
- Check current usage: `kubectl describe certificate bankapp-tls -n bankapp`

**Certificate validation failed:**
- Verify DNS is fully propagated
- Check Gateway configuration
- Ensure HTTP port 80 is accessible for ACME challenge

## 🔧 Advanced Usage

### Complete Cleanup (Recommended)
Use the automated cleanup script that removes all resources AND checkpoint files:
```bash
./cleanup.sh
```

**What cleanup.sh does:**
- Deletes ArgoCD application
- Removes monitoring stack
- Deletes BankApp namespace
- Removes cert-manager
- Uninstalls Envoy Gateway
- Deletes Gateway API CRDs
- **Deletes all checkpoint files** (ensures fresh deployment)
- Waits for LoadBalancers to terminate
- Verifies cleanup completion

After running cleanup.sh, deployment scripts will start fresh from Step 1.

### Manual Cleanup (Alternative)
```bash
# Clean up test deployment
kubectl delete certificate,gateway,httproute -n bankapp --all
rm /tmp/bankapp-test-deploy-checkpoint.txt

# Clean up production deployment
kubectl delete certificate,gateway,httproute -n bankapp --all
rm /tmp/bankapp-production-deploy-checkpoint.txt
```

### Resume from Checkpoint
Both scripts support checkpoints. If deployment fails, simply re-run the script:
```bash
./deploy-test.sh      # Resumes from last successful step
./deploy-production.sh # Resumes from last successful step
```

### Force Fresh Deployment
```bash
# Remove checkpoint file to start fresh
rm /tmp/bankapp-test-deploy-checkpoint.txt
rm /tmp/bankapp-prod-deploy-checkpoint.txt
```

## 📝 Best Practices

1. **Always test first** - Use deploy-test.sh before production
2. **Verify DNS** - Ensure DNS propagates before certificate issuance
3. **Monitor rate limits** - Check certificate events regularly
4. **Use staging for CI/CD** - Integrate deploy-test.sh in pipelines
5. **Document changes** - Keep track of deployments and configurations
6. **Backup certificates** - Export production certificates for disaster recovery

## 🔐 Security Notes

- Test certificates are **NOT** trusted by browsers
- Production certificates are **fully trusted**
- Both use the same ACME HTTP-01 challenge validation
- Gateway API handles TLS termination
- Certificates auto-renew at 2/3 of lifetime (60 days before expiry)

## 📞 Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review kubectl logs for cert-manager and envoy-gateway
3. Verify DNS configuration in your provider
4. Check ArgoCD sync status if using GitOps

## 🎯 Quick Reference

```bash
# Test deployment (unlimited)
./deploy-test.sh
# Domain: test.aicloudops.in
# Certificate: Untrusted (staging)

# Production deployment (5/week limit)
./deploy-production.sh
# Domain: aibankapp.aicloudops.in
# Certificate: Trusted (production)

# Check certificate status
kubectl get certificate -n bankapp

# Monitor deployment
kubectl get gateway,httproute -n bankapp

# View certificate details
kubectl describe certificate bankapp-tls -n bankapp
```
