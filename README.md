# MuchToDo API — Cloud Engineering Deployment

**AltSchool Africa | Semester 3 Cloud Engineering Assessment**

## 1. Project Overview

MuchToDo is a Go-based REST API application deployed using Docker containers and AWS cloud infrastructure.

This project demonstrates the application of Cloud Engineering and DevOps practices, including:

- Infrastructure as Code (IaC) using Terraform.
- Containerisation using Docker.
- Container orchestration for local development using Docker Compose.
- AWS infrastructure provisioning and networking.
- Amazon Elastic Container Registry (ECR) for container image storage.
- AWS Systems Manager Parameter Store for application configuration and secrets.
- AWS Identity and Access Management (IAM) for access control.
- Application deployment on Amazon EC2.
- Application Load Balancer (ALB) for traffic distribution and health checks.
- Persistent and encrypted Amazon EBS storage for MongoDB.

The deployment uses a private backend architecture, with public access provided through an Application Load Balancer.

## 2. Architecture Overview

The infrastructure is deployed in an AWS Virtual Private Cloud (VPC).

### Network architecture

| Component | Configuration |
|---|---|
| VPC | 10.0.0.0/16 |
| Public subnet 1 | 10.0.1.0/24 |
| Public subnet 2 | 10.0.2.0/24 |
| Private subnet 1 | 10.0.11.0/24 |
| Private subnet 2 | 10.0.12.0/24 |
| Availability Zones | Two |
| Internet Gateway | One |
| NAT Gateway | One |
| Application Load Balancer | Internet-facing |

### Compute architecture

The deployment contains three EC2 instances:

1. **Bastion Host:** Provides controlled SSH access to private instances.
2. **Backend Server:** Runs the MuchToDo API in a Docker container.
3. **MongoDB Server:** Runs MongoDB in a Docker container and uses persistent EBS storage.

The backend and database servers are deployed in private subnets. The Bastion Host is deployed in a public subnet.

### Request flow

```text
                    Internet
                       |
                       |
              Application Load Balancer
                       |
                HTTP - Port 80
                       |
                Target Group
                       |
              Backend EC2 Instance
                Private Subnet
                       |
                 Port 27017
                       |
                MongoDB EC2
                Private Subnet
                       |
              Encrypted EBS Volume
```

The Application Load Balancer forwards HTTP traffic to the backend on port 8080. The backend communicates with MongoDB on port 27017.

The ALB uses `/health` as its health-check endpoint.

### Security group configuration

| Security Group | Port | Source | Purpose |
|---|---:|---|---|
| ALB | 80 | Internet | HTTP application access |
| ALB | 443 | Internet | Inbound rule configured; HTTPS listener not implemented |
| Bastion | 22 | Approved SSH CIDR | Administrative access |
| Backend | 8080 | ALB security group | Application traffic |
| Backend | 22 | Bastion security group | Administrative access |
| MongoDB | 27017 | Backend security group | Database traffic |
| MongoDB | 22 | Bastion security group | Administrative access |

Security group rules restrict backend and database access to the required sources rather than exposing these services directly to the internet.

## 3. Repository Structure

The repository is organised into application source code, infrastructure configuration, deployment files and assessment evidence.

```text
much-to-do/
│
├── evidence/
│   └── Semester3_Cloud_Engineering_Library_Evidence/
│
├── Server/
│   ├── MuchToDo/
│   │   ├── cmd/
│   │   │   └── api/
│   │   ├── docs/
│   │   │   ├── docs.go
│   │   │   ├── swagger.json
│   │   │   └── swagger.yaml
│   │   ├── internal/
│   │   │   ├── auth/
│   │   │   ├── cache/
│   │   │   ├── config/
│   │   │   ├── database/
│   │   │   ├── handlers/
│   │   │   ├── logger/
│   │   │   ├── middleware/
│   │   │   ├── models/
│   │   │   └── routes/
│   │   ├── .env.example
│   │   ├── docker-compose.yaml
│   │   ├── go.mod
│   │   ├── go.sum
│   │   └── Makefile
│   │
│   └── README.md
│
├── terraform/
│   ├── .terraform.lock.hcl
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── versions.tf
│   ├── terraform.tfvars.example
│   ├── scripts/
│   └── user_data/
│       ├── backend_setup.sh
│       └── mongodb_setup.sh
│
├── .dockerignore
├── .gitignore
├── Dockerfile
├── docker-compose.yml
├── docker-compose.aws.yml
├── docker-compose.yml.bak
└── README.md
```

