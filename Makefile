PROJECT_NAME=sa_web
CONTAINER_NAME=duwamish

# Always run docker-compose with the --project-name flag, or you won't be
# able to correctly base off of the main image for a testing image.
COMPOSE=docker-compose --project-name $(CONTAINER_NAME)

# State tracking, to avoid rebuilding the container on every run.
SENTINEL_DIR=.sentinel
SENTINEL_CONTAINER_CREATED=$(SENTINEL_DIR)/.test-container
SENTINEL_CONTAINER_RUNNING=$(SENTINEL_DIR)/.container-up


# Default target builds the whole enchilada.
default: help


.PHONY: setup
setup: ##[distribution] no-op for compatibility
setup:
	@echo "no-op"

.env:
	touch .env

################
# Distribution #
################

.PHONY: dist
dist: ##[distribution] Builds the docker image
dist: .env
	docker build .


###############
# Local Image #
###############

$(SENTINEL_CONTAINER_CREATED): .env requirements*.txt Dockerfile Procfile package.json manage.py */static/*
	mkdir -p $(@D)
	$(COMPOSE) build
	@# Start the DB right away to help avoid a race condition
	$(COMPOSE) up -d db
	until docker exec ${CONTAINER_NAME}_db_1 pg_isready; do sleep 1; done
	touch $@

.PHONY: test-container
test-container: ##[local image] Create a container using docker-compose
test-container: $(SENTINEL_CONTAINER_CREATED)


###########
# Testing #
###########

# Directory in the container to write test/coverage output
TEST_OUTPUT_DIR=/test-output

TEST_OUTPUT?=nosetests.xml
COVERAGE_OUTPUT?=coverage.xml
COVERAGE_HTML_DIR?=cover
TEST_SETTINGS?=$(PROJECT_NAME).settings.test

.PHONY: lint
lint: ##[testing] Run a linter on your project
lint: test-container
	$(COMPOSE) run app flake8 --exclude=migrations,bower_components --jobs=auto $(PROJECT_NAME)/

# Copy the test artifacts out of the 'testoutput' data container.
.PHONY: .copy-test-artifacts
.copy-test-artifacts:
	-docker cp ${CONTAINER_NAME}_testoutput_1:${TEST_OUTPUT_DIR}/${TEST_OUTPUT} .
	-docker cp ${CONTAINER_NAME}_testoutput_1:${TEST_OUTPUT_DIR}/${COVERAGE_HTML_DIR} .

# Copy the test artifacts out of the 'testoutput' data container and exit with
# an error. This is called when a 'test' target fails. We have to manually
# throw an error because we have to suppress the actual error from the test run
# so that we can copy the artifacts out of the container first.
.PHONY: .copy-failed-test-artifacts
.copy-test-artifacts-and-fail: .copy-test-artifacts
	@exit 1

.PHONY: test
test: ##[testing] Run your tests
test: test-container
	$(COMPOSE) run app python manage.py test \
	    --settings=${TEST_SETTINGS} \
	    --with-coverage \
	    --cover-html \
	    --cover-html-dir=${TEST_OUTPUT_DIR}/${COVERAGE_HTML_DIR} \
	    --cover-xml \
	    --cover-xml-file=${TEST_OUTPUT_DIR}/${COVERAGE_OUTPUT} \
	    --cover-package=$(PROJECT_NAME) \
	    --with-doctest \
	    --with-xunit \
	    --xunit-file=${TEST_OUTPUT_DIR}/${TEST_OUTPUT} || $(MAKE) .copy-test-artifacts-and-fail
	@$(MAKE) .copy-test-artifacts

#########
# Utils #
#########

# These utils are provided for convenience, and to show you how to run commands
# using docker-compose. They are not meant to be exhaustive. If you are trying
# to run something and don't see it here, you should first learn how to call
# docker-compose manually, and only add is as a convenience command if it is
# complex or often repeated.

.PHONY: migrations
migrations: ##[dev utils] Generate django migrations (mange.py makemigrations)
migrations: test-container
	$(COMPOSE) run app python manage.py makemigrations

.PHONY: logs
logs: ##[dev utils] View the logs for your container
logs: test-container
	$(COMPOSE) logs

.PHONY: shell
shell: ##[dev utils] Get a django shell in your container
shell: test-container
	$(COMPOSE) run app python manage.py shell

.PHONY: shellplus
shell_plus: ##[dev utils] Get a django shell_plus in your container
shell_plus: test-container
	$(COMPOSE) run app python manage.py shell_plus

.PHONY: shellplus
shellplus: ##[dev utils] Alias for shell_plus
shellplus: shell_plus

.PHONY: bash
bash: ##[dev utils] Get a bash shell in your container
bash: test-container
	$(COMPOSE) run app /bin/bash

.PHONY: startapp
startapp: ##[dev utils] Shortcut to add a new app to your project.
startapp:
ifdef APP
	mkdir ${PROJECT_NAME}/${APP}
	$(COMPOSE) run app python manage.py startapp ${APP} ${PROJECT_NAME}/${APP}
	@echo "Don't forget to add ${PROJECT_NAME}.${APP} to your INSTALLED_APPS and run make migrations."
else
	@echo "Usage: make startapp APP='my_app_name'"
endif

.PHONY: manage
manage: ##[dev utils] Run an arbitrary manage.py command
manage: test-container
ifdef ARGS
	${COMPOSE} run app python manage.py ${ARGS}
else
	@echo "Usage: make manage ARGS='my_command'"
endif

###########
# Running #
###########
.PHONY: migrate
migrate: ##[running] Run the migrations
migrate: up
	$(COMPOSE) run app python manage.py migrate

$(SENTINEL_CONTAINER_RUNNING): $(SENTINEL_CONTAINER_CREATED)
	mkdir -p $(@D)
	$(COMPOSE) up -d app
	touch $@

.PHONY: up
up: ##[running] Start your app with docker-compose
up: test-container $(SENTINEL_CONTAINER_RUNNING)

.PHONY: runserver
runserver: ##[dev utils] Run the django dev server
runserver: $(SENTINEL_CONTAINER_CREATED)
ifdef ARGS
	${COMPOSE} run --service-ports --rm app python manage.py runserver ${ARGS}
else
	${COMPOSE} run --service-ports --rm app python manage.py runserver 0.0.0.0:8002
endif

.PHONY: down
down: ##[running] Stop the app and dependent containers
down:
	$(COMPOSE) stop
	rm -f $(SENTINEL_CONTAINER_RUNNING)

###########
# Cleanup #
###########

.PHONY: clean
clean: ##[clean up] Stop your containers and delete sentinel files.
clean: ##[clean up] Will cause your containers to get rebuilt.
clean: down
	rm -rf $(PYTHON_SDIST_DIR)
	rm -rf *.egg*/
	rm -rf __pycache__/
	rm -f MANIFEST
	rm -f $(TEST_OUTPUT)
	rm -f $(COVERAGE_OUTPUT)
	rm -rf $(COVERAGE_HTML_DIR)
	find . -type f -name '*.pyc' -delete
	rm -rf $(SENTINEL_DIR)


.PHONY: teardown
teardown: ##[clean up] Stop & delete all containers
teardown:
	$(COMPOSE) kill
	$(COMPOSE) rm -f -v


define newline


endef

define HELP_FN
import sys, re, itertools
pattern = re.compile(r'(?P<cmd>^\w+):\s+##(?:(?:\[)(?P<group>[\w\s]+)(?:\]))? (?P<doc>.*)$$')
with open('Makefile', 'r') as makefile:
    matches = sorted(
        [match.groups() for match in (pattern.match(line) for line in makefile) if match],
        key=lambda match: (match[1], match[0]))
for (group, docs) in itertools.groupby(matches, lambda match: match[1]):
    print('%s:' % (group or 'options').title())
    last_cmd = None
    for (cmd, _, doc) in docs:
        print('  {:<19}{}{}'.format(
	    cmd if cmd != last_cmd else '',
	    '' if cmd != last_cmd else '  ',
	    doc))
        last_cmd = cmd
    print('')
endef

help: ## Show this help.
	@# Have to escape the newlines because of make, then un-escape them
	@# (via echo) so python doesn't choke.
	@python -c "`echo \"$(subst $(newline),\n,${HELP_FN})\"`"
