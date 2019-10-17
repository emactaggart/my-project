# Creates an executable with the lisp package management system (ASDF)
build: test
	sbcl --no-userinit --no-sysinit --non-interactive \
			 --load ~/quicklisp/setup.lisp \
			 --eval "(ql:quickload :my-portfolio)" \
			 --eval "(asdf:make :my-portfolio)"

# Runs unit tests against the current version of our project
test:
	sbcl --no-userinit --no-sysinit --non-interactive \
			 --load ~/quicklisp/setup.lisp \
			 --eval "(ql:quickload :my-portfolio/tests)" \
			 --eval "(asdf:test-system :my-portfolio)"

# Runs the test against the current local version of the base project docker image
docker-test:
	docker run --rm emactaggart/my-portfolio-base:alpine make test

# Runs the test in against a freshly built version of the project docker image
docker-test-clean-build: _update-local-images _portfolio-base docker-test

# First creates an sbcl executable containing our lisp application,
# Then bundles the executable to produces a production ready docker image
# containing a webserver executable and static files
docker-build-prod: docker-test-clean-build
	docker run --rm \
	-v ${pwd}/builds:/root/my-portfolio/builds \
	emactaggart/my-portfolio-base:alpine \
	make build \
	&& docker build \
	-t emactaggart/my-portfolio:latest \
	-f Dockerfile.prod .

# FIXME shouldn't have to build prod exe... take a look in docker-compose.util.yml
run-dev:
	docker-compose \
	-f docker-compose.yml \
	-f docker-compose.dev.yml \
	up --force-recreate my-portfolio

# Runs our current local version of our production ready webapp
# FIXME requires nginx.dev.conf to be used instead, although this is about as close to the prod environment we'll get due to ssl related stuff
run-prod-local: _update-local-images
	docker-compose \
	-f docker-compose.yml \
	-f docker-compose.dev.yml \
	up --force-recreate

# Runs a fresh prod build on our local machine
run-prod-clean: docker-build-prod run-prod-local

# Pushes a freshly built and tested webappliction image
dockerhub-publish: docker-test-clean-build
	docker push emactaggart/my-portfolio:latest

# TODO we need to decide if a certbot deploy is also required
# Does a full deploy to our hosting server # Does this even blong in a make file?
full-deploy: dockerhub-publish _all-configs
	ssh tagg "docker-compose docker-compose.yml pull" \
	&& ssh tagg "docker-compose up -d --force-recreate"

# Does an webapp deploy on our webserver
my-portfolio-deploy: dockerhub-publish _my-portfolio-configs
	ssh tagg "docker-compose pull my-portfolio" \
	&& ssh tagg "docker-compose up -d --force-recreate my-portfolio"

# Does an nginx deploy on our hosting server
nginx-deploy: _nginx-configs
	ssh tagg "docker-compose pull nginx" \
	&& ssh tagg "docker-compose  up -d --force-recreate nginx"

# FIXME we must be careful with our deploys, as certbot requires updated docker-compose.yml files,
# which may lead to our deployed application being out of sync with it's compose and config files...
# ... perhaps prevent certbot from being deployed without a full deploy?
# Does loads certbot to renew our ssl certs via webroot plugin, requires nginx to serve directories
certbot-deploy: _all-configs
	ssh tagg "docker-compose -f docker-compose.yml pull nginx certbot" \
	&& ssh tagg "docker-compose -f docker-compose.yml up -d --force-recreate nginx certbot"

# TODO
# run stack locally
# run tests against stack
# have some for prod
# have some for  staging environment
integration-test:
	echo "not yet implemented"

# TODO what should we even clean?
# - all the lisp .fasl files,
# - perhaps the files generated by org-mode?
# - docker images and containers?
# - npm garbage? (not yet)
# TODO dont forget to add this to the clean runs
clean:
	echo "Not yet implemented"

## Helpers for preparing the prod server configs

_my-portfolio-configs:
	ssh tagg 'mv ~/prod.taggrc{,.bak}' \
	&& ssh tagg 'mv ~/docker-compose.yml{,.bak}' \
	&& scp {~/,tagg:~/}prod.taggrc \
	&& scp {./,tagg:~/}docker-compose.yml

_nginx-configs:
	ssh tagg 'mv ~/nginx.conf{,.bak}' \
	&& scp {./,tagg:~/}nginx.conf

_all-configs: _my-portfolio-configs _nginx-configs
	ssh tagg 'mv ~/nginx.certbot.conf{,.bak}' \
	&& scp {./,tagg:~/}nginx.certbot.conf


# Helpers for building docker images

_update-local-images:
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml pull

_portfolio-base: _lisp-base
	docker build \
	-t emactaggart/my-portfolio-base:alpine \
	-f Dockerfile.my-portfolio-base .

_lisp-base: _sbcl
	docker build \
	-t emactaggart/lisp-base:alpine \
	-f Dockerfile.lisp-base .

_sbcl:
	docker pull daewok/sbcl:alpine
