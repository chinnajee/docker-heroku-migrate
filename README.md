* [Introduction](#introduction)
* [Preparing for the Migration](#preparing-for-the-migration)
* [ProfitBricks Environment](#profitbricks-environment)
* [MongoDB on Heroku](#mongodb-on-heroku)
* [PostgreSQL on Heroku](#opostgresql-on-heroku)
* [Migration](#migration)
* [Passenger with Ruby-on-Rails Container](#passenger-with-ruby-on-rails-container)
* [Running the Migration](#running-the-migration)
* [Post Migration](#post-migration)
* [Conclusion](#conclusion)

## Introduction

My company, [StackPointCloud](http://www.stackpointcloud.com), just finished up a project where we were asked to migrate a Ruby-on-Rails application running at Heroku to ProfitBricks. This gave me a chance to explore more complex Docker solutions that leveraged custom images, as opposed to using pre-built ones. 

The process for moving from Heroku to Docker involved a number of things from determining the total number of containers the target will eventually require, where services will live, how the environment is configured and organized, to how to pull the code from Heroku's repository automatically and migrate the databases. The first goal of this project was to simply bring up a container environment that matches the environment the developers were using at Heroku. In a later article I will expand upon this work showing you how to introduce high-availability and database redundancy into your Heroku to Docker solution.

It was also very important to me that the source and the current database content be automatically synchronized into the Docker environment upon container build. This allows us to always use real data to test and validate bugs against. It also makes the migration fully automated. 

You can follow along with the files from our [repository](https://github.com/StackPointCloud/docker-heroku-migrate).

## Preparing for the Migration

I chose to use [Fig](http://www.fig.sh/) to help define, build, and spin up the environment.  The next few sections of this tutorial will walk you through all the relevant files before you wire them together in a single *fig.yml* file. 

Fig will spin up four containers during the migration portion with three remaining once the migration happens. Our containers will be:

1. Passenger with Ruby-on-Rails
2. PostgreSQL
3. MongoDB
4. Migration

As you can see, our customer is using PostgreSQL alongside MongoDB. This tutorial assumes you're running both. If not, then simply omit any steps that don't apply to your running environment from your own process. Overtime we hope to expand our repository to include templates for different services at Heroku. 

Before you begin you will need to: 

* have credentials with sufficient privileges to pull data from your Heroku PostgreSQL database.
* have credentials with sufficient privileges to pull data from your Heroku MongoDB database.  
* setup a OAuth token for your application at GitHub. You can read more about how to do that [here](tutorials/configure-a-docker-container-to-automatically-pull-from-github-using-oauth)

When you execute `fig up` for the first time Fig will build the containers and spin them up. Once the migration container completes its process the whole environment spins back down. You would then remove any references to the migration container from the system unless you want to re-use it. This is all covered in more detail throughout this article. 

## ProfitBricks Environment

To keep things simple I built out a single *Ubuntu 14.04* instance in its own dedicated Virtual Datacenter. The volume is configured for 50GB, which should be sufficient for our data sets and number of Docker images. 

From within the DCD R2, create a Virtual Datacenter with the following in it:

* One server connected to the public Internet. 
* One volume attached to the server. Your distribution doesn't really matter as long as it can run the latest version of Docker. 

Your configuration values should match up with what your current needs our. In my case, I went with 4 cores and 8 GB in memory. What's nice is I can scale this at anytime, so be sure to configure your server to allow hot plug for memory and core. 

Next, you need to install Docker. You can follow this other post if you need information on how to [get Docker running on Ubuntu](https://devops.profitbricks.com/tutorials/setup-docker-on-ubuntu-at-profitbricks/).

## MongoDB on Heroku

There are a few providers who sell MongoDB hosting in the Heroku marketplace. This tutorial covers migrating from the Compose MongoDB product into a Docker container on ProfitBricks.

First, log into your Heroku account and navigate to your application, then click on the *Compose MongoDB* or *Mongohq* link. This should take you to the Compose UI. On the left hand side, click on Admin. 

You should now see *Connection Strings*. Your string should look something like this: 

    MONGOHQ_URL=mongodb://heroku:password@kahana.mongohq.com:10033/app12345678
    
Your password will be a long, random string. You will be using this in *run.sh* for the migration. 

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

You'll notice that I map a volume from within the container to a local volume on my host. This allows me to persist my mongo data across container restarts. Eventually, it'll also allow me to abstract the volume into its own container for greater portability and adherence to Docker's data volume patterns.

## PostgreSQL on Heroku

Your application will most likely use PostgreSQL provided by Heroku. If so, then you can find your credentials and connection settings by going to the *Databases* section of your account and clicking on the appropriate database for your app. 

Again, your password will be a long, random string and will be used in *run.sh*. 

### PostgreSQL Container Docker

For PostgreSQL I went with having the build process happen within Fig versus leveraging a Dockerfile; Fig is simply instructed to always build postgres from the latest build. 

## Migration

Now that you have, for the time being, situated both databases we can prepare our migration container. This container will be used once and then discarded at the end of this process. Any help in simplifying this process is appreciated, of course.  

We have two components here: 

* Our Dockerfile
* Our *run.sh* script

If you're using [the repo](https://github.com/StackPointCloud/docker-heroku-migrate), these are kept in the `migration` directory.

The Dockerfile installs our Mongo and Postgres tools, the other performs the migration.

If you're using a git repository you will need to add `migration/run.sh` to *.gitignore*. This will protect you from adding your credentials to your repo. 

### Migration Container Dockerfile

This will install our tools and run *run.sh*.

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

### Migration *run.sh*

You will want to update the host, database name, username, and password values throughout, but this should work to pull your data across the wire. Mind you, be aware of any security implications in doing this and how you handle this file, so modify accordingly for your needs.  

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

`$MONGODB_PORT_27017_TCP_ADDR` and `$POSTGRES_PORT_5432_TCP_ADDR` correspond to environment variables created by Docker during the container linking process. We link the migration container with the other containers. 

This script manages the entirety of your data migration from Heroku into your Docker containers. You can extend this to accommodate 

## Passenger with Ruby-on-Rails Container

The most complex piece is the container hosting the Ruby-on-Rails application. For this we went with a *Passenger* container provided by [Phusion](https://www.phusionpassenger.com/). The files at the root of the repo -- except for*fig.yml* -- are used with this container. 

Those are:  

* nginxapp.conf
* database.yml
* Dockerfile
* mongodb-env.conf
* mongoid.yml
* postgres-env.conf

This container also, when spun up, links to the mongo and postgres containers.

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

In our case, the customer is using Ruby 1.9.3 so we've customized the *Passenger* settings for this. 

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

You'll note we're referencing environment variables created by Docker. The first one, `POSTGRES_PORT_5432_TCP_ADDR`, is our PostgreSQL server. The second, `POSTGRES_DB_NAME`, is our DB name and is set within our Dockerfile. 

### mongoid.yml

We also replace Heroku's *mongoid.yml* with our own. The production section looks like this: 

    production:
      sessions:
        default:
          uri: <%= ENV['MONGODB_URI'] %>

`MONGODB_URI` is set within our *Passenger* Dockerfile. 

### mongodb-env.conf

We copy this into nginx so that our MongoDB environment variables are available within the webserver. 

    env MONGODB_PORT_27017_TCP_ADDR;
    env MONGODB_PORT_27017_TCP_PORT;
    env MONGODB_DB_NAME;
    env MONGODB_URI;

### postgres-env.conf

We copy this into nginx so that our Postgres environment variables are available within the webserver. 

    env POSTGRES_PORT_5432_TCP_ADDR;
    env POSTGRES_PORT_5432_TCP_PORT;
    env POSTGRES_DB_NAME;

### *Passenger* Container Dockerfile

Finally, we wire this all together with our main Dockerfile. Again, this is the one at the root of our directory where *fig.yml* lives. 

Stepping through this file, the first thing we do is setup our environment variables. You can make this even easier by simply passing these in at spin up time.

    # Let's use the official Passenger container.
    FROM phusion/passenger-ruby19:latest
    MAINTAINER Matt Baldwin "baldwin@spc"

    # Set our ENV Settings
    ENV POSTGRES_DB_NAME <database_name>
    ENV MONGODB_DB_NAME <database_name>
    ENV MONGODB_URI mongodb://mongodb:27017/<database_name>

Next, we synchronize our code from GitHub. Our customer is synchronizing their Heroku repo into GitHub. This process can be swapped out with one that connects to your Heroku repo specifically. 

    # Clone our private GitHub Repository
    RUN git clone https://<token>:x-oauth-basic@github.com/StackPointCloud/myapp.git /myapp/
    RUN cp -R /myapp/* /home/app/
    RUN mkdir /home/app/tmp && touch /home/app/tmp/restart.txt
    ADD database.yml /home/app/config/
    ADD mongoid.yml /home/app/config/
    RUN chown app:app -R /home/app/

Once the repo is synchronized and the application is in its proper location we run *bundle* to install any required Gems. 

    # Setup Gems
    RUN bundle install --gemfile=/home/app/Gemfile

Copy over our Nginx configuration files and enable the service.

    # Setup Nginx
    ENV HOME /root
    RUN rm -f /etc/service/nginx/down
    ADD nginxapp.conf /etc/nginx/sites-enabled/
    RUN rm /etc/nginx/sites-enabled/default

    # Setup Database Configuration. Since we use both we'll add both here.
    # This is done to preserve Docker linking of environment variables within Nginx.
    ADD postgres-env.conf /etc/nginx/main.d/postgres-env.conf
    ADD mongodb-env.conf /etc/nginx/main.d/mongodb-env.conf

Install our tools and clean up the environment. We execute the container's *my_init* and expose 80 and 443. 

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

At this point, you have all the components ready to move onto performing the migration and running the environment with Fig. 

## Running the Migration

Now that you're ready, you can create your *fig.yml* file. Be sure you've installed Fig by doing `pip install -U fig`. Additional information on this can be found [here](http://www.fig.sh/install.html).

You will need to use the [migration *fig.yml* configuration](#migration-fig-yml-configuration), named *fig.yml-migration* in the repo, for your first Fig run.

To kick-off the migration simply issue the command: `fig up`. This will run for a bit after which all the containers get shut down. You should see output reflecting various tasks. They will be color coded by container name. Ensure the migration tasks run successfully.  

### Migration *fig.yml* configuration

We instruct Fig to build our *web* container using the Dockerfile at the root of the directory, expose both our ports, then link to the mongodb and postgres containers. 

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

Our *postgres* container builds using the latest version and maps the location of our database in the container to a location on our host. You'll notice that we do not expose any ports. This ensures communication happens only within the containers. 

    postgres:
      hostname: postgres
      image: postgres:latest
      volumes:
        - /opt/postgres:/var/lib/postgresql/data
      dns:
       - 8.8.8.8
       - 8.8.4.4

Our *mongodb* container builds using the Dockerfile located in the mongo directory. It, too, maps a volume from the container to one on the host. 

    mongodb:
      hostname: mongodb
      build: mongo/.
      volumes:
        - /opt/mongodb:/data/db
      dns:
       - 8.8.8.8
       - 8.8.4.4

This section is temporary. We build using the Dockerfile in the migration directory and then instruct the container to link to *web*, *postgres*, and *mongodb*.  

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

Fig will build *postgres* and *mongodb* first since *web* and *migration* link to them. *migration* will be built last, which is what is desired. 

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

Once you've ran `fig up` for the first time the environment should now be spun down. You should have seen the containers spin up and output reflecting the migration tasks as they completed. Before you run Fig again you will need to first remove any references to the migration container. 

You will need to:

* remove the migration container's entry from *fig.yml*. See [Post-Migration *fig.yml*](#post-migration-fig-yml). The repo file *fig.yml-production* is also a copy of this file.
* remove the migration container and image from Docker. 

The second item is optional and really depends on if you'll need that container ever again. 

It is, also, a good idea to `docker commit` the *web*, *mongodb*, and *postgres* containers once the migration is complete and you're happy with the setup. 

Now, simply run `fig up` again to bring up your production environment.

You should now be able to do a `docker ps` and see the three running containers. You should also be able to reach the Ruby-on-Rails application by browsing to port 80 of the server's IP. 

## Conclusion

Hopefully, at this point, your Heroku application is running within Docker. As you can see, there is more to do with this environment such as setting up redundancy, automating code updates, and so on. I hope to cover that in future articles as we iterate on this project. 