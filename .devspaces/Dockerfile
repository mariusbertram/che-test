# Custom Dev Spaces workspace image.
#
# Base already ships Go and Terraform (see devfile/developer-images repo);
# the only missing piece for this stack is Ansible, added below at build
# time so nothing needs to be installed when the workspace starts.
FROM quay.io/devfile/universal-developer-image:ubi9-latest

USER 0
RUN pip3 install --no-cache-dir ansible
USER 10001

RUN go version && python3 --version && terraform version && ansible --version
