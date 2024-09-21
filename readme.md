# Simple Storage in *RubyOnRails*, with multiple Backend Storages

## Project Initialization:
To initiallize your RoR project after cloning, run the following commands:

```shell
# install gems (i.e. dependency packages)
sudo bundle install
# set up the database and run migrations (idk if this is necessary)
rails db:setup
```

## Requirements:

see [`./app/assets/pdfs/project_details.pdf`](/app/assets/pdfs/project_details.pdf) for details.


## Local Filesystem Storage Requirements:
- the following relative path should be made available:
  [`/storage/fs/`](/storage/fs/)


## Minio S3 Bucket Server Requirements:

### Set up via script
Run the following rake script to have your minio executable auto downloaded and have its executable permission enabled.

```shell
rails minio:download
```

### Set up manually

- Download Mino server for linux:
  [link](https://dl.min.io/server/minio/release/linux-amd64/minio)
- Place it in the following location (relative to project root):
  [`/vendor/bin/minio/minio`](/vendor/bin/minio)
- Give it execution permission.
- Run the server:
  > ./vendor/bin/minio/ server "./storage/s3/" --console-address :9001
- (Optional) Watch the Minio server's logging in your browser at:
  [`http://localhost:9001`](http://localhost:9001)


This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
