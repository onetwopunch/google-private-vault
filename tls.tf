#
# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
# This file contains the steps to create and sign TLS self-signed certs for
# Vault.
#

# Generate a self-sign TLS certificate that will act as the root CA.
resource "null_resource" "vault-tls" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/create-tls-certs.sh"
    environment = {
      SHOULD_RUN           = "${google_storage_bucket.vault.name == local.vault_tls_bucket ? "1" : "0"}"
      ENCRYPT_AND_UPLOAD   = "1"
      PROJECT              = "${var.project_id}"
      BUCKET               = "${google_storage_bucket.vault.name}"
      LB_IP                = "${var.internal_lb_ip}"
      KMS_KEYRING          = "${google_kms_key_ring.vault.name}"
      KMS_LOCATION         = "${google_kms_key_ring.vault.location}"
      KMS_KEY              = "${google_kms_crypto_key.vault-init.name}"
    }
  }
  depends_on = ["google_storage_bucket.vault"]
}
