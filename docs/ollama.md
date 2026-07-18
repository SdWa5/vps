# Ollama

Local LLM inference server — currently **inactive** (uses Docker Compose profile `ollama`, excluded from default `up`, same pattern as Minecraft).

- Port: `11434` (bound to `0.0.0.0` — publicly accessible, no auth)
- Data / model cache: `ollama-data/`
- Container name: `docker_ollama_1`

## Warning

Port 11434 is open to the internet with no authentication. Anyone can run inference or pull models.
Restrict via firewall or rebind to `127.0.0.1:11434` in `docker-compose.yml` if external access is not needed.

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
