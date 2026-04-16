locals {
  normalized_tags = merge(
    {
      project    = "nawex-hybrid-devops-platform"
      managed_by = "terraform"
      component  = "network"
    },
    var.tags,
  )
}
