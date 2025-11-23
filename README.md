# Bug Buster AI Agent

## A Code Analyzer via Semgrep MCP server for Azure and GCP

![Course Image](assets/cyber.png)

## Key Features

- OpenAI-driven analysis married with Semgrep MCP rules for multi-layered security scanning
- FastAPI backend coordinating LLM inference, static analysis, and reporting pipelines
- Next.js frontend delivering secure uploads, vulnerability triage, and fix guidance
- Docker-based build that packages frontend and backend for consistent environments
- Terraform IaC targeting Azure Container Apps and Google Cloud Run
- GitHub Actions workflows plus reusable bash scripts for automated deploy/destroy sequences

## Local Setup

Choose one of the following options:

### Option 1: Docker (Recommended - No local dependencies needed)

Only requires Docker to be installed. All dependencies are handled inside the container.

**Prerequisites:**
- Docker must be installed and the Docker daemon must be running
- The Makefile will automatically check if Docker is running before executing commands
- If Docker isn't running, you'll get a clear error message with instructions on how to start it

**Quick start with Makefile:**
```bash
make run
```

Or use Docker commands directly:
```bash
docker build -t bug-buster .
docker run --rm --name bug-buster -p 8000:8000 --env-file .env bug-buster
```

**Available Makefile commands:**
- `make run` - Build and run the container (default)
- `make build` - Build the Docker image
- `make stop` - Stop the running container
- `make restart` - Restart the container
- `make logs` - View container logs
- `make shell` - Open a shell in the running container
- `make clean` - Remove container and image
- `make status` - Show container status
- `make help` - Show all available commands

### Option 2: Local Development (Requires node and uv)

For local development without Docker, you'll need to install `node` and `uv`:

```bash
node --version
uv --version
```

#### Run Backend Server 

```bash
cd backend
uv run server.py
```

#### Run Frontend 
```bash
cd frontend
npm install
npm run dev
```

## Deployment

For detailed deployment instructions, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

#llms #mcpservers #semgrep #fastapi #nextjs #docker #terraform #githubactions #azure #openai