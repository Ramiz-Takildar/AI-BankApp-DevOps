# AI BankApp - DevOps Project Presentation
## Production-Ready GitOps Deployment on AWS EKS

---

## Slide 1: Title Slide

**AI BankApp - DevOps Project**
*Production-Ready GitOps Deployment on AWS EKS*

**Presenter:** Ramiz Takildar

**Live Demo:** https://bankapp.aicloudops.in

**Technologies:**
- Spring Boot | Kubernetes | ArgoCD | Terraform | AWS EKS

---

## Slide 2: Project Overview

### What is AI BankApp?

A **modern, cloud-native banking application** demonstrating enterprise-grade DevOps practices

**Key Highlights:**
- ✅ Full-stack banking application (Spring Boot + MySQL)
- ✅ GitOps-based continuous deployment
- ✅ Production-ready on AWS EKS
- ✅ Automated CI/CD pipeline
- ✅ Zero-downtime deployments
- ✅ TLS/HTTPS with Let's Encrypt
- ✅ Monitoring & Observability

**Purpose:** Showcase modern DevOps practices in a real-world application

---

## Slide 3: High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        End Users                             │
│                    (Web Browsers)                            │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTPS
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    DNS Provider                              │
│              bankapp.aicloudops.in                           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                      AWS Cloud                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              EKS Cluster                              │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────┐    │  │
│  │  │  Network Load Balancer                      │    │  │
│  │  └──────────────┬──────────────────────────────┘    │  │
│  │                 │                                    │  │
│  │  ┌──────────────▼──────────────────────────────┐    │  │
│  │  │  Envoy Gateway (Gateway API)                │    │  │
│  │  │  - TLS Termination                          │    │  │
│  │  │  - Routing                                  │    │  │
│  │  └──────────────┬──────────────────────────────┘    │  │
│  │                 │                                    │  │
│  │  ┌──────────────▼──────────────────────────────┐    │  │
│  │  │  BankApp Pods (3 replicas)                  │    │  │
│  │  │  - Spring Boot Application                  │    │  │
│  │  │  - Auto-scaling (HPA)                       │    │  │
│  │  └──────────────┬──────────────────────────────┘    │  │
│  │                 │                                    │  │
│  │  ┌──────────────▼──────────────────────────────┐    │  │
│  │  │  MySQL Database                             │    │  │
│  │  │  - Persistent Storage (EBS)                 │    │  │
│  │  └─────────────────────────────────────────────┘    │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────┐    │  │
│  │  │  ArgoCD (GitOps Controller)                 │    │  │
│  │  │  - Continuous Deployment                    │    │  │
│  │  │  - Sync from Git Repository                 │    │  │
│  │  └─────────────────────────────────────────────┘    │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────┐    │  │
│  │  │  cert-manager                               │    │  │
│  │  │  - Let's Encrypt Certificates               │    │  │
│  │  └─────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Key Components:**
- **AWS EKS:** Managed Kubernetes cluster (8 nodes)
- **Envoy Gateway:** Modern API Gateway with Gateway API
- **ArgoCD:** GitOps continuous deployment
- **cert-manager:** Automated TLS certificate management

---

## Slide 4: Technology Stack

### Application Layer
- **Backend:** Spring Boot 3.x (Java 21)
- **Frontend:** Thymeleaf, HTML5, CSS3, JavaScript
- **Database:** MySQL 8.0
- **Build Tool:** Maven 3.9+

### Infrastructure & DevOps
- **Cloud:** AWS (EKS, VPC, EBS, NLB)
- **Container:** Docker
- **Orchestration:** Kubernetes 1.28+
- **IaC:** Terraform 1.5.7+
- **GitOps:** ArgoCD 2.9+
- **CI/CD:** GitHub Actions
- **API Gateway:** Envoy Gateway (Gateway API v1.2)
- **Certificates:** cert-manager + Let's Encrypt

### Monitoring
- **Metrics:** Prometheus
- **Visualization:** Grafana
- **Logging:** Kubernetes native

---

## Slide 5: GitOps Workflow

### What is GitOps?

**Git as Single Source of Truth**
- All infrastructure and application config in Git
- Automated sync from Git to production
- Changes via pull requests with review
- Simple rollbacks (revert Git commit)

### Our GitOps Flow

```
┌──────────────┐
│ Developer    │
│ Pushes Code  │
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ GitHub Actions   │
│ - Build & Test   │
│ - Build Image    │
│ - Push to Docker │
│ - Update K8s     │
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│ Git Repository   │
│ (Manifest Change)│
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│ ArgoCD Detects   │
│ - Compare States │
│ - Auto Sync      │
└──────┬───────────┘
       │
       ▼
┌──────────────────┐
│ Kubernetes       │
│ Rolling Update   │
└──────────────────┘
```

**Benefits:**
- ✅ Declarative & Versioned
- ✅ Auditable & Recoverable
- ✅ Automated & Consistent

---

## Slide 6: CI/CD Pipeline

### GitHub Actions Workflow

