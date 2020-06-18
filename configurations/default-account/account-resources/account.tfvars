# IAM resources created in the account layer are named generically (e.g. "cassandra-role").  If you're worried about
# naming collisions, you can add a prefix or suffix here (e.g. prefix "dpp-" would result in "dpp-cassandra-role").
# By default, these are set to empty strings.  Whether you create a prefix/suffix or not, these resources are still
# deployed on an account-wide basis, and shared across all clusters you deploy.

iam_resource_prefix=""
iam_resource_suffix=""