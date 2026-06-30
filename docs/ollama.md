# Ollama

Local LLM inference server.

- Port: `11434` (bound to `0.0.0.0` — publicly accessible, no auth)
- Data / model cache: `ollama-data/`
- Container name: `docker_ollama_1`

## Warning

Port 11434 is open to the internet with no authentication. Anyone can run inference or pull models.
Restrict via firewall or rebind to `127.0.0.1:11434` in `docker-compose.yml` if external access is not needed.

## Operations

```bash
# List loaded models
docker exec docker_ollama_1 ollama list

# Pull a model
docker exec docker_ollama_1 ollama pull llama3

# Run interactive
docker exec -it docker_ollama_1 ollama run llama3
```
