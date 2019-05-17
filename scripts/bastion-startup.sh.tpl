sudo apt install -y zip curl

# Install Vault
curl -o /tmp/vault.zip https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_linux_amd64.zip
pushd /tmp
unzip vault.zip
mv vault /usr/local/bin/
popd

# TLS cert
mkdir /etc/vault/
gsutil cp gs://${vault_tls_bucket}/${vault_ca_cert_filename} /etc/vault/ca.crt

cat << 'EOF' > /etc/motd
____   ____            .__   __    __________                  __  .__
\   \ /   /____   __ __|  |_/  |_  \______   \_____    _______/  |_|__| ____   ____
 \   Y   /\__  \ |  |  \  |\   __\  |    |  _/\__  \  /  ___/\   __\  |/  _ \ /    \
  \     /  / __ \|  |  /  |_|  |    |    |   \ / __ \_\___ \  |  | |  (  <_> )   |  \
   \___/  (____  /____/|____/__|    |______  /(____  /____  > |__| |__|\____/|___|  /
               \/                          \/      \/     \/                      \/
-------------------------------------------------------------------------------------


export VAULT_ADDR=https://${lb_ip}:8200
export VAULT_CACERT=/etc/vault/ca.crt

EOF
