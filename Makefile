# Makefile - campus lab driver. Run inside WSL2 Ubuntu from the repo root.
#
#   make setup        install docker/containerlab/tools, load kernel modules
#   make up           build local images, deploy the lab (no-op if already up and healthy)
#   make down         destroy the lab and clean up
#   make verify       acceptance matrix V1..V12, non-zero exit on any FAIL
#   make accept M=M2  one milestone's acceptance tests (M=all runs every built one)
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

.PHONY: help setup images up down redeploy inspect graph verify accept attack-demo quarantine release record

help:
	@sed -n '3,11p' Makefile | sed 's/^# \{0,1\}//'

setup:
	bash scripts/00-setup.sh

# Every images/<name>/Dockerfile becomes campus/<name>:latest (build cache = no-op if unchanged).
images:
	@for d in images/*/; do n=$$(basename $$d); echo "building campus/$$n:latest"; \
	  $(DOCKER) build -q -t campus/$$n:latest $$d >/dev/null || exit 1; done

up: images
	@if bash -c '. scripts/lib.sh; lab_healthy'; then \
	  echo "lab '$(LAB)' is already up and healthy (use 'make redeploy' to rebuild it)"; \
	else \
	  $(CLAB) deploy -t $(TOPO) --reconfigure && \
	  bash -c '. scripts/lib.sh; info "waiting for node init"; wait_lab_ready && info "lab ready"'; \
	fi

redeploy: images
	$(CLAB) deploy -t $(TOPO) --reconfigure
	@bash -c '. scripts/lib.sh; info "waiting for node init"; wait_lab_ready && info "lab ready"'

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

# Per-milestone acceptance tests (CLAUDE.md section 5): make accept M=M2
M ?= all
accept:
	@bash scripts/accept.sh $(M)

attack-demo:
	@echo "attack-demo arrives with milestone M10 (validation harness)."; exit 1

quarantine:
	@echo "quarantine arrives with milestone M6 (Campus Guardian)."; exit 1

release:
	@echo "release arrives with milestone M6 (Campus Guardian)."; exit 1

record:
	bash scripts/record.sh
