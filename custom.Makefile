CODEBASE_BRANCH := develop

.SILENT: clone-codebase
clone-codebase:
	[ -d "codebase" ] || (git clone --recursive -b ${CODEBASE_BRANCH} git@github.com:asulibraries/islandora-repo.git codebase)

	# Ideally the following would be in packagist so we can just add them to composer.json, 
	# but for now, due to the GitHub API rate limiting, it is simplier to do it here while we can use our own tokens.
	mkdir -p codebase/web/modules/contrib && cd codebase/web/modules/contrib && \
	([ -d "persistent_identifiers" ]       || (git clone https://github.com/mjordan/persistent_identifiers.git))       && \
	([ -d "islandora_bagger_integration" ] || (git clone https://github.com/mjordan/islandora_bagger_integration.git)) && \
	([ -d "islandora_riprap" ]             || (git clone https://github.com/mjordan/islandora_riprap.git))
	# We don't actually need to clone islandora_repository_reports since it is currently listed as a sub-project of islandora-repo.
	#([ -d "islandora_repository_reports" ] || (git clone https://github.com/mjordan/islandora_repository_reports.git)) && \

.PHONY: dev
#.SILENT: dev
## Make a local site with codebase directory bind mounted, modeled after sandbox.islandora.ca
dev: QUOTED_CURDIR = "$(CURDIR)"
dev: generate-secrets clone-codebase
	$(MAKE) download-default-certs ENVIROMENT=local
	$(MAKE) -B docker-compose.yml ENVIRONMENT=local
	$(MAKE) pull ENVIRONMENT=local
	$(MAKE) set-files-owner SRC=$(CURDIR)/codebase ENVIROMENT=local
	docker-compose up -d --remove-orphans
	docker-compose exec -T drupal with-contenv bash -lc 'composer install; chown -R nginx:nginx .'
	$(MAKE) remove_standard_profile_references_from_config drupal-database8 update-settings-php ENVIROMENT=local
	docker-compose exec -T drupal with-contenv bash -lc "drush si -y minimal --account-pass $(shell cat secrets/live/DRUPAL_DEFAULT_ACCOUNT_PASSWORD)"
	docker-compose exec -T drupal with-contenv bash -lc "./vendor/bin/drupal config:import --directory /var/www/drupal/config/sync"
	docker-compose exec -T drupal with-contenv bash -lc "./vendor/bin/drupal config:import:single --file /var/www/drupal/web/modules/contrib/islandora/modules/islandora_core_feature/config/install/migrate_plus.migration.islandora_tags.yml"
	docker-compose exec -T drupal with-contenv bash -lc "./vendor/bin/drupal config:import:single --file /var/www/drupal/web/modules/contrib/islandora_defaults/config/install/migrate_plus.migration.islandora_defaults_tags.yml"
	docker-compose exec -T drupal drush cr -y

	# Disable filelog since we are using the docker logging instead.
	docker-compose exec -T drupal with-contenv bash -lc "drush pm:un -y filelog"
	$(MAKE) hydrate-asu ENVIRONMENT=local
	#-docker-compose exec -T drupal with-contenv bash -lc 'mkdir -p /var/www/drupal/config/sync && chmod -R 775 /var/www/drupal/config/sync'
	docker-compose exec -T drupal with-contenv bash -lc 'chown -R nginx:nginx /var/www/drupal/web/sites'
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
hydrate-asu: update-config-from-environment namespaces run-islandora-migrations
	docker-compose exec -T drupal drush cr -y