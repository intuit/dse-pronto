# OpsCenter

DataStax OpsCenter is an easy-to-use visual management and monitoring solution enabling administrators, architects, and
developers to quickly provision, monitor, and maintain DataStax Enterprise (DSE) clusters.

### Build AMI

You can skip this step if you've already got an opscenter AMI baked.

See the AMI baking instructions [here](2.PACKER.md).  Ensure the following `PACKER_` configurations are present in your
[variables.yaml](../configurations/default-account/variables.yaml):

| Variable                  | Description                   | Sample value                          |
|---------------------------|-------------------------------|---------------------------------------|
| PACKER_OPSCENTER_FULL_VER | Opscenter version             | 6.7.4-1                               |
| PACKER_DS_AGENT_VER       | DSE agent version             | 6.7.4-1                               |
| PACKER_DS_STUDIO_VER      | Version of the DSE studio     | 6.7.0                                 |

Once you are ready with prerequisites, you can bake an AMI as follows:
```
./core-components/bake-ami.sh -a ${account_name} -t opscenter
```

**NOTE:** currently **Amazon Linux** is the only supported OS for OpsCenter.

### Deploy

Prerequisites to deploying OpsCenter:

* Ensure that you created a dedicated C* cluster for opscenter storage.
  * Deploy a C* cluster [as normal](3.TERRAFORM.md), with a meaningful cluster name like "ops-storage-cluster."
* **Remember to run the `init` operation after deploying**:
  * `./core-components/operations.sh -a ${account_name} -v ${vpc_name} -c ${storage_cluster_name} -o init`
  * This will update the password for the `cassandra` user to what you specified during deployment (with `init-secrets.sh`).
    This step is **required** for any cluster you try to connect to OpsCenter.
* Create a self-signed SSL certificate if you don't have one already.
  * `openssl req -newkey rsa:2048 -nodes -keyout opscenter.key -x509 -days 36500 -out opscenter.crt`
    * **NOTE:**  you _must_ provide a common name for the cert (e.g. "test.com") even if you don't have a `hosted_zone` to
      use for OpsCenter.  Otherwise, the cert will be invalid for use in a load balancer, and Terraform will fail with a
      "CertificateNotFound" error while deploying the `aws_lb_listener` resource.
  * `aws acm import-certificate --certificate file://opscenter.crt --private-key file://opscenter.key --region us-west-2`
    * If you have your own cert, replace the file argument with the path to your SSL cert file.
    * **NOTE:**  using awscliv2, you'll get an "Invalid Base64" error from the above command.  You need to use `fileb://`
      (instead of `file://`) for both filepath options.
  * Copy the ARN from that command's output into the `ssl_certificate_id` variable in your
    [opscenter.tfvars](../configurations/default-account/default-vpc/opscenter-resources/opscenter.tfvars) file.
* Ensure you have a hosted-zone, or else create one now.
  * If you have a HZ, fill in the `hosted_zone_name` and `private_hosted_zone` vars in your [opscenter.tfvars](../configurations/default-account/default-vpc/opscenter-resources/opscenter.tfvars).
    * If terraform returns a "no matching Route53Zone found" error, run `aws route53 list-hosted-zones` and make sure you
      have both variables filled in correctly.
  * **NOTE:**  this is not required, just "nice to have."  Terraform will create a Route53 record if the HZ variable is
    provided.  Without it, you'll still be able to use the OpsCenter LB DNS in your browser.

See the deployment instructions [here](3.TERRAFORM.md).  Ensure the following vars are present in your
[opscenter.tfvars](../configurations/default-account/default-vpc/opscenter-resources/opscenter.tfvars):

| Variable                    | Description                                                           | Sample value                |
|-----------------------------|-----------------------------------------------------------------------|---------------------------- |
| `hosted_zone_name`          | Name of the hosted zone (optional)                                    | `test.com.`                 |
| `private_hosted_zone`       | Boolean for if the hosted zone is private (required if HZ is present) | `true`                      |
| `opscenter_storage_cluster` | Name of the storage C* cluster                                        | `opscenter-storage-cluster` |
| `ssl_certificate_id`        | SSL certificate to be used for opscenter Load Balancer                | (a valid ACM ARN)           |

Once you are ready with prerequisites, you can deploy as follows:
```
./core-components/deploy.sh -a ${account_name} -v ${vpc_name} -l opscenter -m apply
```

### Debugging

OpsCenter logs during startup will be in the following locations:

