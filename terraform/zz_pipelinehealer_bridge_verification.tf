resource "null_resource" "pipelinehealer_bridge_verification" {
  triggers = {
    broken = "missing-closing-brace"
  }
