# Semester 3 Cloud Engineering — Evidence Index

This archive contains selected screenshots documenting the MuchToDo backend deployment assessment for AltSchool Africa Semester 3 Cloud Engineering.

## Evidence Categories

### 01 — API and Connectivity
`01-api-and-connectivity/`

API health endpoint, root response, and backend/database connectivity.

### 02 — Authentication and User Management
`02-authentication-and-user-management/`

Login, Swagger bearer authentication, and authenticated user profile.

### 03 — Docker and MongoDB
`03-docker-and-mongodb/`

Image build, Compose container status, Docker health check, and MongoDB persistent volume.

### 04 — Terraform
`04-terraform/`

Terraform provider/version configuration, initialization, directory structure, validation, networking, security groups, and AMI validation.

### 05 — AWS Infrastructure
`05-aws-infrastructure/`

AWS IAM Identity Center authentication and EC2 key-pair description.

### 06 — AWS ALB CRUD
`06-aws-alb-crud/`

Eight screenshots demonstrating Todo creation, retrieval, listing, updating, deletion, and public ALB endpoint verification through the AWS Application Load Balancer.
- alb-endpoint-verification.png — Public ALB /health and root endpoint verification, both returning HTTP 200.

### 07 — ECR and Parameter Store
`07-ecr-and-parameter-store/`

- `12-ecr-docker-images.png` — Amazon ECR image tags, digests, image sizes, and push dates for versions 1.0 and 1.1.
- `13-ssm-parameter-store.png` — AWS Systems Manager Parameter Store configuration, showing parameter names, types, and versions without exposing secret values.

### 08 — Production Deployment and ALB
`08-production-deployment-and-alb/`

- `09-production-and-rollback-containers.png` — Production container running image 1.1 and stopped previous container using image 1.0, retained for rollback.
- `10-public-alb-endpoint-verification.png` — Public ALB root and health endpoint responses, both returning HTTP 200.
- `11-alb-target-health.png` — ALB target group health confirmation for the backend EC2 instance on port 8080.

## Deployment Summary

- Application: MuchToDo API
- Deployment platform: AWS EC2
- Containerisation: Docker
- Container registry: Amazon Elastic Container Registry (ECR)
- Infrastructure provisioning: Terraform
- Configuration management: AWS Systems Manager Parameter Store
- Load balancing: AWS Application Load Balancer
- Database: MongoDB
- Production image: 1.1
- Previous image retained for rollback: 1.0
- Production health endpoint: HTTP 200 OK
- Public root endpoint: HTTP 200 OK
- ALB target health: healthy
- Database connectivity: Backend health endpoint reports database: ok; MongoDB replica set rs0 verified with one PRIMARY member.

## Curation Notes

Filenames have been normalised for clarity; image content has not been edited.

A separate screenshot containing a transient AWS SSO OAuth authorisation URL was excluded.

An older localhost Todo deletion screenshot was excluded because the current ALB CRUD evidence is retained in 06-aws-alb-crud.

Two similarly named Terraform project-structure screenshots were not both retained; the selected file documents provider and version configuration.

The AWS identity screenshot contains account/role identifiers. Keep this archive private unless that information is redacted before public sharing.

The login screenshot contains a visually redacted password and JWT response token. Verify the redaction at full resolution before publishing.

## Important

This archive contains supporting screenshots covering application connectivity, authentication, Docker, MongoDB, Terraform, AWS infrastructure, ALB-based CRUD operations, ECR image management, Parameter Store configuration, and production deployment verification.

The screenshots complement, but do not replace, the application source code, Terraform configuration, deployment scripts, application logs, and other project documentation.