```
Code Push → Trigger Check → Build (Maven) → Test (JUnit)
                                    ↓
                            Build Docker Image
                                    ↓
                            Push to DockerHub
                                    ↓
                            Update K8s Manifest
                                    ↓
                            Commit & Push
                                    ↓
                            ArgoCD Auto-Sync
                                    ↓
                            Rolling Update
                                    ↓
                            ✅ Deployment Complete
```

### Pipeline Features
- **Smart Triggers:** Only builds when code changes
- **Multi-platform:** Builds for amd64 architecture
- **Automated Tagging:** Uses commit SHA for versioning
- **GitOps Integration:** Updates manifests automatically
- **Zero Manual Steps:** Fully automated deployment

---

## Slide 7: AWS Infrastructure

### EKS Cluster Specifications

**Cluster Configuration:**
- **Name:** bankapp-eks
- **Region:** us-west-2
- **Kubernetes Version:** 1.28+
- **Node Type:** t3.small (2 vCPU, 2GB RAM)
- **Node Count:** 8 nodes
- **Availability Zones:** 3 (High Availability)

### Network Architecture

```
VPC: 10.0.0.0/16
├── Public Subnets (3 AZs)
│   ├── 10.0.1.0/24 (us-west-2a)
│   ├── 10.0.2.0/24 (us-west-2b)
│   └── 10.0.3.0/24 (us-west-2c)
│   └── Network Load Balancer
│
└── Private Subnets (3 AZs)
    ├── 10.0.4.0/24 (us-west-2a)
    ├── 10.0.5.0/24 (us-west-2b)
    └── 10.0.6.0/24 (us-west-2c)
    └── EKS Worker Nodes
```

**Infrastructure as Code:**
- All provisioned via Terraform
- Reproducible and version-controlled
- Automated deployment in ~15 minutes

---

## Slide 8: Application Features

### Banking Capabilities
- 🏦 **Account Management** - Create and manage accounts
- 💰 **Transactions** - Deposit, withdraw, transfer
- 📊 **Dashboard** - Real-time account overview
- 🔐 **Authentication** - Secure login/registration
- 🤖 **AI Chatbot** - Customer support (placeholder)
- 📱 **Responsive Design** - Mobile-friendly

### DevOps Features
- 🔄 **GitOps Deployment** - Declarative infrastructure
- 🚀 **Zero-Downtime** - Rolling updates with health checks
- 🔒 **Automated TLS** - Let's Encrypt certificates
- 📈 **Auto-Scaling** - HPA based on CPU/memory
- 🔍 **Health Monitoring** - Liveness/readiness probes
- 🏗️ **IaC** - Complete Terraform automation

---

## Slide 9: Deployment Process

### Automated Deployment Script

**One Command Deployment:**
```bash
./deploy-bankapp.sh
```

**What It Does:**
1. ✅ Installs Gateway API CRDs
2. ✅ Installs Envoy Gateway
3. ✅ Installs cert-manager
4. ✅ Deploys application via ArgoCD
5. ✅ Configures DNS (interactive)
6. ✅ Issues TLS certificate
7. ✅ Verifies application access
8. ✅ Optionally installs monitoring

**Features:**
- **Idempotent:** Safe to re-run
- **Auto-recovery:** Retries failed steps
- **Checkpoints:** Resume from last success
- **Interactive:** Pauses for DNS configuration

**Time:** ~15-20 minutes (including DNS propagation)

---

## Slide 10: Security & Best Practices

### Security Features
- ✅ **TLS/HTTPS** - Automated Let's Encrypt certificates
- ✅ **Non-root Containers** - Security context enforced
- ✅ **Resource Limits** - Prevent resource exhaustion
- ✅ **Network Policies** - Control pod communication
- ✅ **Secrets Management** - Kubernetes secrets
- ✅ **RBAC** - Role-based access control
- ✅ **Private Subnets** - Worker nodes isolated

### DevOps Best Practices
- **Least Privilege:** Minimal IAM permissions
- **Immutable Infrastructure:** No manual changes
- **Automated Updates:** GitOps-driven
- **Audit Trail:** All changes in Git
- **Encrypted Communication:** TLS everywhere
- **Container Scanning:** Image vulnerability checks

---

## Slide 11: Monitoring & Observability

### Monitoring Stack (kube-prometheus-stack)

**Components:**
- **Prometheus** - Metrics collection & storage
- **Grafana** - Visualization & dashboards
- **Alertmanager** - Alert routing
- **Node Exporters** - Hardware/OS metrics
- **Kube State Metrics** - K8s object metrics

### Pre-configured Dashboards
- Cluster-wide resource usage
- Per-namespace metrics
- Per-node metrics
- Application-specific metrics

### Key Metrics Monitored
- CPU & Memory usage
- Network I/O
- Pod restart count
- Request latency
- Error rates

---

## Slide 12: Live Demo

### Application Access

**Production URL:** https://bankapp.aicloudops.in

