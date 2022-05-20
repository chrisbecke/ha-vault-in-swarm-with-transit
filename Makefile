include .env

stack = $(notdir $(PWD))
context = 
service ?= transit

DOCKER = docker
ifneq ($(context),)
DOCKER += --context $(context)
endif

FILES = vault-stack.yml
STACK = $(stack)
SERVICE = $(STACK)_$(service)
TRANSIT_FILES += transit-stack.yml
VAULT_FILES += vault-stack.yml

service_ps_1 = $(shell $(DOCKER) service ps $(SERVICE) --no-trunc --filter desired-state=running --format '{{.Name}}.{{.ID}} {{.Node}}')
service_name = $(word 1,$(service_ps_1))
service_node = $(word 2,$(service_ps_1))

ENV += DOMAIN=$(DOMAIN)
ENV += STACK=$(STACK)
ENV += TRANSIT_TOKEN=$(TRANSIT_TOKEN)
cmd = /bin/sh

#.EXPORT_ALL_VARIABLES:

transit:
	@$(ENV) $(DOCKER) stack deploy $(addprefix --compose-file ,$(TRANSIT_FILES)) $(STACK)
	@open http://transit.$(STACK).$(DOMAIN)

ps:
	@$(DOCKER) stack ps $(STACK) --no-trunc --format "table{{.ID}}\t{{.Name}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}"

shell:
	$(MAKE) exec context=$(service_node) container=$(service_name) cmd='$(cmd)'

transit-shell:
	$(MAKE) exec context=$(service_node) container=$(service_name) cmd=/bin/sh

exec:
	$(DOCKER) exec -it $(container) $(cmd)

vault:
	$(ENV) $(DOCKER) stack deploy $(addprefix --compose-file ,$(VAULT_FILES)) $(STACK)
	@open http://vault.$(STACK).$(DOMAIN)

vault-shell:
	@$(MAKE) shell service=vault

clean:
	@$(DOCKER) stack rm $(STACK)
	@$(DOCKER) volume rm $(STACK)_transit
	@$(DOCKER) volume rm $(STACK)_vault-1
	@$(DOCKER) volume rm $(STACK)_vault-2
	@$(DOCKER) volume rm $(STACK)_vault-3
