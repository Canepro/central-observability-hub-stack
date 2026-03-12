resource "null_resource" "jenkins_bridge_direct_excerpts_proof" {
  triggers = {
    # Intentional syntax error for bridge-evidence proof.
    proof = "missing-quote
  }
}
