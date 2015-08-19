#!/bin/bash
TAGS_ROLE=app uwsgi --yaml /duwamish/uwsgi.yml:${UWSGI_CONFIG_TYPE:-uwsgi}
