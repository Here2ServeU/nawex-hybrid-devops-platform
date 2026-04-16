locals {
  node_names = [
    for index in range(var.node_count) : "${var.environment}-nawex-node-${index + 1}"
  ]
}