The `local-secrets/` and `recovery-backups/` directories contain local operational data and are intentionally excluded from the documented source structure. Terraform state, execution plans, virtual environments and backup configurations are also excluded.

The `terraform/scripts/` directory contains supporting scripts, while `terraform/user_data/` contains the EC2 bootstrap scripts used to configure the backend and MongoDB instances.

## 4. Prerequisites

The following tools and services are used in the project:

- AWS account.
- AWS CLI.
- Terraform version 1.6 or later.
- Docker Desktop.
- Docker Compose.
- Git.
- VS Code or another code editor.

The AWS CLI is configured to use the `cloud-engineering` profile.

Verify the local tools:

```bash
aws --version
terraform version
docker --version
docker compose version
git --version
```

Verify the AWS identity:

```bash
aws sts get-caller-identity --profile cloud-engineering
```

Do not include AWS credentials, private keys, database passwords or Terraform state files in this repository.

## 5. Infrastructure as Code — Terraform

Terraform is used to define and manage the AWS infrastructure.

The Terraform configuration provisions:

- VPC and subnets.
- Internet Gateway.
- NAT Gateway and Elastic IP.
- Public and private route tables.
- Security groups.
- Bastion EC2 instance.
- Backend EC2 instance.
- MongoDB EC2 instance.
- IAM roles and instance profiles.
- IAM permissions for accessing AWS Systems Manager Parameter Store.
- AWS Key Management Service (KMS) encryption key.
- Amazon Elastic Container Registry repository.
- Encrypted EBS storage for MongoDB.
- Application Load Balancer.
- Target group and HTTP listener.

### Terraform configuration

The configuration is separated into the following files:

| File | Responsibility |
|---|---|
| `main.tf` | Main AWS infrastructure resources |
| `variables.tf` | Input variables |
| `outputs.tf` | Infrastructure outputs |
| `provider.tf` | AWS provider configuration |
| `versions.tf` | Terraform and provider version requirements |
| `terraform.tfvars.example` | Example variable values |
| `.terraform.lock.hcl` | Locks the selected Terraform provider dependency versions |

### Terraform workflow

Before running Terraform, create a local variable file from the example.

Run the following commands from the `terraform/` directory:

```bash
cp terraform.tfvars.example terraform.tfvars

Initialise Terraform:

```bash
terraform init
```

Format the configuration:

```bash
terraform fmt -recursive
```

Validate the configuration:

```bash
terraform validate
```

Review the proposed infrastructure changes:

```bash
terraform plan
```

Apply changes only after reviewing the plan and confirming that the proposed changes are safe:

```bash
terraform apply
```

View the configured outputs:

```bash
terraform output
```

**Important:** The example variables file must be reviewed before deployment. In particular, `allowed_ssh_cidr` must contain the authorised public IP address in `/32` format.

The AWS resources also depend on deployment prerequisites, including the required Systems Manager parameters, ECR image and EC2 key pair. These must be configured before the corresponding instance bootstrap processes run.

The Terraform provider is configured to use the `cloud-engineering` AWS CLI profile.

## 6. Docker Containerisation

The MuchToDo API is packaged using a multi-stage Docker build.

The Dockerfile uses:

- `golang:1.25.1-alpine` as the build environment.
- `alpine:3.22` as the runtime environment.

### Containerisation features

- Multi-stage image build.
- Dependency caching through separate Go module copy steps.
- Compiled Go application binary.
- Lightweight runtime image.
- Non-root application user.
- Port 8080 exposed by the container.
- Application health monitoring through the `/health` endpoint, configured in the deployment's container health-check settings.

Build the application image:

```bash
docker build -t muchtodo-api:1.0 .
```

List locally available images:

```bash
docker images
```

The production deployment uses the image stored in Amazon ECR rather than relying on a locally built image.

## 7. Docker Compose

The repository contains separate Compose configurations for different deployment contexts.

### Root Docker Compose

The root `docker-compose.yml` supports the local assessment environment.

It defines the MongoDB, MongoDB initialisation and backend services, alongside the associated network and persistent storage configuration.

The MongoDB configuration uses authentication and replica-set initialisation.

The backend is configured to communicate with MongoDB through the Compose network.

### AWS deployment Compose

The `docker-compose.aws.yml` file defines the backend service used for the AWS deployment.

The production backend service includes:

- Application image configuration.
- Environment-file configuration.
- Port 8080.
- Health checks against `/health`.
- Automatic restart policy.
- Container initialisation.

The AWS bootstrap process generates the deployment Compose configuration on the backend EC2 instance.

### Application development Compose

The nested `Server/MuchToDo/docker-compose.yaml` supports the application development environment. It includes MongoDB, Mongo Express, Redis and Redis Commander.

These development services are distinct from the production AWS deployment configuration.

Management interfaces such as Mongo Express and Redis Commander should not be exposed publicly.

## 8. Amazon ECR — Container Image Registry

Amazon Elastic Container Registry is used to store and distribute the application container images.

The ECR repository is named:

```text
muchtodo-api
```

The deployment uses versioned image tags, including:

```text
1.0
1.1
```

The production backend runs image version `1.1`.

ECR provides a centralised location from which the backend EC2 instance can authenticate and pull the application image.

The EC2 instance accesses ECR through its IAM role rather than requiring permanent AWS access keys.

## 9. AWS Systems Manager Parameter Store and Secrets Management

AWS Systems Manager Parameter Store stores application configuration and sensitive deployment values.

### Backend parameters

```text
/muchtodo/backend/mongo-uri
/muchtodo/backend/db-name
/muchtodo/backend/jwt-secret
/muchtodo/backend/enable-cache
```

### MongoDB parameters

```text
/muchtodo/mongodb/root-username
/muchtodo/mongodb/root-password
/muchtodo/mongodb/replica-key
```

The instance bootstrap scripts retrieve the required values using their assigned IAM permissions.

The backend bootstrap process creates protected environment files with restrictive file permissions.

AWS KMS provides a customer-managed encryption key with automatic key rotation enabled. The project uses the alias:

```text
alias/muchtodo-secrets
```

This approach avoids embedding application secrets directly in the Docker image or Terraform configuration.

## 10. MongoDB Persistence and Storage

MongoDB runs in a Docker container on its dedicated EC2 instance.

Persistent database storage is provided through an encrypted Amazon EBS volume.

### Storage configuration

| Property | Configuration |
|---|---|
| Volume type | gp3 |
| Capacity | 20 GB |
| Encryption | Enabled |
| Filesystem | XFS |
| Mount location | `/data/mongodb` |
| MongoDB port | 27017 |
| Replica set | rs0 |

The Terraform EBS resource includes:

```hcl
prevent_destroy = true
```

This provides an additional safeguard against accidental destruction of the database volume through Terraform.

The MongoDB bootstrap script identifies the attached EBS volume, checks its filesystem and mounts it persistently.

It does not blindly format an existing volume. It checks for an existing filesystem before considering formatting.

MongoDB is configured as a single-node replica set. This supports replica-set functionality but does not provide high availability.

## 11. EC2 Bootstrap and Deployment Automation

Terraform user-data scripts automate the configuration of the backend and database instances.

### MongoDB bootstrap

`terraform/user_data/mongodb_setup.sh`:

- Installs Docker and required system packages.
- Retrieves MongoDB configuration from Parameter Store.
- Configures MongoDB authentication.
- Prepares and mounts the encrypted EBS volume.
- Starts the MongoDB container.
- Configures replica set `rs0`.
- Waits for the database to become available.

### Backend bootstrap

`terraform/user_data/backend_setup.sh`:

- Installs Docker and AWS CLI.
- Installs Docker Compose.
- Retrieves backend configuration from Parameter Store.
- Authenticates to Amazon ECR.
- Pulls the configured application image.
- Generates protected environment files.
- Creates the production Compose configuration.
- Starts the backend container.
- Performs application health checks.
- Attempts container-level rollback if a new deployment fails its health check.

The backend deployment script retains the previous working container until the new container passes its health check.

This provides a basic deployment rollback mechanism. It is not a full infrastructure or database rollback solution.

**Deployment consideration:** The Terraform configuration sets `user_data_replace_on_change` to `false`. Updating a user-data script does not automatically rerun the bootstrap process on an existing EC2 instance.

## 12. Application Verification

The deployed application was tested through the public Application Load Balancer endpoint.

### Health endpoint

```bash
curl -i http://<ALB-DNS-NAME>/health
```

Expected successful response:

```json
{
  "cache": "disabled",
  "database": "ok"
}
```

### Root endpoint

```bash
curl -i http://<ALB-DNS-NAME>/
```

Expected successful response:

```json
{
  "message": "Welcome to MuchToDo API"
}
```

### Verification results

The deployment verification confirmed:

- The public ALB endpoint returned HTTP 200.
- The `/health` endpoint returned a successful response.
- The application reported a healthy database connection.
- The ALB target group reported a healthy backend target.
- The MongoDB container was healthy.
- An authenticated MongoDB connectivity test passed.
- The production backend ran image version `1.1`.
- The previous version `1.0` container was retained in a stopped state for rollback.

## 13. Assessment Evidence

Screenshots and supporting evidence are organised in:

```text
evidence/Semester3_Cloud_Engineering_Library_Evidence/
```

The evidence archive is organised into the following categories:

1. API connectivity.
2. Authentication and user management.
3. Docker and MongoDB.
4. Terraform.
5. AWS infrastructure.
6. AWS ALB CRUD operations.
7. ECR and Parameter Store.
8. Production deployment and ALB verification.

The evidence archive complements the source code, infrastructure configuration, deployment scripts and application documentation. It does not replace them.

Some screenshots may contain AWS account or role identifiers. Review and redact sensitive identifiers before publishing the evidence publicly.

## 14. Design Decisions and Known Limitations

The following points describe the implemented architecture and its current limitations.

| Area | Implemented configuration | Limitation |
|---|---|---|
| Operating system | Amazon Linux 2023 | Assessment specification requested Amazon Linux 2 |
| Networking | Two public and two private subnets | One NAT Gateway creates a single point of failure for private-subnet internet egress |
| Database | MongoDB single-node replica set | No database high availability |
| Load balancing | Internet-facing ALB | HTTP listener only |
| HTTPS | Port 443 permitted by ALB security group | HTTPS listener and TLS certificate not configured |
| Storage | Encrypted persistent EBS volume | Single database storage instance |
| Deployment | Docker Compose on EC2 | Not an orchestrated multi-node container platform |
| Rollback | Previous backend container retained | Container rollback does not restore database state |

These limitations are documented to distinguish implemented functionality from possible future improvements.

## 15. Security and Repository Hygiene

The following security practices are applied:

- Restrict SSH access through an authorised CIDR.
- Use a Bastion Host to access private instances.
- Restrict backend and database ports through security groups.
- Use IAM instance roles instead of permanent AWS credentials.
- Store deployment secrets in AWS Systems Manager Parameter Store.
- Use KMS encryption for managed secrets.
- Encrypt persistent database storage.
- Run the application container as a non-root user.
- Apply restrictive permissions to generated environment files.
- Exclude sensitive files, Terraform state and local backups from Git tracking.

Before pushing changes to a remote repository, inspect the Git status and verify that no secrets, state files, private keys or database backups are staged.

Terraform state may contain sensitive information, including infrastructure details and application secrets. Do not commit it to Git or share it publicly. Keep it in a protected location and provide it for assessment only if explicitly required through an approved private submission channel.

## 16. Cleanup and Resource Protection

AWS resources may incur charges while running, including EC2 instances, NAT Gateway, EBS volumes, load balancers and related services.

Before performing any cleanup:

1. Review the resources currently in use.
2. Confirm whether the assessment environment must remain available.
3. Back up important database data.
4. Review Terraform's proposed changes.
5. Confirm that no protected database resources will be affected.

The MongoDB EBS volume has a Terraform lifecycle safeguard configured through `prevent_destroy = true`. This helps prevent accidental deletion through Terraform while the resource and lifecycle rule remain in the configuration. It does not prevent manual deletion through AWS. The presence of `prevent_destroy` should not be treated as a substitute for database backups or independent AWS resource protection.

Do not run `terraform destroy` without reviewing its consequences and confirming that the infrastructure and database data are no longer required.

## 17. Conclusion

The MuchToDo API deployment demonstrates the application of core Cloud Engineering and DevOps practices through infrastructure automation, containerisation, AWS networking, identity and access management, secrets management, persistent storage and application deployment.

The project provides practical experience in designing and deploying a backend application using Terraform, Docker, AWS EC2, ECR, Systems Manager, KMS, EBS and an Application Load Balancer.

It also establishes a foundation for future improvements involving HTTPS, high availability, automated CI/CD pipelines, infrastructure monitoring, and container orchestration.

---

**Project:** MuchToDo API
**Programme:** AltSchool Africa — Diploma in Cloud Engineering
**Semester:** 3
**Focus:** Terraform, Infrastructure as Code, Docker, AWS and Backend Deployment
