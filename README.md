Docker-based Concourse deployment
===

A very simple set of script to easily deploy a Concourse sandbox instance with [Vault](https://www.vaultproject.io/) and [S3](https://aws.amazon.com/s3) ([Minio](https://www.minio.io/)) integration.

Tool rely on Traefik to expose Web UIs through `*.dev.localhost` (see below for more details). All main ports are randomly exposed on Docker host. Use `docker port <container>` to get host port numbers.

## Usage

Use `./manage.sh start` script to create and initialize containers. `--clear` and `--pull` options can be used respectively to remove pre-existing data/container and update Docker image. A list of services can also be provided but all are started by default.

_Note: All created Docker objects are tagged with label `project=concourse` to easily identify them._

### `start`

Start requested services (all by default) and (re-)create and initialized all needed objects.

_Note: create Docker custom network if it not already exist, but don't reinitiliazed it when `--clear` flag is used._


### `status`

Print status of container of requested services (all by default).

### `clear`

Try to remove all services (and associated data), then Docker custom network.


### `get-fly`

Download Concourse CLI (`fly`) to provided path (`./fly` by default).

### `vault`

Execute the provided vault command (inside Vault container).

### `help`

Print a summary of available commands.

## Docker objects

### Network

#### concourse

Custom dedicated network to have embedded DNS to link containers (especially for worker [Garden](https://github.com/cloudfoundry/garden)).

### Volumes

#### concourse-vault-config

Configuration files for Vault server

#### concourse-vault-file

Data files generated by Vault server

#### concourse-vault-logs

Log files generated by Vault server

#### concourse-web-keys

SSH configuration used by [TSA](https://concourse-ci.org/concepts.html#component-tsa) to register [workers](https://concourse-ci.org/concepts.html#architecture-worker)

#### concourse-worker-keys

SSH configuration used by [worker](https://concourse-ci.org/concepts.html#architecture-worker) to connect to [TSA](https://concourse-ci.org/concepts.html#component-tsa).


### Containers

#### concourse-vault

_Service: vault_
_Network alias: vault.concourse.local_
_Ports: 8200_
_Token: `vault-root-token`_

[Vault](https://www.vaultproject.io/) instance to store Concourse secrets at `/concourse`.

#### concourse-s3

_Service: s3_
_Network alias: s3.concourse.local_
_Ports: 9000_
_Access key: `minio-access-key`_
_Secret key: `minio-secret-key`_

[S3](https://aws.amazon.com/s3) ([Minio](https://www.minio.io/)) instance to store files generated by pipelines into `concourse` bucket.

#### concourse-postgres

_Service: db_
_Network alias: db.concourse.local_
_Ports: none_
_Database: `concourse`_
_User: `concourse`_
_Password: `changeme`_

PostgreSQL instance which serves as Concourse database to store pipelines, states and logs.

#### concourse

_Service:  web_
_Network alias: web.concourse.local_
_Ports: 80_
_Team: main_
_User: admin_
_Password: admin_

Main Concourse component ([ATC](https://concourse-ci.org/concepts.html#component-atc) and [TSA](https://concourse-ci.org/concepts.html#component-tsa))

#### concourse-worker

_Service: worker_
_Network alias: worker.concourse.local_
_Ports: none_

[Concourse Worker](https://concourse-ci.org/concepts.html#architecture-worker) instance which will create containers that execute pipeline. Sometimes called agent in other CI/CD tools.

