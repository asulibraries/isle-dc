.SILENT: clone-codebase
clone-codebase:
	[ -d "codebase" ] || (git clone git@github.com:asulibraries/islandora-repo.git codebase)
ifdef BRANCH
	cd codebase && git checkout -b "${BRANCH}" "origin/${BRANCH}"
endif