**Features to Demonstrate:**
1. **Login Page** - Secure authentication
2. **Dashboard** - Account overview
3. **Transactions** - Deposit/withdraw/transfer
4. **Responsive Design** - Mobile view

### Behind the Scenes

**ArgoCD Dashboard:**
- View deployment status
- See sync history
- Monitor application health

**Grafana Dashboard:**
- Real-time metrics
- Resource utilization
- Performance monitoring

---

## Slide 13: Key Achievements

### Technical Accomplishments
- ✅ **Production-Ready** - Running on AWS EKS
- ✅ **Fully Automated** - One-command deployment
- ✅ **GitOps Enabled** - Declarative infrastructure
- ✅ **Secure** - TLS/HTTPS with Let's Encrypt
- ✅ **Scalable** - Auto-scaling with HPA
- ✅ **Observable** - Comprehensive monitoring

### DevOps Maturity
- **CI/CD:** Automated build, test, deploy
- **IaC:** Complete Terraform automation
- **GitOps:** ArgoCD continuous deployment
- **Monitoring:** Prometheus + Grafana
- **Security:** Multiple layers of protection

---

## Slide 14: Lessons Learned

### Critical Insights

**1. Architecture Matters**
- Use Gateway API (modern, extensible)
- Separate concerns (gateway, app, data)

**2. Automation is Key**
- Idempotent scripts save time
- Auto-recovery prevents manual intervention

**3. DNS & Certificates**
- DNS propagation takes time (5-15 min)
- cert-manager needs Gateway API support

**4. Platform Compatibility**
- Apple Silicon requires `--platform linux/amd64`
- Always test on target architecture

**5. Monitoring is Essential**
- Observability from day one
- Pre-configured dashboards accelerate debugging

---

## Slide 15: Project Structure

```
AI-BankApp-DevOps/
├── .github/workflows/     # CI/CD pipeline
├── argocd/               # ArgoCD application
├── k8s/                  # Kubernetes manifests
│   ├── bankapp-deployment.yml
│   ├── mysql-deployment.yml
│   ├── gateway.yml
│   ├── certificate.yml
│   └── ...
├── terraform/            # Infrastructure as Code
│   ├── vpc.tf
│   ├── eks.tf
│   ├── argocd.tf
│   └── ...
├── src/                  # Application source
│   ├── main/java/
│   └── main/resources/
├── deploy-bankapp.sh     # Automated deployment
├── cleanup.sh            # Resource cleanup
└── Dockerfile            # Container image
```

---

## Slide 16: Future Enhancements

### Planned Improvements

**Application:**
- 🤖 Integrate real AI chatbot (OpenAI/Gemini)
- 📊 Advanced analytics dashboard
- 🔔 Real-time notifications
- 📱 Mobile app (React Native)

**Infrastructure:**
- 🌍 Multi-region deployment
- 🔄 Blue-green deployments
- 📈 Advanced auto-scaling (KEDA)
- 🔐 Service mesh (Istio)

**DevOps:**
- 🧪 Automated testing (integration, e2e)
- 🔍 Distributed tracing (Jaeger)
- 📝 Centralized logging (ELK stack)
- 🚨 Advanced alerting (PagerDuty)

---

## Slide 17: Resources & Links

### Project Resources
- **GitHub Repository:** https://github.com/Ramiz-Takildar/AI-BankApp-DevOps
- **Live Application:** https://bankapp.aicloudops.in
- **Documentation:** README.md, DEPLOYMENT_GUIDE_2026.md

### Learning Resources
- **ArgoCD:** https://argo-cd.readthedocs.io/
- **Gateway API:** https://gateway-api.sigs.k8s.io/
- **Terraform AWS:** https://registry.terraform.io/providers/hashicorp/aws
- **EKS Best Practices:** https://aws.github.io/aws-eks-best-practices/

### Technologies Used
- Spring Boot | Kubernetes | ArgoCD | Terraform
- AWS EKS | Docker | GitHub Actions | Envoy Gateway
- cert-manager | Prometheus | Grafana

---

## Slide 18: Q&A

### Questions?

**Contact Information:**
- **GitHub:** @Ramiz-Takildar
- **Project:** AI-BankApp-DevOps

**Topics for Discussion:**
- GitOps implementation details
- AWS EKS architecture decisions
- CI/CD pipeline optimization
- Security best practices
- Monitoring & observability
- Scaling strategies

---

## Slide 19: Thank You!

### Key Takeaways

1. **GitOps** enables declarative, auditable deployments
2. **Automation** reduces errors and saves time
3. **Kubernetes** provides powerful orchestration
4. **Monitoring** is essential for production systems
5. **Security** must be built-in, not bolted-on

### Try It Yourself!

**Clone the repository:**
```bash
git clone https://github.com/Ramiz-Takildar/AI-BankApp-DevOps.git
cd AI-BankApp-DevOps
./deploy-bankapp.sh
```

**Visit the live demo:**
https://bankapp.aicloudops.in

---

*Presentation created for AI BankApp DevOps Project*
*© 2026 Ramiz Takildar*
