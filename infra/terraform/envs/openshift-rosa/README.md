# ROSA (Red Hat OpenShift on AWS) — Classic

Provisions a managed OpenShift cluster on AWS via the
[`terraform-redhat/rosa-classic`](https://registry.terraform.io/modules/terraform-redhat/rosa-classic/rhcs)
module.

## Prerequisites

1. An AWS account with the [ROSA prerequisites satisfied](https://docs.openshift.com/rosa/rosa_install_access_delete_clusters/rosa_getting_started_iam/rosa-sts-aws-prereqs.html).
2. An OCM API token from [https://console.redhat.com/openshift/token](https://console.redhat.com/openshift/token).
3. ROSA CLI installed and account roles created:

   ```bash
   rosa login --token="$RHCS_TOKEN"
   rosa create account-roles --mode auto --yes
   rosa create ocm-role --mode auto --yes
   rosa create user-role --mode auto --yes
   ```

4. Record the account role ARNs from `rosa list account-roles` — pass them as
   `installer_role_arn`, `support_role_arn`, `controlplane_role_arn`, and
   `worker_role_arn` in a `terraform.tfvars` file.

## Apply

```bash
export RHCS_TOKEN='...'
terraform init
terraform apply
```

Expect ~40 minutes for a fresh cluster. The console URL is in the outputs;
log in with `oc login` (the command is printed).
