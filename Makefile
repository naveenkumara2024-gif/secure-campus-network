# Makefile - campus lab driver. Run inside WSL2 Ubuntu from the repo root.
#
#   make setup        install docker/containerlab/tools, load kernel modules
#   make up           build local images, deploy the lab (no-op if already up and healthy)
#   make down         destroy the lab and clean up
#   make verify       acceptance matrix V1..V12, non-zero exit on any FAIL
#   make graph        topology graph (or use VS Code TopoViewer)
#   make attack-demo  Guardian validation harness (M10)
#   make quarantine P=p2 N=acc1   isolate an access port (M6), `make release` undoes it
#   make record       capture a clean verify run
SHELL  := /bin/bash
LAB    := campus
TOPO   := campus.clab.yml
SUDO   := $(shell [ "$$(id -u)" -eq 0 ] || echo sudo)
# containerlab is installed setuid-root for the clab_admins group, so members need no sudo.
CLAB_SUDO := $(shell if [ "$$(id -u)" -eq 0 ] || id -nG | grep -qw clab_admins; then :; else echo sudo; fi)
CLAB   := $(CLAB_SUDO) containerlab
DOCKER := $(shell docker info >/dev/null 2>&1 && echo docker || echo "$(SUDO) docker")
P ?= p2
N ?= acc1

.PHONY: help setup images up down redeploy inspect graph verify attack-demo quarantine release record

help:
	@sed -n '3,10p' Makefile | sed 's/^# \{0,1\}//'

setup:
	bash scripts/00-setup.sh

images:
	$(DOCKER) build -q -t campus/vpn:latest images/vpn

up: images
	@if bash -c '. scripts/lib.sh; lab_healthy'; then \
	  echo "lab '$(LAB)' is already up and healthy (use 'make redeploy' to rebuild it)"; \
	else \
	  $(CLAB) deploy -t $(TOPO) --reconfigure; \
	fi

redeploy: images
	$(CLAB) deploy -t $(TOPO) --reconfigure

down:
	$(CLAB) destroy -t $(TOPO) --cleanup

inspect:
	$(CLAB) inspect -t $(TOPO)

graph:
	@echo "Serving the topology graph on http://localhost:50080 (Ctrl-C to stop)."
	@echo "In VS Code, the Containerlab extension's TopoViewer draws the same graph."
	$(CLAB) graph -t $(TOPO)

verify:
	@bash scripts/verify.sh

attack-demo:
	@echo "attack-demo arrives with milestone M10 (validation harness)."; exit 1

quarantine:
	@echo "quarantine arrives with milestone M6 (Campus Guardian)."; exit 1

release:
	@echo "release arrives with milestone M6 (Campus Guardian)."; exit 1

record:
	bash scripts/record.sh
