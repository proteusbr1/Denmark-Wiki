.PHONY: up down restart logs status ps build pull backup clean help

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
