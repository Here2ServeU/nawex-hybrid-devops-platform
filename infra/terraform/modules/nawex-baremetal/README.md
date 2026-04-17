# nawex-baremetal

Reusable Terraform module that turns a vendor-agnostic host list into the
structure OpenShift's `platform: baremetal` install-config expects, with
the correct Redfish virtual-media URL per vendor:

| Vendor | URL scheme                  | Typical platform         |
|--------|-----------------------------|--------------------------|
| `dell` | `idrac-virtualmedia://`     | PowerEdge R650 / R750    |
| `hpe`  | `ilo5-virtualmedia://`      | ProLiant DL360 / DL380   |
| `cisco`| `redfish-virtualmedia://`   | UCS C220 / C240 standalone CIMC |

## Usage

```hcl
module "baremetal" {
  source = "../../modules/nawex-baremetal"

  bmc_username = var.bmc_username
  bmc_password = var.bmc_password

  bm_hosts = [
    {
      name = "master-0", role = "master", vendor = "dell",
      bmc_address = "10.0.0.11", bmc_system_id = "System.Embedded.1",
      boot_mac = "aa:bb:cc:00:00:01", root_device = "/dev/nvme0n1"
    },
    {
      name = "worker-0", role = "worker", vendor = "hpe",
      bmc_address = "10.0.0.21", bmc_system_id = "1",
      boot_mac = "aa:bb:cc:00:01:00", root_device = "/dev/sda"
    },
  ]
}

# Consume in install-config.yaml:
locals {
  install_config = yamlencode({
    # ...
    platform = {
      baremetal = {
        apiVIPs     = [var.api_vip]
        ingressVIPs = [var.ingress_vip]
        hosts       = module.baremetal.hosts
        # ...
      }
    }
  })
}
```

## Outputs

- `hosts` — ready-to-embed list of host blocks for the `baremetal` platform.
- `host_count_by_vendor` — map of vendor → count; useful for dashboards.
- `summary` — one-line human-readable summary per host.
