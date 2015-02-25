FROM ubuntu:latest
MAINTAINER Matt Baldwin "baldwin@stackpointcloud.com"

# Install MongoDB and PostgreSQL Tools
# Let's add our MongoDB and PostgreSQL tools
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
RUN echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list
RUN \
  apt-get update && apt-get -qy install \
  mongodb-org-shell \
  mongodb-org-tools \
  postgresql-client

ADD run.sh /run.sh
RUN chmod 755 /*.sh

CMD ["/run.sh"]