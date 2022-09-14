.SILENT: clone-codebase
clone-codebase:
	[ -d "codebase" ] || (git clone git@github.com:asulibraries/islandora-repo.git codebase)
ifdef BRANCH
	cd codebase && git checkout -b "${BRANCH}" "origin/${BRANCH}"
endif

.PHONY: dev
#.SILENT: dev
## Make a local site with codebase directory bind mounted, modeled after sandbox.islandora.ca
dev: QUOTED_CURDIR = "$(CURDIR)"
dev: generate-secrets
	$(MAKE) download-default-certs ENVIROMENT=local
	$(MAKE) -B docker-compose.yml ENVIRONMENT=local
	$(MAKE) pull ENVIRONMENT=local
	mkdir -p $(CURDIR)/codebase
	if [ -z "$$(ls -A $(QUOTED_CURDIR)/codebase)" ]; then \
		docker container run --rm -v $(CURDIR)/codebase:/home/root $(REPOSITORY)/nginx:$(TAG) with-contenv bash -lc 'git clone -b main git@github.com:asulibraries/islandora-repo.git /tmp/codebase; mv /tmp/codebase/* /home/root;'; \
	fi
	$(MAKE) set-files-owner SRC=$(CURDIR)/codebase ENVIROMENT=local
	docker-compose up -d --remove-orphans
	docker-compose exec -T drupal with-contenv bash -lc 'composer install; chown -R nginx:nginx .'
	$(MAKE) remove_standard_profile_references_from_config drupal-database8 update-settings-php ENVIROMENT=local
	docker-compose exec -T drupal with-contenv bash -lc "drush si -y standard --account-pass $(shell cat secrets/live/DRUPAL_DEFAULT_ACCOUNT_PASSWORD)"
	docker-compose exec -T drupal with-contenv bash -lc "drush pm:enable -y islandora_defaults"
	$(MAKE) hydrate-asu ENVIRONMENT=local
	-docker-compose exec -T drupal with-contenv bash -lc 'mkdir -p /var/www/drupal/config/sync && chmod -R 775 /var/www/drupal/config/sync'
	$(MAKE) login

.PHONY: drupal-database8
## Creates required databases for drupal site(s) using environment variables.
.SILENT: drupal-database8
drupal-database8:
	docker-compose exec -T drupal timeout 300 bash -c "while ! test -e /var/run/nginx/nginx.pid -a -e /var/run/php-fpm8/php-fpm81.pid; do sleep 1; done"
	docker-compose exec -T drupal with-contenv bash -lc "for_all_sites create_database"

.PHONY: hydrate-asu
.SILENT: hydrate-asu
## Reconstitute the site from environment variables.
hydrate-asu: update-settings-php update-config-from-environment namespaces run-islandora-migrations
	docker-compose exec -T drupal drush cr -y