.PHONY: help build run stop restart logs clean shell check-env check-docker status

# Default values
IMAGE_NAME := bug-buster
CONTAINER_NAME := bug-buster
PORT := 8000
ENV_FILE := .env

# Default target
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "Bug Buster AI - Docker Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

check-env: ## Check if .env file exists
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "Error: $(ENV_FILE) file not found!"; \
		echo "Please create a $(ENV_FILE) file with required environment variables."; \
		exit 1; \
	fi
	@echo "✓ $(ENV_FILE) file found"

check-docker: ## Check if Docker is running
	@if ! docker info > /dev/null 2>&1; then \
		echo "Error: Docker daemon is not running!"; \
		echo ""; \
		echo "Please start Docker Desktop (or Docker daemon) and try again."; \
		echo "On macOS: Open Docker Desktop application"; \
		echo "On Linux: sudo systemctl start docker"; \
		exit 1; \
	fi
	@echo "✓ Docker is running"

build: check-docker ## Build the Docker image
	@echo "Building Docker image: $(IMAGE_NAME)"
	docker build -t $(IMAGE_NAME) .
	@echo "✓ Build complete"

run: check-docker check-env build ## Build and run the container
	@echo "Starting container: $(CONTAINER_NAME)"
	@if docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "Stopping existing container..."; \
		docker stop $(CONTAINER_NAME) > /dev/null 2>&1 || true; \
		docker rm $(CONTAINER_NAME) > /dev/null 2>&1 || true; \
	fi
	docker run -d \
		--name $(CONTAINER_NAME) \
		-p $(PORT):8000 \
		--env-file $(ENV_FILE) \
		$(IMAGE_NAME)
	@echo "✓ Container started on http://localhost:$(PORT)"
	@echo "View logs with: make logs"

stop: check-docker ## Stop the running container
	@if docker ps --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "Stopping container: $(CONTAINER_NAME)"; \
		docker stop $(CONTAINER_NAME); \
		echo "✓ Container stopped"; \
	else \
		echo "Container $(CONTAINER_NAME) is not running"; \
	fi

restart: stop run ## Restart the container

logs: check-docker ## View container logs
	@if docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		docker logs -f $(CONTAINER_NAME); \
	else \
		echo "Container $(CONTAINER_NAME) does not exist"; \
	fi

shell: check-docker ## Open a shell in the running container
	@if docker ps --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		docker exec -it $(CONTAINER_NAME) /bin/bash; \
	else \
		echo "Container $(CONTAINER_NAME) is not running"; \
		echo "Start it with: make run"; \
	fi

clean: check-docker ## Remove container and image
	@echo "Cleaning up Docker resources..."
	@if docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		docker stop $(CONTAINER_NAME) > /dev/null 2>&1 || true; \
		docker rm $(CONTAINER_NAME) > /dev/null 2>&1 || true; \
		echo "✓ Container removed"; \
	fi
	@if docker images --format '{{.Repository}}' | grep -q "^$(IMAGE_NAME)$$"; then \
		docker rmi $(IMAGE_NAME) > /dev/null 2>&1 || true; \
		echo "✓ Image removed"; \
	fi

status: check-docker ## Show container status
	@echo "Container status:"
	@docker ps -a --filter "name=$(CONTAINER_NAME)" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