* [cloud-init](../core-components/terraform/modules/opscenter/scripts/opscenter-init.tpl):  `tail -f /var/log/messages | grep "cloud-init"`
* [bootstrap](../core-components/packer/opscenter/scripts/bootstrap.sh):  `tail -f /var/log/bootstrap_opscenter.log`
* service startup:  `tail -f /var/log/opscenter/opscenterd.log`

**Known Issue:** if you see this in `/var/log/opscenter/opscenterd.log`:
```
INFO: Loading per-cluster config file /etc/opscenter/clusters/.conf (MainThread)
```
You'll need to locate and delete the file `.conf` (empty cluster name) both on disk and in s3:
```
aws s3 rm s3://${TFSTATE_BUCKET}/opscenter-resources/files/etc/clusters/.conf
sudo rm -f /etc/opscenter/clusters/.conf
sudo service opscenterd restart
```
**TODO:** figure out why this happens and fix it.

### Operations

See the remote operation instructions [here](4.ANSIBLE.md).  The important playbooks to run on your OpsCenter node and
clusters are:

#### • Update datastax agent:

```
./core-components/operations.sh -a ${account_name} -v ${vpc_name} -c ${cluster_name} -o update-datastax-agent
```
**This must be run on each cluster you attach to OpsCenter,** including your storage cluster.  This playbook will add
the OpsCenter IP to datastax-agent config, enabling it to connect and report metrics.

If you change the OpsCenter keystore or IP, you will need to run this playbook on every cluster again.

#### • Attach cluster to opscenter:

```
./core-components/operations.sh -a ${account_name} -v ${vpc_name} -c ${cluster_name} -o attach-to-opscenter
```
**This must be run for each cluster you attach to OpsCenter.**  This playbook will build and install a cluster.conf file
on the OpsCenter node, under `/etc/opscenter/clusters`.

#### • Install the default alerts:

```
./core-components/operations.sh -a ${account_name} -v ${vpc_name} -c ${cluster_name} -o install-alerts-dashboards
```
**This must be run for each cluster you intend to monitor.**  This playbook will install the
[alerts](../core-components/ansible/scripts/opscenter-alerts.json),
[dashboard](../core-components/ansible/scripts/opscenter-dashboard.json), and
[best practices](../core-components/ansible/scripts/opscenter-enabled-bestpractices.json)
defined under `core-components/ansible/scripts`.  In the UI, you can find these in the following locations:

* **Alerts:** click "Alerts" at the top-right of the page, then click the "Manage Alerts" button and select a cluster.
* **Dashboard:** click a cluster name on the left, then the Dashboard tab in the bar that pops up.
* **Best Practices:** click a cluster name on the left, then the Services tab in the bar that pops up, then "Details" next
  to Best Practice Service.

### FAQ

#### Where can I see the OpsCenter UI?

Get your load balancer DNS from the EC2 console (also output after deploying with Terraform), then go here in your browser:

`https://${LOAD_BALANCER_DNS}/opscenter/login.html`

The username and password are both "admin" by default.

#### What is a storage cluster?

A storage cluster is a separate DSE cluster, in which OpsCenter stores information about the metrics for all the other
clusters being monitored.

#### How can I re-stack OpsCenter?

If you have a new AMI or any other updates to push, restacking is a two step process:

1. Run terraform with `deploy.sh` as normal.
2. Terminate the OpsCenter EC2 instance.

The OpsCenter ASG will launch a replacement with your newly deployed launch configuration.

#### The agents on my DSE nodes are no longer connected after I restacked my cluster.

After restacking your DSE nodes using the `restack` ansible operation, the `update-datastax-agent` playbook needs to be
run as well.

#### What alerts are configured by default?

There are about 17 alerts defined in [this JSON file](../core-components/ansible/scripts/opscenter-alerts.json).  These
alerts are added to the monitored cluster by default.

#### What are the default graphs in the dashboard that are enabled for a cluster?

There are about 41 graphs defined in [this JSON file](../core-components/ansible/scripts/opscenter-dashboard.json).  These
graphs are added to the monitored cluster by default under the **Custom** dashboard.

#### Why am I getting an authentication error?

You may not have your passwords set properly.  Remember to run the `init` operation on all new (or newly restacked) DSE
clusters, to set up those credentials:
```
 ./core-components/operations.sh -a ${account_name} -v ${vpc_name} -c ${cluster_name} -o init
 ```
