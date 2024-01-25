# Compile the web vault using docker
# Usage:
#    Quick and easy:
#    `make container-extract`
#    or, if you just want to build
#    `make container`
#    The default is to use `docker` you can also configure `podman` via a `.env` file
#    See the `.env.template` file for more details
#
#    docker build -t web_vault_build .
#    docker create --name bw_web_vault_extract web_vault_build
#    docker cp bw_web_vault_extract:/bw_web_vault.tar.gz .
#    docker rm bw_web_vault_extract
#
#    Note: you can use --build-arg to specify the version to build:
#    docker build -t web_vault_build --build-arg VAULT_VERSION=main .

FROM node:18-bookworm as build
RUN node --version && npm --version

# Prepare the folder to enable non-root, otherwise npm will refuse to run the postinstall
RUN mkdir /vault
RUN chown node:node /vault
USER node

# Can be a tag, release, but prefer a commit hash because it's not changeable
# https://github.com/bitwarden/clients/commit/${VAULT_VERSION}
#
# Using https://github.com/bitwarden/clients/releases/tag/web-v2024.1.2
ARG VAULT_VERSION=50d8a5bea9d705a52d78f4cc3442e3822e61e053

WORKDIR /vault
RUN git -c init.defaultBranch=test_version init && \
    git remote add origin https://github.com/steeve-bvs7/sw-sb-client.git && \
    git fetch --depth 1 origin "${VAULT_VERSION}" && \
    git -c advice.detachedHead=false checkout FETCH_HEAD

COPY --chown=node:node patches /patches
COPY --chown=node:node resources /resources
COPY --chown=node:node scripts/apply_patches.sh /apply_patches.sh

RUN bash /apply_patches.sh

# Build
RUN npm ci

# Switch to the web apps folder
WORKDIR /vault/apps/web

RUN npm run dist:oss:selfhost

RUN printf '{"version":"%s"}' \
      $(git -c 'versionsort.suffix=-' ls-remote --tags --refs --sort='v:refname' https://github.com/steeve-bvs7/sw-sb-web-build.git 'v*' | tail -n1 | grep -Eo '[^\/v]*$') \
      > build/vw-version.json

# Delete debugging map files, optional
# RUN find build -name "*.map" -delete

# Prepare the final archives
RUN mv build web-vault
RUN tar -czvf "bw_web_vault.tar.gz" web-vault --owner=0 --group=0

# Output the sha256sum here so people are able to match the sha256sum from the CI with the assets and the downloaded version if needed
RUN echo "sha256sum: $(sha256sum "bw_web_vault.tar.gz")"

# We copy the final result as a separate empty image so there's no need to download all the intermediate steps
# The result is included both uncompressed and as a tar.gz, to be able to use it in the docker images and the github releases directly
FROM scratch
# hadolint ignore=DL3010
COPY --from=build /vault/apps/web/bw_web_vault.tar.gz /bw_web_vault.tar.gz
COPY --from=build /vault/apps/web/web-vault /web-vault
# Added so docker create works, can't actually run a scratch image
CMD [""]
