###########################################################
# Dockerfile to build Python WSGI Application Containers
# Based on Ubuntu
############################################################

# Set the base image to Ubuntu
FROM ubuntu

# File Author / Maintainer
MAINTAINER Luke Swart <luke@smartercleanup.org>

# Update the sources list
RUN apt-get update

# Install basic applications
RUN apt-get install -y tar git curl wget dialog net-tools build-essential gettext

# Install Python and Basic Python Tools
RUN sudo apt-get install -y python-distribute python-pip python-dev 

# Install Postgres dependencies
RUN sudo apt-get install -y postgresql libpq-dev

# TODO: ASK SOMEONE ABOUT THIS, IDK what this does.
# RUN git checkout docker-deploy
# RUN git clone https://github.com/smartercleanup/duwamish.git && cd duwamish && git checkout docker-deploy && cd -

ENV APP_ENV_DIR /duwamish

# Install pip requirements
ADD requirements.txt $APP_ENV_DIR/
RUN pip install -r $APP_ENV_DIR/requirements.txt

# Add everything to the container.
ADD manage.py $APP_ENV_DIR/
ADD .env $APP_ENV_DIR/
ADD app.json $APP_ENV_DIR/
ADD dotcloud.yml $APP_ENV_DIR/
ADD Gruntfile.js $APP_ENV_DIR/
ADD package.json $APP_ENV_DIR/
ADD wsgi.py $APP_ENV_DIR/
ADD src/ $APP_ENV_DIR/src
ADD run_scripts/ $APP_ENV_DIR/run_scripts/

ADD requirements-dev.txt $APP_ENV_DIR/

# Expose ports
EXPOSE 8002

# Set the default directory where CMD will execute
WORKDIR $APP_ENV_DIR

ENV PYTHONPATH='/duwamish/src'
ENV STATIC_ROOT $APP_ENV_DIR/static
RUN python manage.py compilemessages
RUN python manage.py collectstatic --noinput
RUN ln -s staticfiles static
VOLUME /duwamish/static

# # Set the default command to execute
# # when creating a new container
CMD gunicorn wsgi:application -w 3 -b 0.0.0.0:8002 --log-level=debug

# Switch from root to daemon, for a little extra security.
# USER daemon
# CMD ["honcho", "start"]
