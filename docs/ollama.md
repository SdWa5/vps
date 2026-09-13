# Ollama

Local LLM inference server — currently **inactive** (uses Docker Compose profile `ollama`, excluded from default `up`, same pattern as Minecraft).

- Port: `11434`, bound to `0.0.0.0` in the compose file and **not reachable from the internet**
- Data / model cache: `ollama-data/`
- Container name: `docker_ollama_1`

## The port, and what actually closes it

**This section said the port was open to the internet until 2026-09-13, and that had not been true
since 1.11.0.** The container does bind `0.0.0.0:11434` and it does run without authentication, but a
packet arriving from `eth0` toward a container is DNAT'd and traverses `FORWARD`, where
[`hardening/firewall/sdwa5-firewall.sh`](../hardening/firewall/sdwa5-firewall.sh) drops everything in
`DOCKER-USER` except the ports it names, and `11434` is not one of them. Measured on the live host on
2026-09-13: `DOCKER-USER` ends in `-i eth0 -j DROP`, and nothing is listening on `11434` at all,
because the container is profile-gated and stopped.

**Rebind it anyway before starting it again.** `127.0.0.1:11434` in `docker-compose.yml` makes the
container safe on its own rather than safe because of the chain around it, and an unauthenticated
inference endpoint is worth two layers rather than one.

## July 2026 disk cleanup

Ollama was the single biggest disk consumer when the VPS hit 100% full — `ollama-data/models/` held **22 GB**. Since it was unused, it was profile-gated and the models purged:

```bash
cd /opt/docker
docker compose stop ollama && docker compose rm -f ollama
rm -rf ollama-data/models/*
docker image prune -a            # drops the now-unused ollama image
```

The `ollama-data/` dir is kept (ssh keys etc., tiny); only `models/` was wiped. See [maintenance.md](maintenance.md) for the full incident runbook.

## To start (re-enable)

```bash
docker compose --profile ollama up -d ollama
```

Models are gone after the cleanup — re-pull what you need (`ollama pull <model>`).

## Operations

```bash
# List loaded models
docker exec docker_ollama_1 ollama list

# Pull a model
docker exec docker_ollama_1 ollama pull llama3

# Run interactive
docker exec -it docker_ollama_1 ollama run llama3
```
