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
# This file contains the actual Vault server definitions
#

# Template for creating Vault nodes
resource "google_compute_instance_template" "vault" {
  project     = "${var.project_id}"
  region      = "${var.region}"
  name_prefix = "vault-"

  machine_type = "${var.vault_machine_type}"

  labels = "${var.vault_instance_labels}"

  network_interface {
    subnetwork         = "${google_compute_subnetwork.vault-subnet.self_link}"
    subnetwork_project = "${var.project_id}"
  }

  disk {
    source_image = "debian-cloud/debian-9"
    type         = "PERSISTENT"
    disk_type    = "pd-ssd"
    mode         = "READ_WRITE"
    boot         = true
  }

  service_account {
    email  = "${google_service_account.vault-admin.email}"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = "${merge(var.vault_instance_metadata, map(
    "google-compute-enable-virtio-rng", "true",
    "startup-script", data.template_file.vault-startup-script.rendered,
  ))}"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = ["google_project_service.service"]
}

resource "google_compute_instance" "bastion" {
  project     = "${var.project_id}"
  zone         = "${var.region}-a"
  name        = "vault-bastion"

  machine_type = "${var.vault_machine_type}"
  network_interface {
    subnetwork         = "${google_compute_subnetwork.vault-subnet.self_link}"
    subnetwork_project = "${var.project_id}"
  }

  service_account {
    email  = "${google_service_account.bastion.email}"
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }

  scratch_disk {}
  metadata_startup_script = "${data.template_file.bastion-startup-script.rendered}"
  depends_on = ["google_project_service.service"]
}

resource "google_compute_health_check" "vault" {
 name = "internal-service-health-check"

 timeout_sec        = 1
 check_interval_sec = 1

 tcp_health_check {
   port = "${var.vault_port}"
 }
}

# Forward external traffic to the target pool
resource "google_compute_forwarding_rule" "vault" {
  project = "${var.project_id}"

  name                  = "vault"
  region                = "${var.region}"
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL"
  ip_address            = "${var.internal_lb_ip}"
  network               = "${google_compute_network.vault-network.self_link}"
  subnetwork            = "${google_compute_subnetwork.vault-subnet.self_link}"

  backend_service       = "${google_compute_region_backend_service.vault.self_link}"
  ports                 = ["${var.vault_port}"]

  depends_on = ["google_project_service.service"]
}

# Vault instance group manager
resource "google_compute_region_instance_group_manager" "vault" {
  project = "${var.project_id}"

  name   = "vault-igm"
  region = "${var.region}"

  base_instance_name = "vault-${var.region}"
  instance_template  = "${google_compute_instance_template.vault.self_link}"
  wait_for_instances = false

  named_port {
    name = "vault-http"
    port = "${var.vault_port}"
  }

  depends_on = ["google_project_service.service"]
}

resource "google_compute_region_backend_service" "vault" {
  name          = "vault-backend-service"
  region        = "${var.region}"
  health_checks = ["${google_compute_health_check.vault.self_link}"]
  backend {
    group = "${google_compute_region_instance_group_manager.vault.instance_group}"
  }
}

# Autoscaling policies for vault
resource "google_compute_region_autoscaler" "vault" {
  project = "${var.project_id}"

  name   = "vault-as"
  region = "${var.region}"
  target = "${google_compute_region_instance_group_manager.vault.self_link}"

  autoscaling_policy {
    min_replicas    = "${var.vault_min_num_servers}"
    max_replicas    = "${var.vault_max_num_servers}"
    cooldown_period = 300

    cpu_utilization {
      target = 0.8
    }
  }

  depends_on = ["google_project_service.service"]
}
