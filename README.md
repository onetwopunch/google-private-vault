# Vault on GCE behind IAP with Bastion Terraform Module


## Differences from Upstream

This was originally forked from [terraform-google-vault](https://github.com/terraform-google-modules/terraform-google-vault) and adds the following security controls/enhancements:

* TLS private keys are not added in plain text to the terraform state file
* Ability for orgs to manage their own TLS certificates via a bucket
* Vault is not reachable by anything but the bastion host by default.
* Vault is behind an internal load balancer, whose IP is in the SAN of the TLS certificate
* Bastion host is private and only available via IAP tunnelling
* Firewall rules use service accounts instead of network tags

## Features

- **Vault HA** - Vault is configured to run in high availability mode with
  Google Cloud Storage. Choose a `min_num_vault_servers` greater than 0 to
  enable HA mode.

- **Production hardened** - Vault is deployed according to applicable parts of
  the [production hardening guide][vault-production-hardening].

    - Traffic is encrypted with end-to-end TLS using self-signed certificates.

    - Vault is the main process on the VMs, and Vault runs as an unprivileged
      user `(vault:vault)` on the VMs under systemd.

    - Outgoing Vault traffic happens through a restricted NAT gateway through
      dedicated IPs for logging and monitoring. You can further restrict
      outbound access with additional firewall rules.

    - The Vault nodes are not publicly accessible. They _do_ have SSH enabled,
      but require a bastion host on their dedicated network to access. You can
      disable SSH access entirely by setting `ssh_allowed_cidrs` to the empty
      list.

    - Swap is disabled (the default on all GCE VMs), reducing the risk that
      in-memory data will be paged to disk.

    - Core dumps are disabled.

    The following values do not represent Vault's best practices and you may
    wish to change their defaults:

    - Auditing is not enabled by default, because an initial bootstrap requires
      you to initialize the Vault. Everything is pre-configured for when you're
      ready to enable audit logging, but it cannot be enabled before Vault is
      initialized.

  - **Auto-unseal** - Vault is automatically unsealed using the built-in Vault
    1.0+ auto-unsealing mechanisms for Google Cloud KMS. The Vault servers are
    **not** automatically initialized, providing a clear separation.

  - **Isolation** - The Vault nodes are not exposed publicly. They live in a
    private subnet with a dedicated NAT gateway.

  - **Audit logging** - The system is setup to accept Vault audit logs with a
    single configuration command. Vault audit logs are not enabled by default
    because you have to initialize the system first.


## Usage

1. Add the module definition to your Terraform configurations:

    ```hcl
    module "vault" {
      source         = "github.com/onetwopunch/gcp-vault-bastion-iap"
      project_id     = "${var.project_id}"
      region         = "${var.region}"
      kms_keyring    = "${var.kms_keyring}"
      kms_crypto_key = "${var.kms_crypto_key}"
    }
    ```

1. Execute Terraform:

    ```
    $ terraform apply
    ```

1. Wait for the bastion and vault servers to come online

    ```
    $ gcloud beta compute ssh vault-bastion --tunnel-through-iap
    ```

1. Initialize the Vault cluster, generating the initial root token and unseal
keys:

    ```
    $ vault operator init \
        -recovery-shares 5 \
        -recovery-threshold 3
    ```

    The Vault servers will automatically unseal using the Google Cloud KMS key
    created earlier. The recovery shares are to be given to operators to unseal
    the Vault nodes in case Cloud KMS is unavailable in a disaster recovery.
    They can also be used to generate a new root token. Distribute these keys to
    trusted people on your team (like people who will be on-call and responsible
    for maintaining Vault).

    The output will look like this:

    ```
    Recovery Key 1: 2EWrT/YVlYE54EwvKaH3JzOGmq8AVJJkVFQDni8MYC+T
    Recovery Key 2: 6WCNGKN+dU43APJuGEVvIG6bAHA6tsth5ZR8/bJWi60/
    Recovery Key 3: XC1vSb/GfH35zTK4UkAR7okJWaRjnGrP75aQX0xByKfV
    Recovery Key 4: ZSvu2hWWmd4ECEIHj/FShxxCw7Wd2KbkLRsDm30f2tu3
    Recovery Key 5: T4VBvwRv0pkQLeTC/98JJ+Rj/Zn75bLfmAaFLDQihL9Y

    Initial Root Token: s.kn11NdBhLig2VJ0botgrwq9u
    ```

    **Save this initial root token and do not clear your history. You will need
    this token to continue the tutorial.**


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| `allowed_service_accounts` | Service account emails that are allowed to communicate to Vault over HTTPS on port 8200. By default, only the bastion and Vault nodes themselves are permitted. | list | `<list>` | no |
| `internal_lb_ip` | RFC 1918 Address for internal load balancer | string | `"10.127.13.37"` | no |
| `kms_crypto_key` | The name of the Cloud KMS Key used for encrypting initial TLS certificates and for configuring Vault auto-unseal. | string | `"vault-init"` | no |
| `kms_keyring` | Name of the Cloud KMS KeyRing for asset encryption. | string | n/a | yes |
| `kms_protection_level` | The protection level to use for the KMS crypto key. | string | `"software"` | no |
| `network_subnet_cidr_range` | CIDR block range for the subnet. | string | `"10.127.0.0/20"` | no |
| `project_id` | ID of the project in which to create resources and add IAM bindings. | string | n/a | yes |
| `project_services` | List of services to enable on the project where Vault will run. These services are required in order for this Vault setup to function.<br><br>To disable, set to the empty list []. You may want to disable this if the services have already been enabled and the current user does not have permission to enable new services. | list | `<list>` | no |
| `region` | Region in which to create resources. | string | `"us-east4"` | no |
| `service_account_name` | Name of the Vault service account. | string | `"vault-admin"` | no |
| `service_account_project_additional_iam_roles` | List of custom IAM roles to add to the project. | list | `<list>` | no |
| `service_account_project_iam_roles` | List of IAM roles for the Vault admin service account to function. If you need to add additional roles, update `service_account_project_additional_iam_roles` instead. | list | `<list>` | no |
| `service_account_storage_bucket_iam_roles` | List of IAM roles for the Vault admin service account to have on the storage bucket. | list | `<list>` | no |
| `storage_bucket_force_destroy` | Set to true to force deletion of backend bucket on `terraform destroy`. | string | `"false"` | no |
| `storage_bucket_location` | Location for the multi-regional Google Cloud Storage bucket in which Vault data will be stored. Valid values include:<br><br>  - asia   - eu   - us | string | `"us"` | no |
| `storage_bucket_name` | Name of the Google Cloud Storage bucket for the Vault backend storage. This must be globally unique across of of GCP. If left as the empty string, this will default to: "<project-id>-vault-data". | string | `""` | no |
| `vault_args` | Additional command line arguments passed to Vault server/ | string | `""` | no |
| `vault_ca_cert_filename` | GCS object path within the vault_tls_bucket. This is the root CA certificate. Default: ca.crt | string | `"ca.crt"` | no |
| `vault_instance_labels` | Labels to apply to the Vault instances. | map | `<map>` | no |
| `vault_instance_metadata` | Additional metadata to add to the Vault instances. | map | `<map>` | no |
| `vault_instance_tags` | Additional tags to apply to the instances. Note "allow-ssh" and "allow-vault" will be present on all instances. | list | `<list>` | no |
| `vault_log_level` | Log level to run Vault in. See the Vault documentation for valid values. | string | `"warn"` | no |
| `vault_machine_type` | Machine type to use for Vault instances. | string | `"n1-standard-1"` | no |
| `vault_max_num_servers` | Maximum number of Vault server nodes to run at one time. The group will not autoscale beyond this number. | string | `"7"` | no |
| `vault_min_num_servers` | Minimum number of Vault server nodes in the autoscaling group. The group will not have less than this number of nodes. | string | `"2"` | no |
| `vault_port` | Numeric port on which to run and expose Vault. This should be a high-numbered port, since Vault does not run as a root user and therefore cannot bind to privledged ports like 80 or 443. The default is 8200, the standard Vault port. | string | `"8200"` | no |
| `vault_tls_bucket` | GCS bucket where TLS certificates and encrypted keys are stored. Override this value if you already have certificates created and managed for Vault. | string | `""` | no |
| `vault_tls_cert_filename` | GCS object path within the vault_tls_bucket. This is the vault server certificate. Default: vault.crt | string | `"vault.crt"` | no |
| `vault_tls_disable_client_certs` | Use and expect client certificates. You may want to disable this if users will not be authenticating to Vault with client certificates. | string | `"false"` | no |
| `vault_tls_key_filename` | Encrypted GCS object path within the vault_tls_bucket. This is the Vault TLS private key. Default: vault.key.enc | string | `"vault.key.enc"` | no |
| `vault_ui_enabled` | Controls whether the Vault UI is enabled and accessible. | string | `"true"` | no |
| `vault_version` | Version of vault to install. This version must be 1.0+ and must be published on the HashiCorp releases service. | string | `"1.0.3"` | no |

## Outputs

| Name | Description |
|------|-------------|
| bastion_ssh_command | Command to run to allow access into the Vault Bastion for administration via IAP tunnel |


## Resources

See the [resources in the Terraform module registry][registry-resources]. Be
sure to choose the version that corresponds to the version of the module you are
using locally.


## Additional permissions

The default installation includes the most minimal set of permissions to run
Vault. Certain plugins may require more permissions, which you can grant to the
service account using `service_account_project_additional_iam_roles`:

### GCP auth method

The GCP auth method requires the following additional permissions:

```
roles/iam.serviceAccountKeyAdmin
```

### GCP secrets engine

The GCP secrets engine requires the following additional permissions:

```
roles/iam.serviceAccountKeyAdmin
roles/iam.serviceAccountAdmin
```

### GCP KMS secrets engine

The GCP secrets engine permissions vary. There are examples in the secrets
engine documentation.


## Logs

The Vault server logs will automatically appear in Stackdriver under "GCE VM
Instance" tagged as "vaultproject.io/server".

The Vault audit logs, once enabled, will appear in Stackdriver under "GCE VM
Instance" tagged as "vaultproject.io/audit".



## FAQ

- **I see unhealthy Vault nodes in my load balancer pool!**

    This is the expected behavior. Only the _active_ Vault node is added to the
    load balancer to [prevent redirect loops][vault-redirect-loop]. If that node
    loses leadership, its health check will start failing and a standby node
    will take its place in the load balancer.

- **Can I connect to the Vault nodes directly?**

    Connecting to the vault nodes directly is not recommended, even if on the
    same network. Always connect through the load balance. You can alter the
    load balancer to be an internal-only load balancer if needed.

[vault-redirect-loop]: https://www.vaultproject.io/docs/concepts/ha.html#behind-load-balancers
[vault-production-hardening]: https://www.vaultproject.io/guides/operations/production.html
[registry-inputs]: https://registry.terraform.io/modules/terraform-google-modules/vault/google?tab=inputs
[registry-outputs]: https://registry.terraform.io/modules/terraform-google-modules/vault/google?tab=outputs
[registry-resources]: https://registry.terraform.io/modules/terraform-google-modules/vault/google?tab=resources
