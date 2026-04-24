.PHONY: up down restart logs status ps build pull update prod-update backup clean help

# Default target
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

up: ## Start Wiki.js (detached)
	docker compose up -d

down: ## Stop Wiki.js
	docker compose down

restart: ## Restart all services
	docker compose restart

logs: ## Show logs (follow mode)
	docker compose logs -f

logs-wiki: ## Show only wiki logs
	docker compose logs -f wiki

logs-db: ## Show only database logs
	docker compose logs -f db

status: ## Show container status
	docker compose ps

pull: ## Pull latest images
	docker compose pull

update: pull ## Update images and recreate containers
	docker compose up -d --remove-orphans

prod-update: ## Full prod update: git pull → pull images → up → wait healthy → prune
	@set -e; \
	echo "==> [1/5] git pull --ff-only"; \
	git pull --ff-only; \
	echo "==> [2/5] Pulling images"; \
	docker compose pull; \
	echo "==> [3/5] Up -d --remove-orphans"; \
	docker compose up -d --remove-orphans; \
	echo "==> [4/5] Waiting for services healthy (timeout 180s)"; \
	deadline=$$(( $$(date +%s) + 180 )); \
	for pair in "db:demark-wiki-db" "wiki:demark-wiki"; do \
	  svc=$${pair%%:*}; cname=$${pair##*:}; \
	  echo "    checking $$svc ($$cname)..."; \
	  while true; do \
	    health=$$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' $$cname 2>/dev/null || echo missing); \
	    state=$$(docker inspect --format '{{.State.Status}}' $$cname 2>/dev/null || echo missing); \
	    if [ "$$health" = "healthy" ]; then echo "      $$svc: healthy"; break; fi; \
	    if [ "$$health" = "no-healthcheck" ] && [ "$$state" = "running" ]; then echo "      $$svc: running (no HEALTHCHECK)"; break; fi; \
	    if [ $$(date +%s) -ge $$deadline ]; then \
	      echo "      $$svc: TIMEOUT (state=$$state health=$$health)"; \
	      docker compose logs --tail=30 $$svc; \
	      exit 1; \
	    fi; \
	    sleep 3; \
	  done; \
	done; \
	echo "==> [5/5] Pruning dangling images"; \
	docker image prune -f; \
	echo "prod-update complete"

backup: ## Backup database to backups/ folder
	@mkdir -p backups
	docker compose exec db pg_dump -U $${DB_USER:-wikijs} $${DB_NAME:-wiki} | gzip > backups/wiki-$$(date +%Y%m%d-%H%M%S).sql.gz
	@echo "Backup saved to backups/"
	@ls -lh backups/*.gz | tail -1

restore: ## Restore database from latest backup (usage: make restore FILE=backups/file.sql.gz)
	@if [ -z "$(FILE)" ]; then echo "Usage: make restore FILE=backups/your-backup.sql.gz"; exit 1; fi
	@echo "Restoring from $(FILE)..."
	gunzip -c $(FILE) | docker compose exec -T db psql -U $${DB_USER:-wikijs} $${DB_NAME:-wiki}
	@echo "Restore complete."

shell-db: ## Open psql shell in database
	docker compose exec db psql -U $${DB_USER:-wikijs} $${DB_NAME:-wiki}

shell-wiki: ## Open shell in wiki container
	docker compose exec wiki sh

clean: ## Stop and remove containers, networks, and volumes (DESTRUCTIVE)
	@echo "WARNING: This will delete all data including the database!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	docker compose down -v
