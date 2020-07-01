# DSE Pronto

An automation suite for deploying and managing [DataStax Cassandra](https://docs.datastax.com/en/landing_page/doc/landing_page/current.html)
clusters in AWS.

[![pronto](./docs/images/pronto-logo.png)](https://github.intuit.com/pages/open-source/logo-generator/)

This repository collects Intuit's DSE automation.  We've taken all of our learning for managing Cassandra in AWS and
condensed it into a single package for others to leverage.  It uses standard tools
([Packer](https://packer.io/docs/index.html), [Terraform](https://www.terraform.io/docs/index.html), and
[Ansible](https://docs.ansible.com/ansible/latest/index.html)) and can be run from a laptop.  That said, we have a hard
preference for automated deployments using a CICD orchestrator along the lines of [Jenkins](https://jenkins.io/),
[CodeBuild](https://aws.amazon.com/codebuild/)/[CodeDeploy](https://aws.amazon.com/codedeploy/),
[Bamboo](https://www.atlassian.com/software/bamboo), [GitLab](https://about.gitlab.com/), or [Spinnaker](https://www.spinnaker.io/).

The tools in this repo can take you from an empty AWS account to a fully-functional DSE cluster, but you should have an
understanding of AWS resources, Cassandra cluster management, and at least a passing familiarity with Packer, Terraform,
and Ansible.

**This is not a "managed" Cassandra solution.**  If you need one of those, [AWS has you covered](https://aws.amazon.com/keyspaces/).
If you need a fully managed _DataStax_ solution including OpsCenter and other DSE features,
[DataStax Astra](https://www.datastax.com/products/datastax-astra) is now officially a thing.

On the other hand, if what you're looking for is an open source framework to help you _manage your own_ DSE cluster...
then welcome to DSE Pronto!

## Notes and Features

* Support for every phase of deployment, from an empty account to production:
  * Baking an AMI
  * Deploying a new VPC
  * Creating account-wide resources (like IAM roles) and VPC-wide resources (like a bastion host for SSH)
  * Launching a cluster
  * Runtime operations
    * Restacking and resizing a cluster
    * Bringing nodes up and down
  * Configuring OpsCenter
    * Including a number of predefined alerts and best practices
* Transparent restacking operations, to keep in compliance with latest baseline images
  * Data stored on persistent EBS volumes, static EIP for predictable address, both located (using EC2 tags) and reattached
    during restack
* DSE 5 & DSE 6 both supported, along with DSE OpsCenter & DSE Studio
* Latest Amazon Linux 2.0 & Python 3 in use
* [More FAQs and details here](docs/MORE_DETAILS.md)

## Tools Required

* **On MacOS:** `brew install awscli coreutils packer ansible tfenv jq && tfenv install 0.12.24`
  * The scripts in this repo require a minimum of `aws-cli/1.16.280` and `botocore/1.13.16`.  Type `aws --version` to verify.
    * Everything has also been tested with `aws-cli/2.0.0` and associated prerequisites.
  * Some scripts also require Python 3 ([installation](https://docs.python-guide.org/starting/install3/osx/)).
* **In Docker:** the included [Dockerfile](./Dockerfile) will produce a suitable Docker image, including all tools needed.
* Elsewhere:
  * Install Packer: https://www.packer.io/intro/getting-started/install.html
  * Install Terraform (0.12.24): https://www.terraform.io/intro/getting-started/install.html
  * install Ansible: https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html
* **Why Terraform 0.12.24?** Go [here](docs/MORE_DETAILS.md) to find out!

## 1. Initial Setup

There's a bunch of **one-time** setup you'll need to do before you start baking AMIs or deploying clusters.

Please follow [all of the steps here](docs/1.INITIAL_SETUP.md) before proceeding.

## 2. Baking AMIs

Instructions for baking AWS images with Packer are [here](docs/2.PACKER.md).

## 3. Deploying

Instructions for deploying AWS resources with Terraform are [here](docs/3.TERRAFORM.md).

## 4. Runtime Operations

Instructions for running playbooks with Ansible are [here](docs/4.ANSIBLE.md).

## 5. OpsCenter

Instructions for deploying and managing an OpsCenter node are [here](docs/OPSCENTER.md).

## 6. Debugging

If you're having trouble getting anything to work, go [here](docs/MORE_DETAILS.md) for tips on debugging!

## 7. Cleaning Up

Instructions for deleting everything deployed by this repo are [here](docs/CLEANUP.md).

### Links

* [Contributing](.github/CONTRIBUTING.md)
* [License](LICENSE)

---
Copyright 2020 Intuit Inc.
