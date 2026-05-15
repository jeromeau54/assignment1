# Assignment 1 — Node.js MySQL CRUD on AWS (Free Tier)

Infrastructure-as-Code deployment of [chapagain/nodejs-mysql-crud](https://github.com/chapagain/nodejs-mysql-crud) onto AWS using **Terragrunt** and **Terraform**, with a Cloudflare-managed domain and a trusted Let's Encrypt SSL certificate.

---

## Architecture

```
Browser
   │  HTTPS (443)
   ▼
Cloudflare DNS  ──── A record ──▶  Elastic IP (static)
                                        │
                                   EC2 t3.micro (Ubuntu 24.04)
                                   ┌───────────────────────────┐
                                   │  Nginx (port 80 / 443)    │
                                   │    │ reverse proxy         │
                                   │    ▼                       │
                                   │  Node.js app (port 3000)  │
                                   │    │                       │
                                   │    ▼                       │
                                   │  MySQL (localhost)         │
                                   └───────────────────────────┘
```

- **Port 80** → permanently redirects to HTTPS  
- **Port 443** → Nginx terminates TLS (Let's Encrypt cert) and proxies to Node.js  
- **Port 22** → SSH access (key-pair only)  
- **Port 3000** → internal only, not exposed to the internet  

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | ≥ 1.5 | https://developer.hashicorp.com/terraform/install |
| Terragrunt | ≥ 0.50 | https://terragrunt.gruntwork.io/docs/getting-started/install |
| AWS CLI | v2 | https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html |
| Git | any | https://git-scm.com |

**AWS CLI must be configured with the `assignment1` profile:**
```powershell
aws configure --profile assignment1
# Enter: Access Key ID, Secret Access Key, region (ap-southeast-1), output (json)
```

---

## Project Structure

```
terragrunt/
├── .gitignore
├── terragrunt.hcl             # Root config — local state backend + provider generation
├── terraform.tfvars.example   # Template for secrets — copy to terraform.tfvars
├── terraform.tfvars           # Your actual secrets (gitignored, auto-read by Terraform)
└── ec2/
    ├── terragrunt.hcl         # Module inputs (instance type, DB name/user)
    ├── versions.tf            # Required providers (aws, cloudflare, tls, local)
    ├── variables.tf           # Variable declarations
    ├── main.tf                # EC2, EIP, security group, key pair, Cloudflare DNS record
    ├── outputs.tf             # Public IP, app URL, SSH command
    └── user_data.sh.tpl       # Bootstrap script (Node.js, MySQL, PM2, Nginx, Certbot)
```

State file is stored locally at `tfstate/ec2/terraform.tfstate` (gitignored).

---

## Configuration

Copy the example vars file and fill in your values — Terraform reads this automatically, no manual loading needed:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
db_password          = "your-strong-password"

cloudflare_api_token = "your-cloudflare-api-token"
cloudflare_zone_id   = "your-32-char-zone-id"
domain_name          = "assignment1.yourdomain.com"
certbot_email        = "you@example.com"
```

**Where to find Cloudflare values:**
- **API Token** → Cloudflare Dashboard → My Profile → API Tokens → Create Token → *Edit zone DNS* template
- **Zone ID** → Cloudflare Dashboard → click your domain → Overview page → right sidebar

---

## Deployment

Run these commands in order from the `terragrunt/` directory.

**Step 1 — Initialise (downloads providers, sets up local state backend)**
```powershell
cd ec2
terragrunt init
```

**Step 2 — Preview what will be created**
```powershell
terragrunt plan
```

**Step 3 — Deploy**
```powershell
terragrunt apply
```
Type `yes` when prompted.

**Step 4 — Get connection details**
```powershell
terragrunt output
```

### What gets created

| Resource | Details |
|---|---|
| EC2 instance | t3.micro, Ubuntu 24.04 LTS, 20 GB gp2 |
| Elastic IP | Static public IP, associated with the instance |
| Security group | Ports 22 (SSH), 80 (HTTP), 443 (HTTPS) — port 3000 internal only |
| SSH key pair | Auto-generated, saved as `ec2/assignment1-key.pem` |
| Cloudflare A record | `domain_name → Elastic IP` (TTL 120s) |

### What runs on first boot (via user_data)

1. Installs all packages — Node.js 20 LTS, MySQL 8.0, Nginx, Certbot, git
2. Creates the MySQL database and application user
3. Obtains a Let's Encrypt certificate via Cloudflare DNS-01 challenge
4. Clones [chapagain/nodejs-mysql-crud](https://github.com/chapagain/nodejs-mysql-crud) into `/home/ubuntu/nodejs-mysql-crud`
5. Writes `config.js` with database credentials and creates the `users` table
6. Starts the app with PM2 (auto-restarts on crash/reboot)
7. Configures Nginx: port 80 redirects to HTTPS, port 443 proxies to port 3000
8. Sets up automatic certificate renewal

---

## Accessing the App

After `terragrunt apply` completes, run:

```powershell
terragrunt output app_url        # https://assignment1.yourdomain.com
terragrunt output elastic_ip     # raw IP if needed
terragrunt output ssh_command    # ready-to-run SSH command
```

> The app takes **3–5 minutes** after apply to be fully ready — the EC2 instance needs time to run the bootstrap script and obtain the SSL certificate.

---

## SSH Access

The SSH private key is auto-generated and saved locally:

```powershell
# Use the exact command from the output
ssh -i assignment1-key.pem ubuntu@<elastic-ip>

# Check bootstrap logs if something looks wrong
sudo tail -f /var/log/user_data.log

# Check app status
pm2 status
pm2 logs nodejs-crud
```

---

## Teardown

To destroy all AWS resources:

```powershell
cd ec2
terragrunt destroy
```

This removes the EC2 instance, Elastic IP, security group, key pair, and Cloudflare DNS record. The local state file and SSH key are also deleted.

---

## Free Tier Limits

| Resource | Free Tier Allowance | This Setup |
|---|---|---|
| EC2 | 750 hrs/month (t3.micro) | 1 × t3.micro |
| EBS storage | 30 GB/month | 20 GB |
| Elastic IP | Free while instance is running | 1 EIP |
| Data transfer | 100 GB/month outbound | Minimal |

> **Note:** The Elastic IP incurs a small charge (~$0.005/hr) if the EC2 instance is **stopped** but the IP is still reserved. Run `terragrunt destroy` when not in use to avoid charges.
