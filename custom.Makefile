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

	# Install and Site settings
	docker-compose exec -T drupal with-contenv bash -lc 'composer install; chown -R nginx:nginx .'
	$(MAKE) remove_standard_profile_references_from_config drupal-database8 update-settings-php ENVIROMENT=local
	docker-compose exec -T drupal with-contenv bash -lc "for_all_sites install_site"
	docker-compose exec -T drupal drush cr -y

	# More settings plus content
	$(MAKE) hydrate-asu ENVIRONMENT=local

	# Login URLs
	docker-compose exec -T drupal with-contenv bash -lc "drush uli --uri=$(DOMAIN)"
	docker-compose exec -T drupal with-contenv bash -lc "drush uli --uri=$(PRISM_DOMAIN)"

.PHONY: drupal-database8
## Creates required databases for drupal site(s) using environment variables.
.SILENT: drupal-database8
drupal-database8:
	docker-compose exec -T drupal timeout 300 bash -c "while ! test -e /var/run/nginx/nginx.pid -a -e /var/run/php-fpm8/php-fpm81.pid; do sleep 1; done"
	docker-compose exec -T drupal with-contenv bash -lc "for_all_sites create_database"

.PHONY: hydrate-asu
.SILENT: hydrate-asu
## Reconstitute the site from environment variables.
hydrate-asu: update-config-from-environment solr-cores namespaces run-islandora-migrations
	-docker-compose exec -T drupal with-contenv bash -lc "for_all_sites configure_riprap"
	docker-compose exec -T drupal drush cr -y
	docker-compose exec -T drupal with-contenv bash -lc 'chown -R nginx:nginx /var/www/drupal/web/sites'
	-docker-compose exec -T drupal with-contenv bash -lc "drush --uri=$(DOMAIN) mim --userid=1 --all"
	-docker-compose exec -T drupal with-contenv bash -lc "drush --uri=$(DOMAIN) en -y content_sync"
	-docker-compose exec -T drupal with-contenv bash -lc "drush --uri=$(DOMAIN) content-sync-import -y --actions=create"
	-docker-compose exec -T drupal with-contenv bash -lc "drush --uri=$(PRISM_DOMAIN) mim --userid=1 --all"
	-docker-compose exec -T drupal with-contenv bash -lc "drush --uri=$(PRISM_DOMAIN) en -y content_sync"
	-docker-compose exec -T drupal with-contenv bash -lc "drush --uri=$(PRISM_DOMAIN) content-sync-import -y --actions=create"