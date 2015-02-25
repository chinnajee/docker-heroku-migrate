# Let's use the official Passenger container.
FROM phusion/passenger-ruby19:latest
MAINTAINER Matt Baldwin "baldwin@spc"

# Set our ENV Settings
ENV POSTGRES_DB_NAME <database_name>
ENV MONGODB_DB_NAME <database_name>
ENV MONGODB_URI mongodb://mongodb:27017/<database_name>

# Clone our private GitHub Repository
RUN git clone https://<token>:x-oauth-basic@github.com/StackPointCloud/myapp.git /myapp/
RUN cp -R /myapp/* /home/app/
RUN mkdir /home/app/tmp && touch /home/app/tmp/restart.txt
ADD database.yml /home/app/config/
ADD mongoid.yml /home/app/config/
RUN chown app:app -R /home/app/

# Setup Gems
RUN bundle install --gemfile=/home/app/Gemfile

# Setup Nginx
ENV HOME /root
RUN rm -f /etc/service/nginx/down
ADD nginxapp.conf /etc/nginx/sites-enabled/
RUN rm /etc/nginx/sites-enabled/default

# Setup Database Configuration. Since we use both we'll add both here.
# This is done to preserve Docker linking of environment variables within Nginx.
ADD postgres-env.conf /etc/nginx/main.d/postgres-env.conf
ADD mongodb-env.conf /etc/nginx/main.d/mongodb-env.conf

# Let's add our MongoDB and PostgreSQL tools
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
RUN echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list
RUN \
  apt-get update && apt-get -qy install \
  mongodb-org-shell \
  mongodb-org-tools \
  postgresql-client

# Clean-up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /myapp/

CMD ["/sbin/my_init"]
EXPOSE 80 443