# ha-vault-in-swarm-with-transit

A repo containing an example of Hashicorp vault on Docker Swarm using integrated raft storage, and autounseal via transit.

## Environment Setup

A couple of things are going to need to be setup for this sample to actually run out the box.

I do the bulk of my scripting in gnu make because its widely available. On linux and MacOS systems. On Windows You might need to install gnu make in WSL2.

There must be a docker swarm. The Box being used to deploy must be a manager, or a Docker Desktop with the default docker context pointing to a swarm manager. Addtionally the helper functions that open shells into the transit and vault instances assume that there are preconfigured contexts for each swarm node.

I also assume the existence of a docker volume plugin that provides cluster volumes. On my swarm, "glusterfs" is available, and each vault replica uses a named volume `'{{index .Service.Labels "com.docker.stack.namespace"}}_vault-{{.Task.Slot}}'`. This will need to be adjusted for however your own swarm handles clustered persistent volumes.

I assume Traefik is used on the swarm for ingress routing, and that there is a wildcard DNS pointing to the swarm. Plug your wildcard dns DOMAIN into `.env` to replace `example.com`. Using the vault GUI is not an imporant part of this demo, so fixing this is optional.

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

## Additional notes.

Using `caddy` to offload the Traefik connections from vault might add an extra hop but is an important design choice. Vault rejects listening on 0.0.0.0 if that represents more than one network interface, the alternative is to provide a `VAULT_CLUSTER_INTERFACE: eth0`. This in turn overrides more than the listen address, but also `cluster_addr` and means that the cluster and raft both snapshot the container IPs at a point in time - Any task restarts will pick new IPs and the vault cluster will fail.
Using `caddy` means there is only a single network attached to vault and solves this complication.
