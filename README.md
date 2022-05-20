# ha-vault-in-swarm-with-transit

A repo containing an example of Hashicorp vault on Docker Swarm using integrated raft storage, and autounseal via transit.

## Docker Swarm Setup

For the best results, this needs to be run on a docker swarm that has traefik, and wildcard dns.

Plug your wildcard dns DOMAIN into `.env` to replace `example.com`.

## Setup the transit vault

The transit vault is not intended as a production ready configuration example. It merely provides a minimal vault that can host the `transit` secrets engine. In a real setup this would be a different highly available vault entirely and would not sit in the same stack.

Bring up transit with the following commands.

```bash
docker context use <your swarm manager context>
make transit
```

Then setup the transit vault. If you have traefik, then [transit.ha-vault-in-swarm-with-transit.example.com](http://transit.ha-vault-in-swarm-with-transit.example.com) should be available. Either use the GUI to set it up with key shares: `1` key threshold: `1`, save the keys and proceed to unseal and login.

Otherwise, use the cli to initialize the transit vault and proceed:

```bash
make transit-shell
vault operator-init -n 1 -t 1
vault operator unseal <unseal_key>
vault login <token>
```

Now, use the GUI to enable the transit secrets engine at the default path, and create an encryption key called `autounseal`, and a policy called `autounseal` granting access to the newly created transit key.

```hcl
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
```

Alternatively, the cli commands with the transit-shell are

```bash
vault secrets enable transit
vault vault write -f transit/keys/autounseal
# Create a policy granting to the key
tee autounseal.hcl <<EOF
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
EOF
vault policy write autounseal autounseal.hcl
```

I don't know how to obtain a Token via the GUI. At the CLI execute the following to obtain a token and unwrap it. Substitute the value for .wrap_info.token for `{token}`

```bash
# If you don't have a transit shell already
make transit-shell
vault login <token>
# Obtain a token
vault token create -policy=autounseal -wrap-ttl=120 -format=json
VAULT_TOKEN={token} vault unwrap
```

## Deploy HA Vault

Paste the obtained token into the `.env` file as the value of `TRANSIT_TOKEN` and run the following to deploy a 3 node vault.

```bash
make vault
make vault-shell
vault operator init
```

This will initialize vault on the first node, which will create 5 recovery keys and an initial root token. 
Use the root token to log in and see that the raft storage has found and configured all 3 cluster peers.

```bash
vault login root_token
vault operator members
vault operator raft list-peers
```

You can now verify the HA status of this cluster by using docker commands to kill the vault1..3 tasks and verifying the vault cluster recovers when there is a quorum of nodes available.

