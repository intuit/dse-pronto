# Cleaning Up

Time to delete everything, in the opposite order from creation.

### 1. Terraform Destroy

The `terraform destroy` command works perfectly.  Just invoke it on each layer, starting with the last thing you deployed
and working backwards:
```
$ ./core-components/deploy.sh -a ${ACCOUNT_NAME} -v ${VPC_NAME} -c ${CLUSTER_NAME} -l opscenter -m destroy
$ ./core-components/deploy.sh -a ${ACCOUNT_NAME} -v ${VPC_NAME} -c ${CLUSTER_NAME} -l cluster -m destroy
$ ./core-components/deploy.sh -a ${ACCOUNT_NAME} -v ${VPC_NAME} -c ${CLUSTER_NAME} -l account -m destroy
$ ./core-components/deploy.sh -a ${ACCOUNT_NAME} -v ${VPC_NAME} -c ${CLUSTER_NAME} -l vpc -m destroy
```
* **Note** that each `destroy` command will pause and ask you for manual verification.  You must type "yes."  The `-auto-approve`
  flag hasn't been added (in terraform.sh) for destroy commands, but it can be if you're feeling adventurous.

Remember to delete your tfstate bucket too.  Using your base Admin profile, first empty the `TERRAFORM_STATE_BUCKET` you
specified in variables.yaml:
```
$ aws --profile ${PROFILE} s3 rm --recursive s3://${BUCKET_NAME}/
```
Then delete the bucket itself:
```
$ aws --profile ${PROFILE} s3 rb s3://${BUCKET_NAME}
```

### 3. Delete EBS Volumes

EBS volumes are not created by Terraform, they're created (or located) and attached by the bootstrap process that runs on
each node.  This is to prevent Terraform from accidentally deleting data, but it does mean you'll need to find and delete
the volumes yourself.

At this point you should still have your `terraform` and `packer` AWS profiles.  Both of them (as well as your default base
profile) should be capable of the following commands:
```
# list all volumes
aws ec2 describe-volumes \
  --output table --query 'Volumes[*].[Tags[?Key==`Name`].Value|[0],VolumeId,State]' \
  --region ${REGION} --profile ${PROFILE}

# for each volume marked "available" that we want to delete...
aws ec2 delete-volume \
  --volume-id ${VOLUME_ID} \
  --region ${REGION} --profile ${PROFILE}
```

### 4. Deregister AMIs

Follow a similar process to deregister AMIs and delete snapshots:
```
# get account_id
aws sts get-caller-identity \
  --output text --query 'Account' \
  --profile ${PROFILE}

# find images owned by account_id
aws ec2 describe-images \
  --output table --query 'Images[*].[Name,ImageId]' \
  --filters Name=owner-id,Values=${ACCOUNT_ID} \
  --region ${REGION} --profile ${PROFILE}

# for each image we want to deregister...
aws ec2 deregister-image \
  --image-id ${AMI_ID} \
  --region ${REGION} --profile ${PROFILE}

# find snapshots owned by account_id
aws ec2 describe-snapshots \
  --output table --query 'Snapshots[*].[Tags[?Key==`Name`].Value|[0],SnapshotId]' \
  --filters Name=owner-id,Values=${ACCOUNT_ID} \
  --region ${REGION} --profile ${PROFILE}

# for each snapshot we want to delete...
aws ec2 delete-snapshot \
  --snapshot-id ${SNAPSHOT_ID} \
  --region ${REGION} --profile ${PROFILE}
```

### 5. Delete Packer/Terraform Roles

At this point, you'll need to revert to using your "base" profile (since you're about to delete the roles the other profiles
point at):
```
# list AWS-managed policies attached to the role
aws iam list-attached-role-policies \
  --output json --query 'AttachedPolicies[*].PolicyArn' --role-name ${ROLE_NAME} \
  --profile ${PROFILE}

# for each policy...
aws iam detach-role-policy \
  --role-name ${ROLE_NAME} --policy-arn ${POLICY_ARN} \
  --profile ${PROFILE}

# list inline policies
aws iam list-role-policies \
  --role-name terraform-role --query 'PolicyNames' \
  --profile ${PROFILE}

# for each policy...
aws iam delete-role-policy \
  --role-name ${ROLE_NAME} --policy-name ${POLICY_NAME} \
  --profile ${PROFILE}

# finally, delete the role
aws iam delete-role \
  --role-name ${ROLE_NAME} \
  --profile ${PROFILE}
```

### ALL Non-Terraform Resources

The steps above haven't been scripted to run automatically, **for safety's sake**.  But if you use the default AMI prefixes
of `dse-cassandra` and `dse-opscenter`, the default role names of `packer-role` and `terraform-role`, and the default Volume
naming patterns, the following will work:
```shell
PROFILE=$1
REGION=$2
BUCKET=$3
ACCOUNT=$(aws sts get-caller-identity --output text --query 'Account' --profile ${PROFILE})

echo "deleting tfstate bucket: ${BUCKET}"
aws s3 rm --recursive s3://${BUCKET}/ --region ${REGION} --profile ${PROFILE}
aws s3 rb s3://${BUCKET} --region ${REGION} --profile ${PROFILE}

vols=$(aws ec2 describe-volumes --query 'Volumes[*].VolumeId' --output text --filters Name=status,Values=available Name=tag:Name,Values=*-seed-*-data-* --region ${REGION} --profile ${PROFILE})
for v in $vols; do
  echo "deleting EBS volume: ${v}"
  aws ec2 delete-volume --volume-id ${v} --region ${REGION} --profile ${PROFILE}
done

amis=$(aws ec2 describe-images --query 'Images[*].ImageId' --output text --filters Name=owner-id,Values=${ACCOUNT} Name=name,Values=dse-* --region ${REGION} --profile ${PROFILE})
for a in $amis; do
  echo "deregistering image: ${a}"
  aws ec2 deregister-image --image-id ${a} --region ${REGION} --profile ${PROFILE}

  snap=$(aws ec2 describe-snapshots --query 'Snapshots[*].SnapshotId' --output text Name=owner-id,Values=${ACCOUNT} Name=description,Values=*${a}* --region ${REGION} --profile ${PROFILE})
  echo "deleting snapshot: ${snap}"
  aws ec2 delete-snapshot --snapshot-id ${s} --region ${REGION} --profile ${PROFILE}
done

for role in "terraform-role" "packer-role"; do
  pols=$(aws iam list-attached-role-policies --query 'AttachedPolicies[*].PolicyArn' --output text --role-name ${role} --profile ${PROFILE})
  for p in $pols; do
    echo "detaching policy: ${p}"
    aws iam detach-role-policy --role-name ${role} --policy-arn ${p} --profile ${PROFILE}
  done

  pols=$(aws iam list-role-policies --query 'PolicyNames' --output text --role-name ${role} --profile ${PROFILE})
  for p in $pols; do
    echo "deleting policy: ${p}"
    aws iam delete-role-policy --role-name ${role} --policy-name ${p} --profile ${PROFILE}
  done

  echo "deleting role: ${role}"
  aws iam delete-role --role-name ${role} --profile ${PROFILE}
done
```
