* [Introduction](#introduction)
* [Preparing for the Migration](#preparing-for-the-migration)
* [ProfitBricks Environment](#profitbricks-environment)
* [MongoDB on Heroku](#mongodb-on-heroku)
* [PostgreSQL on Heroku](#postgresql-on-heroku)
* [Migration](#migration)
* [Passenger with Ruby-on-Rails Container](#passenger-with-ruby-on-rails-container)
* [Running the Migration](#running-the-migration)
* [Post Migration](#post-migration)
* [Conclusion](#conclusion)

## Introduction

Our company, [StackPointCloud](http://www.stackpointcloud.com), just finished up a project where we were asked to migrate a Ruby-on-Rails application running at Heroku to ProfitBricks. This gave us a chance to explore more complex Docker solutions that leveraged custom images, as opposed to using pre-built ones. 

The process for moving from Heroku to Docker involved a number of things including,
- Determining the total number of containers the target would eventually require.
- Choosing where the services would live. 
- Specifying how the environment was configured and organized.
- Pulling the code from Heroku's repository automatically and migrating the databases. 

The primary goal of this project was to simply bring up a container environment that matched the environment the developers were using at Heroku. In a later article, we will expand upon this work, showing you how to introduce high-availability and database redundancy into your Heroku to Docker solution.

A second, important, goal was to have the source and the current database content automatically synchronized into the Docker environment upon container build; this allows us to always use real data to test against and validate bugs. It also makes the migration fully automated. 

You can follow along with the files from our [repository](https://github.com/StackPointCloud/docker-heroku-migrate).

## Preparing for the Migration

We use [Fig](http://www.fig.sh/) to help define, build, and spin up the environment. The next few sections of this tutorial will walk you through all the relevant files before you wire them together in a single *fig.yml* file. 

### Architecture
Fig will spin up four containers during the migration portion with three remaining once the migration happens. 

Our containers will be:

1. Passenger with Ruby-on-Rails
2. PostgreSQL
3. MongoDB
4. Migration

As we can see, our customer is using PostgreSQL alongside MongoDB. This tutorial assumes we're running both. If that's not the case, simply omit any steps that don't apply to your running environment. 

Over time, we hope to expand the repository to include templates for different services at Heroku. 

### Requirements
Before you begin, you will need: 

* Credentials with sufficient privileges to pull data from your Heroku PostgreSQL and MongoDB databases.
* An OAuth token for your application at GitHub. You can read more about how to do that [here](tutorials/configure-a-docker-container-to-automatically-pull-from-github-using-oauth)

When we execute `$ fig up` for the first time, Fig will build the containers and spin them up. The whole environment spins back down once the migration container completes its process. We then remove any references to the migration container from the system, unless we want to re-use it. This is all covered in more detail throughout this article. 

## ProfitBricks Environment

To keep things simple, we built out a single *Ubuntu 14.04* instance in its own dedicated Virtual Data Center. The volume is configured for 50GB, which should be sufficient for our data sets and number of Docker images. 

From within the DCD R2, we create a Virtual Data Center with the following:

* One server connected to the public Internet. 
* One volume attached to the server. Our distribution doesn't really matter as long as it can run the latest version of Docker. 

The configuration values should match up to our current needs. In this case, we went with 4 cores and 8 GB in memory. We can scale this at anytime - which is nice; so, be sure to configure your server to allow hot plug for memory and core. 

Next, we need to install Docker. Follow this other post if you need information on how to [get Docker running on Ubuntu](https://devops.profitbricks.com/tutorials/setup-docker-on-ubuntu-at-profitbricks/).

## MongoDB on Heroku

There are a few different providers selling MongoDB hosting in the Heroku marketplace. This tutorial covers migrating from the Compose MongoDB product into a Docker container on ProfitBricks. Follow these steps:

1. Log into your Heroku account and navigate to your application, 
2. Click on the *Compose MongoDB* or *Mongohq* link. This should take you to the Compose UI. 
3. On the left hand side, click Admin. 
4. Find *Connection Strings*. 

Copy the URL string; it looks something like this:

``` MONGOHQ_URL=mongodb://heroku:password@kahana.mongohq.com:10033/app12345678 ```
 
The password will be a long, random string. We will be using this in *run.sh* for the migration. 

### Mongo Container Dockerfile

Our MongoDB container is simple. We spin it up using the following Dockerfile configuration found in the `mongo` directory of the repo:

    FROM ubuntu
    MAINTAINER Matt Baldwin "baldwin@spc"

    RUN \
       apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10 && \
       echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list && \
       apt-get update && \
       apt-get install -y mongodb-org

    VOLUME ["/data/db"]
    WORKDIR /data

    EXPOSE 27017

    CMD ["mongod"]

Notice that we map a volume from within the container to a local volume on the host. This allows us to persist our mongo data across container restarts. Eventually, it will also enable us to abstract the volume into its own container, allowing for greater portability; it also better adheres to Docker's data volume patterns.

## PostgreSQL on Heroku

Your application will most likely use the PostgreSQL provided by Heroku. If so, find the credentials and connection settings by going to the *Databases* section of the account and clicking on the appropriate database for the app. 

Again, the password will be a long, random string and will be used in *run.sh*. 

### PostgreSQL Container Docker

For PostgreSQL, we went with having the build process happen within Fig versus leveraging a Dockerfile; Fig is instructed to always build postgres from the latest build. 

## Migration

Let's prepare our migration container now that we have situated both databases. This container will be used once and then discarded at the end of the process. Any help in simplifying this process is appreciated, of course.  

We have two components here: 

1. Our Dockerfile
2. Our *run.sh* script

The Dockerfile installs our Mongo and Postgres tools; run.sh performs the migration.

If you're using [our repo](https://github.com/StackPointCloud/docker-heroku-migrate), these are kept in the `migration` directory.

If you're using a git repository, add `migration/run.sh` to *.gitignore*. This will protect you from publishing private credentials to your repo. 

### Migration Container Dockerfile

The following code sample installs our tools and runs *run.sh*.

    FROM ubuntu:latest
    MAINTAINER Matt Baldwin "baldwin@spc"

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

### Migration *run.sh*

In the following sample, we will want to update the following values,

- host
- database name 
- username
- password 

This should work to pull your data across the wire. Please be aware of any security implications in doing this and how you handle this file - so, modify it according to your needs.  

    #!/bin/bash
    # Backup Heroku MongoDB and Restore to Mongo container
    cd /tmp/
    mongodump -h kahana.mongohq.com:10033 -d <database_name> -u heroku -p <password>
    mongorestore -h $MONGODB_PORT_27017_TCP_ADDR dump/<database_name>/

    # Backup Heroku PostgreSQL and Restore to Postgres container
    touch ~/.pgpass && chmod 0600 ~/.pgpass
    echo "*:*:<database_name>:<username>:<password>" > ~/.pgpass
    cd /tmp/
    psql -h $POSTGRES_PORT_5432_TCP_ADDR -U postgres -c "CREATE DATABASE <database_name>;"
    pg_dump -w -c -U <username> -h <host> datebase_name > pg.out
    psql --dbname <database_name> -h $POSTGRES_PORT_5432_TCP_ADDR -U postgres -w < pg.out

We link the migration container with the other containers. `$MONGODB_PORT_27017_TCP_ADDR` and `$POSTGRES_PORT_5432_TCP_ADDR` correspond to environment variables created by Docker during the container linking process. 

This script manages the entirety of your data migration from Heroku into your Docker containers. You can extend this to accommodate any specific needs. 

## Passenger with Ruby-on-Rails Container

The most complex piece is the container hosting the Ruby-on-Rails application. For this we went with a *Passenger* container provided by [Phusion](https://www.phusionpassenger.com/). The files at the root of the repo -- except for *fig.yml* -- are used with this container. 

Those files are:  

- nginxapp.conf
- database.yml
- Dockerfile
- mongodb-env.conf
- mongoid.yml
- postgres-env.conf

This container also links to the mongo and postgres containers when spun up.

### nginxapp.conf

The *Passenger* container runs Nginx as the web server. Our web app configuration is simple: 

    server {
        listen 80;
        server_name myapp.com;
        root /home/app/public;

        passenger_enabled on;
        passenger_user app;

        # For Ruby 1.9.3 (you can ignore the "1.9.1" suffix)
        passenger_ruby /usr/bin/ruby1.9.1;
    }

In our case, the customer is using Ruby 1.9.3 so we've customized the *Passenger* settings to account for this. 

### database.yml

We've updated the Ruby project's *database.yml* file and simply overwrite the one that comes in from Heroku. The production section looks like this: 

    default: &default
      adapter: postgresql
      encoding: unicode
      pool: 5
      timeout: 5000
      host: <%= ENV['POSTGRES_PORT_5432_TCP_ADDR'] %>
      port: 5432

    production:
      <<: *default
      database: <%= ENV['POSTGRES_DB_NAME'] %>
      username: postgres

Note that we're referencing environment variables created by Docker. The first one, `POSTGRES_PORT_5432_TCP_ADDR`, is our PostgreSQL server. The second, `POSTGRES_DB_NAME`, is our DB name and is set within our Dockerfile. 

### mongoid.yml

We also replace Heroku's *mongoid.yml* with our own. The production section looks like this: 

    production:
      sessions:
        default:
          uri: <%= ENV['MONGODB_URI'] %>

`MONGODB_URI` is set within our *Passenger* Dockerfile. 

### mongodb-env.conf

We copy the following into nginx so that our MongoDB environment variables are available within the webserver. 

    env MONGODB_PORT_27017_TCP_ADDR;
    env MONGODB_PORT_27017_TCP_PORT;
    env MONGODB_DB_NAME;
    env MONGODB_URI;

### postgres-env.conf

We copy the following into nginx so that our Postgres environment variables are available within the webserver. 

    env POSTGRES_PORT_5432_TCP_ADDR;
    env POSTGRES_PORT_5432_TCP_PORT;
    env POSTGRES_DB_NAME;

### *Passenger* Container Dockerfile

Finally, we wire this all together in our main Dockerfile. Again, this is the one at the root of our directory where *fig.yml* lives. 

Stepping through this file, the first thing we do is setup our environment variables. This can also be done at spin up time.

    # Let's use the official Passenger container.
    FROM phusion/passenger-ruby19:latest
    MAINTAINER Matt Baldwin "baldwin@spc"

    # Set our ENV Settings
    ENV POSTGRES_DB_NAME <database_name>
    ENV MONGODB_DB_NAME <database_name>
    ENV MONGODB_URI mongodb://mongodb:27017/<database_name>

Next, we synchronize our code from GitHub. 

    # Clone our private GitHub Repository
    RUN git clone https://<token>:x-oauth-basic@github.com/StackPointCloud/myapp.git /myapp/
    RUN cp -R /myapp/* /home/app/
    RUN mkdir /home/app/tmp && touch /home/app/tmp/restart.txt
    ADD database.yml /home/app/config/
    ADD mongoid.yml /home/app/config/
    RUN chown app:app -R /home/app/

Our customer is synchronizing their Heroku repo into GitHub. This process can be swapped out with one that connects to your Heroku repo specifically. 

Once the repo is synchronized and the application is in its proper location, we run `bundle install` to install the required Gems. 

    # Setup Gems
    RUN bundle install --gemfile=/home/app/Gemfile

We also copy over our Nginx configuration files and enable the service.

    # Setup Nginx
    ENV HOME /root
    RUN rm -f /etc/service/nginx/down
    ADD nginxapp.conf /etc/nginx/sites-enabled/
    RUN rm /etc/nginx/sites-enabled/default

    # Setup Database Configuration. Since we use both we'll add both here.
    # This is done to preserve Docker linking of environment variables within Nginx.
    ADD postgres-env.conf /etc/nginx/main.d/postgres-env.conf
    ADD mongodb-env.conf /etc/nginx/main.d/mongodb-env.conf

Lastly, we install our tools and clean up the environment. And, we execute the container's *my_init* to expose ports 80 and 443. 

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

At this point, we have all the components ready to perform the migration and run the environment with Fig. 

## Running the Migration

Now that we're ready, let's create our *fig.yml* file. 

Install Fig using `$ pip install -U fig`. Additional information on this can be found [here](http://www.fig.sh/install.html).

For our first Fig run, we will need to use the [migration *fig.yml* configuration](#migration-fig-yml-configuration), *fig.yml-migration* in the repo.

To kick-off the migration, simply issue the command: `$ fig up`. 

This will run for a bit after which all the containers get shut down. We will see output reflecting various tasks. The output will be color coded by container name. Ensure that the migration tasks run successfully.  

### Migration *fig.yml* configuration

We instruct Fig to perform the following:

1. Build our *web* container using the Dockerfile at the root of the directory.
2. Expose both our ports.
3. Link to the mongodb and postgres containers. 

    web:
          build: .
      ports:
       - "80:80"
       - "443:443"
      links:
       - postgres
       - mongodb
      dns:
       - 8.8.8.8
       - 8.8.4.4

Our *postgres* container builds using the latest version, mapping the location of our database in the container to a location on our host. Notice that we do not expose any ports; this ensures communication happens only within the containers. 

    postgres:
      hostname: postgres
      image: postgres:latest
      volumes:
        - /opt/postgres:/var/lib/postgresql/data
      dns:
       - 8.8.8.8
       - 8.8.4.4

Using the Dockerfile located in our mongo directory, our *mongodb* container builds. It, too, maps a volume from the container to the host. 

    mongodb:
      hostname: mongodb
      build: mongo/.
      volumes:
        - /opt/mongodb:/data/db
      dns:
       - 8.8.8.8
       - 8.8.4.4

Lastly, we build using the Dockerfile in the migration directory, instructing the container to link to *web*, *postgres*, and *mongodb*.  

    migration:
      hostname: migration
      build: migration/.
      links:
       - postgres
       - mongodb
       - web
      dns:
       - 8.8.8.8
       - 8.8.4.4

Fig will build *postgres* and *mongodb* first, given *web* and *migration* link to them. *migration* will be built last, which is what is desired. 

### Post-Migration *fig.yml*

Upon running Fig once your *fig.yml* should be updated to look like this: 

    web:
      build: .
      ports:
       - "80:80"
       - "443:443"
      links:
       - postgres
       - mongodb
      dns:
       - 8.8.8.8
       - 8.8.4.4
    postgres:
      hostname: postgres
      image: postgres:latest
      volumes:
        - /opt/postgres:/var/lib/postgresql/data
      dns:
       - 8.8.8.8
       - 8.8.4.4
    mongodb:
      hostname: mongodb
      build: mongo/.
      volumes:
        - /opt/mongodb:/data/db
      dns:
       - 8.8.8.8
       - 8.8.4.4

## Post Migration

Once we've ran `$ fig up` for the first time, the environment should be spun down. We should have seen the containers spin up and the output reflecting the migration tasks as they completed. Before we run Fig again, we will need to first remove any references to the migration container. We will:

1. Remove the migration container's entry from *fig.yml*. See [Post-Migration *fig.yml*](#post-migration-fig-yml). The repo file *fig.yml-production* is also a copy of this file.
2. Optionally, remove the migration container and image from Docker. 

The second item is optional and depends on if we'll need that container again. 

Also, it is a good practice to `$ docker commit` the *web*, *mongodb*, and *postgres* containers once the migration is complete and we're happy with the setup. 

Now, we simply run `fig up` again to bring up the production environment.

We should now be able to do a `docker ps` and see the three running containers. We should also be able to reach the Ruby-on-Rails application by browsing to port 80 of the server's IP. 

## Conclusion

At this point, our Heroku application is running within Docker. As we can see, there is more to do with this environment. We still need to set up redundancy, automate code updates, and so on. We hope to cover that in future articles as we continue to iterate on the project. 
